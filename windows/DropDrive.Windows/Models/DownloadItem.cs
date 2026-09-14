using System.ComponentModel;
using System.Runtime.CompilerServices;
using System.Text.Json.Serialization;
using Avalonia.Media.Imaging;

namespace DropDrive.Windows.Models;

public sealed class DownloadItem : INotifyPropertyChanged
{
    private double _progress;
    private string _status = "Waiting";
    private string _name = "ดาวน์โหลด";
    private string _detail = "";
    private bool _canCancel;
    private bool _canRetry;
    private bool _canStart;
    private string _actionLabel = "ดาวน์โหลด";
    private string _speed = "—";
    private string _eta = "—";
    private string? _resultPath;
    public Guid Id { get; init; } = Guid.NewGuid();
    public required string Url { get; init; }
    public string Name { get => _name; set => Set(ref _name, value); }
    public string Source { get; set; } = "Link";
    public bool AudioOnly { get; set; }
    public int Quality { get; set; }
    public int SubtitleMode { get; set; }
    public bool SaveThumbnail { get; set; }
    public bool SplitChapters { get; set; }
    public bool CompatibleVideo { get; set; } = true;
    public long? BandwidthLimit { get; set; }
    public string ClipStart { get; set; } = "";
    public string ClipEnd { get; set; } = "";
    public bool IsMedia { get; set; } = true;
    public bool IsCollection { get; set; }
    public bool IsDrive { get; set; }
    public bool AnalysisCompleted { get; set; }
    public List<MediaEntry> Entries { get; set; } = [];
    public string? ThumbnailUrl { get; set; }
    public string? PartialPath { get; set; }
    public string? TargetPath { get; set; }
    public string? EntityTag { get; set; }
    public string? ResultPath { get => _resultPath; set { Set(ref _resultPath, value); Notify(nameof(CanOpen)); } }
    [JsonIgnore] public bool CanOpen => Status == "Complete" && !string.IsNullOrEmpty(ResultPath);
    [JsonIgnore] public bool IsActive => Status is "Starting" or "Waiting" or "Downloading";
    [JsonIgnore] public bool IsTransferring => Status == "Downloading";
    [JsonIgnore] public bool NeedsAttention => Status == "Failed";
    [JsonIgnore] public bool CanRemove => !IsActive && Status != "Analyzing";
    [JsonIgnore] public bool CanReorder => Status == "Waiting";
    [JsonIgnore] public Bitmap? Thumbnail { get; set; }
    public string Speed { get => _speed; set => Set(ref _speed, value); }
    public string Eta { get => _eta; set => Set(ref _eta, value); }
    public string? Destination { get; set; }
    public long? EstimatedBytes { get; set; }
    public DateTimeOffset CreatedAt { get; init; } = DateTimeOffset.Now;
    public double Progress { get => _progress; set => Set(ref _progress, value); }
    public string Status {
        get => _status;
        set {
            if (_status == value) return;
            _status = value;
            PropertyChanged?.Invoke(this, new PropertyChangedEventArgs(nameof(Status)));
            PropertyChanged?.Invoke(this, new PropertyChangedEventArgs(nameof(DisplayStatus)));
            foreach (var property in new[] { nameof(IsActive), nameof(IsTransferring), nameof(NeedsAttention), nameof(CanRemove), nameof(CanOpen), nameof(CanReorder) }) Notify(property);
        }
    }
    public string DisplayStatus => Status switch {
        "Ready" => "พร้อม", "Waiting" => "รอคิว", "Starting" => "กำลังเริ่ม",
        "Analyzing" => "กำลังวิเคราะห์", "Downloading" => "กำลังดาวน์โหลด",
        "Complete" => "เสร็จแล้ว", "Failed" => "ไม่สำเร็จ", "Cancelled" => "ยกเลิกแล้ว",
        "Paused" => "หยุดชั่วคราว", _ => Status
    };
    public string Detail { get => _detail; set => Set(ref _detail, value); }
    public bool CanCancel { get => _canCancel; set => Set(ref _canCancel, value); }
    public bool CanRetry { get => _canRetry; set => Set(ref _canRetry, value); }
    public bool CanStart { get => _canStart; set => Set(ref _canStart, value); }
    public string ActionLabel { get => _actionLabel; set => Set(ref _actionLabel, value); }
    public event PropertyChangedEventHandler? PropertyChanged;
    public void Notify(string property) => PropertyChanged?.Invoke(this, new PropertyChangedEventArgs(property));

    private void Set<T>(ref T field, T value, [CallerMemberName] string? property = null)
    {
        if (EqualityComparer<T>.Default.Equals(field, value)) return;
        field = value;
        PropertyChanged?.Invoke(this, new PropertyChangedEventArgs(property));
    }
}

public sealed class MediaEntry : INotifyPropertyChanged
{
    private bool _selected = true;
    public int Index { get; init; }
    public required string Title { get; init; }
    public string? Url { get; init; }
    public string? ThumbnailUrl { get; init; }
    public string RelativeFolder { get; init; } = "";
    public DownloadItem? Transfer { get; set; }
    public string Kind { get; init; } = "video";
    public long? Size { get; init; }
    public bool Selected { get => _selected; set { if (_selected == value) return; _selected = value; PropertyChanged?.Invoke(this, new(nameof(Selected))); } }
    [JsonIgnore] public Bitmap? Thumbnail { get; set; }
    [JsonIgnore] public string Icon => Kind switch { "audio" => "♫", "image" => "▧", "video" => "▷", _ => "▤" };
    public event PropertyChangedEventHandler? PropertyChanged;
    public void RefreshThumbnail() => PropertyChanged?.Invoke(this, new(nameof(Thumbnail)));
}
