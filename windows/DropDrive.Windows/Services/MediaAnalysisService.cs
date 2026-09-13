using System.Diagnostics;
using System.Text.Json;

namespace DropDrive.Windows.Services;

public sealed record MediaAnalysis(string Title, string Source, string Detail, string? ThumbnailUrl, long? EstimatedBytes);

public sealed class MediaAnalysisService
{
    public async Task<MediaAnalysis> AnalyzeAsync(string url, CancellationToken cancellationToken)
    {
        var uri = new Uri(url);
        if (DownloadService.IsDirectFile(url))
            return new MediaAnalysis(Path.GetFileName(uri.LocalPath), uri.Host, "Direct file", null, null);

        var tool = Path.Combine(AppContext.BaseDirectory, "Tools", "yt-dlp.exe");
        if (!File.Exists(tool)) return new MediaAnalysis(uri.Host, uri.Host, "Media link", null, null);
        var startInfo = new ProcessStartInfo(tool) {
            UseShellExecute = false, RedirectStandardOutput = true,
            RedirectStandardError = true, CreateNoWindow = true
        };
        foreach (var argument in new[] { "--dump-single-json", "--no-playlist", "--skip-download", url })
            startInfo.ArgumentList.Add(argument);
        using var process = Process.Start(startInfo) ?? throw new InvalidOperationException("Could not start link analysis.");
        var outputTask = process.StandardOutput.ReadToEndAsync(cancellationToken);
        var errorTask = process.StandardError.ReadToEndAsync(cancellationToken);
        await process.WaitForExitAsync(cancellationToken);
        var output = await outputTask;
        var error = await errorTask;
        if (process.ExitCode != 0) throw new InvalidOperationException(DownloadService.FriendlyError(error));
        using var json = JsonDocument.Parse(output);
        var root = json.RootElement;
        var title = GetString(root, "title") ?? uri.Host;
        var extractor = GetString(root, "extractor_key") ?? GetString(root, "extractor") ?? uri.Host;
        var duration = root.TryGetProperty("duration", out var durationValue) && durationValue.TryGetDouble(out var seconds)
            ? TimeSpan.FromSeconds(seconds).ToString(seconds >= 3600 ? @"h\:mm\:ss" : @"m\:ss") : null;
        var detail = duration is null ? extractor : $"{extractor} · {duration}";
        long? estimatedBytes = null;
        if (root.TryGetProperty("filesize_approx", out var size) && size.TryGetInt64(out var parsed)) estimatedBytes = parsed;
        else if (root.TryGetProperty("filesize", out size) && size.TryGetInt64(out parsed)) estimatedBytes = parsed;
        return new MediaAnalysis(title, extractor, detail, GetString(root, "thumbnail"), estimatedBytes);
    }

    private static string? GetString(JsonElement root, string name) =>
        root.TryGetProperty(name, out var value) && value.ValueKind == JsonValueKind.String ? value.GetString() : null;
}
