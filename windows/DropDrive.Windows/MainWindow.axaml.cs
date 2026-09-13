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
        Closing += HandleClosing;
        Opened += async (_, _) => { if (_settings.CheckUpdatesAutomatically) await CheckForUpdatesAsync(true); };
    }

    private async void AddDownload(object? sender, RoutedEventArgs e) => await QueueLinksAsync();

    private async Task QueueLinksAsync()
    {
        var links = LinkInputParser.Parse(LinkBox.Text);
        if (links.Count == 0) { SetStatus("Paste a valid web link first."); return; }
        LinkBox.Text = "";
        DownloadButton.IsEnabled = false;
        HeaderStatus.Text = "Analyzing";
        foreach (var link in links)
        {
            var uri = new Uri(link);
            var item = new DownloadItem { Url = link, Name = uri.Host.Replace("www.", "", StringComparison.OrdinalIgnoreCase), Source = uri.Host, AudioOnly = Mp3Toggle.IsChecked == true, Status = "Analyzing", Detail = "Reading link information…" };
            _downloads.Insert(0, item);
            try
            {
                using var timeout = new CancellationTokenSource(TimeSpan.FromSeconds(30));
                var analysis = await _analysisService.AnalyzeAsync(link, timeout.Token);
                item.Name = analysis.Title;
                item.Source = analysis.Source;
                item.Detail = analysis.Detail + (item.AudioOnly ? " · MP3" : "");
                item.Status = "Waiting";
            }
            catch (OperationCanceledException) { item.Detail = "Analysis timed out; download will still be attempted."; item.Status = "Waiting"; }
            catch (Exception error)
            {
                item.Status = "Failed"; item.Detail = error.Message; item.CanRetry = true;
                _stateService.AddHistory(item); RefreshHistory(); continue;
            }
            _ = RunDownloadAsync(item);
        }
        DownloadButton.IsEnabled = true;
        HeaderStatus.Text = "Ready";
        UpdateQueueSummary();
    }

    private async Task RunDownloadAsync(DownloadItem item)
    {
        var cancellation = new CancellationTokenSource();
        _cancellations[item.Id] = cancellation;
        item.CanCancel = true; item.CanRetry = false;
        var enteredGate = false;
        try
        {
            await _downloadGate.WaitAsync(cancellation.Token);
            enteredGate = true;
            HeaderStatus.Text = "Downloading";
            UpdateQueueSummary();
            await _downloadService.DownloadAsync(item, _settings.Destination, cancellation.Token);
            SetStatus($"Finished: {item.Name}");
        }
        catch (OperationCanceledException)
        {
            item.Status = "Cancelled"; item.Detail = "Download cancelled"; item.CanCancel = false; item.CanRetry = true;
            SetStatus($"Cancelled: {item.Name}");
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
            HeaderStatus.Text = _downloads.Any(IsInProgress) ? "Downloading" : "Ready";
            UpdateQueueSummary();
        }
    }

    private void CancelDownload(object? sender, RoutedEventArgs e)
    {
        if (sender is Button { Tag: DownloadItem item } && _cancellations.TryGetValue(item.Id, out var cancellation)) cancellation.Cancel();
    }

    private void RetryDownload(object? sender, RoutedEventArgs e)
    {
        if (sender is not Button { Tag: DownloadItem item }) return;
        item.Progress = 0; item.Status = "Waiting"; item.Detail = item.AudioOnly ? "Waiting · MP3" : "Waiting";
        _ = RunDownloadAsync(item);
    }

    private async void ChooseFolder(object? sender, RoutedEventArgs e)
    {
        var choices = await StorageProvider.OpenFolderPickerAsync(new FolderPickerOpenOptions { Title = "Choose download folder", AllowMultiple = false });
        var path = choices.FirstOrDefault()?.TryGetLocalPath();
        if (string.IsNullOrWhiteSpace(path)) return;
        _settings.Destination = path; _stateService.SaveSettings(_settings); UpdateDestinationLabels(); SetStatus("Download folder updated.");
    }

    private void SettingsChanged(object? sender, RoutedEventArgs e)
    {
        if (_loadingSettings) return;
        _settings.CheckUpdatesAutomatically = AutoUpdateToggle.IsChecked == true;
        _settings.HideToTray = HideToTrayToggle.IsChecked == true;
        _stateService.SaveSettings(_settings); SetStatus("Settings saved.");
    }

    private void ShowDownloads(object? sender, RoutedEventArgs e) => ShowPage(DownloadsPage);
    private void ShowHistory(object? sender, RoutedEventArgs e) { RefreshHistory(); ShowPage(RecentPage); }
    private void ShowAccounts(object? sender, RoutedEventArgs e) => ShowPage(AccountsPage);
    private void ShowSettings(object? sender, RoutedEventArgs e) => ShowPage(SettingsPage);

    private void ShowPage(Control page)
    {
        DownloadsPage.IsVisible = page == DownloadsPage; RecentPage.IsVisible = page == RecentPage;
        AccountsPage.IsVisible = page == AccountsPage; SettingsPage.IsVisible = page == SettingsPage;
    }

    private void ClearHistory(object? sender, RoutedEventArgs e) { _stateService.ClearHistory(); RefreshHistory(); SetStatus("Download history cleared."); }

    private void RefreshHistory()
    {
        _history.Clear(); foreach (var entry in _stateService.LoadHistory()) _history.Add(entry);
        HistoryEmpty.IsVisible = _history.Count == 0;
    }

    private void LinkBoxKeyDown(object? sender, KeyEventArgs e)
    {
        if (e.Key != Key.Enter) return; e.Handled = true; _ = QueueLinksAsync();
    }

    private async void CheckForUpdates(object? sender, RoutedEventArgs e) => await CheckForUpdatesAsync(false);
    private async Task CheckForUpdatesAsync(bool silent)
    {
        if (!silent) SetStatus("Checking for updates…");
        var result = await _updateService.CheckDownloadAndRestartAsync();
        if (!silent || result.Restarting || result.IsError) SetStatus(result.Message);
    }

    private void HandleClosing(object? sender, WindowClosingEventArgs e)
    {
        if (_settings.HideToTray) { e.Cancel = true; Hide(); SetStatus("DropDrive is still running in the notification area."); }
        else if (Avalonia.Application.Current?.ApplicationLifetime is IClassicDesktopStyleApplicationLifetime desktop) desktop.Shutdown();
    }

    private void UpdateDestinationLabels() { DestinationLabel.Text = _settings.Destination; SettingsDestinationLabel.Text = _settings.Destination; }
    private void UpdateQueueSummary() { var active = _downloads.Count(IsInProgress); QueueSummary.Text = active == 0 ? "No active downloads" : $"{active} active"; EmptyState.IsVisible = _downloads.Count == 0; }
    private static bool IsInProgress(DownloadItem item) => item.Status is "Waiting" or "Analyzing" or "Downloading";
    private void SetStatus(string message) => StatusLabel.Text = message;
}
