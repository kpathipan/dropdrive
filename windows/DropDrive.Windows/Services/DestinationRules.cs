using DropDrive.Windows.Models;

namespace DropDrive.Windows.Services;

public static class DestinationRules
{
    public static string Source(string url) => PublicDriveService.IsDriveUrl(url) ? "drive.google.com" : LinkIdentity.Platform(url);
    // Same document/archive lists as Mac FileCategoryClassifier so both apps show the same type chips.
    private static readonly HashSet<string> DocumentExtensions = [".pdf", ".doc", ".docx", ".rtf", ".txt", ".odt", ".pages",
        ".xls", ".xlsx", ".csv", ".numbers", ".ppt", ".pptx", ".key", ".md"];
    private static readonly HashSet<string> ArchiveExtensions = [".zip", ".rar", ".7z", ".tar", ".gz", ".bz2", ".xz", ".tgz"];
    private static readonly HashSet<string> DocumentMimeTypes = ["application/pdf", "application/msword",
        "application/vnd.openxmlformats-officedocument.wordprocessingml.document", "application/vnd.ms-excel",
        "application/vnd.openxmlformats-officedocument.spreadsheetml.sheet", "application/vnd.ms-powerpoint",
        "application/vnd.openxmlformats-officedocument.presentationml.presentation", "application/rtf", "text/csv"];
    private static readonly HashSet<string> ArchiveMimeTypes = ["application/zip", "application/x-zip-compressed",
        "application/x-rar-compressed", "application/x-7z-compressed", "application/x-tar", "application/gzip", "application/x-bzip2"];

    /// One of images, videos, documents, archives, other. kind is null for a single non-collection file.
    public static string EntryCategory(string name, string? kind, string? mime = null)
    {
        var ext = Path.GetExtension(name).ToLowerInvariant();
        mime ??= "";
        if (kind == "image" || mime.StartsWith("image/", StringComparison.Ordinal)) return "images";
        if (kind == "video" || mime.StartsWith("video/", StringComparison.Ordinal)) return "videos";
        if (kind == "audio") return "other";
        if (ext is ".jpg" or ".jpeg" or ".png" or ".gif" or ".webp" or ".heic") return "images";
        if (ext is ".mp4" or ".mov" or ".mkv" or ".webm") return "videos";
        if (ArchiveMimeTypes.Contains(mime) || ArchiveExtensions.Contains(ext)) return "archives";
        if (DocumentMimeTypes.Contains(mime) || mime.StartsWith("text/", StringComparison.Ordinal) || DocumentExtensions.Contains(ext)) return "documents";
        return "other";
    }
    public static string EntryCategory(MediaEntry entry) => EntryCategory(entry.Title, entry.Kind, entry.MimeType);
    public static readonly string[] CategoryOrder = ["videos", "images", "documents", "archives", "other"];

    /// File-type chip: a fully selected type is cleared, anything else selects the whole type.
    public static void ToggleCategory(IReadOnlyCollection<MediaEntry> entries, string category)
    {
        var group = entries.Where(entry => EntryCategory(entry) == category).ToArray();
        var select = !group.All(entry => entry.Selected);
        foreach (var entry in group) entry.Selected = select;
    }

    public static string? Category(DownloadItem item)
    {
        if (item.IsMedia && !item.IsPhotoCollection) return "videos";
        if (!item.IsCollection) return EntryCategory(item.Name, null);
        var categories = item.Entries.Select(entry => EntryCategory(entry)).Distinct().ToArray();
        return categories.Length == 1 ? categories[0] : null;
    }
    public static string? Resolve(AppSettings settings, DownloadItem item)
    {
        if (settings.SourceDestinationRules.TryGetValue(Source(item.Url), out var source)) return source;
        var category = Category(item);
        return category != null && settings.CategoryDestinationRules.TryGetValue(category, out var folder) ? folder : null;
    }
    public static string CategoryLabel(string category) => category switch {
        "images" => Locale.Choose("รูปภาพ", "images"), "videos" => Locale.Choose("วิดีโอ", "videos"),
        "documents" => Locale.Choose("เอกสาร", "documents"), "archives" => Locale.Choose("ไฟล์บีบอัด", "archives"),
        _ => Locale.Choose("ไฟล์อื่น", "other files") };
}
