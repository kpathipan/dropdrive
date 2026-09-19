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
            AudioOnly = item.AudioOnly, Status = item.Status, ResultPath = item.ResultPath,
            Destination = item.Destination, Quality = item.Quality
            , Bytes = item.ReceivedBytes
        });
        if (history.Count > 100) history.RemoveRange(100, history.Count - 100);
        Save("history.json", history);
    }

    public void ClearHistory() => Save("history.json", new List<DownloadHistoryEntry>());

    public List<DownloadItem> LoadQueue() => Load("queue.json", new List<DownloadItem>());

    public void SaveQueue(IEnumerable<DownloadItem> items) => Save("queue.json", items.Take(100).ToList());

    public Dictionary<string, CollectionReceipt> LoadReceipts() => Load("collections.json", new Dictionary<string, CollectionReceipt>());
    public void SaveReceipts(Dictionary<string, CollectionReceipt> receipts) => Save("collections.json", receipts);

    public LocalStatistics LoadStatistics() => Load("statistics.json", new LocalStatistics());
    public void RecordCompletion(DownloadItem item)
    {
        var stats = LoadStatistics();
        stats.Downloads++;
        stats.Bytes += Math.Max(0, item.ReceivedBytes);
        Save("statistics.json", stats);
        var receipts = LoadReceipts();
        if (item.IsCollection)
        {
            var key = CollectionReceipt.CollectionKey(item.Url);
            var receipt = receipts.GetValueOrDefault(key) ?? new CollectionReceipt();
            foreach (var entry in item.Entries.Where(e => e.Selected))
                receipt.Files[CollectionReceipt.EntryKey(entry)] = CollectionReceipt.Version(entry);
            receipt.UpdatedAt = DateTimeOffset.UtcNow;
            receipt.Files = receipt.Files.TakeLast(10000).ToDictionary(pair => pair.Key, pair => pair.Value);
            receipts[key] = receipt;
            SaveReceipts(receipts.OrderByDescending(pair => pair.Value.UpdatedAt).Take(24).ToDictionary(pair => pair.Key, pair => pair.Value));
        }
    }

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
