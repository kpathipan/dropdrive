using System.Diagnostics;
using System.Globalization;
using System.Net;
using System.Net.Http.Headers;
using Avalonia.Threading;
using DropDrive.Windows.Models;

namespace DropDrive.Windows.Services;

public sealed class DownloadService
{
    private readonly HttpClient _client;
    public Action? Checkpoint { get; set; }
    public DownloadService(HttpClient? client = null) => _client = client ?? new() { Timeout = Timeout.InfiniteTimeSpan };

    public async Task DownloadAsync(DownloadItem item, string destination, CancellationToken cancellationToken)
    {
        // Never recreate a missing user-selected destination (e.g. an unplugged drive).
        TransferGuard.EnsureSpace(destination, item.IsMedia ? null : item.EstimatedBytes);
        item.Status = "Downloading"; item.CanCancel = true; item.CanRetry = false;
        if (item.IsDrive && item.IsCollection) await DownloadDriveFolderAsync(item, destination, cancellationToken);
        else if (item.IsDrive || IsDirectFile(item.Url)) await DownloadDirectAsync(item, destination, cancellationToken);
        else await DownloadMediaAsync(item, destination, cancellationToken);
        item.Progress = 100; item.Status = "Complete"; item.CanCancel = false;
        item.Detail = item.AudioOnly ? "บันทึกเป็น MP3 แล้ว" : "บันทึกในโฟลเดอร์ปลายทางแล้ว";
    }

    private async Task DownloadDirectAsync(DownloadItem item, string destination, CancellationToken cancellationToken)
    {
        var name = MediaOptions.SafeName(item.Name == "ดาวน์โหลด" ? Path.GetFileName(Uri.UnescapeDataString(new Uri(item.Url).LocalPath)) : item.Name);
        // Resume only our own job's partial in the originally chosen folder.
        var target = item.TargetPath;
        if (target == null || !string.Equals(Path.GetDirectoryName(target), destination, StringComparison.OrdinalIgnoreCase))
        {
            target = UniquePath(destination, name);
            item.TargetPath = target;
            item.PartialPath = Path.Combine(destination, $".dropdrive-{item.Id:N}.part");
            item.EntityTag = null;
        }
        var partial = item.PartialPath!;
        var offset = File.Exists(partial) && item.EntityTag != null ? new FileInfo(partial).Length : 0;
        var downloadUrl = item.IsDrive ? PublicDriveService.DownloadUrl(item.Url) : item.Url;
        async Task<HttpResponseMessage> Request(string url)
        {
            using var request = new HttpRequestMessage(HttpMethod.Get, url);
            if (offset > 0)
            {
                request.Headers.Range = new RangeHeaderValue(offset, null);
                request.Headers.TryAddWithoutValidation("If-Range", item.EntityTag);
            }
            return await _client.SendAsync(request, HttpCompletionOption.ResponseHeadersRead, cancellationToken);
        }
        var firstResponse = await Request(downloadUrl);
        if (item.IsDrive && firstResponse.Content.Headers.ContentType?.MediaType == "text/html")
        {
            using (firstResponse)
            {
                await firstResponse.Content.LoadIntoBufferAsync(2_000_000, cancellationToken);
                downloadUrl = PublicDriveService.ConfirmationUrl(await firstResponse.Content.ReadAsStringAsync(cancellationToken));
            }
            firstResponse = await Request(downloadUrl);
        }
        using var response = firstResponse;
        if (item.IsDrive && response.Content.Headers.ContentType?.MediaType == "text/html")
            throw new InvalidOperationException("Drive ไม่ได้ส่งไฟล์กลับมา กรุณาตรวจสิทธิ์หรือโควตาของไฟล์");
        if (response.StatusCode == HttpStatusCode.RequestedRangeNotSatisfiable)
        {
            // A changed remote object cannot be resumed safely. Keep the partial
            // for this attempt, and explicitly restart it on the next retry.
            item.EntityTag = null;
            throw new IOException("ไฟล์ต้นทางเปลี่ยนไป กดลองใหม่เพื่อเริ่มไฟล์นี้อีกครั้ง");
        }
        response.EnsureSuccessStatusCode();
        var range = response.Content.Headers.ContentRange;
        var append = offset > 0 && response.StatusCode == HttpStatusCode.PartialContent && range?.From == offset;
        if (response.StatusCode == HttpStatusCode.PartialContent && !append)
            throw new IOException("ข้อมูลดาวน์โหลดต่อไม่ตรงกัน กรุณาลองใหม่");
        if (!append) offset = 0;
        var total = append ? range?.Length : response.Content.Headers.ContentLength;
        TransferGuard.EnsureSpace(destination, total is { } size ? Math.Max(0, size - offset) : null);
        item.EntityTag = response.Headers.ETag is { IsWeak: false } etag ? etag.ToString() : null;
        Checkpoint?.Invoke();
        await using var input = await response.Content.ReadAsStreamAsync(cancellationToken);
        await using (var output = new FileStream(partial, append ? FileMode.Append : FileMode.Create, FileAccess.Write, FileShare.Read, 128 * 1024, true))
        {
            var buffer = new byte[128 * 1024];
            long received = offset, sessionBytes = 0;
            var clock = Stopwatch.StartNew();
            var lastUpdate = TimeSpan.Zero;
            int read;
            while ((read = await input.ReadAsync(buffer, cancellationToken)) > 0)
            {
                await output.WriteAsync(buffer.AsMemory(0, read), cancellationToken);
                received += read; sessionBytes += read;
                if (item.BandwidthLimit is > 0)
                {
                    var delay = TimeSpan.FromSeconds(sessionBytes / (double)item.BandwidthLimit.Value) - clock.Elapsed;
                    if (delay > TimeSpan.Zero) await Task.Delay(delay, cancellationToken);
                }
                if (clock.Elapsed - lastUpdate < TimeSpan.FromMilliseconds(200)) continue;
                lastUpdate = clock.Elapsed;
                var rate = sessionBytes / Math.Max(0.001, clock.Elapsed.TotalSeconds);
                if (total > 0) item.Progress = Math.Min(99.9, received * 100d / total.Value);
                item.Speed = rate >= 1_048_576 ? $"{rate / 1_048_576:0.0} MB/s" : $"{rate / 1024:0} KB/s";
                item.Eta = total > received ? $"{Math.Ceiling((total.Value - received) / rate):0}s" : "—";
                item.Detail = "กำลังบันทึกไฟล์";
            }
            if (total is > 0 && received != total) throw new IOException("การเชื่อมต่อขาดหาย กดดาวน์โหลดต่อได้");
        }
        if (File.Exists(target)) target = UniquePath(destination, name);
        File.Move(partial, target);
        item.ResultPath = target; item.PartialPath = null; item.TargetPath = target;
    }

    private async Task DownloadDriveFolderAsync(DownloadItem item, string destination, CancellationToken token)
    {
        var selected = item.Entries.Where(entry => entry.Selected).ToArray();
        if (selected.Length == 0) throw new InvalidOperationException("เลือกอย่างน้อย 1 ไฟล์");
        var count = 0;
        foreach (var entry in selected)
        {
            token.ThrowIfCancellationRequested();
            // The chosen folder receives the contents; do not wrap it in another
            // folder with the same name. Only original nested folders are created.
            var root = Path.GetFullPath(destination).TrimEnd(Path.DirectorySeparatorChar) + Path.DirectorySeparatorChar;
            var folder = Path.GetFullPath(Path.Combine(destination, entry.RelativeFolder));
            if (folder != Path.GetFullPath(destination) && !folder.StartsWith(root, StringComparison.OrdinalIgnoreCase))
                throw new IOException("ชื่อโฟลเดอร์ต้นทางไม่ปลอดภัย");
            TransferGuard.EnsureSpace(destination, entry.Size);
            Directory.CreateDirectory(folder);
            entry.Transfer ??= new DownloadItem { Url = entry.Url!, Name = entry.Title, IsDrive = true, IsMedia = false, Destination = folder };
            var child = entry.Transfer;
            if (child.Status == "Complete" && File.Exists(child.ResultPath) && child.Destination == folder) { count++; item.Progress = count * 100d / selected.Length; continue; }
            child.Destination = folder; child.BandwidthLimit = item.BandwidthLimit;
            item.Detail = $"{count + 1}/{selected.Length} · {entry.Title}";
            void Progress(object? sender, System.ComponentModel.PropertyChangedEventArgs args)
            {
                item.Progress = Math.Min(99.9, (count + child.Progress / 100) * 100 / selected.Length);
                item.Speed = child.Speed; item.Eta = child.Eta;
            }
            child.PropertyChanged += Progress;
            try { await DownloadAsync(child, folder, token); }
            finally { child.PropertyChanged -= Progress; Checkpoint?.Invoke(); }
            count++;
        }
        item.ResultPath = destination;
    }

    private static async Task DownloadMediaAsync(DownloadItem item, string destination, CancellationToken cancellationToken)
    {
        var toolsPath = Path.Combine(AppContext.BaseDirectory, "Tools");
        var tool = Path.Combine(toolsPath, "yt-dlp.exe");
        if (!File.Exists(tool)) throw new FileNotFoundException("ไม่พบตัวดาวน์โหลด กรุณาติดตั้ง DropDrive ใหม่");
        var startInfo = new ProcessStartInfo(tool) { UseShellExecute = false, RedirectStandardOutput = true, RedirectStandardError = true, CreateNoWindow = true };
        var arguments = MediaOptions.Arguments(item, destination, toolsPath);
        string? infoPath = null;
        if (TikTokMediaService.IsTikTok(item.Url) && !item.IsCollection)
        {
            string original;
            try { original = await TikTokMediaService.ResolveOriginalAsync(item.Url, item.Quality, cancellationToken); }
            catch (Exception error) when (error is HttpRequestException or TaskCanceledException && !cancellationToken.IsCancellationRequested)
            { throw new InvalidOperationException("เชื่อมต่อ TikTok ไม่ได้ในขณะนี้ ลองใหม่อีกครั้ง"); }
            // A temporary info document preserves the chosen title/cover for MP3
            // while skipping the slow web-page extraction. Always removed below.
            infoPath = Path.Combine(Path.GetTempPath(), $"dropdrive-info-{Guid.NewGuid():N}.json");
            var metadata = new { id = item.Id.ToString("N"), title = item.Name, url = original, ext = "mp4",
                webpage_url = item.Url, thumbnail = item.ThumbnailUrl, extractor = "TikTok",
                http_headers = new { Referer = "https://www.tiktok.com/" } };
            try { await File.WriteAllTextAsync(infoPath, System.Text.Json.JsonSerializer.Serialize(metadata), cancellationToken); }
            catch { File.Delete(infoPath); throw; }
            arguments.RemoveRange(arguments.Count - 2, 2);
            arguments.AddRange(["--load-info-json", infoPath]);
        }
        try
        {
        foreach (var argument in arguments) startInfo.ArgumentList.Add(argument);
        using var process = Process.Start(startInfo) ?? throw new InvalidOperationException("ไม่สามารถเริ่มตัวดาวน์โหลดได้");
        using var registration = cancellationToken.Register(() => { try { process.Kill(true); } catch (InvalidOperationException) { } });
        var errors = new Queue<string>();
        async Task ReadLines(StreamReader reader, bool isError)
        {
            while (await reader.ReadLineAsync(cancellationToken).ConfigureAwait(false) is { } line)
            {
                if (isError) { errors.Enqueue(line.Length <= 2000 ? line : line[..2000]); if (errors.Count > 8) errors.Dequeue(); }
                Dispatcher.UIThread.Post(() => ParseProgress(item, line));
            }
        }
        await Task.WhenAll(ReadLines(process.StandardOutput, false), ReadLines(process.StandardError, true), process.WaitForExitAsync(cancellationToken));
        // Drain callbacks before declaring completion so queued progress cannot
        // make a completed card appear to be downloading again.
        await Dispatcher.UIThread.InvokeAsync(() => { }, DispatcherPriority.Background);
        if (process.ExitCode != 0) throw new InvalidOperationException(FriendlyError(string.Join('\n', errors)));
        }
        finally
        {
            if (infoPath != null) try { File.Delete(infoPath); } catch (IOException) { }
        }
    }

    public static void ParseProgress(DownloadItem item, string line)
    {
        if (line.StartsWith("DDPATH:", StringComparison.Ordinal))
        {
            var path = line[7..].Trim();
            if (Path.IsPathFullyQualified(path)) item.ResultPath = path;
            return;
        }
        if (line.StartsWith("DDPROGRESS:", StringComparison.Ordinal))
        {
            var fields = line[11..].Split('|');
            if (double.TryParse(fields[0].Trim().TrimEnd('%'), NumberStyles.Float, CultureInfo.InvariantCulture, out var percent) && double.IsFinite(percent))
                item.Progress = Math.Clamp(percent, 0, 99.9);
            if (fields.Length > 1) item.Speed = fields[1].Trim();
            if (fields.Length > 2) item.Eta = fields[2].Trim();
            item.Detail = "กำลังดาวน์โหลด"; return;
        }
        if (line.StartsWith("[Merger]", StringComparison.Ordinal) || line.StartsWith("[VideoRemuxer]", StringComparison.Ordinal)) item.Detail = "กำลังรวมไฟล์วิดีโอ…";
        if (line.StartsWith("[ExtractAudio]", StringComparison.Ordinal)) item.Detail = "กำลังแปลงเป็น MP3…";
    }

    public static bool IsDirectFile(string url) =>
        Uri.TryCreate(url, UriKind.Absolute, out var uri) &&
        new[] { ".zip", ".7z", ".rar", ".pdf", ".mp4", ".mp3", ".mov", ".m4a", ".wav", ".flac", ".jpg", ".jpeg", ".png", ".webp", ".gif", ".txt", ".docx", ".xlsx", ".pptx" }
            .Contains(Path.GetExtension(uri.AbsolutePath), StringComparer.OrdinalIgnoreCase);

    public static void CleanupPartials(DownloadItem item)
    {
        if (item.IsActive) return;
        if (item.PartialPath is { } partial && Path.GetFileName(partial) == $".dropdrive-{item.Id:N}.part")
            File.Delete(partial);
        foreach (var entry in item.Entries)
            if (entry.Transfer is { } child) { child.Status = "Paused"; CleanupPartials(child); }
        if (item.IsDrive || !item.IsMedia || item.Destination == null || !Directory.Exists(item.Destination)) return;
        var suffix = "-" + item.Id.ToString("N") + ".";
        foreach (var path in Directory.EnumerateFiles(item.Destination))
        {
            var name = Path.GetFileName(path);
            if (!name.Contains(suffix, StringComparison.Ordinal)) continue;
            if (name.EndsWith(".part", StringComparison.Ordinal) || name.EndsWith(".ytdl", StringComparison.Ordinal) || name.Contains(".part-Frag", StringComparison.Ordinal))
                File.Delete(path);
        }
    }

    public static void CleanupStaleMetadata()
    {
        try
        {
            foreach (var path in Directory.EnumerateFiles(Path.GetTempPath(), "dropdrive-info-*.json"))
            {
                var name = Path.GetFileNameWithoutExtension(path);
                if (Guid.TryParseExact(name["dropdrive-info-".Length..], "N", out _) &&
                    DateTime.UtcNow - File.GetLastWriteTimeUtc(path) > TimeSpan.FromDays(1))
                    try { File.Delete(path); } catch (IOException) { }
            }
        }
        catch (Exception error) when (error is IOException or UnauthorizedAccessException) { }
    }

    public static string DescribeFailure(Exception error) => error switch
    {
        DirectoryNotFoundException => "ไม่พบโฟลเดอร์ปลายทาง เชื่อมต่อไดรฟ์หรือเลือกโฟลเดอร์ใหม่",
        UnauthorizedAccessException => "ไม่มีสิทธิ์เขียนไฟล์ในโฟลเดอร์นี้ เลือกโฟลเดอร์ใหม่",
        IOException io when (io.HResult & 0xFFFF) is 39 or 112 => "พื้นที่ว่างไม่พอ เลือกโฟลเดอร์ใหม่แล้วลองอีกครั้ง",
        HttpRequestException => "การเชื่อมต่อขาดหายหรือไฟล์ไม่พร้อม กดลองใหม่",
        _ => error.Message
    };

    public static string FriendlyError(string? detail)
    {
        var text = detail ?? "";
        if (text.Contains("no space", StringComparison.OrdinalIgnoreCase)) return "พื้นที่ว่างไม่พอ เลือกโฟลเดอร์ใหม่แล้วลองอีกครั้ง";
        if (text.Contains("permission denied", StringComparison.OrdinalIgnoreCase) || text.Contains("no such file", StringComparison.OrdinalIgnoreCase)) return "เขียนไฟล์ไม่ได้ ตรวจไดรฟ์และสิทธิ์ของโฟลเดอร์ปลายทาง";
        if (text.Contains("Unsupported URL", StringComparison.OrdinalIgnoreCase)) return "ยังไม่รองรับลิงก์นี้ ตรวจสอบว่าเป็นลิงก์ไฟล์หรือวิดีโอโดยตรง";
        if (text.Contains("Private video", StringComparison.OrdinalIgnoreCase) || text.Contains("Sign in", StringComparison.OrdinalIgnoreCase) || text.Contains("login", StringComparison.OrdinalIgnoreCase)) return "รายการนี้เป็นส่วนตัวหรือต้องมีสิทธิ์เข้าถึง Windows ยังไม่รองรับการล็อกอินบัญชี";
        if (text.Contains("not available", StringComparison.OrdinalIgnoreCase) || text.Contains("removed", StringComparison.OrdinalIgnoreCase)) return "รายการนี้ใช้งานไม่ได้หรือถูกลบแล้ว";
        if (text.Contains("HTTP Error 403", StringComparison.OrdinalIgnoreCase)) return "ถูกปฏิเสธการเข้าถึง ตรวจสิทธิ์ของลิงก์หรืออัปเดต DropDrive";
        return "ดาวน์โหลดลิงก์นี้ไม่ได้ ตรวจลิงก์และการเชื่อมต่ออินเทอร์เน็ตแล้วลองอีกครั้ง";
    }

    private static string UniquePath(string folder, string name)
    {
        var path = Path.Combine(folder, name);
        if (!File.Exists(path) && !Directory.Exists(path)) return path;
        var stem = Path.GetFileNameWithoutExtension(name); var extension = Path.GetExtension(name);
        for (var index = 2; ; index++)
        {
            path = Path.Combine(folder, $"{stem} ({index}){extension}");
            if (!File.Exists(path) && !Directory.Exists(path)) return path;
        }
    }
}
