using System.Text;

// Package the existing Mac artwork without redrawing, resizing or recoloring it.
// PNG frames in the ICO retain the exact source pixels and alpha channel.
internal static class IconAssetChecks
{
    public static void Run(bool update = false)
    {
        var root = FindRoot();
        var mac = Path.Combine(root, "DropDrive", "Assets.xcassets");
        var assets = Path.Combine(root, "windows", "DropDrive.Windows", "Assets");
        var logo = File.ReadAllBytes(Path.Combine(mac, "AppLogo.imageset", "logo-256.png"));
        (int Size, string File)[] variants = [
            (16, "icon_16x16.png"), (32, "icon_32x32.png"),
            (64, "icon_32x32@2x.png"), (128, "icon_128x128.png"), (256, "icon_256x256.png")];
        var frames = variants.Select(v => (v.Size, Bytes: File.ReadAllBytes(Path.Combine(mac, "AppIcon.appiconset", v.File)))).ToArray();
        Require(frames[^1].Bytes.SequenceEqual(logo), "Mac app icon and header logo must share the same artwork");
        foreach (var frame in frames)
        {
            var png = frame.Bytes;
            Require(png.Length > 24 && png.AsSpan(0, 8).SequenceEqual(new byte[] { 137, 80, 78, 71, 13, 10, 26, 10 }), "valid source PNG");
            Require(System.Buffers.Binary.BinaryPrimitives.ReadInt32BigEndian(png.AsSpan(16, 4)) == frame.Size
                && System.Buffers.Binary.BinaryPrimitives.ReadInt32BigEndian(png.AsSpan(20, 4)) == frame.Size, "source PNG dimensions match ICO entry");
        }
        using var buffer = new MemoryStream();
        using (var writer = new BinaryWriter(buffer, Encoding.UTF8, leaveOpen: true))
        {
            writer.Write((ushort)0); writer.Write((ushort)1); writer.Write((ushort)frames.Length);
            var offset = 6 + 16 * frames.Length;
            foreach (var frame in frames)
            {
                writer.Write((byte)(frame.Size == 256 ? 0 : frame.Size));
                writer.Write((byte)(frame.Size == 256 ? 0 : frame.Size));
                writer.Write((byte)0); writer.Write((byte)0);
                writer.Write((ushort)1); writer.Write((ushort)32);
                writer.Write(frame.Bytes.Length); writer.Write(offset);
                offset += frame.Bytes.Length;
            }
            foreach (var frame in frames) writer.Write(frame.Bytes);
        }
        var ico = buffer.ToArray();
        var pngPath = Path.Combine(assets, "dropdrive.png");
        var icoPath = Path.Combine(assets, "dropdrive.ico");
        if (update)
        {
            File.WriteAllBytes(pngPath, logo);
            File.WriteAllBytes(icoPath, ico);
            Console.WriteLine("Updated Windows PNG and multi-size ICO from the existing Mac artwork.");
        }
        Require(File.ReadAllBytes(pngPath).SequenceEqual(logo), "Windows logo differs from Mac; run checks with --sync-icons");
        Require(File.ReadAllBytes(icoPath).SequenceEqual(ico), "Windows ICO differs from Mac; run checks with --sync-icons");
        if (!update)
        {
            Require(File.ReadAllBytes(Path.Combine(AppContext.BaseDirectory, "Assets", "dropdrive.ico")).SequenceEqual(ico), "output tray ICO must match source");
            using var embedded = Avalonia.Platform.AssetLoader.Open(new Uri("avares://DropDrive/Assets/dropdrive.png"));
            using var embeddedBytes = new MemoryStream(); embedded.CopyTo(embeddedBytes);
            Require(embeddedBytes.ToArray().SequenceEqual(logo), "embedded window/header/tray PNG must match Mac");
            using var iconStream = new MemoryStream(ico);
            _ = new Avalonia.Controls.WindowIcon(iconStream);
        }
        Console.WriteLine("PASS Mac/Windows logo parity: exact PNG and 16/32/64/128/256px ICO frames.");
    }

    private static string FindRoot()
    {
        foreach (var start in new[] { Directory.GetCurrentDirectory(), AppContext.BaseDirectory })
            for (var folder = new DirectoryInfo(start); folder != null; folder = folder.Parent)
                if (File.Exists(Path.Combine(folder.FullName, "DropDrive", "Assets.xcassets", "AppLogo.imageset", "logo-256.png"))) return folder.FullName;
        throw new DirectoryNotFoundException("Run icon checks from the DropDrive repository.");
    }
    private static void Require(bool condition, string message)
    {
        if (!condition) throw new InvalidOperationException(message);
    }
}
