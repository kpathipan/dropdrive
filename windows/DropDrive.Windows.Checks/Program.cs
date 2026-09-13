using DropDrive.Windows.Services;

static void Expect(bool condition, string message)
{
    if (!condition) throw new InvalidOperationException(message);
}

var links = LinkInputParser.Parse("https://youtu.be/a\nhttps://example.com/file.zip  https://youtu.be/a");
Expect(links.Count == 2, "valid links should be parsed and duplicates removed");
Expect(LinkInputParser.Parse("ftp://example.com/file").Count == 0, "non-web schemes must be rejected");
Expect(LinkInputParser.Parse("not a link").Count == 0, "invalid text must be rejected");
Console.WriteLine("PASS link parsing and duplicate protection");
