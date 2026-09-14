using System.ComponentModel;
using System.Runtime.CompilerServices;

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
    public Guid Id { get; init; } = Guid.NewGuid();
    public required string Url { get; init; }
    public string Name { get => _name; set => Set(ref _name, value); }
    public string Source { get; set; } = "Link";
    public bool AudioOnly { get; set; }
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

    private void Set<T>(ref T field, T value, [CallerMemberName] string? property = null)
    {
        if (EqualityComparer<T>.Default.Equals(field, value)) return;
        field = value;
        PropertyChanged?.Invoke(this, new PropertyChangedEventArgs(property));
    }
}
