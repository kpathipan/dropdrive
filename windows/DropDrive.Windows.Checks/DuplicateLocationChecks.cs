using Avalonia.Controls;
using Avalonia.Interactivity;
using DropDrive.Windows;
using DropDrive.Windows.Models;
using DropDrive.Windows.Services;

internal static class DuplicateLocationChecks
{
    public static void Run(string folder)
    {
        static void Check(bool value, string message) { if (!value) throw new Exception(message); }
        Directory.CreateDirectory(folder);
        var output = Path.Combine(folder, "วิดีโอ renamed (1).mp4");
        File.WriteAllText(output, "fixture");
        const string url = "https://youtu.be/duplicateFixture";
        DownloadHistoryEntry Entry(string path, string status = "Complete", string link = url) => new()
        { Url = link, Name = "Original title", Source = "YouTube", Status = status, ResultPath = path };
        var history = new[] { Entry(Path.Combine(folder, "deleted.mp4")), Entry(output) };
        Check(DuplicateDownloadLocation.CompletedPath(url, [], history) == output, "missing recent output falls back to existing recorded output");
        Check(DuplicateDownloadLocation.CompletedPath(url, [], [Entry(output, "Failed"), Entry(output, link: "https://youtu.be/different")]) == null, "failed and unrelated entries excluded");
        Check(DuplicateDownloadLocation.ExistingPath("https://fixture.test/video") == null && DuplicateDownloadLocation.ExistingPath("relative.mp4") == null, "non-local and relative paths rejected");
        Check(DuplicateDownloadLocation.CompletedPath(url, [], []) == null, "trimmed history has no guessed path");
        var completed = new DownloadItem { Url = url, Name = "Original", Status = "Complete", ResultPath = folder };
        Check(DuplicateDownloadLocation.CompletedPath(url, [completed], []) == folder, "completed queue folder can be revealed");
        completed.Status = "Downloading";
        Check(DuplicateDownloadLocation.CompletedPath(url, [completed], []) == null, "in-progress output is not a completed copy");

        var state = new AppStateService(Path.Combine(folder, "state"));
        state.SaveSettings(new AppSettings { Destination = folder, CheckUpdatesAutomatically = false, HideToTray = false });
        completed.Status = "Complete"; completed.ResultPath = output; state.AddHistory(completed);
        var window = new MainWindow(state, false, googleAccounts: new GoogleAccountService(new GoogleChecks.MemoryGoogleStore()));
        window.Show();
        try
        {
            var review = new DownloadItem { Url = url, Name = "Original", Status = "Ready", AnalysisCompleted = true, IsMedia = true, AudioOnly = true, Destination = folder };
            window.OpenReview(review);
            var button = window.FindControl<Button>("RevealDuplicateButton")!;
            Check(button.IsVisible && button.Tag as string == output, "duplicate review exposes the recorded Unicode output");
            Check(review.Status == "Ready" && review.AudioOnly, "location review preserves MP3 and download state");
            File.Delete(output);
            button.RaiseEvent(new RoutedEventArgs(Button.ClickEvent));
            Check(!button.IsVisible && window.FindControl<TextBlock>("DuplicateLocationUnavailable")!.IsVisible, "stale click rechecks path and reports missing file without launching Explorer");
            Check(review.Status == "Ready" && review.AudioOnly, "missing location never starts or cancels download");

            var collision = Path.Combine(folder, "existing.pdf"); File.WriteAllText(collision, "preserve");
            var direct = new DownloadItem { Url = "https://fixture.test/file.pdf", Name = "existing.pdf", Status = "Ready", IsMedia = false, Destination = folder };
            window.OpenReview(direct);
            Check(window.FindControl<StackPanel>("CollisionNotice")!.IsVisible && window.FindControl<Button>("RevealCollisionButton")!.Tag as string == collision, "exact destination collision offers reveal even without history");
            window.FindControl<TextBox>("ReviewName")!.Text = "new.pdf";
            Avalonia.Threading.Dispatcher.UIThread.RunJobs();
            Check(!window.FindControl<StackPanel>("CollisionNotice")!.IsVisible, "rename refreshes collision location");
            Check(File.ReadAllText(collision) == "preserve", "checking locations preserves originals");
            direct.IsCollection = true; direct.Name = Path.GetFileName(folder);
            Check(DuplicateDownloadLocation.CollisionPath(direct, folder, direct.Name) == null, "explicit source-named destination is not a duplicate nested folder");
        }
        finally { window.Close(); }
        Console.WriteLine("PASS duplicate locations: recorded files/folders, stale paths, Unicode, MP3 preservation and destination collisions");
    }
}
