using System.Diagnostics;
using System.Net;
using System.Net.Sockets;
using System.Security.Cryptography;
using System.Text;
using System.Text.Json;

namespace DropDrive.Windows.Services;

public sealed record GoogleAccountInfo(string Id, string Email, string Name, bool IsDefault, bool NeedsReconnect);
public sealed class GoogleSession
{
    public string Id { get; set; } = "";
    public string Email { get; set; } = "";
    public string Name { get; set; } = "";
    public string AccessToken { get; set; } = "";
    public string RefreshToken { get; set; } = "";
    public DateTimeOffset ExpiresAt { get; set; }
    public bool NeedsReconnect { get; set; }
}
public sealed class GoogleSessions
{
    public string? DefaultId { get; set; }
    public List<GoogleSession> Accounts { get; set; } = [];
}
public interface IGoogleSessionStore { GoogleSessions Load(); void Save(GoogleSessions sessions); }

// Stable user-bound Windows protection: no credentials in settings/history,
// no passwords, and no signing-key or application-version dependency.
public sealed class WindowsGoogleSessionStore : IGoogleSessionStore
{
    private readonly string _path;
    public WindowsGoogleSessionStore(string? folder = null) => _path = Path.Combine(folder ?? Path.Combine(Environment.GetFolderPath(Environment.SpecialFolder.LocalApplicationData), "DropDrive"), "google-accounts.v1.bin");
    public GoogleSessions Load()
    {
        if (!OperatingSystem.IsWindows() || !File.Exists(_path)) return new();
        var plain = ProtectedData.Unprotect(File.ReadAllBytes(_path), null, DataProtectionScope.CurrentUser);
        try { return JsonSerializer.Deserialize<GoogleSessions>(plain) ?? new(); }
        finally { CryptographicOperations.ZeroMemory(plain); }
    }
    public void Save(GoogleSessions sessions)
    {
        if (!OperatingSystem.IsWindows()) throw new PlatformNotSupportedException();
        var plain = JsonSerializer.SerializeToUtf8Bytes(sessions);
        try
        {
            var encrypted = ProtectedData.Protect(plain, null, DataProtectionScope.CurrentUser);
            Directory.CreateDirectory(Path.GetDirectoryName(_path)!);
            File.WriteAllBytes(_path + ".tmp", encrypted);
            File.Move(_path + ".tmp", _path, true);
        }
        finally { CryptographicOperations.ZeroMemory(plain); }
    }
}
public sealed record GoogleOAuthClient(string ClientId, string ClientSecret)
{
    public static GoogleOAuthClient? Bundled()
    {
        var assembly = typeof(GoogleOAuthClient).Assembly;
        using var stream = assembly.GetManifestResourceStream("DropDrive.Windows.oauth-client.json");
        if (stream == null) return null;
        using var document = JsonDocument.Parse(stream);
        if (!document.RootElement.TryGetProperty("installed", out var client)) return null;
        var id = client.GetProperty("client_id").GetString(); var secret = client.GetProperty("client_secret").GetString();
        return id?.EndsWith(".apps.googleusercontent.com", StringComparison.Ordinal) == true && !string.IsNullOrWhiteSpace(secret) ? new(id, secret) : null;
    }
}

public sealed class GoogleAccountService
{
    public const string DriveScope = "https://www.googleapis.com/auth/drive.readonly";
    private readonly IGoogleSessionStore _store;
    private readonly HttpClient _client;
    private readonly GoogleOAuthClient? _oauth;
    private readonly SemaphoreSlim _gate = new(1);
    private GoogleSessions _sessions;
    public bool IsConfigured => _oauth != null;
    public string? RestoreError { get; }
    public IReadOnlyList<GoogleAccountInfo> Accounts => _sessions.Accounts.OrderByDescending(a => a.Id == _sessions.DefaultId)
        .Select(a => new GoogleAccountInfo(a.Id, a.Email, a.Name, a.Id == _sessions.DefaultId, a.NeedsReconnect)).ToArray();
    public GoogleAccountService(IGoogleSessionStore? store = null, GoogleOAuthClient? oauth = null, HttpClient? client = null)
    {
        _store = store ?? new WindowsGoogleSessionStore(); _oauth = oauth ?? GoogleOAuthClient.Bundled();
        _client = client ?? new HttpClient { Timeout = TimeSpan.FromSeconds(20) };
        try { _sessions = _store.Load(); }
        catch (Exception error) when (error is CryptographicException or IOException or JsonException or UnauthorizedAccessException)
        { _sessions = new(); RestoreError = "อ่านบัญชีที่บันทึกไว้ไม่ได้ ไฟล์เดิมยังอยู่ กรุณาล็อกอินใหม่"; }
    }
    public static string Base64Url(byte[] value) => Convert.ToBase64String(value).TrimEnd('=').Replace('+', '-').Replace('/', '_');
    public static string Challenge(string verifier) => Base64Url(SHA256.HashData(Encoding.ASCII.GetBytes(verifier)));
    public static string AuthorizationUrl(GoogleOAuthClient client, string redirect, string state, string verifier) =>
        "https://accounts.google.com/o/oauth2/v2/auth?" + Query(new Dictionary<string, string> {
            ["client_id"] = client.ClientId, ["redirect_uri"] = redirect, ["response_type"] = "code",
            ["scope"] = "openid email profile " + DriveScope, ["state"] = state,
            ["code_challenge"] = Challenge(verifier), ["code_challenge_method"] = "S256",
            ["access_type"] = "offline", ["prompt"] = "consent select_account", ["include_granted_scopes"] = "true" });
    private static string Query(Dictionary<string, string> values) => string.Join('&', values.Select(p => Uri.EscapeDataString(p.Key) + "=" + Uri.EscapeDataString(p.Value)));

    public async Task SignInAsync(CancellationToken token, Action<string>? launchBrowser = null)
    {
        var oauth = _oauth ?? throw new InvalidOperationException("รุ่นนี้ยังไม่ได้ตั้งค่า Google OAuth สำหรับ Windows");
        using var deadline = CancellationTokenSource.CreateLinkedTokenSource(token); deadline.CancelAfter(TimeSpan.FromMinutes(3));
        using var listener = new TcpListener(IPAddress.Loopback, 0); listener.Start();
        var redirect = $"http://127.0.0.1:{((IPEndPoint)listener.LocalEndpoint).Port}/";
        var state = Base64Url(RandomNumberGenerator.GetBytes(32)); var verifier = Base64Url(RandomNumberGenerator.GetBytes(64));
        var authorizationUrl = AuthorizationUrl(oauth, redirect, state, verifier);
        if (launchBrowser != null) launchBrowser(authorizationUrl);
        else Process.Start(new ProcessStartInfo(authorizationUrl) { UseShellExecute = true });
        while (true)
        {
            using var socket = await listener.AcceptTcpClientAsync(deadline.Token);
            await using var stream = socket.GetStream();
            using var requestDeadline = CancellationTokenSource.CreateLinkedTokenSource(deadline.Token); requestDeadline.CancelAfter(TimeSpan.FromSeconds(5));
            var line = new List<byte>(); var one = new byte[1];
            try
            {
                while (line.Count < 8192 && await stream.ReadAsync(one, requestDeadline.Token) == 1 && one[0] != '\n') line.Add(one[0]);
            }
            catch (OperationCanceledException) when (!deadline.IsCancellationRequested) { continue; }
            catch (IOException) { continue; }
            var request = Encoding.ASCII.GetString(line.ToArray()).Split(' ');
            var fields = request.Length >= 2 && request[0] == "GET" ? ParseCallback(request[1], state) : null;
            var body = fields == null ? "Invalid callback. Return to DropDrive." : "You can close this tab and return to DropDrive.";
            var bytes = Encoding.UTF8.GetBytes(body);
            await stream.WriteAsync(Encoding.ASCII.GetBytes($"HTTP/1.1 {(fields == null ? "400 Bad Request" : "200 OK")}\r\nContent-Type: text/plain; charset=utf-8\r\nCache-Control: no-store\r\nContent-Security-Policy: default-src 'none'\r\nContent-Length: {bytes.Length}\r\nConnection: close\r\n\r\n"), deadline.Token);
            await stream.WriteAsync(bytes, deadline.Token);
            if (fields == null) continue;
            if (fields.ContainsKey("error")) throw new InvalidOperationException("ยังไม่ได้อนุญาตบัญชี Google สามารถใช้งานไฟล์สาธารณะต่อได้");
            if (!fields.TryGetValue("code", out var code)) continue;
            await ExchangeCodeAsync(code, redirect, verifier, deadline.Token); return;
        }
    }
    public static Dictionary<string, string>? ParseCallback(string target, string expectedState)
    {
        if (!target.StartsWith("/?", StringComparison.Ordinal) || target.Length > 8192) return null;
        var pairs = target[2..].Split('&').Select(p => p.Split('=', 2)).Where(p => p.Length == 2).ToArray();
        if (pairs.GroupBy(p => p[0]).Any(g => g.Count() != 1)) return null;
        var values = pairs.ToDictionary(p => p[0], p => Uri.UnescapeDataString(p[1].Replace('+', ' ')));
        return values.TryGetValue("state", out var actual) && CryptographicOperations.FixedTimeEquals(Encoding.UTF8.GetBytes(actual), Encoding.UTF8.GetBytes(expectedState)) ? values : null;
    }
    public async Task ExchangeCodeAsync(string code, string redirect, string verifier, CancellationToken token)
    {
        await _gate.WaitAsync(token);
        try
        {
            var oauth = _oauth ?? throw new InvalidOperationException("Missing Windows OAuth client");
            using var response = await _client.PostAsync("https://oauth2.googleapis.com/token", new FormUrlEncodedContent(new Dictionary<string, string> {
                ["client_id"] = oauth.ClientId, ["client_secret"] = oauth.ClientSecret, ["code"] = code,
                ["redirect_uri"] = redirect, ["code_verifier"] = verifier, ["grant_type"] = "authorization_code" }), token);
            if (!response.IsSuccessStatusCode) throw new InvalidOperationException("เชื่อมต่อ Google ไม่สำเร็จ กรุณาล็อกอินใหม่");
            using var document = JsonDocument.Parse(await response.Content.ReadAsStringAsync(token)); var data = document.RootElement;
            if (!data.TryGetProperty("scope", out var scope) || !(scope.GetString() ?? "").Split(' ').Contains(DriveScope))
                throw new InvalidOperationException("ต้องอนุญาตให้อ่านไฟล์ Google Drive จึงจะดาวน์โหลดไฟล์ส่วนตัวได้");
            var access = data.GetProperty("access_token").GetString()!;
            using var request = new HttpRequestMessage(HttpMethod.Get, "https://www.googleapis.com/oauth2/v3/userinfo");
            request.Headers.Authorization = new("Bearer", access);
            using var profileResponse = await _client.SendAsync(request, token); profileResponse.EnsureSuccessStatusCode();
            using var profileDoc = JsonDocument.Parse(await profileResponse.Content.ReadAsStringAsync(token)); var profile = profileDoc.RootElement;
            var id = profile.GetProperty("sub").GetString() ?? throw new InvalidOperationException("Google account identity missing");
            var old = _sessions.Accounts.FirstOrDefault(a => a.Id == id);
            var session = new GoogleSession { Id = id, Email = profile.GetProperty("email").GetString() ?? "", Name = profile.TryGetProperty("name", out var name) ? name.GetString() ?? "" : "",
                AccessToken = access, RefreshToken = data.TryGetProperty("refresh_token", out var refresh) ? refresh.GetString() ?? "" : old?.RefreshToken ?? "",
                ExpiresAt = DateTimeOffset.UtcNow.AddSeconds(data.GetProperty("expires_in").GetInt32()) };
            if (session.RefreshToken.Length == 0) throw new InvalidOperationException("Google ไม่ส่งสิทธิ์ใช้งานต่อเนื่อง กรุณาเชื่อมต่อใหม่");
            var next = new GoogleSessions { DefaultId = _sessions.DefaultId ?? id, Accounts = _sessions.Accounts.Where(a => a.Id != id).Append(session).ToList() };
            _store.Save(next); _sessions = next;
        }
        finally { _gate.Release(); }
    }
    public async Task<string> AccessTokenAsync(string id, CancellationToken token)
    {
        await _gate.WaitAsync(token);
        try
        {
            var session = _sessions.Accounts.FirstOrDefault(a => a.Id == id) ?? throw new InvalidOperationException("บัญชีถูกนำออกแล้ว กรุณาเชื่อมต่อใหม่");
            if (session.ExpiresAt > DateTimeOffset.UtcNow.AddMinutes(1) && !session.NeedsReconnect) return session.AccessToken;
            var oauth = _oauth ?? throw new InvalidOperationException("Missing Windows OAuth client");
            using var response = await _client.PostAsync("https://oauth2.googleapis.com/token", new FormUrlEncodedContent(new Dictionary<string, string> {
                ["client_id"] = oauth.ClientId, ["client_secret"] = oauth.ClientSecret, ["refresh_token"] = session.RefreshToken, ["grant_type"] = "refresh_token" }), token);
            if (response.StatusCode is HttpStatusCode.BadRequest or HttpStatusCode.Unauthorized)
            { session.NeedsReconnect = true; _store.Save(_sessions); throw new InvalidOperationException("บัญชี Google ต้องเชื่อมต่อใหม่"); }
            response.EnsureSuccessStatusCode();
            using var document = JsonDocument.Parse(await response.Content.ReadAsStringAsync(token)); var data = document.RootElement;
            session.AccessToken = data.GetProperty("access_token").GetString()!;
            if (data.TryGetProperty("refresh_token", out var refresh)) session.RefreshToken = refresh.GetString()!;
            session.ExpiresAt = DateTimeOffset.UtcNow.AddSeconds(data.GetProperty("expires_in").GetInt32()); session.NeedsReconnect = false;
            _store.Save(_sessions); return session.AccessToken;
        }
        finally { _gate.Release(); }
    }
    public async Task RemoveAsync(string id, CancellationToken token = default)
    {
        await _gate.WaitAsync(token);
        try
        {
            var next = new GoogleSessions { Accounts = _sessions.Accounts.Where(a => a.Id != id).ToList() };
            next.DefaultId = _sessions.DefaultId == id ? next.Accounts.FirstOrDefault()?.Id : _sessions.DefaultId;
            _store.Save(next); _sessions = next;
        }
        finally { _gate.Release(); }
    }
    public async Task SetDefaultAsync(string id, CancellationToken token = default)
    {
        await _gate.WaitAsync(token);
        try
        {
            if (!_sessions.Accounts.Any(a => a.Id == id)) return;
            var next = new GoogleSessions { DefaultId = id, Accounts = _sessions.Accounts.ToList() };
            _store.Save(next); _sessions = next;
        }
        finally { _gate.Release(); }
    }
}
