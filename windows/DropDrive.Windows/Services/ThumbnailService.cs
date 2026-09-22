using Avalonia.Media.Imaging;
using SkiaSharp;

namespace DropDrive.Windows.Services;

public sealed class ThumbnailService : IDisposable
{
    private readonly HttpClient _client;
    private readonly SemaphoreSlim _gate = new(3);
    // Keep compressed bytes only. Callers own decoded images so eviction cannot
    // invalidate an image currently displayed by a card or Space preview.
    private readonly Dictionary<string, byte[]> _cache = [];
    private readonly LinkedList<string> _order = [];
    private readonly object _cacheLock = new();
    private long _cachedBytes;
    private readonly long _maximumBytes;
    public GoogleAccountService? GoogleAccounts { get; set; }
    public ThumbnailService(HttpClient? client = null, long maximumBytes = 24 * 1024 * 1024)
    { _client = client ?? new HttpClient(); _maximumBytes = Math.Max(1, maximumBytes); }

    private byte[]? Cached(string key)
    {
        lock (_cacheLock)
        {
            if (!_cache.TryGetValue(key, out var bytes)) return null;
            _order.Remove(key); _order.AddLast(key); return bytes;
        }
    }
    private void Store(string key, byte[] bytes)
    {
        lock (_cacheLock)
        {
            if (_cache.Remove(key, out var previous)) _cachedBytes -= previous.Length;
            _order.Remove(key); _order.AddLast(key); _cache[key] = bytes; _cachedBytes += bytes.Length;
            while ((_cachedBytes > _maximumBytes || _cache.Count > 100) && _order.First is { } oldest)
            { _order.RemoveFirst(); if (_cache.Remove(oldest.Value, out var removed)) _cachedBytes -= removed.Length; }
        }
    }
    private static Bitmap? Decode(byte[] bytes)
    {
        using var stream = new MemoryStream(bytes);
        using var codec = SKCodec.Create(stream);
        if (codec == null || codec.Info.Width <= 0 || codec.Info.Height <= 0 || (long)codec.Info.Width * codec.Info.Height > 40_000_000) return null;
        var portrait = codec.Info.Height > codec.Info.Width; stream.Position = 0;
        return portrait ? Bitmap.DecodeToHeight(stream, 320) : Bitmap.DecodeToWidth(stream, 320);
    }

    public async Task<Bitmap?> GetAsync(string? url, CancellationToken token = default, string? accountId = null)
    {
        if (!Uri.TryCreate(url, UriKind.Absolute, out var uri) || uri.Scheme is not ("https" or "http")) return null;
        var cacheKey = (accountId ?? "public") + "|" + url;
        using var deadline = CancellationTokenSource.CreateLinkedTokenSource(token);
        deadline.CancelAfter(TimeSpan.FromSeconds(15)); token = deadline.Token;
        try { await _gate.WaitAsync(token); }
        catch (OperationCanceledException) { return null; }
        try
        {
            if (Cached(cacheKey) is { } existing) return Decode(existing);
            using var request = new HttpRequestMessage(HttpMethod.Get, uri);
            if (accountId != null && GoogleAccounts != null && uri.Scheme == "https" &&
                (uri.Host == "googleusercontent.com" || uri.Host.EndsWith(".googleusercontent.com", StringComparison.Ordinal)))
                request.Headers.Authorization = new("Bearer", await GoogleAccounts.AccessTokenAsync(accountId, token));
            using var response = await _client.SendAsync(request, HttpCompletionOption.ResponseHeadersRead, token);
            response.EnsureSuccessStatusCode();
            if (response.Content.Headers.ContentLength > 8 * 1024 * 1024) return null;
            await using var stream = await response.Content.ReadAsStreamAsync(token);
            using var bytes = new MemoryStream();
            var buffer = new byte[16384];
            int read;
            while ((read = await stream.ReadAsync(buffer, token)) > 0)
            {
                if (bytes.Length + read > 8 * 1024 * 1024) return null;
                bytes.Write(buffer, 0, read);
            }
            var compressed = bytes.ToArray();
            var bitmap = Decode(compressed);
            if (bitmap != null) Store(cacheKey, compressed);
            return bitmap;
        }
        catch (Exception error) when (error is not OutOfMemoryException) { return null; }
        finally { _gate.Release(); }
    }
    public void Dispose() { lock (_cacheLock) { _cache.Clear(); _order.Clear(); _cachedBytes = 0; } _client.Dispose(); }
}
