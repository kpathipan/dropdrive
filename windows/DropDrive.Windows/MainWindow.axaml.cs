using System.Collections.ObjectModel;
using Avalonia.Controls;
using Avalonia.Controls.ApplicationLifetimes;
using Avalonia.Input;
using Avalonia.Interactivity;
using Avalonia.Platform.Storage;
using DropDrive.Windows.Models;
using DropDrive.Windows.Services;

namespace DropDrive.Windows;

public partial class MainWindow : Window
{
    private readonly ObservableCollection<DownloadItem> _downloads = [];
    private readonly ObservableCollection<DownloadHistoryEntry> _history = [];
    private readonly Dictionary<Guid, CancellationTokenSource> _cancellations = [];
    private readonly SemaphoreSlim _downloadGate = new(1, 1);
    private readonly DownloadService _downloadService = new();
    private readonly MediaAnalysisService _analysisService = new();
    private readonly UpdateService _updateService = new();
    private readonly AppStateService _stateService = new();
    private readonly AppSettings _settings;
    private bool _loadingSettings = true;

    public MainWindow()
    {
        InitializeComponent();
        _settings = _stateService.LoadSettings();
        DownloadList.ItemsSource = _downloads;
        HistoryList.ItemsSource = _history;
        RefreshHistory();
        UpdateDestinationLabels();
        AutoUpdateToggle.IsChecked = _settings.CheckUpdatesAutomatically;
        HideToTrayToggle.IsChecked = _settings.HideToTray;
        _loadingSettings = false;
        RestoreQueue();
        Closing += HandleClosing;
        Opened += async (_, _) => await CheckForUpdatesIfDueAsync();
    }

    private async void AddDownload(object? sender, RoutedEventArgs e) => await QueueLinksAsync();

    private async Task QueueLinksAsync()
    {
        var links = LinkInputParser.Parse(LinkBox.Text);
        if (links.Count == 0) { SetStatus("วางลิงก์เว็บที่ถูกต้องก่อน"); return; }
        LinkBox.Text = "";
        DownloadButton.IsEnabled = false;
        HeaderStatus.Text = "กำลังวิเคราะห์";
        foreach (var link in links)
        {
            var uri = new Uri(link);
            var item = new DownloadItem { Url = link, Name = uri.Host.Replace("www.", "", StringComparison.OrdinalIgnoreCase), Source = uri.Host, AudioOnly = false, Destination = _settings.Destination, Status = "Analyzing", Detail = "กำลังอ่านข้อมูลลิงก์…" };
            _downloads.Insert(0, item);
            try
            {
                using var timeout = new CancellationTokenSource(TimeSpan.FromSeconds(30));
                var analysis = await _analysisService.AnalyzeAsync(link, timeout.Token);
                item.Name = analysis.Title;
                item.Source = analysis.Source;
                item.EstimatedBytes = analysis.EstimatedBytes;
                item.Detail = analysis.Detail + (item.AudioOnly ? " · MP3" : "");
                item.Status = "Ready";
                item.CanStart = true;
                item.ActionLabel = _downloads.Any(IsInProgress) ? "เข้าคิว" : "ดาวน์โหลด";
            }
            catch (OperationCanceledException) { item.Detail = "วิเคราะห์ใช้เวลานานเกินไป ตรวจสอบแล้วดำเนินการต่อได้"; item.Status = "Ready"; item.CanStart = true; }
            catch (Exception error)
            {
                item.Status = "Failed"; item.Detail = error.Message; item.CanRetry = true;
                _stateService.AddHistory(item); RefreshHistory(); continue;
            }
            SaveQueue();
        }
        DownloadButton.IsEnabled = true;
        HeaderStatus.Text = "พร้อมใช้งาน";
        UpdateQueueSummary();
    }

    private async Task RunDownloadAsync(DownloadItem item)
    {
        var cancellation = new CancellationTokenSource();
        _cancellations[item.Id] = cancellation;
        item.CanCancel = true; item.CanRetry = false; item.CanStart = false;
        var enteredGate = false;
        try
        {
            await _downloadGate.WaitAsync(cancellation.Token);
            enteredGate = true;
            HeaderStatus.Text = "กำลังดาวน์โหลด";
            UpdateQueueSummary();
            await _downloadService.DownloadAsync(item, item.Destination ?? _settings.Destination, cancellation.Token);
            SetStatus($"ดาวน์โหลดเสร็จแล้ว: {item.Name}");
        }
        catch (OperationCanceledException)
        {
            item.Status = "Cancelled"; item.Detail = "ยกเลิกการดาวน์โหลดแล้ว"; item.CanCancel = false; item.CanRetry = true;
            SetStatus($"ยกเลิกแล้ว: {item.Name}");
        }
        catch (Exception error)
        {
            item.Status = "Failed"; item.Detail = error.Message; item.CanCancel = false; item.CanRetry = true;
            SetStatus(error.Message);
        }
        finally
        {
            if (enteredGate) _downloadGate.Release();
            _cancellations.Remove(item.Id);
            if (item.Status is "Complete" or "Failed" or "Cancelled") _stateService.AddHistory(item);
            RefreshHistory();
            HeaderStatus.Text = _downloads.Any(IsInProgress) ? "กำลังดาวน์โหลด" : "พร้อมใช้งาน";
            UpdateQueueSummary();
            SaveQueue();
        }
    }

    private void StartDownload(object? sender, RoutedEventArgs e)
    {
        if (sender is not Button { Tag: DownloadItem item }) return;
        item.Status = _downloads.Any(IsInProgress) ? "Waiting" : "Starting";
        item.ActionLabel = "เข้าคิว";
        _ = RunDownloadAsync(item);
        SaveQueue();
    }

    private void CancelDownload(object? sender, RoutedEventArgs e)
    {
        if (sender is Button { Tag: DownloadItem item } && _cancellations.TryGetValue(item.Id, out var cancellation)) cancellation.Cancel();
    }

    private void RetryDownload(object? sender, RoutedEventArgs e)
    {
        if (sender is not Button { Tag: DownloadItem item }) return;
        item.Progress = 0; item.Status = "Waiting"; item.Detail = item.AudioOnly ? "รอคิว · MP3" : "รอคิว";
        _ = RunDownloadAsync(item);
    }

    private async void ChooseFolder(object? sender, RoutedEventArgs e)
    {
        var choices = await StorageProvider.OpenFolderPickerAsync(new FolderPickerOpenOptions { Title = "เลือกโฟลเดอร์ดาวน์โหลด", AllowMultiple = false });
        var path = choices.FirstOrDefault()?.TryGetLocalPath();
        if (string.IsNullOrWhiteSpace(path)) return;
        _settings.Destination = path; _stateService.SaveSettings(_settings); UpdateDestinationLabels(); SetStatus("เปลี่ยนโฟลเดอร์ดาวน์โหลดแล้ว");
    }

    private void SettingsChanged(object? sender, RoutedEventArgs e)
    {
        if (_loadingSettings) return;
        _settings.CheckUpdatesAutomatically = AutoUpdateToggle.IsChecked == true;
        _settings.HideToTray = HideToTrayToggle.IsChecked == true;
        _stateService.SaveSettings(_settings); SetStatus("บันทึกการตั้งค่าแล้ว");
    }

    private void ShowDownloads(object? sender, RoutedEventArgs e) => ShowPage(DownloadsPage);
    private void ShowHistory(object? sender, RoutedEventArgs e) { RefreshHistory(); ShowPage(RecentPage); }
    private void ShowSettings(object? sender, RoutedEventArgs e) => ShowPage(SettingsPage);

    private void ShowPage(Control page)
    {
        DownloadsPage.IsVisible = page == DownloadsPage; RecentPage.IsVisible = page == RecentPage;
        SettingsPage.IsVisible = page == SettingsPage;
    }

    private void ClearHistory(object? sender, RoutedEventArgs e) { _stateService.ClearHistory(); RefreshHistory(); SetStatus("ล้างประวัติการดาวน์โหลดแล้ว"); }

    private void RefreshHistory()
    {
        _history.Clear(); foreach (var entry in _stateService.LoadHistory()) _history.Add(entry);
        HistoryEmpty.IsVisible = _history.Count == 0;
    }

    private void LinkBoxKeyDown(object? sender, KeyEventArgs e)
    {
        if (e.Key != Key.Enter) return; e.Handled = true; _ = QueueLinksAsync();
    }

    private void LinkBoxTextChanged(object? sender, TextChangedEventArgs e) =>
        DownloadButton.IsVisible = !string.IsNullOrWhiteSpace(LinkBox.Text);

    private async void CheckForUpdates(object? sender, RoutedEventArgs e) => await CheckForUpdatesAsync(false);
    private async Task CheckForUpdatesIfDueAsync()
    {
        var now = DateTimeOffset.UtcNow;
        if (!_settings.IsAutomaticUpdateCheckDue(now)) return;
        // Record before the network request so an offline PC does not retry on
        // every window open. Manual checks always bypass this 24-hour gate.
        _settings.LastAutomaticUpdateCheckUtc = now;
        _stateService.SaveSettings(_settings);
        await CheckForUpdatesAsync(true);
    }

    private async Task CheckForUpdatesAsync(bool silent)
    {
        if (!silent) SetStatus("กำลังตรวจหาอัปเดต…");
        var result = await _updateService.CheckDownloadAndRestartAsync();
        if (!silent || result.Restarting || result.IsError) SetStatus(result.Message);
    }

    private void HandleClosing(object? sender, WindowClosingEventArgs e)
    {
        SaveQueue();
        if (_settings.HideToTray) { e.Cancel = true; Hide(); SetStatus("DropDrive ยังทำงานอยู่ในถาดระบบ"); }
        else if (Avalonia.Application.Current?.ApplicationLifetime is IClassicDesktopStyleApplicationLifetime desktop) desktop.Shutdown();
    }

    private void UpdateDestinationLabels() { DestinationLabel.Text = _settings.Destination; SettingsDestinationLabel.Text = _settings.Destination; }
    private void RestoreQueue()
    {
        foreach (var item in _stateService.LoadQueue())
        {
            if (item.Status is "Downloading" or "Waiting" or "Starting") item.Status = "Paused";
            if (item.Status is "Ready" or "Paused") { item.CanStart = true; item.ActionLabel = "ดาวน์โหลด"; }
            item.CanCancel = false;
            item.CanRetry = item.Status is "Failed" or "Cancelled";
            _downloads.Add(item);
        }
        UpdateQueueSummary();
    }

    private void SaveQueue() => _stateService.SaveQueue(_downloads.Where(item => item.Status != "Complete"));
    private void UpdateQueueSummary() { var active = _downloads.Count(IsInProgress); QueueSummary.Text = active == 0 ? "ยังไม่มีรายการ" : $"กำลังทำงาน {active} รายการ"; }
    private static bool IsInProgress(DownloadItem item) => item.Status is "Waiting" or "Starting" or "Analyzing" or "Downloading";
    private void SetStatus(string message) => StatusLabel.Text = message;
}
