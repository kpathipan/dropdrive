using System.Text.Json;
using System.Text.RegularExpressions;

namespace DropDrive.Windows.Services;

public sealed partial class TikTokMediaService
{
    private static readonly HttpClient Client = new() { Timeout = TimeSpan.FromSeconds(8) };
    public static bool IsTikTok(string url) => Uri.TryCreate(url, UriKind.Absolute, out var uri) &&
        (uri.Host == "tiktok.com" || uri.Host.EndsWith(".tiktok.com", StringComparison.OrdinalIgnoreCase));

    public static async Task<MediaAnalysis?> AnalyzeFastAsync(string url, CancellationToken token)
    {
        if (!IsTikTok(url) || !new Uri(url).AbsolutePath.Contains("/video/", StringComparison.Ordinal)) return null;
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
        var original = OriginalUrl(await response.Content.ReadAsStringAsync(token), quality);
        return original ?? throw new InvalidOperationException("TikTok ยังไม่ส่งวิดีโอต้นฉบับที่ไม่มีลายน้ำ ลองใหม่อีกครั้ง");
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
                (uri.Host == "tiktokcdn.com" || uri.Host.EndsWith(".tiktokcdn.com", StringComparison.Ordinal) || uri.Host == "tiktokv.com" || uri.Host.EndsWith(".tiktokv.com", StringComparison.Ordinal)))
                return uri.AbsoluteUri;
        return null;
    }
    [GeneratedRegex(@"\d{10,25}")]
    private static partial Regex PostId();
}
