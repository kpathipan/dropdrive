using System.ComponentModel;
using System.Runtime.CompilerServices;

namespace DropDrive.Windows.Models;

public sealed class DownloadItem : INotifyPropertyChanged
{
    private double _progress;
    private string _status = "Waiting";
    private string _name = "Download";
    private string _detail = "";
    private bool _canCancel;
    private bool _canRetry;
    public Guid Id { get; init; } = Guid.NewGuid();
    public required string Url { get; init; }
    public string Name { get => _name; set => Set(ref _name, value); }
    public string Source { get; set; } = "Link";
    public bool AudioOnly { get; set; }
    public DateTimeOffset CreatedAt { get; init; } = DateTimeOffset.Now;
    public double Progress { get => _progress; set => Set(ref _progress, value); }
    public string Status { get => _status; set => Set(ref _status, value); }
    public string Detail { get => _detail; set => Set(ref _detail, value); }
    public bool CanCancel { get => _canCancel; set => Set(ref _canCancel, value); }
    public bool CanRetry { get => _canRetry; set => Set(ref _canRetry, value); }
    public event PropertyChangedEventHandler? PropertyChanged;

    private void Set<T>(ref T field, T value, [CallerMemberName] string? property = null)
    {
        if (EqualityComparer<T>.Default.Equals(field, value)) return;
        field = value;
        PropertyChanged?.Invoke(this, new PropertyChangedEventArgs(property));
    }
}
