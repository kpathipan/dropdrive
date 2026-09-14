using System.Diagnostics;
using System.Globalization;
using System.Text;
using System.Text.RegularExpressions;
using Avalonia.Threading;
using DropDrive.Windows.Models;

namespace DropDrive.Windows.Services;

public sealed partial class DownloadService
{
    private readonly HttpClient _client = new();

    public async Task DownloadAsync(DownloadItem item, string destination, CancellationToken cancellationToken)
    {
        Directory.CreateDirectory(destination);
        TransferGuard.EnsureSpace(destination, item.EstimatedBytes);
        item.Status = "Downloading";
        item.CanCancel = true;
        item.CanRetry = false;
        if (IsDirectFile(item.Url)) await DownloadDirectAsync(item, destination, cancellationToken);
        else await DownloadMediaAsync(item, destination, cancellationToken);
        item.Progress = 100;
        item.Status = "Complete";
        item.Detail = item.AudioOnly ? "บันทึกเป็น MP3 แล้ว" : "บันทึกในโฟลเดอร์ปลายทางแล้ว";
        item.CanCancel = false;
    }

    private async Task DownloadDirectAsync(DownloadItem item, string destination, CancellationToken cancellationToken)
    {
        using var response = await _client.GetAsync(item.Url, HttpCompletionOption.ResponseHeadersRead, cancellationToken);
        response.EnsureSuccessStatusCode();
        var total = response.Content.Headers.ContentLength;
        var name = Path.GetFileName(Uri.UnescapeDataString(new Uri(item.Url).LocalPath));
        if (string.IsNullOrWhiteSpace(name)) name = "download";
        item.Name = name;
        var finalPath = UniquePath(destination, name);
        var partialPath = finalPath + ".part";
        try
        {
            await using var input = await response.Content.ReadAsStreamAsync(cancellationToken);
            await using (var output = File.Create(partialPath))
            {
                var buffer = new byte[128 * 1024];
                long received = 0;
                int read;
                while ((read = await input.ReadAsync(buffer, cancellationToken)) > 0)
                {
                    await output.WriteAsync(buffer.AsMemory(0, read), cancellationToken);
                    received += read;
                    if (total > 0) item.Progress = received * 100d / total.Value;
                }
            }
            File.Move(partialPath, finalPath);
        }
        catch { try { File.Delete(partialPath); } catch { } throw; }
    }

    private static async Task DownloadMediaAsync(DownloadItem item, string destination, CancellationToken cancellationToken)
    {
        var tool = Path.Combine(AppContext.BaseDirectory, "Tools", "yt-dlp.exe");
        if (!File.Exists(tool)) throw new FileNotFoundException("ไม่พบตัวดาวน์โหลด กรุณาติดตั้ง DropDrive ใหม่", tool);
        var arguments = new List<string> {
            "--newline", "--no-playlist", "--windows-filenames", "--concurrent-fragments", "4",
            "--retries", "3", "--fragment-retries", "3",
            "--progress-template", "download:%(progress._percent_str)s",
            "-P", destination, "-o", "%(title).180s [%(id)s].%(ext)s"
        };
        if (item.AudioOnly)
        {
            arguments.AddRange(["-f", "bestaudio/best", "-x", "--audio-format", "mp3", "--audio-quality", "2",
                "--ffmpeg-location", Path.Combine(AppContext.BaseDirectory, "Tools")]);
        }
        else arguments.AddRange(["-f", "bv*+ba/b"]);
        arguments.Add(item.Url);

        var startInfo = new ProcessStartInfo(tool) {
            UseShellExecute = false, RedirectStandardOutput = true,
            RedirectStandardError = true, CreateNoWindow = true
        };
        foreach (var argument in arguments) startInfo.ArgumentList.Add(argument);
        using var process = Process.Start(startInfo) ?? throw new InvalidOperationException("ไม่สามารถเริ่มตัวดาวน์โหลดได้");
        var errors = new StringBuilder();
        process.OutputDataReceived += (_, e) => UpdateProgress(item, e.Data);
        process.ErrorDataReceived += (_, e) => {
            UpdateProgress(item, e.Data);
            if (!string.IsNullOrWhiteSpace(e.Data) && errors.Length < 16_000) errors.AppendLine(e.Data);
        };
        process.BeginOutputReadLine();
        process.BeginErrorReadLine();
        using var cancellation = cancellationToken.Register(() => {
            try { if (!process.HasExited) process.Kill(entireProcessTree: true); } catch { }
        });
        await process.WaitForExitAsync(cancellationToken);
        if (process.ExitCode != 0) throw new InvalidOperationException(FriendlyError(errors.ToString()));
    }

    private static void UpdateProgress(DownloadItem item, string? line)
    {
        var match = PercentRegex().Match(line ?? "");
        if (match.Success && double.TryParse(match.Groups[1].Value, NumberStyles.Float,
            CultureInfo.InvariantCulture, out var value))
            Dispatcher.UIThread.Post(() => item.Progress = value);
    }

    public static bool IsDirectFile(string url) =>
        Uri.TryCreate(url, UriKind.Absolute, out var uri) &&
        new[] { ".zip", ".pdf", ".mp4", ".mp3", ".mov", ".jpg", ".png" }
            .Contains(Path.GetExtension(uri.AbsolutePath), StringComparer.OrdinalIgnoreCase);

    public static string FriendlyError(string? detail)
    {
        var text = detail ?? "";
        if (text.Contains("Unsupported URL", StringComparison.OrdinalIgnoreCase))
            return "ยังไม่รองรับเว็บไซต์นี้";
        if (text.Contains("Private video", StringComparison.OrdinalIgnoreCase) ||
            text.Contains("Sign in", StringComparison.OrdinalIgnoreCase) ||
            text.Contains("login", StringComparison.OrdinalIgnoreCase))
            return "รายการนี้เป็นส่วนตัวหรือต้องมีสิทธิ์เข้าถึง";
        if (text.Contains("not available", StringComparison.OrdinalIgnoreCase) ||
            text.Contains("removed", StringComparison.OrdinalIgnoreCase))
            return "รายการนี้ใช้งานไม่ได้หรือถูกลบแล้ว";
        if (text.Contains("HTTP Error 403", StringComparison.OrdinalIgnoreCase))
            return "ถูกปฏิเสธการเข้าถึง กรุณาตรวจสิทธิ์ของลิงก์หรืออัปเดต DropDrive";
        return "ดาวน์โหลดลิงก์นี้ไม่ได้ กรุณาตรวจลิงก์และการเชื่อมต่ออินเทอร์เน็ต";
    }

    private static string UniquePath(string folder, string name)
    {
        var path = Path.Combine(folder, name);
        if (!File.Exists(path)) return path;
        var stem = Path.GetFileNameWithoutExtension(name);
        var extension = Path.GetExtension(name);
        for (var index = 2; ; index++) {
            path = Path.Combine(folder, $"{stem} ({index}){extension}");
            if (!File.Exists(path)) return path;
        }
    }

    [GeneratedRegex(@"([0-9]+(?:\.[0-9]+)?)%")]
    private static partial Regex PercentRegex();
}
