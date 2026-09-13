namespace DropDrive.Windows.Services;

public static class LinkInputParser
{
    public static IReadOnlyList<string> Parse(string? input) =>
        (input ?? "").Split(['\r', '\n', ' ', '\t'], StringSplitOptions.RemoveEmptyEntries)
            .Where(link => Uri.TryCreate(link, UriKind.Absolute, out var uri) && uri.Scheme is "https" or "http")
            .Distinct(StringComparer.OrdinalIgnoreCase)
            .ToArray();
}
