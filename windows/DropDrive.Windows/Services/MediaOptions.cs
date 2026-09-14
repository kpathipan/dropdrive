using System.Globalization;
using DropDrive.Windows.Models;

namespace DropDrive.Windows.Services;

public static class MediaOptions
{
    public static readonly string[] Qualities = ["อัตโนมัติ", "คุณภาพสูงสุด", "1080p", "720p", "ไฟล์เล็ก · 480p", "เสียง MP3"];
    public static readonly string[] Subtitles = ["ไม่บันทึกคำบรรยาย", "ไฟล์คำบรรยายแยก", "ฝังคำบรรยายในวิดีโอ"];

    public static double? ParseTime(string text)
    {
        if (string.IsNullOrWhiteSpace(text)) return null;
        var parts = text.Trim().Split(':');
        if (parts.Length > 3) throw new FormatException("ใช้เวลาเป็น วินาที หรือ ชั่วโมง:นาที:วินาที");
        double seconds = 0;
        for (var index = 0; index < parts.Length; index++)
        {
            var part = parts[index];
            if (!double.TryParse(part, NumberStyles.AllowDecimalPoint, CultureInfo.InvariantCulture, out var value) ||
                !double.IsFinite(value) || value < 0 || (index > 0 && value >= 60))
                throw new FormatException("เวลาไม่ถูกต้อง เช่น 0:30 หรือ 90");
            seconds = seconds * 60 + value;
        }
        return seconds;
    }

    public static string? Section(DownloadItem item)
    {
        var start = ParseTime(item.ClipStart);
        var end = ParseTime(item.ClipEnd);
        if (start is null && end is null) return null;
        if (end is not null && end <= (start ?? 0)) throw new FormatException("เวลาสิ้นสุดต้องมากกว่าเวลาเริ่ม");
        return $"*{(start ?? 0).ToString(CultureInfo.InvariantCulture)}-{(end?.ToString(CultureInfo.InvariantCulture) ?? "inf")}";
    }

    public static List<string> Arguments(DownloadItem item, string destination, string toolsPath)
    {
        var args = new List<string> {
            "--newline", "--windows-filenames", "--continue", "--no-overwrites",
            "--concurrent-fragments", "4", "--retries", "3", "--fragment-retries", "3",
            "--socket-timeout", "20", "--ffmpeg-location", toolsPath,
            "--progress-template", "download:DDPROGRESS:%(progress._percent_str)s|%(progress._speed_str)s|%(progress._eta_str)s",
            "--no-simulate", "--print", "after_move:DDPATH:%(filepath)s", "--progress",
            "-P", destination, "-o", OutputTemplate(item)
        };
        if (!item.IsCollection) args.Add("--no-playlist");
        if (item.IsCollection && item.Entries.Count > 0)
        {
            var selected = item.Entries.Where(entry => entry.Selected).Select(entry => entry.Index).ToArray();
            if (selected.Length == 0) throw new InvalidOperationException("เลือกอย่างน้อย 1 ไฟล์");
            args.AddRange(["--playlist-items", string.Join(',', selected)]);
        }
        if (item.BandwidthLimit is > 0) args.AddRange(["--limit-rate", item.BandwidthLimit.Value.ToString(CultureInfo.InvariantCulture)]);
        if (Section(item) is { } section) args.AddRange(["--download-sections", section, "--force-keyframes-at-cuts"]);
        if (item.AudioOnly || item.Quality == 5)
            args.AddRange(["-f", "ba/b", "-x", "--audio-format", "mp3", "--audio-quality", "0", "--embed-metadata", "--embed-thumbnail"]);
        else
        {
            var cap = item.Quality switch { 2 => "[height<=1080]", 3 => "[height<=720]", 4 => "[height<=480]", _ => "" };
            var format = item.CompatibleVideo
                ? $"bv{cap}[vcodec^=avc1]+ba[acodec^=mp4a]/b{cap}[ext=mp4]/bv*{cap}+ba/b{cap}"
                : $"bv*{cap}+ba/b{cap}";
            args.AddRange(["-f", format, "--merge-output-format", item.CompatibleVideo ? "mp4" : "mkv"]);
        }
        if (item.SubtitleMode > 0)
        {
            args.AddRange(["--write-subs", "--write-auto-subs", "--sub-langs", "th.*,en.*"]);
            args.AddRange(item.SubtitleMode == 2 ? ["--embed-subs"] : ["--sub-format", "srt/best", "--convert-subs", "srt"]);
        }
        args.Add("--embed-chapters");
        if (item.SplitChapters) args.Add("--split-chapters");
        if (item.SaveThumbnail) args.AddRange(["--write-thumbnail", "--convert-thumbnails", "jpg"]);
        var deno = Path.Combine(toolsPath, "deno.exe");
        if (File.Exists(deno)) args.AddRange(["--js-runtimes", $"deno:{deno}"]);
        args.AddRange(["--", item.Url]);
        return args;
    }

    // A stable job suffix resumes the same task, but an explicit repeat creates
    // a new file without overwriting a user's earlier download.
    public static string OutputTemplate(DownloadItem item)
    {
        var title = item.IsCollection ? "%(title).140s" : SafeName(item.Name).Replace("%", "%%");
        return $"{title} [%(id)s]-{item.Id.ToString("N")[..6]}.%(ext)s";
    }

    public static string SafeName(string name)
    {
        var invalid = "<>:\"/\\|?*".ToCharArray();
        var safe = new string(name.Select(c => c < 32 || invalid.Contains(c) ? '_' : c).ToArray()).Trim().TrimEnd('.');
        if (string.IsNullOrWhiteSpace(safe)) safe = "ดาวน์โหลด";
        var stem = safe.Split('.')[0].ToUpperInvariant();
        if (new[] { "CON", "PRN", "AUX", "NUL", "COM1", "COM2", "COM3", "COM4", "COM5", "COM6", "COM7", "COM8", "COM9", "LPT1", "LPT2", "LPT3", "LPT4", "LPT5", "LPT6", "LPT7", "LPT8", "LPT9" }.Contains(stem)) safe = "_" + safe;
        return safe.Length <= 140 ? safe : safe[..140];
    }
}
