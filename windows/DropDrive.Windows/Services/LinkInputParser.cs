namespace DropDrive.Windows.Services;

public static class LinkInputParser
{
    public static IReadOnlyList<string> ExternalLinks(IEnumerable<string> args) => args
        .Where(arg => Uri.TryCreate(arg, UriKind.Absolute, out var uri) && uri.Scheme == "dropdrive")
        .SelectMany(arg => new Uri(arg).Query.TrimStart('?').Split('&'))
        .Select(pair => pair.Split('=', 2)).Where(pair => pair.Length == 2 && pair[0] == "url")
        .SelectMany(pair => Parse(Uri.UnescapeDataString(pair[1]))).DistinctBy(LinkIdentity.Key).Take(100).ToArray();
    public static IReadOnlyList<string> Parse(string? input) =>
        (input ?? "").Split(['\r', '\n', ' ', '\t'], StringSplitOptions.RemoveEmptyEntries)
            .Where(link => Uri.TryCreate(link, UriKind.Absolute, out var uri) && uri.Scheme is "https" or "http")
            .DistinctBy(LinkIdentity.Key, StringComparer.Ordinal)
            .ToArray();
}
