using DropDrive.Windows.Models;

namespace DropDrive.Windows.Services;

public static class DestinationRules
{
    public static string Source(string url) => PublicDriveService.IsDriveUrl(url) ? "drive.google.com" : LinkIdentity.Platform(url);
    public static string? Category(DownloadItem item)
    {
        string Kind(string name, string? kind) => kind switch {
            "image" => "images", "video" => "videos", "audio" => "other",
            _ => Path.GetExtension(name).ToLowerInvariant() switch {
                ".jpg" or ".jpeg" or ".png" or ".gif" or ".webp" or ".heic" => "images",
                ".mp4" or ".mov" or ".mkv" or ".webm" => "videos",
                ".pdf" or ".doc" or ".docx" or ".xls" or ".xlsx" or ".ppt" or ".pptx" or ".txt" => "documents",
                ".zip" or ".rar" or ".7z" or ".tar" or ".gz" => "archives", _ => "other" } };
        if (item.IsMedia && !item.IsPhotoCollection) return "videos";
        if (!item.IsCollection) return Kind(item.Name, null);
        var categories = item.Entries.Select(e => Kind(e.Title, e.Kind)).Distinct().ToArray();
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
