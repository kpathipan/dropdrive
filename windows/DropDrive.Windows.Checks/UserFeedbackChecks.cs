using Avalonia.Controls;
using DropDrive.Windows;
using DropDrive.Windows.Models;
using DropDrive.Windows.Services;
using System.Net;

internal static class UserFeedbackChecks
{
    public static async Task RunAsync(string folder)
    {
        static void Check(bool condition, string message) { if (!condition) throw new Exception(message); }
        Directory.CreateDirectory(folder);
        var state = new AppStateService(Path.Combine(folder, "state"));
        state.SaveSettings(new AppSettings { Destination = folder, HideToTray = false, CheckUpdatesAutomatically = false });
        var window = new MainWindow(state, false, googleAccounts: new GoogleAccountService(new GoogleChecks.MemoryGoogleStore()));
        window.Show();
        try
        {
            var item = new DownloadItem { Url = "https://fixture.test/repeat.mp4", Name = "Repeat", Status = "Ready", AnalysisCompleted = true, Destination = folder };
            window.OpenReview(item);
            window.FindControl<StackPanel>("ReviewPanel")!.IsVisible = false;
            await window.AnalyzeLinksAsync(item.Url);
            Check(window.FindControl<StackPanel>("ReviewPanel")!.IsVisible, "pasting a pending duplicate reopens review");
            item.Status = "Downloading";
            await window.AnalyzeLinksAsync(item.Url);
            Check(window.FindControl<TextBox>("LinkBox")!.Text == item.Url, "active duplicate preserves pasted input");
            item.Status = "Complete"; state.AddHistory(item);
            await window.AnalyzeLinksAsync(item.Url);
            Check(window.FindControl<TextBlock>("DuplicateNotice")!.IsVisible, "completed duplicate offers explicit confirmation");
        }
        finally { window.Close(); }

        var downloads = Path.Combine(folder, "Downloads"); Directory.CreateDirectory(downloads);
        using var client = new HttpClient(new Bytes());
        var service = new DownloadService(client);
        DownloadItem Collection() => new() { Url = "https://drive.google.com/drive/u/0/folders/test", Name = "Project", IsDrive = true, IsCollection = true, IsMedia = false,
            Entries = [new() { Index = 1, Title = "one.mp4", Url = "https://drive.google.com/file/d/one/view" },
                       new() { Index = 2, Title = "two.mp4", Url = "https://drive.google.com/file/d/two/view", RelativeFolder = "Subfolder" }] };
        var first = Collection();
        await service.DownloadAsync(first, downloads, CancellationToken.None);
        Check(first.ResultPath == Path.Combine(downloads, "Project") && File.Exists(Path.Combine(first.ResultPath, "Subfolder", "two.mp4")), "folder URL preserves root and nested structure");
        Check(!File.Exists(Path.Combine(downloads, "one.mp4")), "files never scatter into the selected parent");
        var remembered = first.ResultPath;
        await service.DownloadAsync(first, downloads, CancellationToken.None);
        Check(first.ResultPath == remembered, "resume keeps the same owned folder");
        var repeat = Collection(); await service.DownloadAsync(repeat, downloads, CancellationToken.None);
        Check(repeat.ResultPath == Path.Combine(downloads, "Project (1)"), "separate download preserves existing folder");
        var explicitFolder = Collection(); await service.DownloadAsync(explicitFolder, remembered!, CancellationToken.None);
        Check(explicitFolder.ResultPath == remembered && !Directory.Exists(Path.Combine(remembered!, "Project")), "explicit matching destination is not nested twice");
        Console.WriteLine("PASS user feedback: visible duplicate confirmation and source-folder grouping without double nesting");
    }
    private sealed class Bytes : HttpMessageHandler
    {
        protected override Task<HttpResponseMessage> SendAsync(HttpRequestMessage request, CancellationToken token) =>
            Task.FromResult(new HttpResponseMessage(HttpStatusCode.OK) { Content = new ByteArrayContent([1, 2, 3]) });
    }
}
