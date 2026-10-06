using System.Diagnostics;
using Avalonia.Controls;
using Avalonia.Interactivity;
using Avalonia.Threading;
using DropDrive.Windows;
using DropDrive.Windows.Models;
using DropDrive.Windows.Services;

internal static class CompletionChecks
{
    public static async Task RunAsync(string folder)
    {
        static void Check(bool ok, string message) { if (!ok) throw new Exception(message); }
        Directory.CreateDirectory(folder);
        var file = Path.Combine(folder, "คลิป ทดสอบ 🎵.mp3");
        await File.WriteAllBytesAsync(file, [1, 2, 3]);
        var calls = 0;
        Task Validate(string path, CancellationToken token) { token.ThrowIfCancellationRequested(); calls++; Check(path == file, "Wrong Unicode path"); return Task.CompletedTask; }
        DownloadItem Item() => new() { Url = "https://www.youtube.com/watch?v=fixture", OutputPaths = [file], ResultPath = file };
        var clean = Item();
        await DownloadCompletion.VerifyMediaAsync(clean, 0, "", Validate, CancellationToken.None);
        Check(clean.CompletionWarning == "" && calls == 1, "Normal completion changed");
        foreach (var url in new[] { "https://www.youtube.com/watch?v=fixture", "https://www.tiktok.com/@fixture/video/123" })
        {
            var late = Item(); late.Url = url;
            await DownloadCompletion.VerifyMediaAsync(late, 1, "ERROR: late post-processing failure", Validate, CancellationToken.None);
            Check(late.CompletionWarning.Length > 0 && late.ResultPath == file && File.Exists(file), "Verified final output was discarded on late error");
        }
        var invalid = Item();
        try { await DownloadCompletion.VerifyMediaAsync(invalid, 1, "late error", (_, _) => throw new IOException("corrupt"), CancellationToken.None); throw new Exception("Corrupt output accepted"); }
        catch (IOException) { Check(invalid.CompletionWarning == "", "Corrupt file marked successful"); }
        var missing = Item(); missing.OutputPaths.Clear();
        try { await DownloadCompletion.VerifyMediaAsync(missing, 1, "connection reset", Validate, CancellationToken.None); throw new Exception("Missing output accepted"); }
        catch (HttpRequestException) { }
        var playlist = Item(); playlist.IsCollection = true;
        try { await DownloadCompletion.VerifyMediaAsync(playlist, 1, "missing entry", Validate, CancellationToken.None); throw new Exception("Partial playlist accepted"); }
        catch (InvalidOperationException) { }
        using var cancelled = new CancellationTokenSource(); cancelled.Cancel();
        try { await DownloadCompletion.VerifyMediaAsync(Item(), 0, "", Validate, cancelled.Token); throw new Exception("Cancellation ignored"); }
        catch (OperationCanceledException) { }
        var done = Item(); done.Status = "Complete";
        DownloadCompletion.Optional(done, "history warning", () => throw new IOException("locked"));
        Check(done.Status == "Complete" && done.CanOpen && done.CompletionWarning.Contains("history warning"), "Ancillary failure changed successful state");
        var parsed = Item(); parsed.OutputPaths.Clear();
        DownloadService.ParseProgress(parsed, "DDPATH:" + file);
        Check(parsed.ResultPath == file && parsed.OutputPaths.Single() == file, "Thai path parsing changed");
        var args = MediaOptions.Arguments(parsed, folder, folder);
        Check(args[args.IndexOf("--encoding") + 1] == "utf-8", "Extractor output encoding not pinned");

        // Exercise the real window's catch boundary, not just the helper: a
        // locked statistics checkpoint must not relabel a finished transfer.
        var statePath = Path.Combine(folder, "state");
        var state = new AppStateService(statePath);
        state.SaveSettings(new AppSettings { Destination = folder, HideToTray = false, CheckUpdatesAutomatically = false });
        Directory.CreateDirectory(Path.Combine(statePath, "statistics.json.tmp"));
        using var client = new HttpClient(new Bytes());
        var window = new MainWindow(state, false, new DownloadService(client), new GoogleAccountService(new GoogleChecks.MemoryGoogleStore()));
        window.Show();
        try
        {
            var item = new DownloadItem { Url = "https://fixture.test/completed.mp4", Name = "completed.mp4", IsMedia = false, AnalysisCompleted = true, Status = "Ready", Destination = folder };
            window.OpenReview(item);
            window.FindControl<Button>("ReviewDownloadButton")!.RaiseEvent(new RoutedEventArgs(Button.ClickEvent));
            var until = DateTime.UtcNow.AddSeconds(10);
            while (string.IsNullOrEmpty(item.CompletionWarning) && DateTime.UtcNow < until) { Dispatcher.UIThread.RunJobs(); await Task.Delay(1); }
            Check(item.Status == "Complete" && item.CanOpen && !item.CanRetry && File.Exists(item.ResultPath), "Statistics failure turned real download into Failed");
            Check(state.LoadHistory().Single().Status == "Complete", "History mislabeled completion");
        }
        finally { window.Close(); }

        if (OperatingSystem.IsWindows())
        {
            var tools = Path.Combine(AppContext.BaseDirectory, "Tools");
            var start = new ProcessStartInfo(Path.Combine(tools, "ffmpeg.exe")) { UseShellExecute = false, CreateNoWindow = true, RedirectStandardError = true };
            foreach (var arg in new[] { "-y", "-v", "error", "-f", "lavfi", "-i", "sine=frequency=440:duration=1", "-c:a", "libmp3lame", file }) start.ArgumentList.Add(arg);
            using var process = Process.Start(start)!;
            var errors = process.StandardError.ReadToEndAsync();
            await process.WaitForExitAsync(); await errors;
            Check(process.ExitCode == 0, "Cannot create native Unicode media fixture");
            await MediaValidator.ValidateAsync(file, true, tools, CancellationToken.None);
            var rename = new DownloadItem { Url = "https://fixture.test/rename" };
            var lockedPath = Path.Combine(folder, $"คลิป-{rename.Id:N}.mp3");
            File.Copy(file, lockedPath); rename.OutputPaths.Add(lockedPath); rename.ResultPath = lockedPath;
            using (var held = new FileStream(lockedPath, FileMode.Open, FileAccess.Read, FileShare.None))
                DownloadService.FinalizeMediaNames(rename, folder);
            Check(rename.ResultPath == lockedPath && File.Exists(lockedPath) && rename.CompletionWarning.Length > 0, "Locked rename discarded playable file");
            var corruptPath = Path.Combine(folder, "เสีย.mp3"); await File.WriteAllBytesAsync(corruptPath, [1, 2, 3]);
            try { await MediaValidator.ValidateAsync(corruptPath, true, tools, CancellationToken.None); throw new Exception("Native validator accepted corrupt media"); }
            catch (IOException) { }
            Console.WriteLine("PASS native ffmpeg/ffprobe round trip with Thai + emoji output path");
        }
        Console.WriteLine("PASS completion: verified late errors, corrupt/missing output rejection, partial playlist rejection, cancellation, Thai paths, real UI statistics failure");
    }
    private sealed class Bytes : HttpMessageHandler
    {
        protected override Task<HttpResponseMessage> SendAsync(HttpRequestMessage request, CancellationToken token) =>
            Task.FromResult(new HttpResponseMessage(System.Net.HttpStatusCode.OK) { Content = new ByteArrayContent([1, 2, 3]) });
    }
}
