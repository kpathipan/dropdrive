using System.Collections.ObjectModel;
using System.ComponentModel;
using System.Diagnostics;
using Avalonia;
using Avalonia.Controls;
using Avalonia.Controls.ApplicationLifetimes;
using Avalonia.Input;
using Avalonia.Input.Platform;
using Avalonia.Interactivity;
using Avalonia.Layout;
using Avalonia.Media;
using Avalonia.Platform.Storage;
using Avalonia.Styling;
using Avalonia.Threading;
using DropDrive.Windows.Models;
using DropDrive.Windows.Services;

namespace DropDrive.Windows;

public partial class MainWindow : Window
{
    private readonly ObservableCollection<DownloadItem> _downloads = [];
    private readonly ObservableCollection<DownloadHistoryEntry> _history = [];
    private readonly Dictionary<Guid, CancellationTokenSource> _cancellations = [];
    private readonly DownloadService _downloadService = new();
    private readonly MediaAnalysisService _analysisService = new();
    private readonly ThumbnailService _thumbnails = new();
    private readonly UpdateService _updateService = new();
    private readonly AppStateService _stateService;
    private readonly AppSettings _settings;
    private readonly DispatcherTimer _updateTimer = new() { Interval = TimeSpan.FromMinutes(1) };
    private DownloadItem? _review;
    private bool _loadingSettings = true;
    private bool _analyzing;
    private bool _pumping;
    private bool _checkingUpdate;
    private bool _manualUpdateQueued;
    private bool _selectingAll;
    private bool _quitting;
    private readonly bool _backgroundServices;
    private CancellationTokenSource? _analysisCancellation;
    private readonly CancellationTokenSource _lifetime = new();

    public MainWindow() : this(new AppStateService(), true) { }

    // The same production UI is used in isolated rendering/interaction tests.
    public MainWindow(AppStateService stateService, bool backgroundServices, DownloadService? downloadService = null)
    {
        InitializeComponent();
        _stateService = stateService;
        if (downloadService != null) _downloadService = downloadService;
        _backgroundServices = backgroundServices;
        _settings = _stateService.LoadSettings();
        _downloadService.Checkpoint = SaveQueue;
        _downloadService.BandwidthProvider = () => _settings.BandwidthLimit;
        DownloadList.ItemsSource = _downloads;
        HistoryList.ItemsSource = _history;
        Locale.Apply(_settings.Language == "en");
        QualityChoice.ItemsSource = MediaOptions.Qualities.Select(Locale.Text).ToArray();
        SubtitleChoice.ItemsSource = MediaOptions.Subtitles.Select(Locale.Text).ToArray();
        AutoUpdateToggle.IsChecked = _settings.CheckUpdatesAutomatically;
        HideToTrayToggle.IsChecked = _settings.HideToTray;
        OpenFolderCheck.IsChecked = _settings.OpenFolderOnComplete;
        InitializeParitySettings();
        CompatibleCheck.IsChecked = _settings.CompatibleVideo;
        ThemeChoice.SelectedIndex = Math.Clamp(_settings.Theme, 0, 2);
        CustomBandwidth.Value = (decimal)(_settings.BandwidthLimit ?? 1_048_576) / 1_048_576;
        BandwidthChoice.SelectedIndex = _settings.BandwidthLimit switch { 1_048_576 => 1, 5_242_880 => 2, 10_485_760 => 3, null => 0, _ => 4 };
        CustomBandwidth.IsVisible = BandwidthChoice.SelectedIndex == 4;
        LayoutChoice.SelectedIndex = Math.Clamp(_settings.FileLayout, 0, 1);
        SizeChoice.SelectedIndex = Math.Clamp(_settings.CardSize, 0, 2);
        VersionLabel.Text = $"v{typeof(MainWindow).Assembly.GetName().Version?.ToString(3)} · Windows";
        _loadingSettings = false;
        ApplyTheme();
        UpdateDestinationLabels();
        RefreshHistory();
        RestoreQueue();
        Closing += HandleClosing;
        Closed += (_, _) => { _updateTimer.Stop(); _lifetime.Cancel(); StopParityServices(); };
        if (backgroundServices)
        {
            DownloadService.CleanupStaleMetadata();
            _updateTimer.Tick += async (_, _) => await CheckForUpdatesIfDueAsync();
            Opened += async (_, _) => { StartParityServices(); _updateTimer.Start(); await CheckForUpdatesIfDueAsync(); };
        }
    }

    private async void AddDownload(object? sender, RoutedEventArgs e) => await AnalyzeLinksAsync(LinkBox.Text);

    public async Task AnalyzeLinksAsync(string? input, bool showReview = true)
    {
        if (_analyzing) return;
        var links = LinkInputParser.Parse(input);
        if (links.Count == 0) { SetStatus("วางลิงก์เว็บที่ถูกต้องก่อน"); return; }
        if (links.Count + _downloads.Count(item => item.Status != "Complete") > 100)
        { SetStatus("คิวรองรับ 100 รายการพร้อมกัน รอให้งานเสร็จหรือแบ่งลิงก์เป็นชุดก่อน"); return; }
        _analyzing = true;
        LinkBox.Text = "";
        DownloadButton.IsEnabled = false;
        DownloadItem? firstReady = null;
        try
        {
            foreach (var link in links)
            {
                if (_downloads.Any(existing => LinkIdentity.Key(existing.Url) == LinkIdentity.Key(link) && existing.Status != "Complete"))
                { SetStatus("ลิงก์นี้อยู่ในคิวแล้ว"); continue; }
                var uri = new Uri(link);
                var quality = _settings.PlatformQuality.GetValueOrDefault(LinkIdentity.Platform(link), _settings.PlatformQuality.GetValueOrDefault(uri.Host));
                var item = new DownloadItem { Url = link, Name = uri.Host, Source = uri.Host,
                    Destination = _settings.Destination, Status = "Analyzing", Detail = "กำลังอ่านข้อมูลลิงก์…",
                    Quality = quality, AudioOnly = quality == 5 };
                AddItem(item);
                _analysisCancellation = CancellationTokenSource.CreateLinkedTokenSource(_lifetime.Token);
                _analysisCancellation.CancelAfter(TimeSpan.FromSeconds(45));
                try
                {
                    var analysis = await _analysisService.AnalyzeAsync(link, _analysisCancellation.Token);
                    ApplyAnalysis(item, analysis);
                    firstReady ??= item;
                    _ = LoadThumbnailAsync(item);
                }
                catch (OperationCanceledException) { item.Status = "Failed"; item.Detail = "วิเคราะห์ไม่สำเร็จภายในเวลาที่กำหนด กดลองใหม่"; item.CanRetry = true; }
                catch (Exception error) { item.Status = "Failed"; item.Detail = error.Message; item.CanRetry = true; }
                finally { _analysisCancellation.Dispose(); _analysisCancellation = null; }
                SaveQueue();
                UpdateQueueSummary();
            }
        }
        finally
        {
            _analyzing = false;
            DownloadButton.IsEnabled = true;
            UpdateQueueSummary();
        }
        if (showReview && firstReady != null && links.Count == 1) OpenReview(firstReady);
        else if (links.Count > 1) { ShowPage(DownloadsPage); UpdateQueueSummary(); }
    }

    private static void ApplyAnalysis(DownloadItem item, MediaAnalysis analysis)
    {
        item.Name = analysis.Title; item.Source = analysis.Source; item.Detail = analysis.Detail;
        item.EstimatedBytes = analysis.EstimatedBytes; item.ThumbnailUrl = analysis.ThumbnailUrl;
        item.IsMedia = analysis.IsMedia; item.IsCollection = analysis.IsCollection;
        item.IsDrive = PublicDriveService.IsDriveUrl(item.Url);
        item.IsPhotoCollection = analysis.Source == "TikTok Photos";
        item.AnalysisCompleted = true;
        item.Entries = analysis.Entries ?? [];
        item.Status = "Ready"; item.CanStart = true; item.CanRetry = false;
        if (!item.IsMedia) { item.AudioOnly = false; item.Quality = 0; }
    }

    private async Task LoadThumbnailAsync(DownloadItem item)
    {
        if (item.Thumbnail != null) return;
        item.Thumbnail = await _thumbnails.GetAsync(item.ThumbnailUrl, _lifetime.Token);
        item.Notify(nameof(item.Thumbnail));
        if (_review == item) ReviewThumbnail.Source = item.Thumbnail;
    }

    private void AddItem(DownloadItem item)
    {
        foreach (var old in _downloads.Where(entry => entry.Status == "Complete").Reverse().Skip(50).ToArray())
        { old.PropertyChanged -= ItemChanged; _downloads.Remove(old); }
        item.PropertyChanged += ItemChanged;
        _downloads.Add(item);
        UpdateQueueSummary();
        if (Height < 520) Height = 520;
    }

    private void ItemChanged(object? sender, PropertyChangedEventArgs args)
    {
        if (args.PropertyName == nameof(DownloadItem.Status)) UpdateQueueSummary();
    }

    private void ReviewItem(object? sender, RoutedEventArgs e)
    {
        if (sender is Button { Tag: DownloadItem item }) OpenReview(item);
    }

    public void OpenReview(DownloadItem item)
    {
        if (item.IsActive || item.Status == "Analyzing") return;
        if (!_downloads.Contains(item)) AddItem(item);
        _review = item;
        ClosePreview(null, new RoutedEventArgs());
        ApplyReceipts(item);
        ReviewName.Text = item.Name;
        ReviewDetail.Text = item.Detail;
        ReviewThumbnail.Source = item.Thumbnail;
        QualityChoice.SelectedIndex = item.AudioOnly ? 5 : item.Quality;
        SubtitleChoice.SelectedIndex = item.SubtitleMode;
        ClipStartBox.Text = item.ClipStart; ClipEndBox.Text = item.ClipEnd;
        SaveThumbnailCheck.IsChecked = item.SaveThumbnail; SplitChaptersCheck.IsChecked = item.SplitChapters;
        MediaOptionsPanel.IsVisible = item.IsMedia;
        DuplicateNotice.IsVisible = _stateService.LoadHistory().Any(entry => LinkIdentity.Key(entry.Url) == LinkIdentity.Key(item.Url) && entry.Status == "Complete");
        FileSelector.IsVisible = item.IsCollection && item.Entries.Count > 0;
        FileSelector.IsExpanded = false;
        SnapshotNotice.Text = item.IsDrive ? "เทียบชื่อและข้อมูลสาธารณะกับครั้งก่อน · Drive อาจไม่แสดงการแก้ไขเนื้อหาทุกครั้ง" : "เลือกเฉพาะรายการใหม่ที่ยังไม่เคยดาวน์โหลดได้";
        FileSearch.Text = "";
        foreach (var entry in item.Entries) { entry.PropertyChanged -= EntryChanged; entry.PropertyChanged += EntryChanged; }
        NewDownloadForm.IsVisible = false; ReviewPanel.IsVisible = true; DownloadList.IsVisible = false;
        ReviewActions.IsVisible = true;
        ReviewDownloadButton.Content = Locale.Text(_downloads.Any(i => i.IsActive) ? "เข้าคิว" : "ดาวน์โหลด");
        UpdateDestinationLabels();
        UpdateSelection();
        RenderFiles();
        ShowPage(DownloadsPage);
        Height = Math.Max(Height, 570);
        _ = LoadThumbnailAsync(item);
        _ = LoadEntryThumbnailsAsync(item);
    }

    private async Task LoadEntryThumbnailsAsync(DownloadItem item)
    {
        await Task.WhenAll(item.Entries.Take(100).Select(async entry => {
            if (entry.Thumbnail != null) return;
            entry.Thumbnail = await _thumbnails.GetAsync(entry.ThumbnailUrl, _lifetime.Token);
            entry.RefreshThumbnail();
        }));
    }

    private void DismissReview(object? sender, RoutedEventArgs e)
    {
        if (_review?.Status == "Ready") RemoveItem(_review);
        CloseReview();
    }

    private void CloseReview()
    {
        _review = null;
        ReviewPanel.IsVisible = false; NewDownloadForm.IsVisible = true; DownloadList.IsVisible = true;
        ReviewActions.IsVisible = false;
        UpdateQueueSummary();
        ResizeForPage();
    }

    private async void ConfirmReview(object? sender, RoutedEventArgs e)
    {
        if (_review is not { } item || item.IsActive) return;
        try
        {
            item.Quality = Math.Max(0, QualityChoice.SelectedIndex); item.AudioOnly = item.IsMedia && item.Quality == 5;
            item.SubtitleMode = Math.Max(0, SubtitleChoice.SelectedIndex);
            item.ClipStart = ClipStartBox.Text ?? ""; item.ClipEnd = ClipEndBox.Text ?? "";
            item.SaveThumbnail = SaveThumbnailCheck.IsChecked == true; item.SplitChapters = SplitChaptersCheck.IsChecked == true;
            item.CompatibleVideo = _settings.CompatibleVideo; item.BandwidthLimit = _settings.BandwidthLimit;
            if (item.IsMedia) _ = MediaOptions.Section(item);
            if (item.IsCollection && !item.Entries.Any(entry => entry.Selected)) { SetStatus("เลือกอย่างน้อย 1 ไฟล์"); return; }
            TransferGuard.EnsureSpace(item.Destination ?? _settings.Destination, item.IsMedia ? null : item.EstimatedBytes);
            if (!string.IsNullOrWhiteSpace(ReviewName.Text)) item.Name = ReviewName.Text.Trim();
            _settings.PlatformQuality[LinkIdentity.Platform(item.Url)] = item.Quality;
            PersistSettings();
            item.Status = "Waiting"; item.CanStart = false; item.CanRetry = false; item.CanCancel = true;
            item.Detail = item.AudioOnly ? "รอคิว · MP3" : "รอคิว";
            item.RetryAttempt = 0; item.RetryAfter = null; item.WaitForDestination = false;
            _settings.QueuePaused = false; PersistSettings();
            CloseReview(); SaveQueue();
            await PumpQueueAsync();
        }
        catch (Exception error) { SetStatus(error.Message); }
    }

    private async Task PumpQueueAsync()
    {
        if (_pumping) return;
        _pumping = true;
        try
        {
            while (!_settings.QueuePaused && _downloads.FirstOrDefault(item => item.Status == "Waiting") is { } item && !_quitting)
            {
                using var cancellation = CancellationTokenSource.CreateLinkedTokenSource(_lifetime.Token);
                _cancellations[item.Id] = cancellation;
                item.Status = "Starting";
                if (_backgroundServices) WindowsIntegration.KeepAwake(true);
                try
                {
                    await _downloadService.DownloadAsync(item, item.Destination ?? _settings.Destination, cancellation.Token);
                    SetStatus($"ดาวน์โหลดเสร็จแล้ว: {item.Name}");
                    _stateService.AddHistory(item);
                    _stateService.RecordCompletion(item);
                    if (_settings.NotifyOnComplete) NotifyResult(item, false);
                    if (_settings.OpenFolderOnComplete) LaunchPath(item.ResultPath is { } path ? Path.GetDirectoryName(path) : item.Destination);
                }
                catch (OperationCanceledException)
                {
                    if (_restartForBandwidth.Remove(item.Id) && !_settings.QueuePaused && !_quitting)
                    { item.Status = "Waiting"; item.Detail = "รอคิว"; item.CanStart = false; }
                    else { item.Status = "Paused"; item.Detail = "หยุดชั่วคราว · กดตรวจรายการเพื่อดาวน์โหลดต่อ"; item.CanStart = true; }
                }
                catch (Exception error)
                {
                    item.Status = "Failed"; item.Detail = DownloadService.DescribeFailure(error); item.CanRetry = true;
                    item.WaitForDestination = error is DirectoryNotFoundException;
                    if (error is HttpRequestException && item.RetryAttempt < 3)
                    { item.RetryAttempt++; item.RetryAfter = DateTimeOffset.UtcNow.AddSeconds(15 * Math.Pow(2, item.RetryAttempt - 1)); item.Detail += " · จะลองใหม่อัตโนมัติ"; }
                    NotifyResult(item, true);
                    SetStatus($"ต้องตรวจสอบ: {item.Name}"); _stateService.AddHistory(item);
                }
                finally
                {
                    if (_backgroundServices) WindowsIntegration.KeepAwake(false);
                    item.CanCancel = false; _cancellations.Remove(item.Id);
                    RefreshHistory(); UpdateQueueSummary(); SaveQueue();
                }
            }
        }
        finally { _pumping = false; }
        if (_backgroundServices) await CheckForUpdatesIfDueAsync();
    }

    private void PauseDownload(object? sender, RoutedEventArgs e)
    {
        if (sender is not Button { Tag: DownloadItem item }) return;
        item.RetryAfter = null; item.WaitForDestination = false;
        if (_cancellations.TryGetValue(item.Id, out var token)) token.Cancel();
        else if (item.Status == "Waiting") { item.Status = "Paused"; item.CanStart = true; item.CanCancel = false; SaveQueue(); }
    }

    private async void RetryDownload(object? sender, RoutedEventArgs e)
    {
        if (sender is not Button { Tag: DownloadItem item }) return;
        if (!item.AnalysisCompleted)
        {
            RemoveItem(item); await AnalyzeLinksAsync(item.Url);
        }
        else OpenReview(item);
    }

    private void RemoveDownload(object? sender, RoutedEventArgs e)
    {
        if (sender is Button { Tag: DownloadItem item } && !item.IsActive && item.Status != "Analyzing") RemoveItem(item);
    }
    private void RemoveItem(DownloadItem item)
    {
        try { DownloadService.CleanupPartials(item); }
        catch (IOException) { SetStatus("เอารายการออกไม่ได้ ยังล้างไฟล์ชั่วคราวไม่สำเร็จ ตรวจไดรฟ์แล้วลองใหม่"); return; }
        item.PropertyChanged -= ItemChanged;
        _downloads.Remove(item); SaveQueue(); UpdateQueueSummary();
        ResizeForPage();
    }
    private void MoveUp(object? sender, RoutedEventArgs e)
    {
        if (sender is not Button { Tag: DownloadItem item } || item.Status != "Waiting") return;
        var index = _downloads.IndexOf(item);
        var previous = _downloads.Take(index).LastOrDefault(other => other.Status == "Waiting");
        if (previous != null) { _downloads.Move(index, _downloads.IndexOf(previous)); SaveQueue(); }
    }
    private void MoveDown(object? sender, RoutedEventArgs e)
    {
        if (sender is not Button { Tag: DownloadItem item } || item.Status != "Waiting") return;
        var index = _downloads.IndexOf(item);
        var next = _downloads.Skip(index + 1).FirstOrDefault(other => other.Status == "Waiting");
        if (next != null) { _downloads.Move(index, _downloads.IndexOf(next)); SaveQueue(); }
    }
    private void ClearCompleted(object? sender, RoutedEventArgs e)
    {
        foreach (var item in _downloads.Where(item => item.Status == "Complete").ToArray()) RemoveItem(item);
    }

    private async void ChooseFolder(object? sender, RoutedEventArgs e)
    {
        // The picker owns focus. Hide only the content, not the owner window:
        // Windows folder dialogs disappear when their owner is hidden/minimized.
        var originalOpacity = Opacity;
        try
        {
            Opacity = 0;
            var choices = await StorageProvider.OpenFolderPickerAsync(new FolderPickerOpenOptions { Title = "เลือกโฟลเดอร์ดาวน์โหลด", AllowMultiple = false });
            var path = choices.FirstOrDefault()?.TryGetLocalPath();
            if (string.IsNullOrWhiteSpace(path)) return;
            if (_review != null) _review.Destination = path;
            _settings.Destination = path;
            _settings.RecentDestinations.Remove(path); _settings.RecentDestinations.Insert(0, path);
            _settings.RecentDestinations = _settings.RecentDestinations.Take(5).ToList();
            PersistSettings(); SaveQueue(); UpdateDestinationLabels();
        }
        catch (Exception error) { SetStatus($"เลือกโฟลเดอร์ไม่ได้: {error.Message}"); }
        finally { Opacity = originalOpacity; Activate(); }
    }

    private void UpdateDestinationLabels()
    {
        DestinationLabel.Text = FolderName(_settings.Destination);
        ToolTip.SetTip(DestinationLabel, _settings.Destination);
        SettingsDestinationLabel.Text = _settings.Destination;
        var path = _review?.Destination ?? _settings.Destination;
        ReviewDestination.Text = FolderName(path); ToolTip.SetTip(ReviewDestination, path);
        try
        {
            TransferGuard.EnsureSpace(path, _review?.EstimatedBytes);
            var root = Path.GetPathRoot(Path.GetFullPath(path));
            var space = root == null ? null : (long?)new DriveInfo(root).AvailableFreeSpace;
            SpaceLabel.Text = $"{(_review?.EstimatedBytes is { } size ? $"ต้องใช้ประมาณ {FormatBytes(size)} · " : "")}{(space is { } free ? $"เหลือ {FormatBytes(free)}" : "จะตรวจพื้นที่ก่อนดาวน์โหลด")}";
        }
        catch (Exception error) { SpaceLabel.Text = error.Message; }
    }
    public static string FolderName(string path) => Path.GetFileName(path.TrimEnd('\\', '/')) is { Length: > 0 } name ? name.Split('\\').Last() : path;
    private static string FormatBytes(long value) => value >= 1_073_741_824 ? $"{value / 1_073_741_824d:0.#} GB" : value >= 1_048_576 ? $"{value / 1_048_576d:0.#} MB" : $"{value / 1024d:0.#} KB";

    private void SettingsChanged(object? sender, RoutedEventArgs e) => SavePreferences();
    private void PreferenceSelectionChanged(object? sender, SelectionChangedEventArgs e) => SavePreferences();
    private void SavePreferences()
    {
        if (_loadingSettings) return;
        _settings.CheckUpdatesAutomatically = AutoUpdateToggle.IsChecked == true;
        _settings.HideToTray = HideToTrayToggle.IsChecked == true;
        _settings.OpenFolderOnComplete = OpenFolderCheck.IsChecked == true;
        _settings.CompatibleVideo = CompatibleCheck.IsChecked == true;
        SaveParitySettings();
        _settings.Theme = Math.Max(0, ThemeChoice.SelectedIndex);
        var previousLimit = _settings.BandwidthLimit;
        _settings.BandwidthLimit = BandwidthChoice.SelectedIndex switch { 1 => 1_048_576, 2 => 5_242_880, 3 => 10_485_760, 4 => (long)((CustomBandwidth.Value ?? 1) * 1_048_576), _ => null };
        CustomBandwidth.IsVisible = BandwidthChoice.SelectedIndex == 4;
        if (_settings.BandwidthLimit != previousLimit)
            foreach (var item in _downloads.Where(item => item.IsActive))
            {
                item.BandwidthLimit = _settings.BandwidthLimit;
                if (item.IsMedia && _cancellations.TryGetValue(item.Id, out var cancellation))
                { _restartForBandwidth.Add(item.Id); cancellation.Cancel(); }
            }
        ApplyTheme(); PersistSettings();
    }
    private void ApplyTheme() => RequestedThemeVariant = _settings.Theme switch { 1 => ThemeVariant.Light, 2 => ThemeVariant.Default, _ => ThemeVariant.Dark };
    private void PersistSettings() { try { _stateService.SaveSettings(_settings); } catch (IOException) { SetStatus("บันทึกการตั้งค่าไม่ได้ ตรวจพื้นที่และสิทธิ์ของเครื่อง"); } }

    private void ShowDownloads(object? sender, RoutedEventArgs e) => ShowPage(DownloadsPage);
    private void ShowHistory(object? sender, RoutedEventArgs e) { RefreshHistory(); ShowPage(RecentPage); }
    private void ShowSettings(object? sender, RoutedEventArgs e) => ShowPage(SettingsPage.IsVisible ? DownloadsPage : SettingsPage);
    private void ShowAttention(object? sender, RoutedEventArgs e) { ShowPage(SettingsPage); AttentionSection.IsExpanded = true; }
    private void ShowPage(Control page)
    {
        DownloadsPage.IsVisible = page == DownloadsPage; RecentPage.IsVisible = page == RecentPage; SettingsPage.IsVisible = page == SettingsPage;
        ReviewActions.IsVisible = page == DownloadsPage && _review != null;
        DownloadsIndicator.IsVisible = page == DownloadsPage; HistoryIndicator.IsVisible = page == RecentPage;
        DownloadsTab.Classes.Set("selected", page == DownloadsPage); HistoryTab.Classes.Set("selected", page == RecentPage);
        if (page != DownloadsPage) Height = Math.Max(Height, 570);
        ResizeForPage();
    }
    private void DismissStatus(object? sender, RoutedEventArgs e) => StatusBanner.IsVisible = false;
    private void SetStatus(string message) { StatusLabel.Text = Locale.Text(message); StatusBanner.IsVisible = !string.IsNullOrWhiteSpace(message); }

    private void ClearHistory(object? sender, RoutedEventArgs e) { _stateService.ClearHistory(); RefreshHistory(); SetStatus("ล้างประวัติแล้ว ไฟล์ที่ดาวน์โหลดยังอยู่"); }
    private void HistorySearchChanged(object? sender, TextChangedEventArgs e) { if (!_loadingSettings) RefreshHistory(); }
    private void RefreshHistory()
    {
        var query = HistorySearch.Text?.Trim() ?? "";
        _history.Clear();
        foreach (var entry in _stateService.LoadHistory().Where(entry => (entry.Name + " " + entry.Source).Contains(query, StringComparison.OrdinalIgnoreCase))) _history.Add(entry);
        HistoryEmpty.IsVisible = _history.Count == 0;
        HistoryEmpty.Text = Locale.Text(query.Length == 0 ? "ยังไม่มีประวัติการดาวน์โหลด" : "ไม่พบรายการที่ค้นหา");
    }
    private async void RepeatHistory(object? sender, RoutedEventArgs e)
    {
        if (sender is not Button { Tag: DownloadHistoryEntry item }) return;
        ShowPage(DownloadsPage); await AnalyzeLinksAsync(item.Url);
    }
    private async void CopyLink(object? sender, RoutedEventArgs e)
    {
        try { if (sender is Button { Tag: DownloadHistoryEntry item } && Clipboard != null) { await Clipboard.SetTextAsync(item.Url); SetStatus("คัดลอกลิงก์แล้ว"); } }
        catch (Exception) { SetStatus("คลิปบอร์ดยังไม่พร้อม กดลองอีกครั้ง"); }
    }
    private void OpenResult(object? sender, RoutedEventArgs e) => LaunchPath(ResultPath(sender));
    private void RevealResult(object? sender, RoutedEventArgs e)
    {
        var path = ResultPath(sender);
        if (path != null && Directory.Exists(path)) { LaunchPath(path); return; }
        if (path == null || !File.Exists(path)) { SetStatus("ไม่พบไฟล์ อาจถูกย้ายหรือลบแล้ว"); return; }
        try
        {
            if (OperatingSystem.IsWindows()) Process.Start(new ProcessStartInfo("explorer.exe") { Arguments = $"/select,\"{path}\"", UseShellExecute = true });
        }
        catch (Exception) { SetStatus("เปิด Explorer ไม่ได้"); }
    }
    private static string? ResultPath(object? sender) => sender is Button button ? button.Tag switch { DownloadItem item => item.ResultPath, DownloadHistoryEntry item => item.ResultPath, _ => null } : null;
    private void LaunchPath(string? path)
    {
        if (path == null || (!File.Exists(path) && !Directory.Exists(path))) { SetStatus("ไม่พบไฟล์ อาจถูกย้ายหรือลบแล้ว"); return; }
        try { Process.Start(new ProcessStartInfo(path) { UseShellExecute = true }); } catch (Exception) { SetStatus("เปิดไฟล์ไม่ได้ ตรวจสอบโปรแกรมที่ใช้เปิดไฟล์ชนิดนี้"); }
    }
    private async void PasteLink(object? sender, RoutedEventArgs e)
    {
        try { if (Clipboard != null) LinkBox.Text = await Clipboard.TryGetTextAsync(); }
        catch (Exception) { SetStatus("อ่านคลิปบอร์ดไม่ได้ กด Ctrl+V เพื่อวางลิงก์"); }
        LinkBox.Focus();
    }
    private void ClearLink(object? sender, RoutedEventArgs e) { LinkBox.Text = ""; LinkBox.Focus(); }
    private void LinkBoxKeyDown(object? sender, KeyEventArgs e) { if (e.Key == Key.Enter) { e.Handled = true; _ = AnalyzeLinksAsync(LinkBox.Text); } }
    private void LinkBoxTextChanged(object? sender, TextChangedEventArgs e)
    {
        if (DownloadButton == null || PasteButton == null || ClearLinkButton == null) return;
        var hasText = !string.IsNullOrWhiteSpace(LinkBox.Text);
        DownloadButton.IsVisible = hasText; ClearLinkButton.IsVisible = hasText; PasteButton.IsVisible = !hasText;
    }
    private void ReviewOptionsChanged(object? sender, SelectionChangedEventArgs e) { }

    private void SelectAllFiles(object? sender, RoutedEventArgs e)
    {
        if (_review == null) return;
        _selectingAll = true;
        // Clicking a mixed state selects all; clicking all clears all.
        var selected = !_review.Entries.All(entry => entry.Selected);
        foreach (var entry in _review.Entries) entry.Selected = selected;
        _selectingAll = false; UpdateSelection();
    }
    private void EntryChanged(object? sender, PropertyChangedEventArgs e) { if (!_selectingAll && e.PropertyName == nameof(MediaEntry.Selected)) UpdateSelection(); }
    private void UpdateSelection()
    {
        if (_review == null) return;
        var count = _review.Entries.Count(entry => entry.Selected);
        SelectAllCheck.IsChecked = count == 0 ? false : count == _review.Entries.Count ? true : null;
        SelectionCount.Text = Locale.Choose($"{count}/{_review.Entries.Count} ไฟล์", $"{count}/{_review.Entries.Count} files");
        ReviewDownloadButton.IsEnabled = !_review.IsCollection || count > 0;
    }
    private void FileSearchChanged(object? sender, TextChangedEventArgs e) => RenderFiles();
    private void FileLayoutChanged(object? sender, SelectionChangedEventArgs e)
    {
        if (_loadingSettings || LayoutChoice == null || SizeChoice == null) return;
        _settings.FileLayout = LayoutChoice.SelectedIndex; _settings.CardSize = SizeChoice.SelectedIndex; PersistSettings(); RenderFiles();
    }
    private void RenderFiles()
    {
        if (FileCards == null || _review == null) return;
        FileCards.Children.Clear();
        var width = LayoutChoice.SelectedIndex == 1 ? 290 : SizeChoice.SelectedIndex switch { 0 => 86, 2 => 290, _ => 138 };
        var query = FileSearch.Text ?? "";
        foreach (var entry in _review.Entries.Where(entry => entry.Title.Contains(query, StringComparison.OrdinalIgnoreCase)))
        {
            var check = new CheckBox { DataContext = entry, Width = width, Margin = new Thickness(0, 0, 6, 6),
                HorizontalContentAlignment = HorizontalAlignment.Stretch, VerticalContentAlignment = VerticalAlignment.Top };
            check.Bind(CheckBox.IsCheckedProperty, new Avalonia.Data.Binding(nameof(MediaEntry.Selected)) { Mode = Avalonia.Data.BindingMode.TwoWay });
            var panel = new StackPanel { Spacing = 5 };
            if (LayoutChoice.SelectedIndex == 0)
            {
                var image = new Image { Height = width * 0.5, Stretch = Stretch.UniformToFill, DataContext = entry };
                image.Bind(Image.SourceProperty, new Avalonia.Data.Binding(nameof(MediaEntry.Thumbnail)));
                panel.Children.Add(new Border { CornerRadius = new CornerRadius(6), ClipToBounds = true,
                    Background = new SolidColorBrush(Color.Parse("#17191C")), Child = new Grid {
                        Children = { new TextBlock { Text = entry.Icon, FontSize = entry.Kind == "document" ? 13 : 24, HorizontalAlignment = HorizontalAlignment.Center, VerticalAlignment = VerticalAlignment.Center }, image } } });
            }
            else
            {
                panel.Orientation = Orientation.Horizontal;
                panel.Children.Add(new TextBlock { Text = entry.Icon, FontSize = 12, Width = 30, VerticalAlignment = VerticalAlignment.Center });
            }
            panel.Children.Add(new TextBlock { Text = entry.Title, FontSize = 10, MaxWidth = LayoutChoice.SelectedIndex == 1 ? 210 : width - 35, TextTrimming = TextTrimming.CharacterEllipsis, MaxLines = 2, TextWrapping = TextWrapping.Wrap });
            check.Content = panel; ToolTip.SetTip(check, entry.Title);
            check.AddHandler(InputElement.KeyDownEvent, async (_, args) => {
                if (args.Key != Key.Space) return;
                args.Handled = true;
                await PreviewEntryAsync(entry);
            }, Avalonia.Interactivity.RoutingStrategies.Tunnel);
            check.AddHandler(InputElement.KeyUpEvent, (_, args) => { if (args.Key == Key.Space) args.Handled = true; }, Avalonia.Interactivity.RoutingStrategies.Tunnel);
            panel.Children.Add(new TextBlock { Text = Locale.Text(entry.SnapshotState), FontSize = 9, Opacity = 0.65 });
            FileCards.Children.Add(check);
        }
    }

    private async void CheckForUpdates(object? sender, RoutedEventArgs e) => await CheckForUpdatesAsync(false);
    private async Task CheckForUpdatesIfDueAsync()
    {
        if (_downloads.Any(item => item.IsActive) || _analyzing || _checkingUpdate || _review != null) return;
        if (_manualUpdateQueued) { _manualUpdateQueued = false; await CheckForUpdatesAsync(false); return; }
        if (!_updateService.HasPendingUpdate && !_settings.IsAutomaticUpdateCheckDue(DateTimeOffset.UtcNow)) return;
        if (!_updateService.HasPendingUpdate) { _settings.LastAutomaticUpdateCheckUtc = DateTimeOffset.UtcNow; PersistSettings(); }
        await CheckForUpdatesAsync(true);
    }
    private async Task CheckForUpdatesAsync(bool silent)
    {
        if (_checkingUpdate) return;
        if (_downloads.Any(item => item.IsActive) || _analyzing)
        {
            if (!silent) { _manualUpdateQueued = true; SetStatus("จะตรวจหาอัปเดตให้อัตโนมัติหลังงานดาวน์โหลดเสร็จ"); }
            return;
        }
        _checkingUpdate = true; CheckUpdateButton.IsEnabled = false;
        try
        {
            if (!silent) SetStatus("กำลังตรวจหาอัปเดต…");
            var result = await _updateService.CheckDownloadAndRestartAsync(() => !_downloads.Any(item => item.IsActive) && !_analyzing && _review == null, _lifetime.Token);
            if (!silent || result.Restarting || result.IsError) SetStatus(result.Message);
        }
        finally { _checkingUpdate = false; CheckUpdateButton.IsEnabled = true; }
    }

    public void Quit()
    {
        _quitting = true; _analysisCancellation?.Cancel(); _lifetime.Cancel();
        foreach (var item in _downloads.Where(item => item.IsActive)) item.Status = "Paused";
        SaveQueue();
        if (Application.Current?.ApplicationLifetime is IClassicDesktopStyleApplicationLifetime desktop) desktop.Shutdown();
        else Close();
    }
    private void HandleClosing(object? sender, WindowClosingEventArgs e)
    {
        SaveQueue();
        if (_quitting) return;
        if (_settings.HideToTray && _backgroundServices) { e.Cancel = true; Hide(); }
        else if (_backgroundServices) { e.Cancel = true; Quit(); }
    }
    private void RestoreQueue()
    {
        foreach (var item in _stateService.LoadQueue())
        {
            if (item.IsActive) item.Status = "Paused";
            if (item.Status is "Paused" or "Ready") item.AnalysisCompleted = true;
            item.IsDrive = PublicDriveService.IsDriveUrl(item.Url);
            if (item.IsDrive || DownloadService.IsDirectFile(item.Url)) item.IsMedia = false;
            if (item.Status == "Analyzing") { item.Status = "Failed"; item.Detail = "การวิเคราะห์ถูกขัดจังหวะ กดลองใหม่"; }
            item.CanStart = item.Status is "Ready" or "Paused";
            item.CanRetry = item.Status is "Failed" or "Cancelled"; item.CanCancel = false;
            AddItem(item);
        }
        UpdateQueueSummary();
    }
    private void SaveQueue() { try { _stateService.SaveQueue(_downloads.Where(item => item.Status != "Complete")); } catch (IOException) { SetStatus("บันทึกคิวไม่ได้ ตรวจพื้นที่และสิทธิ์ของเครื่อง"); } }
    private void UpdateQueueSummary()
    {
        if (QueueHeading == null) return;
        var active = _downloads.Count(item => item.IsActive);
        var analyzing = _downloads.Any(item => item.Status == "Analyzing");
        QueueHeading.IsVisible = _downloads.Count > 0 && _review == null;
        QueueSummary.Text = Locale.Choose(active > 0 ? $"กำลังทำงาน {active} รายการ" : $"{_downloads.Count} รายการ", active > 0 ? $"{active} active" : $"{_downloads.Count} items");
        HeaderStatus.Text = Locale.Text(active > 0 ? "กำลังดาวน์โหลด" : analyzing ? "กำลังวิเคราะห์" : "พร้อมใช้งาน");
        if (_review != null) ReviewDownloadButton.Content = Locale.Text(active > 0 ? "เข้าคิว" : "ดาวน์โหลด");
        var attention = _downloads.Where(item => item.NeedsAttention).ToArray();
        AttentionBanner.IsVisible = attention.Length > 0 && _review == null;
        AttentionBanner.Content = Locale.Choose($"!  มี {attention.Length} รายการที่ต้องตรวจสอบ", $"!  {attention.Length} items need attention");
        AttentionList.ItemsSource = attention; AttentionEmpty.IsVisible = attention.Length == 0;
        UpdateParitySummary();
    }
}
