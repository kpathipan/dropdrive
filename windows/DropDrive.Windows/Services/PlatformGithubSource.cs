using System.Text.Json;
using Velopack.Sources;

namespace DropDrive.Windows.Services;

/// Select by Windows feed assets, never by the latest Mac/Windows tag alone.
public sealed class PlatformGithubSource(IFileDownloader? downloader = null)
    : GithubSource("https://github.com/kpathipan/dropdrive", null, false, downloader)
{
    protected override async Task<GithubRelease[]> GetReleases(bool includePrereleases)
    {
        var json = await Downloader.DownloadString(
            "https://api.github.com/repos/kpathipan/dropdrive/releases?per_page=100",
            GetRequestHeaders("application/vnd.github+json")).ConfigureAwait(false);
        using var document = JsonDocument.Parse(json);
        return document.RootElement.EnumerateArray()
            .Where(r => !r.GetProperty("draft").GetBoolean() && !r.GetProperty("prerelease").GetBoolean())
            .Select(r => r.Deserialize<GithubRelease>())
            .OfType<GithubRelease>()
            .Where(r => r.Assets.Any(a => a.Name == "releases.win.json")
                && r.Assets.Any(a => a.Name?.EndsWith("-full.nupkg", StringComparison.Ordinal) == true))
            .OrderByDescending(r => r.PublishedAt).ToArray();
    }
}
