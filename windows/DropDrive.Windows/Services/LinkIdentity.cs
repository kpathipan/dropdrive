using System.Text.RegularExpressions;

namespace DropDrive.Windows.Services;

public static partial class LinkIdentity
{
    public static string Key(string url)
    {
        if (!Uri.TryCreate(url, UriKind.Absolute, out var uri)) return url;
        if (PublicDriveService.FileId(url) is { } drive) return "drive:" + drive;
        var host = uri.Host.ToLowerInvariant();
        bool Host(string domain) => host == domain || host.EndsWith("." + domain, StringComparison.Ordinal);
        var query = uri.Query.TrimStart('?').Split('&').Select(pair => pair.Split('=', 2)).Where(pair => pair.Length == 2)
            .GroupBy(pair => pair[0]).ToDictionary(group => group.Key, group => Uri.UnescapeDataString(group.First()[1]));
        if (Host("youtube.com") || host == "youtu.be")
        {
            if (uri.AbsolutePath == "/playlist" && query.TryGetValue("list", out var list)) return "youtube-list:" + list;
            if (query.TryGetValue("v", out var video)) return "youtube:" + video;
            if (host == "youtu.be") return "youtube:" + uri.AbsolutePath.Trim('/');
            var parts = uri.AbsolutePath.Split('/', StringSplitOptions.RemoveEmptyEntries);
            if (parts.Length == 2 && parts[0] is "shorts" or "live" or "embed") return "youtube:" + parts[1];
        }
        if (Host("tiktok.com") && TikTokId().Match(uri.AbsolutePath) is { Success: true } match) return "tiktok:" + match.Groups[1].Value;
        if (Host("instagram.com"))
        {
            var parts = uri.AbsolutePath.Split('/', StringSplitOptions.RemoveEmptyEntries);
            if (parts.Length == 2 && parts[0] is "reel" or "p" or "tv") return "instagram:" + parts[1];
        }
        if (Host("facebook.com") && query.TryGetValue("v", out var facebook)) return "facebook:" + facebook;
        return url;
    }
    public static string Platform(string url)
    {
        var host = new Uri(url).Host.ToLowerInvariant();
        foreach (var domain in new[] { "youtube.com", "tiktok.com", "facebook.com", "instagram.com" })
            if (host == domain || host.EndsWith("." + domain, StringComparison.Ordinal)) return domain;
        return host == "youtu.be" ? "youtube.com" : host;
    }
    [GeneratedRegex(@"/(?:video|photo)/(\d+)")]
    private static partial Regex TikTokId();
}
