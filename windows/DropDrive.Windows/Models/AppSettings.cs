namespace DropDrive.Windows.Models;

public sealed class AppSettings
{
    public string Destination { get; set; } = Path.Combine(
        Environment.GetFolderPath(Environment.SpecialFolder.UserProfile), "Downloads");
    public bool CheckUpdatesAutomatically { get; set; } = true;
    public bool HideToTray { get; set; } = true;
}

public sealed class DownloadHistoryEntry
{
    public required string Url { get; init; }
    public required string Name { get; init; }
    public required string Source { get; init; }
    public bool AudioOnly { get; init; }
    public required string Status { get; init; }
    public DateTimeOffset FinishedAt { get; init; } = DateTimeOffset.Now;
}
