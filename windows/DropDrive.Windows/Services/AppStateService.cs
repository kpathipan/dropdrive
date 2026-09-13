using System.Text.Json;
using DropDrive.Windows.Models;

namespace DropDrive.Windows.Services;

public sealed class AppStateService
{
    private static readonly JsonSerializerOptions JsonOptions = new() { WriteIndented = true };
    private readonly string _folder;

    public AppStateService(string? folder = null)
    {
        _folder = folder ?? Path.Combine(
            Environment.GetFolderPath(Environment.SpecialFolder.LocalApplicationData), "DropDrive");
    }

    public AppSettings LoadSettings() => Load("settings.json", new AppSettings());

    public void SaveSettings(AppSettings settings) => Save("settings.json", settings);

    public List<DownloadHistoryEntry> LoadHistory() => Load("history.json", new List<DownloadHistoryEntry>());

    public void AddHistory(DownloadItem item)
    {
        var history = LoadHistory();
        history.Insert(0, new DownloadHistoryEntry {
            Url = item.Url, Name = item.Name, Source = item.Source,
            AudioOnly = item.AudioOnly, Status = item.Status
        });
        if (history.Count > 100) history.RemoveRange(100, history.Count - 100);
        Save("history.json", history);
    }

    public void ClearHistory() => Save("history.json", new List<DownloadHistoryEntry>());

    public List<DownloadItem> LoadQueue() => Load("queue.json", new List<DownloadItem>());

    public void SaveQueue(IEnumerable<DownloadItem> items) => Save("queue.json", items.Take(100).ToList());

    private T Load<T>(string file, T fallback)
    {
        try
        {
            var path = Path.Combine(_folder, file);
            return File.Exists(path)
                ? JsonSerializer.Deserialize<T>(File.ReadAllText(path), JsonOptions) ?? fallback
                : fallback;
        }
        catch { return fallback; }
    }

    private void Save<T>(string file, T value)
    {
        Directory.CreateDirectory(_folder);
        var path = Path.Combine(_folder, file);
        var temporary = path + ".tmp";
        File.WriteAllText(temporary, JsonSerializer.Serialize(value, JsonOptions));
        File.Move(temporary, path, true);
    }
}
