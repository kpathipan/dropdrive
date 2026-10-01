using System.Net;
using System.Net.Http.Headers;
using DropDrive.Windows.Models;
using DropDrive.Windows.Services;

internal static class ParallelTransferChecks
{
    public static async Task RunAsync(string folder)
    {
        Directory.CreateDirectory(folder);
        var bytes = Enumerable.Range(0, 2_000_003).Select(i => (byte)(i % 251)).ToArray();
        var handler = new Ranges(bytes);
        using var client = new HttpClient(handler);
        var partial = Path.Combine(folder, ".parallel.part");
        var item = new DownloadItem { Url = "https://fixture.test/large.mp4" };
        await ParallelRangeTransfer.DownloadAsync(client, item.Url, partial, bytes.Length, "\"stable\"", item, null, null, CancellationToken.None);
        if (!File.ReadAllBytes(partial).SequenceEqual(bytes) || handler.Requests != 6 || handler.Peak < 2 || handler.Peak > 6)
            throw new Exception("Parallel ranges did not preserve bytes/concurrency");
        File.Delete(partial);
        var interrupted = new Ranges(bytes) { InterruptOnce = true };
        using var retryClient = new HttpClient(interrupted);
        await ParallelRangeTransfer.DownloadAsync(retryClient, item.Url, partial, bytes.Length, "\"stable\"", item, null, null, CancellationToken.None);
        if (!File.ReadAllBytes(partial).SequenceEqual(bytes) || interrupted.Requests != 7 || !interrupted.SuffixResumed || item.ReceivedBytes != bytes.Length)
            throw new Exception("Interrupted range must retain its valid prefix and resume only the suffix");
        File.Delete(partial);
        var large = new byte[50 * 1024 * 1024];
        var largeHandler = new Ranges(large);
        using var largeClient = new HttpClient(largeHandler);
        await ParallelRangeTransfer.DownloadAsync(largeClient, item.Url, partial, large.Length, "\"stable\"", item, null, null, CancellationToken.None);
        if (largeHandler.Requests != 7 || largeHandler.LargestRange > 8 * 1024 * 1024 || new FileInfo(partial).Length != large.Length)
            throw new Exception("Large transfer must use bounded work chunks");
        File.Delete(partial);
        handler.BadRange = true;
        try
        {
            await ParallelRangeTransfer.DownloadAsync(client, item.Url, partial, bytes.Length, "\"stable\"", item, null, null, CancellationToken.None);
            throw new Exception("Ignored Range accepted");
        }
        catch (IOException)
        {
            if (File.Exists(partial) || !item.DisableParallel || item.EntityTag != null) throw new Exception("Unsafe parallel partial left resumable");
        }
        using var blockedHandler = new CancelledRanges();
        using var blockedClient = new HttpClient(blockedHandler);
        using var cancellation = new CancellationTokenSource();
        var cancelItem = new DownloadItem { Url = item.Url };
        var cancelling = ParallelRangeTransfer.DownloadAsync(blockedClient, item.Url, partial,
            bytes.Length, "\"stable\"", cancelItem, null, null, cancellation.Token);
        await blockedHandler.Started.Task.WaitAsync(TimeSpan.FromSeconds(5));
        cancellation.Cancel();
        try { await cancelling.WaitAsync(TimeSpan.FromSeconds(5)); throw new Exception("Cancellation was ignored"); }
        catch (OperationCanceledException) { }
        if (File.Exists(partial) || blockedHandler.Active != 0) throw new Exception("Cancellation left writers/partial behind");
        handler.BadRange = false;
        await ParallelRangeTransfer.DownloadAsync(client, item.Url, partial, bytes.Length, "\"stable\"", cancelItem, null, null, CancellationToken.None);
        if (!File.ReadAllBytes(partial).SequenceEqual(bytes)) throw new Exception("Restart after pause changed bytes");
        File.Delete(partial);
        Console.WriteLine("PASS Windows cancellation settles all workers and restart preserves exact bytes");
        Console.WriteLine("PASS parallel transfer: bounded chunks/workers, exact bytes, interrupted-suffix resume, safe rejection/cleanup");
    }
    private sealed class CancelledRanges : HttpMessageHandler
    {
        public readonly TaskCompletionSource Started = new(TaskCreationOptions.RunContinuationsAsynchronously);
        public int Active;
        protected override async Task<HttpResponseMessage> SendAsync(HttpRequestMessage request, CancellationToken token)
        {
            Interlocked.Increment(ref Active);
            Started.TrySetResult();
            try { await Task.Delay(Timeout.Infinite, token); throw new Exception("Unexpected completion"); }
            finally { Interlocked.Decrement(ref Active); }
        }
    }
    private sealed class Ranges(byte[] bytes) : HttpMessageHandler
    {
        public int Requests, Peak, Active;
        public bool BadRange, InterruptOnce, SuffixResumed;
        public int LargestRange;
        protected override async Task<HttpResponseMessage> SendAsync(HttpRequestMessage request, CancellationToken token)
        {
            Requests++; Active++; Peak = Math.Max(Peak, Active);
            try { await Task.Delay(10, token); } finally { Active--; }
            if (!request.Headers.TryGetValues("If-Match", out var values) || values.Single() != "\"stable\"") throw new Exception("No version guard");
            var range = request.Headers.Range!.Ranges.Single();
            var start = (int)range.From!; var end = (int)range.To!;
            LargestRange = Math.Max(LargestRange, end - start + 1);
            if (start == 128 * 1024) SuffixResumed = true;
            var response = new HttpResponseMessage(BadRange ? HttpStatusCode.OK : HttpStatusCode.PartialContent) { Content = new ByteArrayContent(bytes[start..(end + 1)]) };
            if (InterruptOnce && start == 0)
            { InterruptOnce = false; response.Content = new StreamContent(new InterruptedStream(bytes[start..(end + 1)])); }
            response.Content.Headers.ContentRange = new ContentRangeHeaderValue(start, end, bytes.Length);
            response.Headers.ETag = new EntityTagHeaderValue("\"stable\"");
            return response;
        }
    }
    private sealed class InterruptedStream(byte[] bytes) : MemoryStream(bytes)
    {
        public override ValueTask<int> ReadAsync(Memory<byte> buffer, CancellationToken token = default)
        {
            if (Position >= 128 * 1024) throw new IOException("Simulated connection loss");
            return base.ReadAsync(buffer[..Math.Min(buffer.Length, 128 * 1024 - (int)Position)], token);
        }
    }
}
