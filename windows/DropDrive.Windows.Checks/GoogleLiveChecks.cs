using System.Text.Json;
using DropDrive.Windows.Services;

// Explicit, interactive developer smoke check. Never runs in normal CI and
// never stores user tokens on disk. Browser consent must be given by the user.
internal static class GoogleLiveChecks
{
    public static async Task RunAsync(string configurationPath)
    {
        using var config = JsonDocument.Parse(await File.ReadAllTextAsync(configurationPath));
        var installed = config.RootElement.GetProperty("installed");
        var client = new GoogleOAuthClient(installed.GetProperty("client_id").GetString()!, installed.GetProperty("client_secret").GetString()!);
        var store = new GoogleChecks.MemoryGoogleStore();
        var accounts = new GoogleAccountService(store, client);
        using var deadline = new CancellationTokenSource(TimeSpan.FromMinutes(4));
        Console.WriteLine("Interactive Google check: tokens remain in memory; no private Drive listing or file download.");
        try
        {
            await accounts.SignInAsync(deadline.Token, url => Console.WriteLine("OPEN_AUTHORIZATION_URL " + url));
            var account = accounts.Accounts.Single();
            Console.WriteLine("PASS Google browser consent, loopback callback, PKCE code exchange and account identity.");
            store.State.Accounts.Single().ExpiresAt = DateTimeOffset.MinValue;
            if (string.IsNullOrEmpty(await accounts.AccessTokenAsync(account.Id, deadline.Token))) throw new InvalidOperationException("Empty refreshed token");
            Console.WriteLine("PASS real Google refresh token exchange (no second sign-in).");
            var analysis = await new GoogleDriveService(accounts).AnalyzeForAccountAsync(
                "https://drive.google.com/drive/folders/12zxlvJtuHFV6awc3AINaNHnfvRttPv0i", account.Id, deadline.Token);
            if (!analysis.IsCollection || analysis.Entries?.Count != 1) throw new InvalidOperationException("Public Drive fixture differs from expectation");
            Console.WriteLine("PASS authenticated Drive API metadata and document export mapping using the public fixture.");
        }
        catch (OperationCanceledException)
        {
            Console.WriteLine("INCOMPLETE Google consent was cancelled or timed out. Start a fresh check to retry.");
            Environment.ExitCode = 2;
        }
        finally
        {
            foreach (var session in store.State.Accounts) { session.AccessToken = ""; session.RefreshToken = ""; }
            store.State.Accounts.Clear();
            Console.WriteLine("Google smoke-check session discarded; no user tokens written to disk.");
        }
    }
}
