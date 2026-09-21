using DropDrive.Windows.Models;
using DropDrive.Windows.Services;

internal static class ProviderChecks
{
    public static async Task RunAsync(string folder)
    {
        var tools = Path.Combine(AppContext.BaseDirectory, "Tools");
        foreach (var name in new[] { "yt-dlp.exe", "ffmpeg.exe", "ffprobe.exe", "qjs.exe" })
            if (!File.Exists(Path.Combine(tools, name))) throw new FileNotFoundException("Missing live-test tool: " + name);
        // Public test URLs from yt-dlp's upstream extractor regression fixtures.
        var probes = new Dictionary<string, string> {
            ["YouTube"] = "https://www.youtube.com/watch?v=jNQXAC9IVRw",
            ["TikTok"] = "https://www.tiktok.com/@leenabhushan/video/6748451240264420610",
            ["Instagram"] = "https://www.instagram.com/reel/Chunk8-jurw/",
            ["Facebook"] = "https://www.facebook.com/radiokicksfm/videos/3676516585958356/"
        };
        var report = new List<string> { $"Live provider probes · {DateTimeOffset.UtcNow:O}", "No login/cookies. Failures are reported, not interpreted as passing downloads." };
        foreach (var (provider, url) in probes)
        {
            using var deadline = new CancellationTokenSource(TimeSpan.FromSeconds(40));
            var phase = "analysis";
            var diagnostic = "";
            void Capture(string detail)
            {
                // Public fixtures only; strip URLs (including signed CDN query strings)
                // and keep a bounded tail. No browser cookies or real accounts are used.
                diagnostic = System.Text.RegularExpressions.Regex.Replace(detail, @"https?://\S+", "[URL]");
                if (diagnostic.Length > 3000) diagnostic = diagnostic[^3000..];
            }
            try
            {
                var result = await new MediaAnalysisService { DiagnosticSink = Capture }.AnalyzeAsync(url, deadline.Token);
                phase = "download";
                var destination = Path.Combine(folder, provider); Directory.CreateDirectory(destination);
                var item = new DownloadItem { Url = url, Name = "DropDrive public probe", IsMedia = result.IsMedia,
                    IsCollection = result.IsCollection, Entries = result.Entries ?? [], Source = result.Source,
                    ThumbnailUrl = result.ThumbnailUrl, Destination = destination, AudioOnly = provider == "TikTok", Quality = provider == "TikTok" ? 5 : 4,
                    ClipStart = "0", ClipEnd = "2", CompatibleVideo = true };
                await new DownloadService { DiagnosticSink = Capture }.DownloadAsync(item, destination, deadline.Token);
                report.Add($"PASS {provider}: production analysis, download and playback validation");
            }
            catch (Exception error)
            {
                report.Add($"UNAVAILABLE {provider} ({phase}): {error.GetType().Name}: {error.Message}");
                if (diagnostic.Length > 0) report.Add(diagnostic.Trim());
            }
        }
        var evidence = Path.GetFullPath("windows/artifacts/provider-checks.txt");
        Directory.CreateDirectory(Path.GetDirectoryName(evidence)!);
        await File.WriteAllLinesAsync(evidence, report);
        foreach (var line in report) Console.WriteLine(line);
    }
}
