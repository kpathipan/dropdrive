using System.Text.Json;
using System.Text.RegularExpressions;
using DropDrive.Windows.Models;

namespace DropDrive.Windows.Services;

public sealed partial class TikTokMediaService
{
    private static readonly HttpClient Client = new() { Timeout = TimeSpan.FromSeconds(8) };
    public static bool IsTikTok(string url) => Uri.TryCreate(url, UriKind.Absolute, out var uri) &&
        (uri.Host == "tiktok.com" || uri.Host.EndsWith(".tiktok.com", StringComparison.OrdinalIgnoreCase));

    public static async Task<MediaAnalysis?> AnalyzeFastAsync(string url, CancellationToken token)
    {
        if (!IsTikTok(url)) return null;
        if (!new Uri(url).AbsolutePath.Contains("/video/", StringComparison.Ordinal))
        {
            try { if (PhotoAnalysis(await PlayerJsonAsync(url, token), url) is { } photos) return photos; }
            catch (Exception error) when (error is HttpRequestException or JsonException or InvalidOperationException or TaskCanceledException && !token.IsCancellationRequested) { }
            return null;
        }
        try
        {
            using var data = await Client.GetStreamAsync("https://www.tiktok.com/oembed?url=" + Uri.EscapeDataString(url), token);
            using var json = await JsonDocument.ParseAsync(data, cancellationToken: token);
            var root = json.RootElement;
            if (!root.TryGetProperty("title", out var title) || title.ValueKind != JsonValueKind.String) return null;
            return new(title.GetString() ?? "TikTok", "TikTok", "วิดีโอ TikTok", root.TryGetProperty("thumbnail_url", out var thumb) ? thumb.GetString() : null, null);
        }
        catch (Exception error) when (error is HttpRequestException or JsonException or TaskCanceledException && !token.IsCancellationRequested) { return null; }
    }

    public static async Task<string> ResolveOriginalAsync(string url, int quality, CancellationToken token)
    {
        return OriginalUrl(await PlayerJsonAsync(url, token), quality) ??
            throw new InvalidOperationException("TikTok ยังไม่ส่งวิดีโอต้นฉบับที่ไม่มีลายน้ำ ลองใหม่อีกครั้ง");
    }

    private static async Task<string> PlayerJsonAsync(string url, CancellationToken token)
    {
        var id = PostId().Match(new Uri(url).AbsolutePath).Value;
        if (id.Length == 0)
        {
            using var data = await Client.GetStreamAsync("https://www.tiktok.com/oembed?url=" + Uri.EscapeDataString(url), token);
            using var embed = await JsonDocument.ParseAsync(data, cancellationToken: token);
            id = embed.RootElement.TryGetProperty("embed_product_id", out var value) ? value.ToString() : "";
        }
        if (!Regex.IsMatch(id, @"^\d{10,25}$")) throw new InvalidOperationException("อ่านรหัสโพสต์ TikTok ไม่ได้");
        using var request = new HttpRequestMessage(HttpMethod.Get, $"https://www.tiktok.com/player/api/v1/items?item_ids={id}&language=en");
        request.Headers.Referrer = new Uri($"https://www.tiktok.com/player/v1/{id}");
        using var response = await Client.SendAsync(request, token);
        response.EnsureSuccessStatusCode();
        await response.Content.LoadIntoBufferAsync(4_000_000, token);
        return await response.Content.ReadAsStringAsync(token);
    }

    public static MediaAnalysis? PhotoAnalysis(string json, string postUrl)
    {
        using var document = JsonDocument.Parse(json);
        var root = document.RootElement;
        if (!root.TryGetProperty("items", out var items) || items.ValueKind != JsonValueKind.Array || items.GetArrayLength() == 0) return null;
        var item = items[0];
        if (!item.TryGetProperty("image_post_info", out var post) || !post.TryGetProperty("images", out var images) ||
            images.ValueKind != JsonValueKind.Array || images.GetArrayLength() == 0) return null;
        List<MediaEntry> entries = [];
        foreach (var image in images.EnumerateArray())
        {
            if (!image.TryGetProperty("display_image", out var address) || TrustedUrl(address) is not { } url)
                throw new InvalidOperationException("อ่านรูปในโพสต์ TikTok ไม่ครบ กรุณาลองใหม่");
            var extension = Path.GetExtension(new Uri(url).AbsolutePath).ToLowerInvariant();
            if (extension is not (".jpg" or ".jpeg" or ".webp" or ".png")) extension = ".jpg";
            var index = entries.Count + 1;
            entries.Add(new() { Index = index, Title = $"รูปที่ {index:00}{extension}", Url = url,
                StableId = postUrl + "#photo-" + index, ThumbnailUrl = url, Kind = "image" });
        }
        if (item.TryGetProperty("video_info", out var sound) && TrustedUrl(sound) is { } audio)
            entries.Add(new() { Index = entries.Count + 1, Title = "เสียงประกอบ.m4a", Kind = "audio", Url = audio, StableId = postUrl + "#sound" });
        var title = item.TryGetProperty("desc", out var desc) && desc.ValueKind == JsonValueKind.String ? desc.GetString() : null;
        return new(title ?? "รูป TikTok", "TikTok Photos", $"TikTok · {entries.Count} ไฟล์", entries[0].ThumbnailUrl, null, false, true, entries);
    }

    // Mirrors macOS TikTokPlayerMedia: play_addr only, never download_addr or
    // embed-page video, and only trusted TikTok CDN hosts.
    public static string? OriginalUrl(string json, int quality)
    {
        using var document = JsonDocument.Parse(json);
        var root = document.RootElement;
        if (!root.TryGetProperty("items", out var items) || items.ValueKind != JsonValueKind.Array || items.GetArrayLength() == 0 ||
            !items[0].TryGetProperty("video_info", out var video)) return null;
        var candidates = new List<(double Rate, double Size, string Url)>();
        if (video.TryGetProperty("profiles", out var profiles) && profiles.ValueKind == JsonValueKind.Array)
            foreach (var profile in profiles.EnumerateArray())
            {
                if (!profile.TryGetProperty("play_addr", out var address)) continue;
                var url = TrustedUrl(address);
                if (url != null) candidates.Add((Number(profile, "bitrate"), Math.Min(Number(address, "width"), Number(address, "height")), url));
            }
        var cap = quality switch { 2 => 1080, 3 => 720, 4 => 480, _ => double.MaxValue };
        var eligible = candidates.Where(candidate => candidate.Size > 0 && candidate.Size <= cap).ToArray();
        return (eligible.Length > 0 ? eligible : candidates.ToArray()).OrderByDescending(candidate => candidate.Rate).FirstOrDefault().Url ?? TrustedUrl(video);
    }
    private static double Number(JsonElement value, string name) => value.TryGetProperty(name, out var number) && double.TryParse(number.ToString(), out var result) ? result : 0;
    private static string? TrustedUrl(JsonElement address)
    {
        if (!address.TryGetProperty("url_list", out var urls) || urls.ValueKind != JsonValueKind.Array) return null;
        foreach (var value in urls.EnumerateArray())
            if (value.ValueKind == JsonValueKind.String && Uri.TryCreate(value.GetString(), UriKind.Absolute, out var uri) && uri.Scheme == "https" &&
                IsTrustedCdn(uri.Host))
                return uri.AbsoluteUri;
        return null;
    }
    public static bool IsTrustedCdn(string host) => new[] { "tiktokcdn.com", "tiktokcdn-us.com", "tiktokcdn-eu.com", "tiktokv.com", "byteoversea.com", "ibytedtos.com" }
        .Any(domain => host.Equals(domain, StringComparison.OrdinalIgnoreCase) || host.EndsWith("." + domain, StringComparison.OrdinalIgnoreCase));
    [GeneratedRegex(@"\d{10,25}")]
    private static partial Regex PostId();
}
