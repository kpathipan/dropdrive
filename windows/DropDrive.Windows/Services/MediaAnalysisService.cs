using System.Diagnostics;
using System.Text.Json;
using DropDrive.Windows.Models;

namespace DropDrive.Windows.Services;

public sealed record MediaAnalysis(string Title, string Source, string Detail, string? ThumbnailUrl,
    long? EstimatedBytes, bool IsMedia = true, bool IsCollection = false, List<MediaEntry>? Entries = null,
    string? AccountId = null, string? MimeType = null, string? ResourceKey = null, string? DriveFileId = null);

public sealed class MediaAnalysisService
{
    private readonly GoogleAccountService? _accounts;
    // Opt-in diagnostics for isolated public-fixture checks, never persisted by the app.
    public Action<string>? DiagnosticSink { get; init; }
    public MediaAnalysisService(GoogleAccountService? accounts = null) => _accounts = accounts;
    public async Task<MediaAnalysis> AnalyzeAsync(string url, CancellationToken cancellationToken)
    {
        var uri = new Uri(url);
        if (PublicDriveService.IsDriveUrl(url)) return _accounts?.Accounts.Count > 0
            ? await new GoogleDriveService(_accounts).AnalyzeAsync(url, cancellationToken)
            : await new PublicDriveService().AnalyzeAsync(url, cancellationToken);
        if (await TikTokMediaService.AnalyzeFastAsync(url, cancellationToken) is { } quick) return quick;
        if (DownloadService.IsDirectFile(url))
            return new MediaAnalysis(Path.GetFileName(uri.LocalPath), uri.Host, "ไฟล์โดยตรง", null, null, false);
        var tool = Path.Combine(AppContext.BaseDirectory, "Tools", "yt-dlp.exe");
        if (!File.Exists(tool)) throw new FileNotFoundException("ไม่พบตัววิเคราะห์ลิงก์ กรุณาติดตั้ง DropDrive ใหม่");
        var startInfo = new ProcessStartInfo(tool) {
            UseShellExecute = false, RedirectStandardOutput = true,
            RedirectStandardError = true, CreateNoWindow = true
        };
        var args = new List<string> { "--ignore-config", "--dump-single-json", "--skip-download", "--flat-playlist", "--socket-timeout", "15", "--retries", "1" };
        if (uri.AbsolutePath != "/playlist" && (uri.Host.EndsWith("youtube.com", StringComparison.OrdinalIgnoreCase) || uri.Host == "youtu.be"))
            args.Add("--no-playlist");
        MediaOptions.AddRuntimeArguments(args, Path.Combine(AppContext.BaseDirectory, "Tools"));
        foreach (var argument in args.Concat(["--", url])) startInfo.ArgumentList.Add(argument);
        using var process = Process.Start(startInfo) ?? throw new InvalidOperationException("ไม่สามารถเริ่มวิเคราะห์ลิงก์ได้");
        using var registration = cancellationToken.Register(() => { try { process.Kill(true); } catch (InvalidOperationException) { } });
        var outputTask = process.StandardOutput.ReadToEndAsync(cancellationToken);
        var errorTask = process.StandardError.ReadToEndAsync(cancellationToken);
        await process.WaitForExitAsync(cancellationToken);
        var output = await outputTask;
        var error = await errorTask;
        if (process.ExitCode != 0)
        {
            DiagnosticSink?.Invoke(error);
            throw new InvalidOperationException(DownloadService.FriendlyError(error));
        }
        return Parse(output, uri.Host);
    }

    public static MediaAnalysis Parse(string output, string host)
    {
        using var json = JsonDocument.Parse(output);
        var root = json.RootElement;
        var title = String(root, "title") ?? host;
        var extractor = String(root, "extractor_key") ?? String(root, "extractor") ?? host;
        var seconds = Number(root, "duration");
        var duration = seconds is > 0 and < 604800
            ? TimeSpan.FromSeconds(seconds.Value).ToString(seconds >= 3600 ? @"h\:mm\:ss" : @"m\:ss") : null;
        List<MediaEntry> entries = [];
        if (root.TryGetProperty("entries", out var list) && list.ValueKind == JsonValueKind.Array)
        {
            var index = 0;
            foreach (var entry in list.EnumerateArray())
            {
                index++;
                if (entry.ValueKind != JsonValueKind.Object) continue;
                entries.Add(new MediaEntry { Index = index, Title = String(entry, "title") ?? $"ไฟล์ {index}",
                    StableId = String(entry, "id"),
                    Url = String(entry, "webpage_url") ?? String(entry, "url"),
                    ThumbnailUrl = Thumbnail(entry), Size = Size(entry),
                    Kind = String(entry, "ext") is "jpg" or "png" or "webp" ? "image" : "video" });
            }
        }
        var collection = root.TryGetProperty("entries", out list) && list.ValueKind == JsonValueKind.Array;
        if (collection && entries.Count == 0) throw new InvalidOperationException("ไม่พบไฟล์ที่เข้าถึงได้ในรายการนี้");
        var detail = collection ? $"{extractor} · {entries.Count} ไฟล์" : duration is null ? extractor : $"{extractor} · {duration}";
        return new MediaAnalysis(title, extractor, detail, Thumbnail(root), Size(root), true, collection, entries);
    }

    private static string? Thumbnail(JsonElement root)
    {
        if (String(root, "thumbnail") is { } direct) return direct;
        if (root.TryGetProperty("thumbnails", out var list) && list.ValueKind == JsonValueKind.Array)
            return list.EnumerateArray().Select(entry => String(entry, "url")).LastOrDefault(url => url != null);
        return null;
    }
    private static long? Size(JsonElement root) =>
        (Number(root, "filesize") ?? Number(root, "filesize_approx")) is > 0 and < long.MaxValue and var value ? (long)value : null;
    private static double? Number(JsonElement root, string name) =>
        root.ValueKind == JsonValueKind.Object && root.TryGetProperty(name, out var value) &&
        value.ValueKind == JsonValueKind.Number && value.TryGetDouble(out var number) && double.IsFinite(number) ? number : null;
    private static string? String(JsonElement root, string name) =>
        root.ValueKind == JsonValueKind.Object && root.TryGetProperty(name, out var value) && value.ValueKind == JsonValueKind.String ? value.GetString() : null;
}
