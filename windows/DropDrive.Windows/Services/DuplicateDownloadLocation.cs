using DropDrive.Windows.Models;

namespace DropDrive.Windows.Services;

public static class DuplicateDownloadLocation
{
    // Use recorded outputs only: a title match is not proof of a completed download.
    public static string? ExistingPath(string? path) =>
        !string.IsNullOrWhiteSpace(path) && Path.IsPathFullyQualified(path)
        && (File.Exists(path) || Directory.Exists(path)) ? path : null;

    public static string? CompletedPath(string url, IEnumerable<DownloadItem> queue, IEnumerable<DownloadHistoryEntry> history)
    {
        var identity = LinkIdentity.Key(url);
        foreach (var item in queue.Reverse().Where(item => item.Status == "Complete" && LinkIdentity.Key(item.Url) == identity))
            if (ExistingPath(item.ResultPath) is { } path) return path;
        foreach (var item in history.OrderByDescending(item => item.FinishedAt).Where(item => item.Status == "Complete" && LinkIdentity.Key(item.Url) == identity))
            if (ExistingPath(item.ResultPath) is { } path) return path;
        return null;
    }

    // For extracted media the final extension/name is not yet known. Do not guess
    // or scan the user's disk; only warn about an exact known destination name.
    public static string? CollisionPath(DownloadItem item, string destination, string name)
    {
        if (item.IsMedia && !item.IsDrive && !item.IsPhotoCollection) return null;
        if (!Path.IsPathFullyQualified(destination) || string.IsNullOrWhiteSpace(name)) return null;
        var parent = Path.TrimEndingDirectorySeparator(destination);
        var safeName = MediaOptions.SafeName(name);
        var comparison = OperatingSystem.IsWindows() ? StringComparison.OrdinalIgnoreCase : StringComparison.Ordinal;
        if (item.IsCollection && Path.GetFileName(parent).Equals(safeName, comparison)) return null;
        return ExistingPath(Path.Combine(parent, safeName));
    }
}
