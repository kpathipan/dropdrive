using DropDrive.Windows.Models;

namespace DropDrive.Windows.Services;

// Identifiers/fingerprints only: never another copy of a downloaded file.
public sealed class CollectionReceipt
{
    public DateTimeOffset UpdatedAt { get; set; }
    public Dictionary<string, string> Files { get; set; } = [];
    public static string CollectionKey(string url) => LinkIdentity.Key(url);
    public static string EntryKey(MediaEntry entry) => entry.StableId ??
        (PublicDriveService.FileId(entry.Url ?? "") is { } id ? "drive:" + id : entry.Url ?? entry.Title);
    public static string Version(MediaEntry entry) => entry.Fingerprint ?? $"{entry.Kind}|{entry.Title}|{entry.Size}|{entry.RelativeFolder}";
    public string State(MediaEntry entry) => !Files.TryGetValue(EntryKey(entry), out var version) ? "ใหม่" :
        version == Version(entry) ? "โหลดแล้ว" : "เปลี่ยนแปลง";
}

public sealed class LocalStatistics
{
    public long Downloads { get; set; }
    public long Bytes { get; set; }
}
