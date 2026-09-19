using System.Diagnostics;
using System.Text.Json;

namespace DropDrive.Windows.Services;

public static class MediaValidator
{
    public static async Task ValidateAsync(string path, bool audioOnly, string tools, CancellationToken token)
    {
        if (!File.Exists(path) || new FileInfo(path).Length == 0) throw new IOException("ไม่พบไฟล์ที่ดาวน์โหลด หรือไฟล์ว่าง");
        using var deadline = CancellationTokenSource.CreateLinkedTokenSource(token);
        deadline.CancelAfter(TimeSpan.FromSeconds(20));
        var info = new ProcessStartInfo(Path.Combine(tools, "ffprobe.exe")) { UseShellExecute = false, CreateNoWindow = true, RedirectStandardOutput = true, RedirectStandardError = true };
        foreach (var argument in new[] { "-v", "error", "-show_entries", "format=duration:stream=codec_type", "-of", "json", "-i", path }) info.ArgumentList.Add(argument);
        using var process = Process.Start(info) ?? throw new IOException("เปิดตัวตรวจสอบไฟล์ไม่ได้");
        using var registration = deadline.Token.Register(() => { try { process.Kill(true); } catch (InvalidOperationException) { } });
        var output = process.StandardOutput.ReadToEndAsync(deadline.Token);
        var errors = process.StandardError.ReadToEndAsync(deadline.Token);
        await Task.WhenAll(output, errors, process.WaitForExitAsync(deadline.Token));
        if (process.ExitCode != 0 || !IsPlayable(output.Result, audioOnly))
            throw new IOException("ดาวน์โหลดแล้วแต่ตรวจสอบการเล่นไม่ผ่าน ไฟล์อาจไม่สมบูรณ์");
    }
    public static bool IsPlayable(string json, bool audioOnly)
    {
        using var document = JsonDocument.Parse(json);
        var root = document.RootElement;
        return root.TryGetProperty("format", out var format) && format.TryGetProperty("duration", out var duration) &&
            double.TryParse(duration.ToString(), System.Globalization.NumberStyles.Float, System.Globalization.CultureInfo.InvariantCulture, out var seconds) && double.IsFinite(seconds) && seconds > 0 &&
            root.TryGetProperty("streams", out var streams) && streams.EnumerateArray().Any(stream =>
                stream.TryGetProperty("codec_type", out var type) && type.GetString() == (audioOnly ? "audio" : "video"));
    }
}
