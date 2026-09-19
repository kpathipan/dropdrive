using Avalonia;
using Velopack;

namespace DropDrive.Windows;

internal static class Program
{
    [STAThread]
    public static void Main(string[] args)
    {
        VelopackApp.Build().Run();
        using var instance = new Services.SingleInstance();
        if (!instance.IsOwner) { instance.ActivateExisting(args); return; }
        App.Instance = instance;
        BuildAvaloniaApp().StartWithClassicDesktopLifetime(args);
    }

    public static AppBuilder BuildAvaloniaApp() =>
        AppBuilder.Configure<App>().UsePlatformDetect().LogToTrace();
}
