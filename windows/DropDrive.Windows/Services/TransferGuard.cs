namespace DropDrive.Windows.Services;

public static class TransferGuard
{
    public static void EnsureSpace(string destination, long? requiredBytes)
    {
        if (!Directory.Exists(destination))
            throw new DirectoryNotFoundException("ไม่พบโฟลเดอร์ปลายทาง เชื่อมต่อไดรฟ์หรือเลือกโฟลเดอร์ใหม่");
        if (requiredBytes is null or <= 0) return;
        var root = Path.GetPathRoot(Path.GetFullPath(destination));
        if (string.IsNullOrWhiteSpace(root)) return;
        var available = new DriveInfo(root).AvailableFreeSpace;
        if (available < requiredBytes)
            throw new IOException("พื้นที่ว่างไม่เพียงพอสำหรับการดาวน์โหลดนี้");
    }
}
