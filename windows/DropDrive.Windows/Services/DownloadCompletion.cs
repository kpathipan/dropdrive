using DropDrive.Windows.Models;

namespace DropDrive.Windows.Services;

public static class DownloadCompletion
{
    public static void Warn(DownloadItem item, string message)
    {
        if (!item.CompletionWarning.Contains(message, StringComparison.Ordinal))
            item.CompletionWarning = string.IsNullOrEmpty(item.CompletionWarning) ? message : item.CompletionWarning + " · " + message;
        item.Detail = Locale.Choose("บันทึกไฟล์แล้ว · ", "File saved · ") + item.CompletionWarning;
    }

    // Ancillary work must never turn an already verified download into Failed.
    public static void Optional(DownloadItem item, string warning, Action action)
    {
        try { action(); }
        catch (Exception error) when (error is IOException or UnauthorizedAccessException or InvalidOperationException or System.ComponentModel.Win32Exception)
        { Warn(item, warning); }
    }

    public static async Task VerifyMediaAsync(DownloadItem item, int exitCode, string errors,
        Func<string, CancellationToken, Task> validate, CancellationToken token)
    {
        token.ThrowIfCancellationRequested();
        // DDPATH is emitted at after_move, not at 100% transfer progress. Never
        // guess success from a .part file, a pre-existing output, or a partial playlist.
        if (exitCode != 0 && (item.IsCollection || item.OutputPaths.Count != 1))
            ThrowExtractorError(errors);
        if (item.OutputPaths.Count == 0)
            throw new IOException(Locale.Choose("ตัวดาวน์โหลดไม่ส่งไฟล์ผลลัพธ์กลับมา กรุณาตรวจโฟลเดอร์ปลายทาง", "No final output was reported. Check the destination folder."));
        foreach (var path in item.OutputPaths) await validate(path, token);
        token.ThrowIfCancellationRequested();
        if (exitCode != 0)
            Warn(item, Locale.Choose("ไฟล์ผ่านการตรวจแล้ว แต่ตัวดาวน์โหลดแจ้งปัญหาหลังบันทึก", "File validated, but the downloader reported a late error"));
    }

    private static void ThrowExtractorError(string errors)
    {
        if (DownloadService.IsTransientMediaError(errors)) throw new HttpRequestException(DownloadService.FriendlyError(errors));
        throw new InvalidOperationException(DownloadService.FriendlyError(errors));
    }
}
