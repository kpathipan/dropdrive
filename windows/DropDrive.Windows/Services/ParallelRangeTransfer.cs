using System.Diagnostics;
using System.Net;
using System.Net.Http.Headers;
using DropDrive.Windows.Models;

namespace DropDrive.Windows.Services;

public static class ParallelRangeTransfer
{
    public static async Task DownloadAsync(HttpClient client, string url, string partial, long length, string etag,
        DownloadItem item, GoogleAccountService? accounts, Func<long?>? bandwidth, CancellationToken token, int connections = 6)
    {
        if (length <= 0 || connections is < 1 or > 6) throw new ArgumentOutOfRangeException(nameof(length));
        using var group = CancellationTokenSource.CreateLinkedTokenSource(token);
        try
        {
            await using var output = new FileStream(partial, FileMode.Create, FileAccess.Write, FileShare.Read, 1, FileOptions.Asynchronous | FileOptions.RandomAccess);
            output.SetLength(length);
            var count = (int)Math.Min(connections, length);
            long received = 0;
            var timer = Stopwatch.StartNew();
            var progressLock = new object();
            var lastUpdate = TimeSpan.Zero;
            async Task Range(int index)
            {
                var start = length / count * index + Math.Min(index, length % count);
                var end = length / count * (index + 1) + Math.Min(index + 1, length % count) - 1;
                try
                {
                    using var request = new HttpRequestMessage(HttpMethod.Get, url);
                    request.Headers.Range = new RangeHeaderValue(start, end);
                    request.Headers.TryAddWithoutValidation("If-Match", etag);
                    if (item.IsDrive && item.DriveAccountId != null)
                    {
                        var uri = new Uri(url);
                        if (accounts == null || uri.Scheme != "https" || uri.Host != "www.googleapis.com" || !uri.AbsolutePath.StartsWith("/drive/v3/files/", StringComparison.Ordinal))
                            throw new InvalidOperationException("Invalid Drive range destination");
                        request.Headers.Authorization = new("Bearer", await accounts.AccessTokenAsync(item.DriveAccountId, group.Token));
                        if (item.DriveResourceKey != null) request.Headers.TryAddWithoutValidation("X-Goog-Drive-Resource-Keys", (item.DriveFileId ?? PublicDriveService.FileId(item.Url)) + "/" + item.DriveResourceKey);
                    }
                    if (item.DirectTransfer && TikTokMediaService.IsTrustedCdn(new Uri(url).Host)) request.Headers.Referrer = new Uri("https://www.tiktok.com/");
                    using var deadline = CancellationTokenSource.CreateLinkedTokenSource(group.Token); deadline.CancelAfter(TimeSpan.FromSeconds(30));
                    using var response = await client.SendAsync(request, HttpCompletionOption.ResponseHeadersRead, deadline.Token);
                    var range = response.Content.Headers.ContentRange;
                    if (response.StatusCode != HttpStatusCode.PartialContent || range?.From != start || range.To != end || range.Length != length
                        || response.Headers.ETag?.ToString() != etag)
                        throw new IOException(Locale.Choose("ต้นทางไม่รองรับการแบ่งส่วนอย่างปลอดภัย กรุณาลองใหม่", "Source did not return safe byte ranges. Try again."));
                    await using var input = await response.Content.ReadAsStreamAsync(group.Token);
                    var buffer = new byte[128 * 1024];
                    long position = start;
                    while (true)
                    {
                        using var readDeadline = CancellationTokenSource.CreateLinkedTokenSource(group.Token); readDeadline.CancelAfter(TimeSpan.FromSeconds(30));
                        var read = await input.ReadAsync(buffer, readDeadline.Token);
                        if (read == 0) break;
                        if (position + read > end + 1) throw new IOException("Range response exceeded its bounds");
                        await RandomAccess.WriteAsync(output.SafeFileHandle, buffer.AsMemory(0, read), position, group.Token);
                        position += read;
                        var totalReceived = Interlocked.Add(ref received, read);
                        item.ReceivedBytes = totalReceived;
                        var limit = bandwidth != null ? bandwidth() : item.BandwidthLimit;
                        if (limit is > 0) await Task.Delay(TimeSpan.FromSeconds(read * (double)count / limit.Value), group.Token);
                        lock (progressLock)
                        {
                            if (timer.Elapsed - lastUpdate < TimeSpan.FromMilliseconds(200)) continue;
                            lastUpdate = timer.Elapsed;
                            var rate = received / Math.Max(0.001, timer.Elapsed.TotalSeconds);
                            item.Progress = Math.Min(99.9, received * 100d / length);
                            item.Speed = rate >= 1_048_576 ? $"{rate / 1_048_576:0.0} MB/s" : $"{rate / 1024:0} KB/s";
                            item.Eta = $"{Math.Ceiling((length - received) / rate):0}s";
                            item.Detail = Locale.Choose("กำลังดาวน์โหลดหลายการเชื่อมต่อ", "Downloading with multiple connections");
                        }
                    }
                    if (position != end + 1) throw new IOException("Incomplete range response");
                }
                catch { group.Cancel(); throw; }
            }
            await Task.WhenAll(Enumerable.Range(0, count).Select(Range));
            await output.FlushAsync(token);
            item.ReceivedBytes = received;
        }
        catch
        {
            // WaitAll has settled all writers before disposal/deletion here.
            if (File.Exists(partial)) File.Delete(partial);
            item.EntityTag = null; item.PartialPath = null; item.ReceivedBytes = 0;
            item.DisableParallel = true;
            throw;
        }
    }
}
