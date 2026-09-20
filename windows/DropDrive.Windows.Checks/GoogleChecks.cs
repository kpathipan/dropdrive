using System.Net;
using System.Net.Http.Headers;
using System.Text;
using System.Text.Json;
using DropDrive.Windows.Models;
using DropDrive.Windows.Services;

internal static class GoogleChecks
{
    public static async Task RunAsync(string folder)
    {
        static void Check(bool value, string message) { if (!value) throw new Exception(message); }
        static HttpResponseMessage Json(string value) => new(HttpStatusCode.OK) { Content = new StringContent(value, Encoding.UTF8, "application/json") };
        Check(GoogleAccountService.Challenge("dBjftJeZ4CVP-mB92K27uhbUJU1p1r_wW1gFWFOEjXk") == "E9Melhoa2OwvFrEMTJguCHaoeK1t8URWbuGJSstw-cM", "RFC7636 PKCE vector");
        Check(GoogleAccountService.ParseCallback("/?state=right&code=one", "right")?["code"] == "one", "OAuth callback valid state");
        Check(GoogleAccountService.ParseCallback("/?state=wrong&code=one", "right") == null && GoogleAccountService.ParseCallback("/?state=right&state=wrong&code=one", "right") == null, "OAuth CSRF/duplicate parameters rejected");
        var config = new GoogleOAuthClient("test.apps.googleusercontent.com", "test-client-secret");
        var authorization = GoogleAccountService.AuthorizationUrl(config, "http://127.0.0.1:1234/", "nonce", new string('x', 64));
        Check(authorization.Contains("code_challenge_method=S256") && !authorization.Contains(config.ClientSecret), "client secret never sent through browser URL");
        var store = new MemoryGoogleStore { State = new GoogleSessions { DefaultId = "a", Accounts = [
            new() { Id = "a", Email = "first@example.test", AccessToken = "fixture-a", RefreshToken = "refresh-a", ExpiresAt = DateTimeOffset.UtcNow.AddHours(1) },
            new() { Id = "b", Email = "second@example.test", AccessToken = "fixture-b", RefreshToken = "refresh-b", ExpiresAt = DateTimeOffset.UtcNow.AddHours(1) }] } };
        var accounts = new GoogleAccountService(store, config);
        var calls = new List<string>();
        var api = new GoogleDriveService(accounts, new HttpClient(new GoogleFixture(request => {
            Check(request.RequestUri!.Host == "www.googleapis.com", "bearer token sent only to Google API");
            var bearer = request.Headers.Authorization?.Parameter; calls.Add(bearer ?? "missing");
            if (bearer == "fixture-a") return new(HttpStatusCode.Forbidden);
            Check(bearer == "fixture-b", "fallback uses second authorized account");
            if (request.RequestUri.AbsolutePath.EndsWith("/folder")) return Json("""{"id":"folder","name":"Private folder","mimeType":"application/vnd.google-apps.folder"}""");
            if (request.RequestUri.Query.Contains("pageToken=")) return Json("""{"files":[{"id":"doc","name":"Notes","mimeType":"application/vnd.google-apps.document","modifiedTime":"2026-01-02T00:00:00Z","capabilities":{"canDownload":true}}]}""");
            return Json("""{"nextPageToken":"next","files":[{"id":"binary","name":"private.pdf","mimeType":"application/pdf","size":"3","md5Checksum":"abc","capabilities":{"canDownload":true}}]}""");
        })));
        var analysis = await api.AnalyzeAsync("https://drive.google.com/drive/folders/folder", CancellationToken.None);
        Check(analysis.AccountId == "b" && analysis.Entries?.Count == 2 && analysis.Entries[1].Title == "Notes.docx", "multi-account private Drive + pagination + Docs export");
        Check(calls[0] == "fixture-a" && calls[1] == "fixture-b", "default account tried first without prompting sign-in again");
        Check(analysis.Entries![0].Fingerprint == "abc", "authenticated Drive checksum reaches snapshot comparison");
        Directory.CreateDirectory(folder);
        var download = new DownloadService(new HttpClient(new GoogleFixture(request => {
            Check(request.Headers.Authorization?.Parameter == "fixture-b" && request.RequestUri!.Host == "www.googleapis.com", "private transfer uses selected account");
            Check(request.Headers.GetValues("X-Goog-Drive-Resource-Keys").Single() == "binary/key", "Drive resource-key download header");
            return new(HttpStatusCode.OK) { Content = new ByteArrayContent([1, 2, 3]) };
        }))) { GoogleAccounts = accounts };
        var item = new DownloadItem { Url = "https://drive.google.com/file/d/binary/view", Name = "private.pdf", IsDrive = true, IsMedia = false,
            DriveAccountId = "b", DriveFileId = "binary", DriveMimeType = "application/pdf", DriveResourceKey = "key" };
        await download.DownloadAsync(item, folder, CancellationToken.None);
        Check(item.Status == "Complete" && File.ReadAllBytes(item.ResultPath!).SequenceEqual(new byte[] { 1, 2, 3 }), "private file really written");
        Check(!JsonSerializer.Serialize(item).Contains("fixture-b"), "queue never serializes access token");
        var refreshCount = 0;
        store.State.Accounts[1].ExpiresAt = DateTimeOffset.UtcNow.AddMinutes(-1);
        var refreshAccounts = new GoogleAccountService(store, config, new HttpClient(new GoogleFixture(request => {
            refreshCount++; Check(request.RequestUri!.Host == "oauth2.googleapis.com" && request.Method == HttpMethod.Post, "refresh endpoint and method");
            return Json("""{"access_token":"fresh-token","refresh_token":"rotated-refresh","expires_in":3600}""");
        })));
        Check(await refreshAccounts.AccessTokenAsync("b", CancellationToken.None) == "fresh-token", "expired token refreshed");
        Check(await refreshAccounts.AccessTokenAsync("b", CancellationToken.None) == "fresh-token" && refreshCount == 1, "fresh token cached without repeat login");
        Check(store.State.Accounts[1].RefreshToken == "rotated-refresh", "refresh-token rotation persisted");
        await refreshAccounts.RemoveAsync("a"); Check(refreshAccounts.Accounts.Single().Id == "b" && refreshAccounts.Accounts[0].IsDefault, "remove one account preserves other/default");
        await refreshAccounts.RemoveAsync("b"); Check(refreshAccounts.Accounts.Count == 0, "optional login can return to anonymous mode");
        var consentStore = new MemoryGoogleStore();
        var grantDriveScope = false;
        var consent = new GoogleAccountService(consentStore, config, new HttpClient(new GoogleFixture(request => {
            if (request.RequestUri!.Host == "oauth2.googleapis.com") return Json(JsonSerializer.Serialize(new {
                access_token = "consent-access", refresh_token = "consent-refresh", expires_in = 3600,
                scope = grantDriveScope ? "openid email " + GoogleAccountService.DriveScope : "openid email" }));
            Check(request.Headers.Authorization?.Parameter == "consent-access", "profile identity is read with the new token");
            return Json("""{"sub":"consent-user","email":"consent@example.test","name":"Test account"}""");
        })));
        try { await consent.ExchangeCodeAsync("code", "http://127.0.0.1:1234/", "verifier", CancellationToken.None); throw new Exception("partial consent accepted"); }
        catch (InvalidOperationException) { }
        Check(consent.Accounts.Count == 0, "missing Drive consent must not save an unusable account");
        grantDriveScope = true;
        await consent.ExchangeCodeAsync("code", "http://127.0.0.1:1234/", "verifier", CancellationToken.None);
        Check(consent.Accounts.Single().Id == "consent-user" && consentStore.State.Accounts.Single().RefreshToken == "consent-refresh", "code exchange saves authorized identity and refresh token");
        var refreshStarted = new TaskCompletionSource(TaskCreationOptions.RunContinuationsAsynchronously);
        var releaseRefresh = new TaskCompletionSource(TaskCreationOptions.RunContinuationsAsynchronously);
        consentStore.State.Accounts[0].ExpiresAt = DateTimeOffset.MinValue;
        var concurrent = new GoogleAccountService(consentStore, config, new HttpClient(new AsyncGoogleFixture(async () => {
            refreshStarted.SetResult(); await releaseRefresh.Task;
            return Json("""{"access_token":"concurrent-refreshed","expires_in":3600}""");
        })));
        var refreshing = concurrent.AccessTokenAsync("consent-user", CancellationToken.None);
        await refreshStarted.Task;
        var removing = concurrent.RemoveAsync("consent-user");
        Check(!removing.IsCompleted, "account mutation waits for in-flight credential persistence");
        releaseRefresh.SetResult(); await refreshing; await removing;
        Check(concurrent.Accounts.Count == 0 && consentStore.State.Accounts.Count == 0, "refresh must not resurrect a removed account");
        Console.WriteLine("PASS Google optional login: PKCE/state, account fallback, private pagination/export/transfer, token refresh/rotation, sign out, no credentials in queue");
    }
    internal sealed class MemoryGoogleStore : IGoogleSessionStore
    {
        public GoogleSessions State = new();
        public GoogleSessions Load() => State;
        public void Save(GoogleSessions sessions) => State = sessions;
    }
    private sealed class GoogleFixture(Func<HttpRequestMessage, HttpResponseMessage> handler) : HttpMessageHandler
    {
        protected override Task<HttpResponseMessage> SendAsync(HttpRequestMessage request, CancellationToken cancellationToken) => Task.FromResult(handler(request));
    }
    private sealed class AsyncGoogleFixture(Func<Task<HttpResponseMessage>> handler) : HttpMessageHandler
    {
        protected override Task<HttpResponseMessage> SendAsync(HttpRequestMessage request, CancellationToken cancellationToken) => handler();
    }
}
