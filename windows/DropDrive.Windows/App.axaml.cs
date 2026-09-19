using Avalonia;
using Avalonia.Controls;
using Avalonia.Controls.ApplicationLifetimes;
using Avalonia.Markup.Xaml;

namespace DropDrive.Windows;

public partial class App : Application
{
    public static Services.SingleInstance? Instance { get; set; }
    private MainWindow? _window;
    public override void Initialize() => AvaloniaXamlLoader.Load(this);

    public override void OnFrameworkInitializationCompleted()
    {
        if (ApplicationLifetime is IClassicDesktopStyleApplicationLifetime desktop)
        {
            desktop.ShutdownMode = ShutdownMode.OnExplicitShutdown;
            _window = new MainWindow();
            desktop.MainWindow = _window;
            _window.Show();
            if (Instance != null) _ = Instance.ListenAsync(_window.ReceiveActivation);
            if (desktop.Args?.Any(arg => arg.StartsWith("dropdrive:", StringComparison.OrdinalIgnoreCase)) == true)
                Avalonia.Threading.Dispatcher.UIThread.Post(() => _window.ReceiveActivation(desktop.Args));
            if (desktop.Args?.Contains("--background") == true)
                Avalonia.Threading.Dispatcher.UIThread.Post(() => _window.Hide());
        }
        base.OnFrameworkInitializationCompleted();
    }

    private void ShowWindow(object? sender, EventArgs e)
    {
        if (_window is null) return;
        _window.Show();
        _window.WindowState = WindowState.Normal;
        _window.Activate();
    }

    private void QuitApplication(object? sender, EventArgs e)
    {
        _window?.Quit();
    }
}
