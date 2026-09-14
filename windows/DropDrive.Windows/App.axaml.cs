using Avalonia;
using Avalonia.Controls;
using Avalonia.Controls.ApplicationLifetimes;
using Avalonia.Markup.Xaml;

namespace DropDrive.Windows;

public partial class App : Application
{
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
