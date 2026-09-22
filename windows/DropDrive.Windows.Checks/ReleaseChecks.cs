using System.Text;
using System.Text.Json;
using DropDrive.Windows.Services;
using Velopack.Logging;
using Velopack.Sources;

internal static class ReleaseChecks
{
    public static async Task RunAsync()
    {
        object Release(string name, string[] assets, bool draft = false, bool prerelease = false) => new {
            name, draft, prerelease, published_at = "2026-09-22T00:00:00Z",
            assets = assets.Select(a => new { name = a, browser_download_url = $"https://fixture.test/{name}/{a}" }) };
        var transport = new Transport(JsonSerializer.Serialize(new[] {
            Release("Mac-newest", ["DropDrive-v6.25.1.dmg"]),
            Release("shared", ["DropDrive-v6.25.0.dmg", "releases.win.json", "app-full.nupkg"]),
            Release("draft", ["releases.win.json", "app-full.nupkg"], draft: true),
            Release("preview", ["releases.win.json", "app-full.nupkg"], prerelease: true),
            Release("incomplete", ["releases.win.json"]) }));
        var feed = await new PlatformGithubSource(transport).GetReleaseFeed(new Logger(), "com.dropdrive.windows", "win");
        if (feed.Assets.Length != 1 || feed.Assets[0].Version.ToString() != "6.25.0"
            || transport.FeedRequests != 1) throw new Exception("Mixed release selection failed");
        Console.WriteLine("PASS Windows update feed: mixed Mac releases, shared release, draft/prerelease/incomplete isolation");
    }
    private sealed class Logger : IVelopackLogger { public void Log(VelopackLogLevel level, string? message, Exception? error) { } }
    private sealed class Transport(string catalogue) : IFileDownloader
    {
        public int FeedRequests;
        public Task<string> DownloadString(string url, IDictionary<string, string>? headers = null, double timeout = 30)
        {
            if (!url.EndsWith("releases?per_page=100", StringComparison.Ordinal)) throw new Exception("Unexpected catalogue request");
            return Task.FromResult(catalogue);
        }
        public Task<byte[]> DownloadBytes(string url, IDictionary<string, string>? headers = null, double timeout = 30)
        {
            if (url != "https://fixture.test/shared/releases.win.json") throw new Exception("Wrong platform or unpublished feed fetched");
            FeedRequests++;
            return Task.FromResult(Encoding.UTF8.GetBytes("""{"Assets":[{"PackageId":"com.dropdrive.windows","Version":"6.25.0","Type":"Full","FileName":"app-full.nupkg","SHA1":"fixture","Size":1}]}"""));
        }
        public Task DownloadFile(string url, string targetFile, Action<int> progress, IDictionary<string, string>? headers = null, double timeout = 30, CancellationToken cancelToken = default) => throw new Exception("Catalogue test must not install updates");
    }
}
