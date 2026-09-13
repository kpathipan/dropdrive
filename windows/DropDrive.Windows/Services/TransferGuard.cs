namespace DropDrive.Windows.Services;

public static class TransferGuard
{
    private const long ReserveBytes = 256L * 1024 * 1024;

    public static void EnsureSpace(string destination, long? requiredBytes)
    {
        if (requiredBytes is null or <= 0) return;
        var root = Path.GetPathRoot(Path.GetFullPath(destination));
        if (string.IsNullOrWhiteSpace(root)) return;
        var available = new DriveInfo(root).AvailableFreeSpace;
        if (available - ReserveBytes < requiredBytes)
            throw new IOException("There is not enough free space for this download.");
    }
}
