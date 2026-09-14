using Avalonia.Media.Imaging;
using SkiaSharp;

namespace DropDrive.Windows.Services;

public sealed class ThumbnailService : IDisposable
{
    private readonly HttpClient _client = new() { Timeout = TimeSpan.FromSeconds(8) };
    private readonly SemaphoreSlim _gate = new(3);
    private readonly Dictionary<string, Bitmap> _cache = [];

    public async Task<Bitmap?> GetAsync(string? url, CancellationToken token = default)
    {
        if (!Uri.TryCreate(url, UriKind.Absolute, out var uri) || uri.Scheme is not ("https" or "http")) return null;
        if (_cache.TryGetValue(url, out var existing)) return existing;
        try { await _gate.WaitAsync(token); }
        catch (OperationCanceledException) { return null; }
        try
        {
            if (_cache.TryGetValue(url, out existing)) return existing;
            if (_cache.Count >= 100) return null;
            using var response = await _client.GetAsync(uri, HttpCompletionOption.ResponseHeadersRead, token);
            response.EnsureSuccessStatusCode();
            if (response.Content.Headers.ContentLength > 4 * 1024 * 1024) return null;
            await using var stream = await response.Content.ReadAsStreamAsync(token);
            using var bytes = new MemoryStream();
            var buffer = new byte[16384];
            int read;
            while ((read = await stream.ReadAsync(buffer, token)) > 0)
            {
                if (bytes.Length + read > 4 * 1024 * 1024) return null;
                bytes.Write(buffer, 0, read);
            }
            bytes.Position = 0;
            using var codec = SKCodec.Create(bytes);
            if (codec == null || codec.Info.Width <= 0 || codec.Info.Height <= 0 ||
                (long)codec.Info.Width * codec.Info.Height > 40_000_000) return null;
            var portrait = codec.Info.Height > codec.Info.Width;
            bytes.Position = 0;
            var bitmap = portrait ? Bitmap.DecodeToHeight(bytes, 320) : Bitmap.DecodeToWidth(bytes, 320);
            _cache[url] = bitmap;
            return bitmap;
        }
        catch (Exception error) when (error is not OutOfMemoryException) { return null; }
        finally { _gate.Release(); }
    }
    public void Dispose() { foreach (var bitmap in _cache.Values) bitmap.Dispose(); _client.Dispose(); _gate.Dispose(); }
}
