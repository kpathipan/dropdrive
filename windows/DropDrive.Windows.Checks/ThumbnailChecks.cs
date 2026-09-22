using Avalonia;
using Avalonia.Controls;
using Avalonia.Platform;
using Avalonia.Threading;
using DropDrive.Windows;
using DropDrive.Windows.Models;
using DropDrive.Windows.Services;
using System.Net;

internal static class ThumbnailChecks
{
    public static async Task CacheAsync()
    {
        using var input = AssetLoader.Open(new Uri("avares://DropDrive/Assets/dropdrive.png"));
        using var bytes = new MemoryStream(); input.CopyTo(bytes);
        var handler = new Images(bytes.ToArray());
        using var service = new ThumbnailService(new HttpClient(handler), maximumBytes: bytes.Length * 2);
        for (var i = 0; i < 120; i++)
        {
            using var bitmap = await service.GetAsync($"https://fixture.test/{i}.png");
            if (bitmap == null) throw new Exception("Thumbnail stopped after cache capacity");
        }
        var before = handler.Requests;
        using var cached = await service.GetAsync("https://fixture.test/119.png");
        if (cached == null || handler.Requests != before) throw new Exception("Recent thumbnail not cached");
        using var evicted = await service.GetAsync("https://fixture.test/0.png");
        if (evicted == null || handler.Requests != before + 1) throw new Exception("LRU eviction must refetch, not permanently refuse");
        Console.WriteLine("PASS thumbnail byte-budget eviction and >100 unique images; no disk cache");
    }

    public static void Viewport(string folder)
    {
        using var input = AssetLoader.Open(new Uri("avares://DropDrive/Assets/dropdrive.png"));
        using var bytes = new MemoryStream(); input.CopyTo(bytes);
        var handler = new Images(bytes.ToArray());
        var state = new AppStateService(folder);
        state.SaveSettings(new AppSettings { Destination = folder, HideToTray = false, CheckUpdatesAutomatically = false });
        var window = new MainWindow(state, false, googleAccounts: new GoogleAccountService(new GoogleChecks.MemoryGoogleStore()), thumbnails: new ThumbnailService(new HttpClient(handler)));
        window.Show();
        var item = new DownloadItem { Url = "https://fixture.test/folder", Status = "Ready", Name = "Large folder", IsMedia = false, IsCollection = true,
            Entries = Enumerable.Range(1, 130).Select(i => new MediaEntry { Index = i, Title = $"{i}.mp4", ThumbnailUrl = $"https://fixture.test/{i}.png" }).ToList() };
        window.OpenReview(item);
        window.FindControl<Expander>("FileSelector")!.IsExpanded = true;
        var view = window.FindControl<ScrollViewer>("FileViewport")!;
        void Wait(Func<bool> condition)
        {
            var deadline = DateTime.UtcNow.AddSeconds(5);
            while (!condition() && DateTime.UtcNow < deadline) { Dispatcher.UIThread.RunJobs(); Thread.Sleep(1); }
            if (!condition()) throw new Exception("Visible thumbnails did not load");
        }
        Wait(() => item.Entries[0].Thumbnail != null);
        if (handler.Requests >= 30 || item.Entries[100].Thumbnail != null) throw new Exception("Offscreen thumbnails eagerly loaded");
        view.Offset = new Vector(0, 100000);
        Wait(() => item.Entries[^1].Thumbnail != null);
        if (item.Entries[0].Thumbnail != null) throw new Exception("Offscreen decoded thumbnail not released");
        window.Close();
        Console.WriteLine("PASS real folder viewport loads files after index 100 and releases offscreen images");
    }
    private sealed class Images(byte[] png) : HttpMessageHandler
    {
        public int Requests;
        protected override Task<HttpResponseMessage> SendAsync(HttpRequestMessage request, CancellationToken token)
        { Requests++; return Task.FromResult(new HttpResponseMessage(HttpStatusCode.OK) { Content = new ByteArrayContent(png) }); }
    }
}
