using Velopack;
using Velopack.Sources;

namespace DropDrive.Windows.Services;

public sealed class UpdateService
{
    private const string Repository = "https://github.com/kpathipan/dropdrive";

    public async Task<UpdateCheckResult> CheckDownloadAndRestartAsync(CancellationToken cancellationToken = default)
    {
        try
        {
            var manager = new UpdateManager(new GithubSource(Repository, null, false));
            if (!manager.IsInstalled) return new(false, "ตรวจอัปเดตได้หลังติดตั้งแอปแล้ว");
            var update = await manager.CheckForUpdatesAsync();
            if (update is null) return new(false, "DropDrive เป็นเวอร์ชันล่าสุดแล้ว");
            await manager.DownloadUpdatesAsync(update, null, cancellationToken);
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
