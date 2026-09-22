using Velopack;
using Velopack.Sources;

namespace DropDrive.Windows.Services;

public sealed class UpdateService
{
    private UpdateManager? _manager;
    private UpdateInfo? _pending;
    public bool HasPendingUpdate => _pending != null;

    public async Task<UpdateCheckResult> CheckDownloadAndRestartAsync(Func<bool> canRestart, CancellationToken cancellationToken = default)
    {
        try
        {
            var manager = _manager ??= new UpdateManager(new PlatformGithubSource());
            if (!manager.IsInstalled) return new(false, "ตรวจอัปเดตได้หลังติดตั้งแอปแล้ว");
            var update = _pending ?? await manager.CheckForUpdatesAsync();
            if (update is null) return new(false, "DropDrive เป็นเวอร์ชันล่าสุดแล้ว");
            if (_pending == null) await manager.DownloadUpdatesAsync(update, null, cancellationToken);
            _pending = update;
            if (!canRestart()) return new(false, "ดาวน์โหลดอัปเดตแล้ว จะติดตั้งเมื่อไม่มีงานค้าง");
            manager.ApplyUpdatesAndRestart(update);
            return new(true, "กำลังเปิดแอปใหม่เพื่อติดตั้งอัปเดต…");
        }
        catch (Exception error)
        {
            return new(false, $"ตรวจอัปเดตไม่ได้: {FriendlyMessage(error)}", true);
        }
    }

    private static string FriendlyMessage(Exception error) => error switch {
        HttpRequestException => "กรุณาตรวจการเชื่อมต่ออินเทอร์เน็ต",
        TaskCanceledException => "การเชื่อมต่อใช้เวลานานเกินไป",
        _ => "ระบบอัปเดตของ Windows ยังไม่พร้อมใช้งาน"
    };
}

public sealed record UpdateCheckResult(bool Restarting, string Message, bool IsError = false);
