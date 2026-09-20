using DropDrive.Windows.Services;
using DropDrive.Windows.Models;
using DropDrive.Windows;
using Avalonia;
using Avalonia.Controls;
using Avalonia.Headless;
using Avalonia.Input;
using Avalonia.Interactivity;
using Avalonia.Threading;
using System.Net;
using System.Net.Http.Headers;
using Avalonia.VisualTree;

if (args.Contains("--windows-shell")) { WindowsShellChecks.Run(args); return; }

AppBuilder.Configure<App>().UseSkia()
    .UseHeadless(new AvaloniaHeadlessPlatformOptions { UseHeadlessDrawing = false }).SetupWithoutStarting();

static void Expect(bool condition, string message)
{
    if (!condition) throw new InvalidOperationException(message);
}
static void Complete(Task task, int seconds = 15)
{
    var deadline = DateTime.UtcNow.AddSeconds(seconds);
    while (!task.IsCompleted && DateTime.UtcNow < deadline) { Dispatcher.UIThread.RunJobs(); Thread.Sleep(1); }
    Expect(task.IsCompleted, "async operation exceeded test deadline");
    task.GetAwaiter().GetResult();
}

var links = LinkInputParser.Parse("https://youtu.be/a\nhttps://example.com/file.zip  https://youtu.be/a");
Expect(links.Count == 2, "valid links should be parsed and duplicates removed");
Expect(LinkInputParser.Parse("https://youtu.be/aBc https://youtu.be/abc").Count == 2, "case-sensitive video IDs must not be collapsed");
Expect(LinkInputParser.Parse("ftp://example.com/file").Count == 0, "non-web schemes must be rejected");
Expect(LinkInputParser.Parse("not a link").Count == 0, "invalid text must be rejected");
Expect(LinkInputParser.Parse("https://youtu.be/AbCd https://www.youtube.com/watch?v=AbCd&utm_source=test").Count == 1, "share URLs for the same video do not create duplicate jobs");
Expect(LinkIdentity.Platform("https://vm.tiktok.com/test") == LinkIdentity.Platform("https://www.tiktok.com/@x/video/123"), "MP3 preference shared across TikTok short and full links");
Expect(LinkInputParser.ExternalLinks(["dropdrive://download?url=https%3A%2F%2Fexample.com%2Ffile.mp4&url=file%3A%2F%2Ftest"]).Single() == "https://example.com/file.mp4", "external protocol admits web links only");
Expect(DownloadService.IsTransientMediaError("HTTP Error 503") && !DownloadService.IsTransientMediaError("Private video: HTTP Error 403"), "retry transient network errors, never permission failures");
var settings = new AppSettings { CheckUpdatesAutomatically = true };
var now = DateTimeOffset.UtcNow;
Expect(settings.IsAutomaticUpdateCheckDue(now), "first automatic update check must be due");
settings.LastAutomaticUpdateCheckUtc = now.AddHours(-23).AddMinutes(-59);
Expect(!settings.IsAutomaticUpdateCheckDue(now), "automatic update must not run again before 24 hours");
settings.LastAutomaticUpdateCheckUtc = now.AddHours(-24);
Expect(settings.IsAutomaticUpdateCheckDue(now), "automatic update must become due at 24 hours");
settings.CheckUpdatesAutomatically = false;
Expect(!settings.IsAutomaticUpdateCheckDue(now), "disabled automatic updates must never be due");
var stateFolder = Path.Combine(Path.GetTempPath(), $"dropdrive-check-{Guid.NewGuid():N}");
try
{
    var state = new AppStateService(stateFolder);
    Complete(GoogleChecks.RunAsync(Path.Combine(stateFolder, "google")));
    state.SaveSettings(new AppSettings { Destination = "D:\\Media", CheckUpdatesAutomatically = false });
    Expect(state.LoadSettings().Destination == "D:\\Media", "settings must persist across launches");
    state.SaveQueue([new DownloadItem { Url = "https://example.com/a.mp4", Name = "A", Status = "Ready", Destination = "D:\\Media" }]);
    var restored = state.LoadQueue();
    Expect(restored.Count == 1 && restored[0].Destination == "D:\\Media", "queue destination must persist per item");

    var metadata = MediaAnalysisService.Parse("""{"title":"ทดสอบ","duration":null,"filesize":null,"thumbnail":null,"entries":[{"title":"ภาพยนตร์","url":"https://example.com/1","duration":null},null,{"title":"ภาพ","ext":"jpg"}]}""", "example.com");
    Expect(metadata.IsCollection && metadata.Entries?.Count == 2 && metadata.Entries[1].Index == 3, "nullable metadata and original playlist indices");
    var media = new DownloadItem { Url = "https://example.com/media", Name = "100% วิดีโอ", AudioOnly = true, IsCollection = true,
        Entries = metadata.Entries!, ClipStart = "0:30", ClipEnd = "1:20", SubtitleMode = 1, SaveThumbnail = true };
    media.Entries[0].Selected = false;
    var arguments = MediaOptions.Arguments(media, stateFolder, stateFolder);
    Expect(arguments.Contains("--ignore-config"), "external yt-dlp settings cannot override destinations or application options");
    Expect(arguments.Contains("--ffmpeg-location") && arguments.Contains("mp3"), "bundled ffmpeg is used for MP3");
    Expect(arguments[arguments.IndexOf("--playlist-items") + 1] == "3", "only the checked original entry index downloads");
    Expect(arguments.Contains("*30-80") && arguments.Contains("--write-thumbnail"), "clip and artwork options");
    Expect(MediaOptions.SafeName("../CON?.mp4").Contains('/') == false, "filename traversal characters removed");
    Expect(MediaOptions.SafeName("CON.txt") == "_CON.txt", "Windows device names escaped");
    media.AudioOnly = false; media.IsCollection = false;
    arguments = MediaOptions.Arguments(media, stateFolder, stateFolder);
    Expect(arguments.Contains("--ffmpeg-location") && arguments.Contains("--merge-output-format"), "bundled ffmpeg also used for video merge");
    DownloadService.ParseProgress(media, "DDPROGRESS: 42.5%| 1.20MiB/s| 00:21");
    Expect(media.Progress == 42.5 && media.Eta == "00:21", "tagged progress parsed without matching unrelated numbers");
    DownloadService.ParseProgress(media, "[ExtractAudio] target.mp3");
    Expect(media.Detail.Contains("MP3"), "post-processing status is visible");
    var folder = PublicDriveService.ParseFolder("""<title>คลิป</title><div id="flip-contents"><a href="https://drive.google.com/file/d/abcd/view"><div class="flip-entry-title">วิดีโอ.mp4</div></a><a href="https://docs.google.com/document/d/xyz/edit">เอกสาร</a></div>""");
    Expect(folder.Title == "คลิป" && folder.Children.Count == 2 && folder.Children[1].Title == "เอกสาร.docx", "Drive public folder and document export listing");
    Expect(!PublicDriveService.IsDriveUrl("https://drive.google.com.evil.test/file/d/a/view"), "Drive URL host matching is exact");
    Expect(PublicDriveService.DownloadUrl("https://drive.google.com/file/d/abcd/view?resourcekey=key").Contains("resourcekey=key"), "Drive resource keys retained");
    try { PublicDriveService.ConfirmationUrl("""<form id="download-form" action="https://evil.test"><input type="hidden" name="id" value="file"></form>"""); throw new Exception("untrusted confirmation accepted"); }
    catch (InvalidOperationException) { }
    var playerJson = """{"items":[{"video_info":{"profiles":[{"bitrate":1000,"play_addr":{"width":1080,"height":1920,"url_list":["https://v.tiktokcdn.com/original.mp4"]}},{"bitrate":500,"play_addr":{"width":480,"height":854,"url_list":["https://v.tiktokcdn.com/small.mp4"]}}],"download_addr":{"url_list":["https://v.tiktokcdn.com/watermarked.mp4"]}}}]}""";
    Expect(TikTokMediaService.OriginalUrl(playerJson, 0) == "https://v.tiktokcdn.com/original.mp4", "TikTok original player rendition");
    Expect(TikTokMediaService.OriginalUrl(playerJson, 4) == "https://v.tiktokcdn.com/small.mp4", "TikTok size preference");
    Expect(TikTokMediaService.OriginalUrl("""{"items":[{"video_info":{"download_addr":{"url_list":["https://v.tiktokcdn.com/watermarked.mp4"]}}}]}""", 0) == null, "never silently choose watermarked download_addr");
    var photoPost = TikTokMediaService.PhotoAnalysis("""{"items":[{"desc":"Photos","image_post_info":{"images":[{"display_image":{"url_list":["https://p.tiktokcdn.com/one.jpg"]}},{"display_image":{"url_list":["https://p.tiktokcdn.com/two.webp"]}}]},"video_info":{"url_list":["https://v.tiktokcdn.com/music.m4a"]}}]}""", "https://www.tiktok.com/@creator/photo/1234567890123456789");
    Expect(photoPost?.Entries?.Count == 3 && photoPost.Entries[1].Title.EndsWith(".webp") && photoPost.Entries[2].Kind == "audio", "TikTok photo collection keeps original images and soundtrack separate");
    Expect(!TikTokMediaService.IsTrustedCdn("tiktokcdn.com.evil.test"), "photo CDN host boundary");
    Expect(MediaValidator.IsPlayable("""{"format":{"duration":"2.5"},"streams":[{"codec_type":"audio"}]}""", true), "MP3 validator accepts audio stream");
    Expect(!MediaValidator.IsPlayable("""{"format":{"duration":"0"},"streams":[{"codec_type":"audio"}]}""", true), "empty media rejected");
    var collection = new DownloadItem { Url = "https://fixture.test/list", IsCollection = true, Entries = [
        new() { Index = 1, Title = "One", StableId = "one" }, new() { Index = 2, Title = "Two", StableId = "two", Selected = false }] };
    state.RecordCompletion(collection);
    var receipt = state.LoadReceipts()[collection.Url];
    Expect(receipt.State(collection.Entries[0]) == "โหลดแล้ว" && receipt.State(collection.Entries[1]) == "ใหม่", "partial collection receipt never marks unselected entries completed");
    Expect(receipt.State(new() { Index = 1, Title = "Renamed", StableId = "one" }) == "เปลี่ยนแปลง", "changed source metadata detected");
    Expect(PhoneInboxService.ExtractLinks("<plist><string>https://example.com/a?x=1&amp;y=2</string></plist>").Single() == "https://example.com/a?x=1&y=2", "phone inbox understands webloc escaped URLs");
    var inboxFolder = Path.Combine(stateFolder, "inbox"); Directory.CreateDirectory(inboxFolder);
    var input = Path.Combine(inboxFolder, "from-phone.txt"); File.WriteAllText(input, "https://example.com/a"); File.SetLastWriteTimeUtc(input, DateTime.UtcNow.AddMinutes(-1));
    var inbox = new PhoneInboxService();
    Complete(inbox.ScanAsync(inboxFolder, _ => Task.FromResult(false), CancellationToken.None));
    Expect(File.Exists(input), "failed durable receipt keeps original phone input");
    Complete(inbox.ScanAsync(inboxFolder, _ => Task.FromResult(true), CancellationToken.None));
    Expect(!File.Exists(input) && File.Exists(Path.Combine(inboxFolder, "Processed", "from-phone.txt")), "accepted input is moved, not copied or deleted");
    File.WriteAllText(input, "https://example.com/a"); File.SetLastWriteTimeUtc(input, DateTime.UtcNow.AddMinutes(-1));
    Complete(inbox.ScanAsync(inboxFolder, _ => { File.WriteAllText(input, "https://example.com/new"); return Task.FromResult(true); }, CancellationToken.None));
    Expect(File.Exists(input), "phone input changed during processing must not be consumed");

    // Use the real window and controls, with no account, network, updater or user state.
    var uiState = new AppStateService(Path.Combine(stateFolder, "ui"));
    var uiDestination = Path.Combine(stateFolder, "PSN");
    Directory.CreateDirectory(uiDestination);
    uiState.SaveSettings(new AppSettings { Destination = uiDestination, CheckUpdatesAutomatically = false, HideToTray = false });
    var window = new MainWindow(uiState, false);
    window.Show();
    Dispatcher.UIThread.RunJobs();
    var pictures = Path.GetFullPath(Path.Combine("windows", "artifacts", "ui-checks"));
    Directory.CreateDirectory(pictures);
    void Capture(string name) { Dispatcher.UIThread.RunJobs(); using var frame = window.CaptureRenderedFrame(); Expect(frame != null, "UI must render"); frame!.Save(Path.Combine(pictures, name + ".png"), Avalonia.Media.Imaging.PngBitmapEncoderOptions.Default); }
    T Control<T>(string name) where T : Control => window.FindControl<T>(name) ?? throw new Exception($"missing {name}");
    void Click(string name) => Control<Button>(name).RaiseEvent(new RoutedEventArgs(Button.ClickEvent));
    Capture("01-empty-thai");
    Expect(!Control<Grid>("QueueHeading").IsVisible, "empty screen has no redundant queue heading");
    Expect(Control<TextBlock>("DestinationLabel").Text == "PSN", "compact destination is folder name only");
    Control<TextBox>("LinkBox").Text = "https://example.com/test";
    Dispatcher.UIThread.RunJobs();
    Expect(Control<Button>("DownloadButton").IsVisible, "analyze appears after typing");
    Control<TextBox>("LinkBox").Text = "";
    Dispatcher.UIThread.RunJobs();
    Expect(!Control<Button>("DownloadButton").IsVisible, "analyze disappears for blank input");
    Click("SettingsButton");
    Expect(Control<ScrollViewer>("SettingsPage").IsVisible, "settings navigates within the same window");
    Capture("02-settings-thai");
    Control<ComboBox>("ThemeChoice").SelectedIndex = 2;
    Dispatcher.UIThread.RunJobs();
    Expect(window.ActualThemeVariant == Application.Current!.ActualThemeVariant, "system theme follows the OS/application, not a forced dark parent");
    Control<ComboBox>("ThemeChoice").SelectedIndex = 0;
    Click("SettingsButton");
    Expect(Control<ScrollViewer>("DownloadsPage").IsVisible, "gear toggles back from settings");
    Expect(window.Height == 300, "returning to empty home restores the compact window");
    Control<ComboBox>("LanguageChoice").SelectedIndex = 1; Dispatcher.UIThread.RunJobs();
    Expect(Control<TextBox>("LinkBox").PlaceholderText == "Paste a download link", "language setting updates actual UI resources");
    Capture("07-empty-english");
    Control<ComboBox>("LanguageChoice").SelectedIndex = 0;
    var preservedChild = new DownloadItem { Url = "https://drive.google.com/file/d/done/view", Status = "Complete", DriveAccountId = "old-account" };
    var reconnectItem = new DownloadItem { Url = "https://drive.google.com/drive/folders/reconnect", Name = "Reconnect", IsDrive = true,
        Status = "Failed", Destination = uiDestination, IsCollection = true, Entries = [
            new() { Index = 1, Title = "done.mp4", StableId = "drive:done", Fingerprint = "unchanged", Transfer = preservedChild },
            new() { Index = 2, Title = "skip.mp4", StableId = "drive:skip", Selected = false }] };
    window.OpenReview(reconnectItem);
    window.RefreshDriveReview(reconnectItem, new MediaAnalysis("Reconnected", "Google Drive", "Access refreshed", null, null, false, true,
        [new() { Index = 1, Title = "done.mp4", StableId = "drive:done", Fingerprint = "unchanged" },
         new() { Index = 2, Title = "skip.mp4", StableId = "drive:skip" }], "new-account"));
    Dispatcher.UIThread.RunJobs();
    Expect(reconnectItem.Status == "Ready" && Control<Button>("ReviewDownloadButton").IsEnabled, "login refresh immediately enables the same failed review");
    Expect(!reconnectItem.Entries[1].Selected && ReferenceEquals(reconnectItem.Entries[0].Transfer, preservedChild)
        && preservedChild.DriveAccountId == "new-account", "login refresh preserves deselection/completed children and replaces account access");
    Expect(Control<TextBox>("ReviewName").Text == "Reconnected", "login refresh updates the visible review without a second login");
    var review = new DownloadItem { Url = "https://example.com/test", Name = "คลิปทดสอบสำหรับเลือกไฟล์", Detail = "YouTube · 3 ไฟล์", Status = "Ready",
        Destination = uiDestination, IsCollection = true, Entries = [
            new() { Index = 1, Title = "วิดีโอเบื้องหลัง.mp4" },
            new() { Index = 2, Title = "ภาพปก.jpg", Kind = "image" },
            new() { Index = 3, Title = "ดนตรี.wav", Kind = "audio" }] };
    window.OpenReview(review);
    Control<Expander>("FileSelector").IsExpanded = true;
    Control<ScrollViewer>("DownloadsPage").Offset = new Vector(0, 310);
    Capture("03-folder-cards-thai");
    var master = Control<CheckBox>("SelectAllCheck");
    master.RaiseEvent(new RoutedEventArgs(Button.ClickEvent));
    Expect(review.Entries.All(entry => !entry.Selected), "uncheck all clears every entry");
    Expect(!Control<Button>("ReviewDownloadButton").IsEnabled, "zero selection cannot download");
    var individual = Control<WrapPanel>("FileCards").Children.OfType<CheckBox>().First();
    individual.IsChecked = true;
    Dispatcher.UIThread.RunJobs();
    Expect(review.Entries[0].Selected && !review.Entries[1].Selected, "individual checkbox works after deselect all");
    Expect(Control<Button>("ReviewDownloadButton").IsEnabled && master.IsChecked == null, "partial selection enables download and mixed master state");
    individual.Focus(); window.KeyPress(Key.Space, default, PhysicalKey.Space, " "); window.KeyRelease(Key.Space, default, PhysicalKey.Space, " "); Dispatcher.UIThread.RunJobs();
    Expect(Control<Border>("InlinePreview").IsVisible && review.Entries[0].Selected, "Space opens inline preview without toggling selection");
    window.KeyPress(Key.Space, default, PhysicalKey.Space, " "); window.KeyRelease(Key.Space, default, PhysicalKey.Space, " "); Dispatcher.UIThread.RunJobs();
    Expect(!Control<Border>("InlinePreview").IsVisible, "Space closes preview for the same focused file");
    foreach (var size in new[] { 0, 1, 2 }) { Control<ComboBox>("SizeChoice").SelectedIndex = size; Dispatcher.UIThread.RunJobs(); }
    Control<ComboBox>("LayoutChoice").SelectedIndex = 1;
    Capture("04-file-list-thai");
    uiState.RecordCompletion(new DownloadItem { Url = review.Url, IsCollection = true, Entries = [review.Entries[0]] });
    window.OpenReview(review); Control<Expander>("FileSelector").IsExpanded = true;
    Click("SelectNewButton");
    Expect(!review.Entries[0].Selected && review.Entries[1].Selected && review.Entries[2].Selected, "select new uses completed receipt, not last selection");
    review.Entries[0].Selected = true;
    Control<TextBox>("FileSearch").Text = "ดนตรี";
    Dispatcher.UIThread.RunJobs();
    Expect(Control<WrapPanel>("FileCards").Children.Count == 1, "search filters without altering selection");
    Expect(review.Entries[0].Selected, "filter preserves hidden selections");
    Control<ComboBox>("QualityChoice").SelectedIndex = 5;
    Expect(Control<ComboBox>("QualityChoice").SelectedIndex == 5, "MP3 remains selectable on the review screen");
    Click("HistoryTab");
    Expect(Control<ScrollViewer>("RecentPage").IsVisible && Control<Border>("HistoryIndicator").IsVisible, "history selected tab indicator");
    Capture("05-history-thai");
    window.Close();

    // A deterministic HTTP fixture exercises the production direct downloader.
    var destination = Path.Combine(stateFolder, "downloads");
    Directory.CreateDirectory(destination);
    var payload = new byte[] { 1, 2, 3, 4, 5, 6 };
    var handler = new FixtureHandler(request => {
        var response = new HttpResponseMessage(HttpStatusCode.OK) { Content = new ByteArrayContent(payload) };
        response.Headers.ETag = new EntityTagHeaderValue("\"stable\"");
        return response;
    });
    var service = new DownloadService(new HttpClient(handler));
    var direct = new DownloadItem { Url = "https://fixture.test/a.mp4", Name = "a.mp4" };
    Complete(service.DownloadAsync(direct, destination, CancellationToken.None));
    Expect(direct.Status == "Complete" && File.ReadAllBytes(direct.ResultPath!).SequenceEqual(payload), "direct download writes exact result and path");
    var repeat = new DownloadItem { Url = direct.Url, Name = direct.Name };
    Complete(service.DownloadAsync(repeat, destination, CancellationToken.None));
    Expect(repeat.ResultPath != direct.ResultPath && File.Exists(direct.ResultPath), "explicit repeats never overwrite an earlier file");
    var missing = Path.Combine(destination, "unplugged");
    try { Complete(service.DownloadAsync(new DownloadItem { Url = direct.Url }, missing, CancellationToken.None)); throw new Exception("missing destination accepted"); }
    catch (DirectoryNotFoundException) { Expect(!Directory.Exists(missing), "unplugged destination is not recreated"); }
    var resume = new DownloadItem { Url = direct.Url, Name = "resume", TargetPath = Path.Combine(destination, "resumed.mp4"), PartialPath = Path.Combine(destination, ".resume.part"), EntityTag = "\"stable\"" };
    File.WriteAllBytes(resume.PartialPath, payload[..3]);
    var ranged = new DownloadService(new HttpClient(new FixtureHandler(request => {
        Expect(request.Headers.Range?.Ranges.Single().From == 3 && request.Headers.IfRange?.EntityTag?.Tag == "\"stable\"", "resume sends Range and If-Range");
        var response = new HttpResponseMessage(HttpStatusCode.PartialContent) { Content = new ByteArrayContent(payload[3..]) };
        response.Content.Headers.ContentRange = new ContentRangeHeaderValue(3, 5, 6);
        response.Headers.ETag = new EntityTagHeaderValue("\"stable\"");
        return response;
    })));
    Complete(ranged.DownloadAsync(resume, destination, CancellationToken.None));
    Expect(File.ReadAllBytes(resume.ResultPath!).SequenceEqual(payload), "resume appends only matching ranged bytes");
    var queueState = new AppStateService(Path.Combine(stateFolder, "queue-ui"));
    queueState.SaveSettings(new AppSettings { Destination = destination, CheckUpdatesAutomatically = false, HideToTray = false });
    var completion = new TaskCompletionSource<HttpResponseMessage>();
    var queueService = new DownloadService(new HttpClient(new AsyncFixtureHandler((_, token) => completion.Task.WaitAsync(token))));
    var queueWindow = new MainWindow(queueState, false, queueService);
    queueWindow.Show();
    var queued = new DownloadItem { Url = "https://fixture.test/clip.mp4", Name = "คลิปทดสอบ.mp4", Destination = destination, IsMedia = false, AnalysisCompleted = true, Status = "Ready", CanStart = true };
    queueWindow.OpenReview(queued);
    queueWindow.FindControl<Button>("ReviewDownloadButton")!.RaiseEvent(new RoutedEventArgs(Button.ClickEvent));
    Dispatcher.UIThread.RunJobs();
    Expect(queued.Status == "Downloading", "review confirm starts idle download immediately");
    var activeBounds = queueWindow.FindControl<TextBlock>("HeaderStatus")!.Bounds;
    queued.Progress = 9; queued.Speed = "1 KB/s"; queued.Eta = "5s";
    Dispatcher.UIThread.RunJobs();
    var windowBounds = queueWindow.Bounds;
    queued.Progress = 99; queued.Speed = "999 MB/s"; queued.Eta = "99:59";
    Dispatcher.UIThread.RunJobs();
    Expect(queueWindow.Bounds == windowBounds && queueWindow.FindControl<TextBlock>("HeaderStatus")!.Bounds == activeBounds, "running numbers never resize header or window");
    using (var frame = queueWindow.CaptureRenderedFrame()) frame!.Save(Path.Combine(pictures, "06-downloading-thai.png"), Avalonia.Media.Imaging.PngBitmapEncoderOptions.Default);
    var second = new DownloadItem { Url = "https://fixture.test/other.mp4", Name = "อีกไฟล์.mp4", Destination = destination, IsMedia = false, AnalysisCompleted = true, Status = "Ready" };
    queueWindow.OpenReview(second);
    Expect((string?)queueWindow.FindControl<Button>("ReviewDownloadButton")!.Content == "เข้าคิว", "review changes to queue action while busy");
    completion.SetResult(new HttpResponseMessage(HttpStatusCode.OK) { Content = new ByteArrayContent(payload) });
    var finishDeadline = DateTime.UtcNow.AddSeconds(10);
    while (queued.Status != "Complete" && DateTime.UtcNow < finishDeadline) { Dispatcher.UIThread.RunJobs(); Thread.Sleep(1); }
    Dispatcher.UIThread.RunJobs();
    Expect(queued.Status == "Complete" && File.Exists(queued.ResultPath), "queue writes actual result");
    Expect(queueState.LoadHistory().Single().ResultPath == queued.ResultPath, "completed file path reaches history");
    Expect((string?)queueWindow.FindControl<Button>("ReviewDownloadButton")!.Content == "ดาวน์โหลด", "review action returns to download when queue becomes idle");
    queueWindow.Close();
    var pausedState = new AppStateService(Path.Combine(stateFolder, "paused-queue"));
    pausedState.SaveSettings(new AppSettings { Destination = destination, HideToTray = false, CheckUpdatesAutomatically = false });
    var held = new DownloadItem { Url = "https://fixture.test/held.mp4", Destination = destination, Name = "held.mp4", Status = "Waiting", IsMedia = false, AnalysisCompleted = true };
    // Waiting jobs restored after restart become paused until explicitly resumed.
    pausedState.SaveQueue([held]);
    var restoredWindow = new MainWindow(pausedState, false, service);
    restoredWindow.Show(); restoredWindow.PauseEntireQueue();
    Expect(pausedState.LoadSettings().QueuePaused, "pause-all is durable");
    Complete(restoredWindow.ResumeEntireQueueAsync());
    Expect(pausedState.LoadHistory().Count == 1 && !pausedState.LoadSettings().QueuePaused, "resume-all runs the restored job and records completion");
    restoredWindow.Close();
    var renameJob = new DownloadItem { Url = "https://fixture.test/media" };
    var oldMediaPath = Path.Combine(destination, $"clip [id]-{renameJob.Id:N}.mp4");
    File.WriteAllBytes(oldMediaPath, payload); renameJob.OutputPaths.Add(oldMediaPath); renameJob.ResultPath = oldMediaPath;
    DownloadService.FinalizeMediaNames(renameJob, destination);
    Expect(renameJob.ResultPath == Path.Combine(destination, "clip [id].mp4") && !File.Exists(oldMediaPath), "final media naming moves rather than duplicates the file");
    Console.WriteLine("PASS parity additions: receipts, select-new, photo carousel, playback validation, phone inbox durability, English UI, compact resize, final filenames");
    Console.WriteLine("PASS production UI download pipeline, saved history, fixed metrics, dynamic download/queue action");
    if (args.Contains("--live-drive"))
    {
        // Public one-document fixture maintained by the gdown project.
        const string url = "https://drive.google.com/drive/folders/12zxlvJtuHFV6awc3AINaNHnfvRttPv0i";
        using var networkDeadline = new CancellationTokenSource(TimeSpan.FromSeconds(30));
        var task = new PublicDriveService().AnalyzeAsync(url, networkDeadline.Token);
        Complete(task);
        var result = task.Result;
        Expect(result.IsCollection && result.Entries?.Count == 1, "live public Drive fixture enumerates its single document");
        var liveFolder = Path.Combine(stateFolder, "live-drive");
        Directory.CreateDirectory(liveFolder);
        var liveItem = new DownloadItem { Url = url, Name = result.Title, IsDrive = true, IsCollection = true, IsMedia = false, Entries = result.Entries!, Destination = liveFolder };
        Complete(new DownloadService().DownloadAsync(liveItem, liveFolder, networkDeadline.Token));
        var downloaded = Directory.GetFiles(liveFolder);
        Expect(downloaded.Length == 1 && downloaded[0].EndsWith(".pptx", StringComparison.OrdinalIgnoreCase), "live Drive document export saves the proper extension without a duplicate folder");
        Expect(File.ReadAllBytes(downloaded[0]).Take(2).SequenceEqual(new byte[] { 80, 75 }), "live exported document is ZIP/PPTX, never an HTML login page");
        Console.WriteLine("PASS live public Drive folder listing and real Google Slides export");
    }
    if (args.Contains("--live-providers")) Complete(ProviderChecks.RunAsync(Path.Combine(stateFolder, "provider-tests")), 180);
    Console.WriteLine("PASS media metadata, options, file safety and tagged progress");
    Console.WriteLine("PASS production UI: Thai layout, navigation, select-all/individual, card sizes, search, MP3");
    Console.WriteLine("PASS direct HTTP download, repeat protection, unplugged destination, ETag resume");
}
finally { if (Directory.Exists(stateFolder)) Directory.Delete(stateFolder, true); }
Console.WriteLine("PASS link parsing and duplicate protection");
Console.WriteLine("PASS 24-hour automatic update cadence");
Console.WriteLine("PASS settings and queue persistence");

sealed class FixtureHandler(Func<HttpRequestMessage, HttpResponseMessage> handler) : HttpMessageHandler
{
    protected override Task<HttpResponseMessage> SendAsync(HttpRequestMessage request, CancellationToken cancellationToken) => Task.FromResult(handler(request));
}
sealed class AsyncFixtureHandler(Func<HttpRequestMessage, CancellationToken, Task<HttpResponseMessage>> handler) : HttpMessageHandler
{
    protected override Task<HttpResponseMessage> SendAsync(HttpRequestMessage request, CancellationToken cancellationToken) => handler(request, cancellationToken);
}
