using Avalonia;
using Avalonia.Controls;
using Avalonia.Interactivity;
using Avalonia.Platform.Storage;
using Avalonia.Threading;
using DropDrive.Windows.Models;
using DropDrive.Windows.Services;

namespace DropDrive.Windows;

public partial class MainWindow
{
    private WindowsIntegration? _windowsIntegration;
    private readonly PhoneInboxService _inbox = new();
    private readonly DispatcherTimer _recoveryTimer = new() { Interval = TimeSpan.FromSeconds(8) };
    private MediaEntry? _previewEntry;
    private bool _recovering;
    private readonly HashSet<Guid> _restartForBandwidth = [];
    private void CustomBandwidthChanged(object? sender, NumericUpDownValueChangedEventArgs e) => SavePreferences();

    private void InitializeParitySettings()
    {
        LanguageChoice.SelectedIndex = _settings.Language == "en" ? 1 : 0;
        Locale.Apply(_settings.Language == "en");
        NotifyCheck.IsChecked = _settings.NotifyOnComplete;
        SoundCheck.IsChecked = _settings.PlayNotificationSound;
        LaunchCheck.IsChecked = _backgroundServices && OperatingSystem.IsWindows() ? WindowsIntegration.IsLaunchAtLoginEnabled() : _settings.LaunchAtLogin;
        InboxCheck.IsChecked = _settings.PhoneInboxEnabled;
        InboxAutoCheck.IsChecked = _settings.PhoneInboxAutoDownload;
        InboxFolderLabel.Text = _settings.PhoneInboxFolder ?? "ยังไม่ได้เลือกโฟลเดอร์ซิงก์";
    }
    private void LanguageChanged(object? sender, SelectionChangedEventArgs e)
    {
        if (_loadingSettings) return;
        _settings.Language = LanguageChoice.SelectedIndex == 1 ? "en" : "th";
        Locale.Apply(_settings.Language == "en");
        var quality = QualityChoice.SelectedIndex; var subtitle = SubtitleChoice.SelectedIndex;
        QualityChoice.ItemsSource = MediaOptions.Qualities.Select(Locale.Text).ToArray(); QualityChoice.SelectedIndex = quality;
        SubtitleChoice.ItemsSource = MediaOptions.Subtitles.Select(Locale.Text).ToArray(); SubtitleChoice.SelectedIndex = subtitle;
        foreach (var item in _downloads) { item.Notify(nameof(DownloadItem.DisplayStatus)); item.Notify(nameof(DownloadItem.Detail)); }
        UpdateQueueSummary(); UpdateSelection(); RenderFiles(); RefreshHistory(); PersistSettings();
    }
    private void SaveParitySettings()
    {
        _settings.NotifyOnComplete = NotifyCheck.IsChecked == true;
        _settings.PlayNotificationSound = SoundCheck.IsChecked == true;
        _settings.PhoneInboxEnabled = InboxCheck.IsChecked == true;
        _settings.PhoneInboxAutoDownload = InboxAutoCheck.IsChecked == true;
        var launch = LaunchCheck.IsChecked == true;
        if (launch != _settings.LaunchAtLogin && _backgroundServices)
        {
            try { WindowsIntegration.SetLaunchAtLogin(launch); }
            catch (Exception error) when (error is UnauthorizedAccessException or IOException or System.Security.SecurityException)
            { LaunchCheck.IsChecked = WindowsIntegration.IsLaunchAtLoginEnabled(); SetStatus("เปลี่ยนการเปิดพร้อม Windows ไม่ได้ ตรวจสิทธิ์ผู้ใช้"); }
        }
        _settings.LaunchAtLogin = LaunchCheck.IsChecked == true;
    }
    private void StartParityServices()
    {
        if (OperatingSystem.IsWindows())
        {
            try
            {
                _windowsIntegration = new WindowsIntegration(this, BringToFront, () => { BringToFront(); ShowPage(SettingsPage); });
                try { WindowsIntegration.RegisterProtocol(); } catch (Exception error) when (error is UnauthorizedAccessException or System.Security.SecurityException or IOException) { SetStatus("ลงทะเบียนรับลิงก์ไม่ได้ ใช้การวางลิงก์ในแอปได้ตามปกติ"); }
                if (_windowsIntegration.TrayRegistered && Application.Current is { } app && TrayIcon.GetIcons(app) is { } icons)
                    foreach (var icon in icons) icon.IsVisible = false;
                ShortcutLabel.Text = _windowsIntegration.ShortcutRegistered ? "Ctrl+Shift+D · เปิด DropDrive" : "Ctrl+Shift+D ถูกใช้โดยแอปอื่น";
            }
            catch (InvalidOperationException) { SetStatus("ระบบแจ้งเตือนยังไม่พร้อม ใช้ไอคอนในถาดระบบเพื่อเปิดแอปได้"); }
        }
        _recoveryTimer.Tick += RecoveryTick;
        _recoveryTimer.Start();
    }
    private void StopParityServices() { _recoveryTimer.Stop(); _windowsIntegration?.Dispose(); }
    public void BringToFront() { Show(); WindowState = WindowState.Normal; Activate(); }
    public async void ReceiveActivation(string[] args)
    {
        BringToFront();
        var links = LinkInputParser.ExternalLinks(args);
        if (links.Count == 0) return;
        if (_analyzing || _review != null) { LinkBox.Text = string.Join('\n', links); SetStatus("รับลิงก์แล้ว ตรวจรายการปัจจุบันให้เสร็จก่อน"); return; }
        await AnalyzeLinksAsync(string.Join('\n', links));
    }
    private void NotifyResult(DownloadItem item, bool failed)
    {
        _windowsIntegration?.Notify(failed ? "ดาวน์โหลดต้องตรวจสอบ" : "ดาวน์โหลดเสร็จแล้ว", item.Name,
            _settings.PlayNotificationSound, () => { BringToFront(); if (failed) ShowAttention(null, new RoutedEventArgs()); else LaunchPath(item.ResultPath); });
    }
    private async void RecoveryTick(object? sender, EventArgs e)
    {
        if (_recovering || _quitting) return;
        _recovering = true;
        try
        {
            if (!_settings.QueuePaused)
            {
                foreach (var item in _downloads.Where(item => item.Status == "Failed" && item.AnalysisCompleted && item != _review))
                {
                    var recover = item.RetryAfter is { } due && due <= DateTimeOffset.UtcNow;
                    if (item.WaitForDestination && Directory.Exists(item.Destination)) recover = true;
                    if (!recover) continue;
                    item.RetryAfter = null; item.WaitForDestination = false;
                    item.Status = "Waiting"; item.CanRetry = false; item.CanCancel = true;
                }
                SaveQueue();
                _ = PumpQueueAsync();
            }
            if (_settings.PhoneInboxEnabled && _settings.PhoneInboxFolder is { } folder && !_analyzing && _review == null)
                await _inbox.ScanAsync(folder, async links => {
                    var fresh = links.Where(url => !_stateService.LoadHistory().Any(item => LinkIdentity.Key(item.Url) == LinkIdentity.Key(url) && item.Status == "Complete")).ToArray();
                    if (fresh.Length > 0) await AnalyzeLinksAsync(string.Join('\n', fresh), false);
                    var accepted = fresh.All(url => _downloads.Any(item => LinkIdentity.Key(item.Url) == LinkIdentity.Key(url) && item.AnalysisCompleted));
                    if (accepted)
                    {
                        if (_settings.PhoneInboxAutoDownload)
                            foreach (var item in _downloads.Where(item => fresh.Contains(item.Url) && item.Status == "Ready"))
                            { item.CompatibleVideo = _settings.CompatibleVideo; item.BandwidthLimit = _settings.BandwidthLimit; item.Status = "Waiting"; item.CanStart = false; item.CanCancel = true; }
                        _stateService.SaveQueue(_downloads.Where(item => item.Status != "Complete"));
                        SetStatus("รับลิงก์จากมือถือแล้ว");
                        _ = PumpQueueAsync();
                    }
                    return accepted;
                }, _lifetime.Token);
        }
        catch (OperationCanceledException) { }
        catch (Exception error) when (error is IOException or UnauthorizedAccessException) { SetStatus("อ่านกล่องรับลิงก์ไม่ได้ จะลองอีกครั้ง"); }
        finally { _recovering = false; }
    }
    private async void ChooseInbox(object? sender, RoutedEventArgs e)
    {
        var original = Opacity;
        try
        {
            Opacity = 0;
            var folders = await StorageProvider.OpenFolderPickerAsync(new() { Title = "เลือกโฟลเดอร์รับลิงก์จากมือถือ", AllowMultiple = false });
            if (folders.FirstOrDefault()?.TryGetLocalPath() is not { } path) return;
            _settings.PhoneInboxFolder = path; InboxFolderLabel.Text = path; PersistSettings();
        }
        catch (Exception error) { SetStatus(error.Message); }
        finally { Opacity = original; Activate(); }
    }
    private void ApplyReceipts(DownloadItem item)
    {
        var receipt = _stateService.LoadReceipts().GetValueOrDefault(CollectionReceipt.CollectionKey(item.Url));
        foreach (var entry in item.Entries) entry.SnapshotState = receipt?.State(entry) ?? "ใหม่";
    }
    private void SelectNewFiles(object? sender, RoutedEventArgs e)
    {
        if (_review == null) return;
        _selectingAll = true;
        foreach (var entry in _review.Entries) entry.Selected = entry.SnapshotState != "โหลดแล้ว";
        _selectingAll = false; UpdateSelection();
    }
    public void PauseEntireQueue()
    {
        _settings.QueuePaused = true; PersistSettings();
        foreach (var token in _cancellations.Values) token.Cancel();
        UpdateParitySummary();
    }
    public async Task ResumeEntireQueueAsync()
    {
        _settings.QueuePaused = false; PersistSettings();
        foreach (var item in _downloads.Where(item => item.Status == "Paused"))
        { item.Status = "Waiting"; item.CanStart = false; item.CanCancel = true; }
        SaveQueue(); UpdateParitySummary(); await PumpQueueAsync();
    }
    private async void ToggleQueue(object? sender, RoutedEventArgs e)
    {
        if (_settings.QueuePaused) await ResumeEntireQueueAsync(); else PauseEntireQueue();
    }
    private void UpdateParitySummary()
    {
        if (PauseQueueButton == null) return;
        PauseQueueButton.Content = Locale.Text(_settings.QueuePaused ? "เดินคิวต่อ" : "พักคิว");
        PauseQueueButton.IsVisible = _downloads.Any(item => item.IsActive || item.Status == "Paused");
        var stats = _stateService.LoadStatistics();
        StatisticsLabel.Text = Locale.Choose($"{stats.Downloads} งาน · {FormatBytes(stats.Bytes)} · เก็บเฉพาะเครื่องนี้", $"{stats.Downloads} jobs · {FormatBytes(stats.Bytes)} · Local only");
        BatchDownloadButton.IsVisible = _downloads.Count(item => item.Status == "Ready") > 1 && _review == null;
    }
    private async void DownloadReadyBatch(object? sender, RoutedEventArgs e)
    {
        var ready = _downloads.Where(item => item.Status == "Ready" && item.BatchSelected).ToArray();
        try
        {
            foreach (var item in ready) TransferGuard.EnsureSpace(item.Destination ?? _settings.Destination, item.EstimatedBytes);
            foreach (var item in ready)
            {
                item.CompatibleVideo = _settings.CompatibleVideo; item.BandwidthLimit = _settings.BandwidthLimit;
                item.Status = "Waiting"; item.CanStart = false; item.CanCancel = true;
            }
            _settings.QueuePaused = false; PersistSettings(); SaveQueue(); await PumpQueueAsync();
        }
        catch (Exception error) { SetStatus(error.Message); }
    }
    private void ShowDestinations(object? sender, RoutedEventArgs e)
    {
        if (sender is not Button button) return;
        var menu = new ContextMenu();
        foreach (var path in _settings.RecentDestinations.Where(Directory.Exists).Take(5))
        {
            var choice = new MenuItem { Header = FolderName(path) }; ToolTip.SetTip(choice, path);
            choice.Click += (_, _) => { if (_review != null) _review.Destination = path; _settings.Destination = path; PersistSettings(); SaveQueue(); UpdateDestinationLabels(); };
            menu.Items.Add(choice);
        }
        var browse = new MenuItem { Header = Locale.Text("เลือกโฟลเดอร์อื่น…") }; browse.Click += ChooseFolder; menu.Items.Add(browse);
        menu.Open(button);
    }
    private void ResizeForPage()
    {
        // Never driven by progress text, byte counts or ETA.
        Height = SettingsPage.IsVisible || RecentPage.IsVisible || _review != null ? 570 : _downloads.Count > 0 ? 520 : 300;
    }
    private async Task PreviewEntryAsync(MediaEntry entry)
    {
        if (_previewEntry == entry) { ClosePreview(null, new RoutedEventArgs()); return; }
        _previewEntry = entry;
        PreviewTitle.Text = entry.Title;
        PreviewIcon.Text = entry.Icon;
        PreviewImage.Source = entry.Thumbnail;
        InlinePreview.IsVisible = true;
        if (entry.Thumbnail == null) entry.Thumbnail = await _thumbnails.GetAsync(entry.ThumbnailUrl, _lifetime.Token);
        if (_previewEntry == entry) PreviewImage.Source = entry.Thumbnail;
    }
    private void ClosePreview(object? sender, RoutedEventArgs e) { _previewEntry = null; InlinePreview.IsVisible = false; PreviewImage.Source = null; }
    private void QuitFromSettings(object? sender, RoutedEventArgs e) => Quit();
}
