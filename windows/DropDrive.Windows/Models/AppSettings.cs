namespace DropDrive.Windows.Models;

public sealed class AppSettings
{
    public string Destination { get; set; } = Path.Combine(
        Environment.GetFolderPath(Environment.SpecialFolder.UserProfile), "Downloads");
    public bool CheckUpdatesAutomatically { get; set; } = true;
    public bool HideToTray { get; set; } = true;
    public bool OpenFolderOnComplete { get; set; }
    public bool NotifyOnComplete { get; set; } = true;
    public bool PlayNotificationSound { get; set; } = true;
    public bool LaunchAtLogin { get; set; }
    public bool PhoneInboxEnabled { get; set; }
    public bool PhoneInboxAutoDownload { get; set; } = true;
    public string? PhoneInboxFolder { get; set; }
    public bool QueuePaused { get; set; }
    public bool CompatibleVideo { get; set; } = true;
    public long? BandwidthLimit { get; set; }
    public int Theme { get; set; }
    public string Language { get; set; } = "th";
    public int CardSize { get; set; } = 1;
    public int FileLayout { get; set; }
    public Dictionary<string, int> PlatformQuality { get; set; } = [];
    public List<string> RecentDestinations { get; set; } = [];
    public DateTimeOffset? LastAutomaticUpdateCheckUtc { get; set; }

    public bool IsAutomaticUpdateCheckDue(DateTimeOffset now) =>
        CheckUpdatesAutomatically &&
        (LastAutomaticUpdateCheckUtc is null || now - LastAutomaticUpdateCheckUtc >= TimeSpan.FromHours(24));
}

public sealed class DownloadHistoryEntry
{
    public required string Url { get; init; }
    public required string Name { get; init; }
    public required string Source { get; init; }
    public bool AudioOnly { get; init; }
    public string? ResultPath { get; init; }
    public string? Destination { get; init; }
    public int Quality { get; init; }
    public long Bytes { get; init; }
    public bool CanOpen => Status == "Complete" && !string.IsNullOrWhiteSpace(ResultPath);
    public required string Status { get; init; }
    public DateTimeOffset FinishedAt { get; init; } = DateTimeOffset.Now;
    public string DisplayStatus => Services.Locale.Text(Status switch {
        "Complete" => "เสร็จแล้ว", "Failed" => "ไม่สำเร็จ", "Cancelled" => "ยกเลิกแล้ว", _ => Status
    });
}
