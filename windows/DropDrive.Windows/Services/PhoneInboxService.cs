using System.Net;
using System.Text.RegularExpressions;

namespace DropDrive.Windows.Services;

// Explicitly selected synced folder (OneDrive/iCloud/etc.). Inputs are archived
// only after the application confirms a durable receipt. Never deletes originals.
public sealed partial class PhoneInboxService
{
    private bool _scanning;
    public async Task ScanAsync(string folder, Func<IReadOnlyList<string>, Task<bool>> receive, CancellationToken token)
    {
        if (_scanning || !Directory.Exists(folder)) return;
        _scanning = true;
        try
        {
            var files = await Task.Run(() => Directory.EnumerateFiles(folder).Where(path =>
                Path.GetExtension(path).ToLowerInvariant() is ".txt" or ".url" or ".webloc").Take(20).ToArray(), token);
            foreach (var path in files)
            {
                token.ThrowIfCancellationRequested();
                var before = new FileInfo(path);
                if (before.Length > 65536 || DateTime.UtcNow - before.LastWriteTimeUtc < TimeSpan.FromSeconds(2)) continue;
                var modified = before.LastWriteTimeUtc;
                var raw = await File.ReadAllTextAsync(path, token);
                var links = ExtractLinks(raw);
                if (links.Count == 0 || !await receive(links)) continue;
                // A phone/sync client might rewrite a file while analysis runs.
                // In that case do not consume the new content as the old receipt.
                if (File.GetLastWriteTimeUtc(path) != modified || await File.ReadAllTextAsync(path, token) != raw) continue;
                var archive = Path.Combine(folder, "Processed");
                Directory.CreateDirectory(archive);
                var target = Path.Combine(archive, Path.GetFileName(path));
                if (File.Exists(target)) target = Path.Combine(archive, $"{Path.GetFileNameWithoutExtension(path)}-{Guid.NewGuid():N}{Path.GetExtension(path)}");
                File.Move(path, target);
            }
        }
        catch (Exception error) when (error is IOException or UnauthorizedAccessException) { /* Retry next scan; original remains intact. */ }
        finally { _scanning = false; }
    }
    public static IReadOnlyList<string> ExtractLinks(string text) =>
        UrlPattern().Matches(WebUtility.HtmlDecode(text)).Select(match => match.Value.TrimEnd('.', ',', ')', ']')).Distinct(StringComparer.Ordinal).Take(100).ToArray();
    [GeneratedRegex("https?://[^\\s<>\"']+", RegexOptions.IgnoreCase)]
    private static partial Regex UrlPattern();
}
