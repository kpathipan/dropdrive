using Velopack;
using Velopack.Sources;

namespace DropDrive.Windows.Services;

public sealed class UpdateService
{
    private const string Repository = "https://github.com/kpathipan/dropdrive";

    public async Task<UpdateCheckResult> CheckDownloadAndRestartAsync(CancellationToken cancellationToken = default)
    {
        try
        {
            var manager = new UpdateManager(new GithubSource(Repository, null, false));
            if (!manager.IsInstalled) return new(false, "Update checks are available in the installed app.");
            var update = await manager.CheckForUpdatesAsync();
            if (update is null) return new(false, "DropDrive is up to date.");
            await manager.DownloadUpdatesAsync(update, null, cancellationToken);
            manager.ApplyUpdatesAndRestart(update);
            return new(true, "Restarting to install the update…");
        }
        catch (Exception error)
        {
            return new(false, $"Could not check for updates: {FriendlyMessage(error)}", true);
        }
    }

    private static string FriendlyMessage(Exception error) => error switch {
        HttpRequestException => "check your internet connection.",
        TaskCanceledException => "the request timed out.",
        _ => "the Windows update feed is not available yet."
    };
}

public sealed record UpdateCheckResult(bool Restarting, string Message, bool IsError = false);
