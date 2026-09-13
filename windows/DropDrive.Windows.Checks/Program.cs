using DropDrive.Windows.Services;
using DropDrive.Windows.Models;

static void Expect(bool condition, string message)
{
    if (!condition) throw new InvalidOperationException(message);
}

var links = LinkInputParser.Parse("https://youtu.be/a\nhttps://example.com/file.zip  https://youtu.be/a");
Expect(links.Count == 2, "valid links should be parsed and duplicates removed");
Expect(LinkInputParser.Parse("ftp://example.com/file").Count == 0, "non-web schemes must be rejected");
Expect(LinkInputParser.Parse("not a link").Count == 0, "invalid text must be rejected");
var settings = new AppSettings { CheckUpdatesAutomatically = true };
var now = DateTimeOffset.UtcNow;
Expect(settings.IsAutomaticUpdateCheckDue(now), "first automatic update check must be due");
settings.LastAutomaticUpdateCheckUtc = now.AddHours(-23).AddMinutes(-59);
Expect(!settings.IsAutomaticUpdateCheckDue(now), "automatic update must not run again before 24 hours");
settings.LastAutomaticUpdateCheckUtc = now.AddHours(-24);
Expect(settings.IsAutomaticUpdateCheckDue(now), "automatic update must become due at 24 hours");
settings.CheckUpdatesAutomatically = false;
Expect(!settings.IsAutomaticUpdateCheckDue(now), "disabled automatic updates must never be due");
var stateFolder = Path.Combine(Path.GetTempPath(), $"dropdrive-check-{Guid.NewGuid():N}");
try
{
    var state = new AppStateService(stateFolder);
    state.SaveSettings(new AppSettings { Destination = "D:\\Media", CheckUpdatesAutomatically = false });
    Expect(state.LoadSettings().Destination == "D:\\Media", "settings must persist across launches");
    state.SaveQueue([new DownloadItem { Url = "https://example.com/a.mp4", Name = "A", Status = "Ready", Destination = "D:\\Media" }]);
    var restored = state.LoadQueue();
    Expect(restored.Count == 1 && restored[0].Destination == "D:\\Media", "queue destination must persist per item");
}
finally { if (Directory.Exists(stateFolder)) Directory.Delete(stateFolder, true); }
Console.WriteLine("PASS link parsing and duplicate protection");
Console.WriteLine("PASS 24-hour automatic update cadence");
Console.WriteLine("PASS settings and queue persistence");
