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
    public Func<long?>? BandwidthProvider { get; set; }
    public GoogleAccountService? GoogleAccounts { get; set; }
    public DownloadService(HttpClient? client = null) => _client = client ?? new() { Timeout = Timeout.InfiniteTimeSpan };

    public async Task DownloadAsync(DownloadItem item, string destination, CancellationToken cancellationToken)
    {
        // Never recreate a missing user-selected destination (e.g. an unplugged drive).
        TransferGuard.EnsureSpace(destination, item.IsMedia ? null : item.EstimatedBytes);
        item.Status = "Downloading"; item.CanCancel = true; item.CanRetry = false;
        if ((item.IsDrive || item.IsPhotoCollection) && item.IsCollection) await DownloadDriveFolderAsync(item, destination, cancellationToken);
        else if (item.IsDrive || item.DirectTransfer || IsDirectFile(item.Url)) await DownloadDirectAsync(item, destination, cancellationToken);
        else await DownloadMediaAsync(item, destination, cancellationToken);
        item.Progress = 100; item.Status = "Complete"; item.CanCancel = false;
        item.Detail = item.AudioOnly ? "บันทึกเป็น MP3 แล้ว" : "บันทึกในโฟลเดอร์ปลายทางแล้ว";
    }

    private async Task DownloadDirectAsync(DownloadItem item, string destination, CancellationToken cancellationToken)
    {
        var name = MediaOptions.SafeName(item.Name == "ดาวน์โหลด" ? Path.GetFileName(Uri.UnescapeDataString(new Uri(item.Url).LocalPath)) : item.Name);
        // Resume only our own job's partial in the originally chosen folder.
        var target = item.TargetPath;
        if (target == null || item.PartialPath == null || !string.Equals(Path.GetDirectoryName(target), destination, StringComparison.OrdinalIgnoreCase))
        {
            target = UniquePath(destination, name);
            item.TargetPath = target;
            item.PartialPath = Path.Combine(destination, $".dropdrive-{item.Id:N}.part");
            item.EntityTag = null;
        }
        var partial = item.PartialPath!;
        var offset = File.Exists(partial) && item.EntityTag != null ? new FileInfo(partial).Length : 0;
        var authenticated = item.IsDrive && item.DriveAccountId != null;
        var downloadUrl = authenticated ? GoogleDriveService.DownloadUrl(item.DriveFileId ?? PublicDriveService.FileId(item.Url)!, item.DriveMimeType)
            : item.IsDrive ? PublicDriveService.DownloadUrl(item.Url) : item.Url;
        async Task<HttpResponseMessage> Request(string url)
        {
            using var request = new HttpRequestMessage(HttpMethod.Get, url);
            if (authenticated)
            {
                var uri = new Uri(url);
                if (uri.Scheme != "https" || uri.Host != "www.googleapis.com" || !uri.AbsolutePath.StartsWith("/drive/v3/files/", StringComparison.Ordinal))
                    throw new InvalidOperationException("ปลายทาง Google Drive ไม่ถูกต้อง");
                if (GoogleAccounts == null) throw new InvalidOperationException("กรุณาเชื่อมต่อบัญชี Google อีกครั้ง");
                request.Headers.Authorization = new("Bearer", await GoogleAccounts.AccessTokenAsync(item.DriveAccountId!, cancellationToken));
                if (item.DriveResourceKey != null) request.Headers.TryAddWithoutValidation("X-Goog-Drive-Resource-Keys", (item.DriveFileId ?? PublicDriveService.FileId(item.Url)) + "/" + item.DriveResourceKey);
            }
            if (item.DirectTransfer && TikTokMediaService.IsTrustedCdn(new Uri(url).Host)) request.Headers.Referrer = new Uri("https://www.tiktok.com/");
            if (offset > 0)
            {
                request.Headers.Range = new RangeHeaderValue(offset, null);
                request.Headers.TryAddWithoutValidation("If-Range", item.EntityTag);
            }
            using var timeout = CancellationTokenSource.CreateLinkedTokenSource(cancellationToken);
            timeout.CancelAfter(TimeSpan.FromSeconds(30));
            try { return await _client.SendAsync(request, HttpCompletionOption.ResponseHeadersRead, timeout.Token); }
            catch (OperationCanceledException) when (!cancellationToken.IsCancellationRequested) { throw new HttpRequestException("การเชื่อมต่อหมดเวลา"); }
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
        if (authenticated && response.StatusCode is HttpStatusCode.Forbidden or HttpStatusCode.NotFound or HttpStatusCode.Unauthorized)
            throw new DriveAccessException();
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
        // Parallel ranges share one owned partial, without segment copies.
        var parallel = !item.DisableParallel && offset == 0 && total is >= 128 * 1024 * 1024 && item.EntityTag != null
            && response.Headers.AcceptRanges.Contains("bytes") && !item.AudioOnly;
        if (parallel)
        {
            var rangeTag = item.EntityTag!;
            // A sparse parallel file cannot be resumed by length after a crash.
            item.EntityTag = null; item.DisableParallel = true; Checkpoint?.Invoke();
            response.Dispose();
            await ParallelRangeTransfer.DownloadAsync(_client, downloadUrl, partial, total!.Value, rangeTag, item,
                GoogleAccounts, BandwidthProvider, cancellationToken);
        }
        else
        {
        await using var input = await response.Content.ReadAsStreamAsync(cancellationToken);
        await using (var output = new FileStream(partial, append ? FileMode.Append : FileMode.Create, FileAccess.Write, FileShare.Read, 128 * 1024, true))
        {
            var buffer = new byte[128 * 1024];
            long received = offset, sessionBytes = 0;
            var clock = Stopwatch.StartNew();
            var lastUpdate = TimeSpan.Zero;
            int read;
            while ((read = await ReadWithTimeout(input, buffer, cancellationToken)) > 0)
            {
                await output.WriteAsync(buffer.AsMemory(0, read), cancellationToken);
                received += read; sessionBytes += read;
                item.ReceivedBytes = received;
                var limit = BandwidthProvider != null ? BandwidthProvider() : item.BandwidthLimit;
                if (limit is > 0)
                {
                    await Task.Delay(TimeSpan.FromSeconds(read / (double)limit.Value), cancellationToken);
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
        }
        if (item.DirectTransfer && item.Source == "TikTok Photos")
        {
            using var probe = File.OpenRead(partial);
            var header = new byte[12]; var count = probe.Read(header);
            var image = count >= 12 && (header[0] == 0xff && header[1] == 0xd8 || header[0] == 0x89 && header[1] == 0x50 ||
                System.Text.Encoding.ASCII.GetString(header, 0, 4) == "RIFF" && System.Text.Encoding.ASCII.GetString(header, 8, 4) == "WEBP");
            if (!image) throw new InvalidOperationException("ไฟล์รูปจาก TikTok ไม่ถูกต้อง กรุณาลองใหม่");
        }
        if (item.ExpectedMd5 is { Length: > 0 } expected)
        {
            item.Detail = Locale.Choose("กำลังตรวจความถูกต้องของไฟล์", "Verifying file integrity");
            string actual;
            await using (var file = new FileStream(partial, FileMode.Open, FileAccess.Read, FileShare.Read, 128 * 1024, FileOptions.Asynchronous | FileOptions.SequentialScan))
                actual = Convert.ToHexString(await System.Security.Cryptography.MD5.HashDataAsync(file, cancellationToken));
            if (!string.Equals(actual, expected, StringComparison.OrdinalIgnoreCase))
            {
                File.Delete(partial); // Only this job's corrupt partial, never an existing destination file.
                item.PartialPath = null; item.EntityTag = null; item.ReceivedBytes = 0;
                Checkpoint?.Invoke();
                throw new IOException(Locale.Choose("ไฟล์ไม่ตรงกับข้อมูล Google Drive กรุณาดาวน์โหลดใหม่", "File checksum differs from Google Drive. Download it again."));
            }
        }
        if (File.Exists(target)) target = UniquePath(destination, name);
        File.Move(partial, target);
        item.ResultPath = target; item.PartialPath = null; item.TargetPath = target;
    }

    private async Task DownloadDriveFolderAsync(DownloadItem item, string destination, CancellationToken token)
    {
        if (item.IsPhotoCollection)
        {
            var fresh = await TikTokMediaService.AnalyzeFastAsync(item.Url, token);
            if (fresh?.Entries == null) throw new InvalidOperationException("รีเฟรชลิงก์รูป TikTok ไม่ได้ กรุณาลองใหม่");
            foreach (var entry in item.Entries.Where(e => e.Selected))
            {
                var replacement = fresh.Entries.FirstOrDefault(e => e.StableId == entry.StableId);
                if (replacement?.Url == null) throw new InvalidOperationException("โพสต์ TikTok เปลี่ยนไป กรุณาวิเคราะห์ลิงก์ใหม่");
                entry.Url = replacement.Url;
                if (entry.Transfer != null) entry.Transfer.Url = replacement.Url;
            }
        }
        var selected = item.Entries.Where(entry => entry.Selected).ToArray();
        if (selected.Length == 0) throw new InvalidOperationException("เลือกอย่างน้อย 1 ไฟล์");
        var collectionRoot = ResolveCollectionRoot(item, destination);
        Checkpoint?.Invoke();
        var count = 0;
        foreach (var entry in selected)
        {
            token.ThrowIfCancellationRequested();
            var root = collectionRoot.TrimEnd(Path.DirectorySeparatorChar) + Path.DirectorySeparatorChar;
            var folder = Path.GetFullPath(Path.Combine(collectionRoot, entry.RelativeFolder));
            if (folder != collectionRoot && !folder.StartsWith(root, StringComparison.OrdinalIgnoreCase))
                throw new IOException("ชื่อโฟลเดอร์ต้นทางไม่ปลอดภัย");
            TransferGuard.EnsureSpace(destination, entry.Size);
            Directory.CreateDirectory(folder);
            entry.Transfer ??= new DownloadItem { Url = entry.Url!, Name = entry.Title, IsDrive = item.IsDrive,
                DriveAccountId = item.DriveAccountId, DriveMimeType = entry.MimeType, DriveResourceKey = entry.ResourceKey, DriveFileId = PublicDriveService.FileId(entry.Url!),
                DirectTransfer = item.IsPhotoCollection, Source = item.IsPhotoCollection && entry.Kind == "image" ? "TikTok Photos" : item.Source,
                IsMedia = false, Destination = folder };
            var child = entry.Transfer;
            if (child.Status == "Complete" && File.Exists(child.ResultPath) && child.Destination == folder) { count++; item.Progress = count * 100d / selected.Length; continue; }
            if (item.IsDrive)
            {
                child.DriveAccountId = item.DriveAccountId;
                child.DriveMimeType = entry.MimeType; child.DriveResourceKey = entry.ResourceKey;
                child.ExpectedMd5 = entry.ExpectedMd5;
            }
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
        item.ResultPath = collectionRoot;
        item.ReceivedBytes = selected.Sum(entry => entry.Transfer?.ReceivedBytes ?? 0);
    }

    public static string ResolveCollectionRoot(DownloadItem item, string destination)
    {
        var parent = Path.TrimEndingDirectorySeparator(Path.GetFullPath(destination));
        var name = MediaOptions.SafeName(item.Name);
        var comparison = OperatingSystem.IsWindows() ? StringComparison.OrdinalIgnoreCase : StringComparison.Ordinal;
        if (item.CollectionDestinationPath == parent && item.CollectionRootPath is { } remembered)
        {
            var full = Path.TrimEndingDirectorySeparator(Path.GetFullPath(remembered));
            if (full.Equals(parent, comparison) || string.Equals(Path.GetDirectoryName(full), parent, comparison))
            { Directory.CreateDirectory(full); return full; }
        }
        // Selecting the source-named folder explicitly means use that folder,
        // not Photos/Photos. Selecting Downloads means create Downloads/Photos.
        var root = parent;
        if (!Path.GetFileName(parent).Equals(name, comparison))
        {
            root = Path.Combine(parent, name);
            for (var suffix = 1; Directory.Exists(root) || File.Exists(root); suffix++)
                root = Path.Combine(parent, $"{name} ({suffix})");
        }
        Directory.CreateDirectory(root);
        item.CollectionRootPath = root; item.CollectionDestinationPath = parent;
        return root;
    }

    private static async Task<int> ReadWithTimeout(Stream input, byte[] buffer, CancellationToken token)
    {
        using var timeout = CancellationTokenSource.CreateLinkedTokenSource(token);
        timeout.CancelAfter(TimeSpan.FromSeconds(30));
        try { return await input.ReadAsync(buffer, timeout.Token); }
        catch (OperationCanceledException) when (!token.IsCancellationRequested) { throw new HttpRequestException("การเชื่อมต่อหมดเวลา"); }
    }

    public Action<string>? DiagnosticSink { get; init; }

    private async Task DownloadMediaAsync(DownloadItem item, string destination, CancellationToken cancellationToken)
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
            { throw new HttpRequestException("เชื่อมต่อ TikTok ไม่ได้ในขณะนี้ ลองใหม่อีกครั้ง", error); }
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
        if (process.ExitCode != 0)
        {
            var detail = string.Join('\n', errors);
            DiagnosticSink?.Invoke(detail);
            if (IsTransientMediaError(detail)) throw new HttpRequestException(FriendlyError(detail));
            throw new InvalidOperationException(FriendlyError(detail));
        }
        if (item.OutputPaths.Count == 0) throw new IOException("ตัวดาวน์โหลดไม่ส่งไฟล์ผลลัพธ์กลับมา กรุณาลองใหม่");
        foreach (var path in item.OutputPaths)
            await MediaValidator.ValidateAsync(path, item.AudioOnly, toolsPath, cancellationToken);
        FinalizeMediaNames(item, destination);
        item.ReceivedBytes = item.OutputPaths.Where(File.Exists).Sum(path => new FileInfo(path).Length);
        if (item.IsCollection) item.ResultPath = destination;
        }
        finally
        {
            if (infoPath != null) try { File.Delete(infoPath); } catch (IOException) { }
        }
    }

    public static void FinalizeMediaNames(DownloadItem item, string destination)
    {
        // The job suffix owns partials during transfer. Successful user-facing
        // files no longer need it; rename in place, never make a second copy.
        var marker = "-" + item.Id.ToString("N") + ".";
        foreach (var path in Directory.EnumerateFiles(destination).Where(path => Path.GetFileName(path).Contains(marker, StringComparison.Ordinal)).ToArray())
        {
            var name = Path.GetFileName(path);
            if (name.EndsWith(".part", StringComparison.Ordinal) || name.EndsWith(".ytdl", StringComparison.Ordinal) || name.Contains(".part-Frag", StringComparison.Ordinal)) continue;
            var renamed = UniquePath(destination, name.Replace(marker, ".", StringComparison.Ordinal));
            File.Move(path, renamed);
            for (var index = 0; index < item.OutputPaths.Count; index++)
                if (item.OutputPaths[index] == path) item.OutputPaths[index] = renamed;
            if (item.ResultPath == path) item.ResultPath = renamed;
        }
    }

    public static void ParseProgress(DownloadItem item, string line)
    {
        if (line.StartsWith("DDPATH:", StringComparison.Ordinal))
        {
            var path = line[7..].Trim();
            if (Path.IsPathFullyQualified(path))
            {
                item.ResultPath = path;
                if (!item.OutputPaths.Contains(path, StringComparer.OrdinalIgnoreCase)) item.OutputPaths.Add(path);
            }
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
        if (item.PartialPath is { } partial && Path.GetFileName(partial) == $".dropdrive-{item.Id:N}.part" && File.Exists(partial))
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
        if (text.Contains("IP address is blocked", StringComparison.OrdinalIgnoreCase)) return "เว็บไซต์ปฏิเสธเครือข่ายนี้ชั่วคราว กรุณาลองใหม่ภายหลัง";
        if (text.Contains("Requested format is not available", StringComparison.OrdinalIgnoreCase)) return "ต้นทางไม่มีคุณภาพไฟล์ที่เลือก ลองเปลี่ยนเป็นอัตโนมัติ";
        if (text.Contains("Cannot parse data", StringComparison.OrdinalIgnoreCase)) return "อ่านข้อมูลจากเว็บไซต์ไม่ได้ในขณะนี้ ตรวจอัปเดต DropDrive หรือลองใหม่ภายหลัง";
        if (text.Contains("Private video", StringComparison.OrdinalIgnoreCase) || text.Contains("Sign in", StringComparison.OrdinalIgnoreCase) || text.Contains("login", StringComparison.OrdinalIgnoreCase)) return "เว็บไซต์นี้ต้องยืนยันบัญชีหรือสิทธิ์เข้าถึง การล็อกอิน Google Drive ไม่ได้เพิ่มสิทธิ์ให้เว็บไซต์วิดีโอ";
        if (text.Contains("not available", StringComparison.OrdinalIgnoreCase) || text.Contains("unavailable", StringComparison.OrdinalIgnoreCase) || text.Contains("removed", StringComparison.OrdinalIgnoreCase)) return "รายการนี้ใช้งานไม่ได้หรือถูกลบแล้ว";
        if (text.Contains("HTTP Error 403", StringComparison.OrdinalIgnoreCase)) return "ถูกปฏิเสธการเข้าถึง ตรวจสิทธิ์ของลิงก์หรืออัปเดต DropDrive";
        return "ดาวน์โหลดลิงก์นี้ไม่ได้ ตรวจลิงก์และการเชื่อมต่ออินเทอร์เน็ตแล้วลองอีกครั้ง";
    }
    public static bool IsTransientMediaError(string text) => new[] { "timed out", "connection reset", "connection aborted", "network is unreachable", "temporary failure", "HTTP Error 503", "HTTP Error 502", "HTTP Error 429" }
        .Any(fragment => text.Contains(fragment, StringComparison.OrdinalIgnoreCase));

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
