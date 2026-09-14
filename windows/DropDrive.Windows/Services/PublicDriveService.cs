using System.Net;
using System.Text.RegularExpressions;
using AngleSharp.Html.Parser;
using DropDrive.Windows.Models;

namespace DropDrive.Windows.Services;

/// <summary>
/// Anonymous Drive shares only. Never reads browser cookies or tries another
/// identity. Missing/inaccessible entries fail analysis instead of silently
/// downloading an incomplete folder.
/// </summary>
public sealed partial class PublicDriveService(HttpClient? client = null)
{
    private readonly HttpClient _client = client ?? new() { Timeout = TimeSpan.FromSeconds(20) };
    public static bool IsDriveUrl(string url) => Uri.TryCreate(url, UriKind.Absolute, out var uri) && uri.Host is "drive.google.com" or "docs.google.com";
    public static string? FileId(string url)
    {
        if (!IsDriveUrl(url)) return null;
        var match = IdPattern().Match(url);
        return match.Success ? match.Groups[1].Value : null;
    }
    public static bool IsFolder(string url) => IsDriveUrl(url) && new Uri(url).AbsolutePath.Contains("/folders/", StringComparison.Ordinal);

    public async Task<MediaAnalysis> AnalyzeAsync(string url, CancellationToken token)
    {
        var id = FileId(url) ?? throw new InvalidOperationException("ไม่พบรหัสไฟล์ในลิงก์ Drive");
        if (!IsFolder(url))
        {
            var html = await GetHtmlAsync(url, token);
            var doc = new HtmlParser().ParseDocument(html);
            var title = doc.QuerySelector("meta[property='og:title']")?.GetAttribute("content") ?? doc.Title;
            if (string.IsNullOrWhiteSpace(title) || title.Contains("Sign in", StringComparison.OrdinalIgnoreCase) || doc.QuerySelector("input[type='password']") != null)
                throw new InvalidOperationException("ไฟล์นี้ต้องมีสิทธิ์เข้าถึง Windows รองรับเฉพาะ Drive ที่เปิดแชร์สาธารณะ");
            title = title.Replace(" - Google Drive", "", StringComparison.Ordinal);
            return new(title, "Google Drive", "ไฟล์ Drive สาธารณะ", $"https://drive.google.com/thumbnail?id={Uri.EscapeDataString(id)}&sz=w320", null, false);
        }
        List<MediaEntry> files = [];
        var visited = new HashSet<string>(StringComparer.Ordinal);
        async Task<string> Walk(string folderId, string relative, int depth)
        {
            if (depth > 20 || files.Count > 2000) throw new InvalidOperationException("โฟลเดอร์นี้ใหญ่หรือซับซ้อนเกินไป กรุณาเลือกลิงก์โฟลเดอร์ย่อย");
            if (!visited.Add(folderId)) throw new InvalidOperationException("พบโฟลเดอร์ที่วนซ้ำ กรุณาเลือกลิงก์โฟลเดอร์ย่อย");
            var html = await GetHtmlAsync($"https://drive.google.com/embeddedfolderview?id={Uri.EscapeDataString(folderId)}", token);
            var (title, children) = ParseFolder(html);
            foreach (var child in children)
            {
                if (IsFolder(child.Url))
                    await Walk(FileId(child.Url)!, Path.Combine(relative, MediaOptions.SafeName(child.Title)), depth + 1);
                else
                {
                    var ext = Path.GetExtension(child.Title).ToLowerInvariant();
                    var kind = ext is ".mp4" or ".mov" or ".mkv" or ".webm" ? "video" :
                        ext is ".jpg" or ".jpeg" or ".png" or ".webp" or ".gif" ? "image" :
                        ext is ".mp3" or ".wav" or ".m4a" or ".flac" ? "audio" : "document";
                    files.Add(new MediaEntry { Index = files.Count + 1, Title = child.Title, Url = child.Url, Kind = kind,
                        RelativeFolder = relative, ThumbnailUrl = kind is "video" or "image" ? $"https://drive.google.com/thumbnail?id={Uri.EscapeDataString(FileId(child.Url)!)}&sz=w320" : null });
                }
            }
            return title;
        }
        var name = await Walk(id, "", 0);
        if (files.Count == 0) throw new InvalidOperationException("โฟลเดอร์ว่าง หรือไม่มีไฟล์ที่เปิดแชร์สาธารณะ");
        return new(name, "Google Drive", $"Google Drive · {files.Count} ไฟล์", files.FirstOrDefault(entry => entry.ThumbnailUrl != null)?.ThumbnailUrl, null, false, true, files);
    }

    public static (string Title, List<(string Title, string Url)> Children) ParseFolder(string html)
    {
        var doc = new HtmlParser().ParseDocument(html);
        if (doc.QuerySelector("#flip-contents") == null)
            throw new InvalidOperationException("อ่านโฟลเดอร์ไม่ได้ ตรวจสอบสิทธิ์แชร์สาธารณะหรือการเชื่อมต่อ");
        // Refuse paginated/incomplete views rather than treating the first page as all.
        if (doc.QuerySelector("[rel='next'], .flip-next-page") != null)
            throw new InvalidOperationException("โฟลเดอร์มีหลายหน้า กรุณาเลือกลิงก์โฟลเดอร์ย่อยเพื่อให้ได้ไฟล์ครบ");
        var children = new List<(string Title, string Url)>();
        var seen = new HashSet<string>(StringComparer.Ordinal);
        foreach (var anchor in doc.QuerySelectorAll("#flip-contents a[href]"))
        {
            var href = anchor.GetAttribute("href");
            if (href == null || FileId(href) == null || !seen.Add(href)) continue;
            var title = anchor.QuerySelector(".flip-entry-title")?.TextContent ?? anchor.TextContent;
            if (string.IsNullOrWhiteSpace(title)) continue;
            if (new Uri(href).Host == "docs.google.com")
            {
                var type = new Uri(href).AbsolutePath.Split('/', StringSplitOptions.RemoveEmptyEntries).FirstOrDefault();
                var extension = type switch { "document" => ".docx", "spreadsheets" => ".xlsx", "presentation" => ".pptx", _ => "" };
                if (extension.Length == 0) throw new InvalidOperationException("มีชนิดเอกสาร Google ที่ยังส่งออกไม่ได้ กรุณาเลือกไฟล์แยก");
                title += extension;
            }
            children.Add((title.Trim(), href));
        }
        return (doc.Title ?? "Google Drive", children);
    }

    private async Task<string> GetHtmlAsync(string url, CancellationToken token)
    {
        using var response = await _client.GetAsync(url, HttpCompletionOption.ResponseHeadersRead, token);
        response.EnsureSuccessStatusCode();
        if (response.Content.Headers.ContentLength > 8_000_000) throw new InvalidOperationException("ข้อมูลโฟลเดอร์ใหญ่เกินไป กรุณาเลือกโฟลเดอร์ย่อย");
        await response.Content.LoadIntoBufferAsync(8_000_000, token);
        return await response.Content.ReadAsStringAsync(token);
    }

    public static string DownloadUrl(string url)
    {
        var id = FileId(url) ?? throw new InvalidOperationException("ลิงก์ Drive ไม่ถูกต้อง");
        var path = new Uri(url).AbsolutePath;
        if (path.StartsWith("/document/", StringComparison.Ordinal)) return $"https://docs.google.com/document/d/{id}/export?format=docx";
        if (path.StartsWith("/spreadsheets/", StringComparison.Ordinal)) return $"https://docs.google.com/spreadsheets/d/{id}/export?format=xlsx";
        if (path.StartsWith("/presentation/", StringComparison.Ordinal)) return $"https://docs.google.com/presentation/d/{id}/export/pptx";
        var keyMatch = ResourceKeyPattern().Match(url);
        return $"https://drive.usercontent.google.com/download?id={id}&export=download" +
            (keyMatch.Success ? "&resourcekey=" + keyMatch.Groups[1].Value : "");
    }

    public static string ConfirmationUrl(string html)
    {
        var doc = new HtmlParser().ParseDocument(html);
        var form = doc.QuerySelector("form#download-form");
        var action = form?.GetAttribute("action");
        if (!Uri.TryCreate(action, UriKind.Absolute, out var endpoint) || endpoint.Scheme != "https" ||
            endpoint.Host is not ("drive.usercontent.google.com" or "drive.google.com" or "docs.google.com"))
            throw new InvalidOperationException("ดาวน์โหลด Drive ไม่ได้ ไฟล์อาจจำกัดสิทธิ์หรือเกินโควตา");
        var values = form!.QuerySelectorAll("input[type='hidden'][name]").Select(input =>
            Uri.EscapeDataString(input.GetAttribute("name")!) + "=" + Uri.EscapeDataString(input.GetAttribute("value") ?? ""));
        return action + (action.Contains('?') ? "&" : "?") + string.Join('&', values);
    }
    [GeneratedRegex(@"(?:/d/|/folders/|[?&]id=)([-\w]+)")]
    private static partial Regex IdPattern();
    [GeneratedRegex(@"[?&]resourcekey=([-\w]+)")]
    private static partial Regex ResourceKeyPattern();
}
