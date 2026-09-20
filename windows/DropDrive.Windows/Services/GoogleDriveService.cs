using System.Net;
using System.Text.Json;
using DropDrive.Windows.Models;

namespace DropDrive.Windows.Services;

public sealed class DriveAccessException : Exception
{
    public DriveAccessException() : base("ไม่มีบัญชีที่เชื่อมต่อมีสิทธิ์เข้าถึงไฟล์นี้ เพิ่มบัญชีที่มีสิทธิ์หรือขอสิทธิ์จากเจ้าของไฟล์") { }
}
public sealed class GoogleDriveService(GoogleAccountService accounts, HttpClient? client = null)
{
    private readonly HttpClient _client = client ?? new() { Timeout = TimeSpan.FromSeconds(25) };
    private const string Fields = "id,name,mimeType,size,md5Checksum,modifiedTime,version,resourceKey,thumbnailLink,webViewLink,capabilities(canDownload),shortcutDetails(targetId,targetMimeType,targetResourceKey)";
    public async Task<MediaAnalysis> AnalyzeAsync(string url, CancellationToken token)
    {
        foreach (var account in accounts.Accounts)
        {
            if (account.NeedsReconnect) continue;
            try { return await AnalyzeForAccountAsync(url, account.Id, token); }
            catch (DriveAccessException) { }
            catch (InvalidOperationException) when (accounts.Accounts.FirstOrDefault(a => a.Id == account.Id)?.NeedsReconnect == true) { }
        }
        // Keep public downloads available even when connected accounts have no
        // rights, were revoked, or the sharing URL requires anonymous access.
        try { return await new PublicDriveService().AnalyzeAsync(url, token); }
        catch (InvalidOperationException) { throw new DriveAccessException(); }
    }
    private async Task<JsonDocument> ReadAsync(string endpoint, string account, string? id, string? key, CancellationToken token)
    {
        using var request = new HttpRequestMessage(HttpMethod.Get, endpoint);
        request.Headers.Authorization = new("Bearer", await accounts.AccessTokenAsync(account, token));
        if (!string.IsNullOrEmpty(id) && !string.IsNullOrEmpty(key)) request.Headers.TryAddWithoutValidation("X-Goog-Drive-Resource-Keys", id + "/" + key);
        using var response = await _client.SendAsync(request, HttpCompletionOption.ResponseHeadersRead, token);
        if (response.StatusCode is HttpStatusCode.Forbidden or HttpStatusCode.NotFound or HttpStatusCode.Unauthorized) throw new DriveAccessException();
        response.EnsureSuccessStatusCode();
        await response.Content.LoadIntoBufferAsync(8_000_000, token);
        return JsonDocument.Parse(await response.Content.ReadAsStringAsync(token));
    }
    private Task<JsonDocument> Metadata(string id, string account, string? key, CancellationToken token) =>
        ReadAsync($"https://www.googleapis.com/drive/v3/files/{Uri.EscapeDataString(id)}?supportsAllDrives=true&fields={Uri.EscapeDataString(Fields)}", account, id, key, token);
    public async Task<MediaAnalysis> AnalyzeForAccountAsync(string url, string account, CancellationToken token)
    {
        var id = PublicDriveService.FileId(url) ?? throw new InvalidOperationException("ลิงก์ Drive ไม่ถูกต้อง");
        var key = ResourceKey(url);
        using var document = await Metadata(id, account, key, token);
        var root = document.RootElement;
        var mime = String(root, "mimeType") ?? "";
        if (mime == "application/vnd.google-apps.shortcut")
        {
            var target = root.GetProperty("shortcutDetails");
            // One explicit lookup; chains/cycles must not recurse indefinitely.
            using var targetDocument = await Metadata(target.GetProperty("targetId").GetString()!, account, String(target, "targetResourceKey"), token);
            return await BuildAsync(targetDocument.RootElement, account, token);
        }
        return await BuildAsync(root, account, token);
    }
    private async Task<MediaAnalysis> BuildAsync(JsonElement root, string account, CancellationToken token)
    {
        var id = root.GetProperty("id").GetString()!; var mime = String(root, "mimeType")!;
        var title = ExportName(String(root, "name") ?? "Google Drive", mime);
        var key = String(root, "resourceKey");
        if (mime != "application/vnd.google-apps.folder")
        {
            AssertDownloadable(root);
            return new(title, "Google Drive", "Google Drive · " + accounts.Accounts.First(a => a.Id == account).Email,
                Thumbnail(root), Size(root), false, false, null, account, mime, key, id);
        }
        List<MediaEntry> files = []; var visiting = new HashSet<string>();
        async Task Walk(string folderId, string relative, string? resourceKey, int depth)
        {
            if (depth > 20 || !visiting.Add(folderId)) throw new InvalidOperationException("โฟลเดอร์ซับซ้อนหรือวนซ้ำ กรุณาเลือกโฟลเดอร์ย่อย");
            string? page = null;
            do
            {
                var endpoint = "https://www.googleapis.com/drive/v3/files?supportsAllDrives=true&includeItemsFromAllDrives=true&pageSize=1000&q=" +
                    Uri.EscapeDataString($"'{folderId.Replace("'", "\\'")}' in parents and trashed = false") + "&fields=" + Uri.EscapeDataString($"nextPageToken,incompleteSearch,files({Fields})") +
                    (page != null ? "&pageToken=" + Uri.EscapeDataString(page) : "");
                using var result = await ReadAsync(endpoint, account, folderId, resourceKey, token);
                if (result.RootElement.TryGetProperty("incompleteSearch", out var incomplete) && incomplete.ValueKind == JsonValueKind.True)
                    throw new InvalidOperationException("Google ส่งรายการมาไม่ครบ กรุณาเลือกโฟลเดอร์ย่อย");
                foreach (var original in result.RootElement.GetProperty("files").EnumerateArray())
                {
                    JsonDocument? shortcut = null;
                    try
                    {
                        var file = original;
                        if (String(file, "mimeType") == "application/vnd.google-apps.shortcut")
                        {
                            var target = file.GetProperty("shortcutDetails");
                            shortcut = await Metadata(target.GetProperty("targetId").GetString()!, account, String(target, "targetResourceKey"), token);
                            file = shortcut.RootElement;
                        }
                        var childId = file.GetProperty("id").GetString()!; var childMime = String(file, "mimeType")!;
                        var name = String(original, "name") ?? String(file, "name") ?? childId;
                        if (childMime == "application/vnd.google-apps.folder") await Walk(childId, Path.Combine(relative, MediaOptions.SafeName(name)), String(file, "resourceKey"), depth + 1);
                        else
                        {
                            AssertDownloadable(file);
                            if (files.Count >= 10000) throw new InvalidOperationException("โฟลเดอร์มีไฟล์มากเกินไป กรุณาเลือกโฟลเดอร์ย่อย");
                            files.Add(new() { Index = files.Count + 1, StableId = "drive:" + childId, Title = ExportName(name, childMime),
                                Url = "https://drive.google.com/file/d/" + childId + "/view", MimeType = childMime, ResourceKey = String(file, "resourceKey"),
                                RelativeFolder = relative, Kind = Kind(childMime), ThumbnailUrl = Thumbnail(file), Size = Size(file),
                                Fingerprint = String(file, "md5Checksum") ?? String(file, "modifiedTime") ?? String(file, "version") });
                        }
                    }
                    finally { shortcut?.Dispose(); }
                }
                page = String(result.RootElement, "nextPageToken");
            } while (page != null);
            visiting.Remove(folderId);
        }
        await Walk(id, "", key, 0);
        if (files.Count == 0) throw new InvalidOperationException("โฟลเดอร์ว่าง");
        return new(title, "Google Drive", $"Google Drive · {files.Count} ไฟล์ · {accounts.Accounts.First(a => a.Id == account).Email}", files.FirstOrDefault(f => f.ThumbnailUrl != null)?.ThumbnailUrl,
            files.All(f => f.Size != null) ? files.Sum(f => f.Size ?? 0) : null, false, true, files, account, mime, key, id);
    }
    private static void AssertDownloadable(JsonElement file)
    {
        if (String(file, "mimeType") == "application/vnd.google-apps.shortcut") throw new InvalidOperationException("ทางลัด Drive ซ้อนกัน กรุณาใช้ลิงก์ไฟล์ต้นทาง");
        if (file.TryGetProperty("capabilities", out var capabilities) && capabilities.TryGetProperty("canDownload", out var can) && can.ValueKind == JsonValueKind.False)
            throw new InvalidOperationException("เจ้าของไฟล์ไม่อนุญาตให้ดาวน์โหลดไฟล์นี้");
    }
    public static string DownloadUrl(string id, string? mime) => mime?.StartsWith("application/vnd.google-apps.", StringComparison.Ordinal) == true
        ? $"https://www.googleapis.com/drive/v3/files/{Uri.EscapeDataString(id)}/export?mimeType={Uri.EscapeDataString(ExportMime(mime))}"
        : $"https://www.googleapis.com/drive/v3/files/{Uri.EscapeDataString(id)}?alt=media&supportsAllDrives=true";
    public static string ExportMime(string mime) => mime switch {
        "application/vnd.google-apps.document" => "application/vnd.openxmlformats-officedocument.wordprocessingml.document",
        "application/vnd.google-apps.spreadsheet" => "application/vnd.openxmlformats-officedocument.spreadsheetml.sheet",
        "application/vnd.google-apps.presentation" => "application/vnd.openxmlformats-officedocument.presentationml.presentation",
        "application/vnd.google-apps.drawing" => "application/pdf",
        _ => throw new InvalidOperationException("ไฟล์ Google ชนิดนี้ยังส่งออกไม่ได้ ใช้ลิงก์ไฟล์ที่ส่งออกแล้ว") };
    public static string ExportName(string name, string mime)
    {
        var extension = mime switch { "application/vnd.google-apps.document" => ".docx", "application/vnd.google-apps.spreadsheet" => ".xlsx", "application/vnd.google-apps.presentation" => ".pptx", "application/vnd.google-apps.drawing" => ".pdf", _ => "" };
        return name.EndsWith(extension, StringComparison.OrdinalIgnoreCase) ? name : name + extension;
    }
    private static string Kind(string mime) => mime.StartsWith("image/", StringComparison.Ordinal) ? "image" : mime.StartsWith("video/", StringComparison.Ordinal) ? "video" : mime.StartsWith("audio/", StringComparison.Ordinal) ? "audio" : "document";
    private static string? String(JsonElement element, string name) => element.TryGetProperty(name, out var value) && value.ValueKind == JsonValueKind.String ? value.GetString() : null;
    private static string? Thumbnail(JsonElement file) => Uri.TryCreate(String(file, "thumbnailLink"), UriKind.Absolute, out var uri) && uri.Scheme == "https" &&
        (uri.Host == "googleusercontent.com" || uri.Host.EndsWith(".googleusercontent.com", StringComparison.Ordinal)) ? uri.AbsoluteUri : null;
    private static long? Size(JsonElement file) => long.TryParse(String(file, "size"), out var value) && value >= 0 ? value : null;
    public static string? ResourceKey(string url) => new Uri(url).Query.TrimStart('?').Split('&').Select(p => p.Split('=', 2)).FirstOrDefault(p => p.Length == 2 && p[0] == "resourcekey") is { } pair ? Uri.UnescapeDataString(pair[1]) : null;
}
