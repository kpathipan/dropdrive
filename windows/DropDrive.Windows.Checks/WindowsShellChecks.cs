using System.Runtime.InteropServices;
using Avalonia;
using Avalonia.Controls;
using Avalonia.Controls.ApplicationLifetimes;
using Avalonia.Threading;
using DropDrive.Windows.Services;
using Microsoft.Win32;

internal static class WindowsShellChecks
{
    public static void Run(string[] args)
    {
        if (!OperatingSystem.IsWindows() || Environment.GetEnvironmentVariable("GITHUB_ACTIONS") != "true")
            throw new InvalidOperationException("Native shell checks run only on disposable Windows CI.");
        AppBuilder.Configure<ShellCheckApp>().UsePlatformDetect().StartWithClassicDesktopLifetime(args);
        if (ShellCheckApp.Failure != null) throw new InvalidOperationException("Windows integration failed", ShellCheckApp.Failure);
    }
}
internal sealed class ShellCheckApp : Application
{
    public static Exception? Failure;
    public override void OnFrameworkInitializationCompleted()
    {
        if (ApplicationLifetime is not IClassicDesktopStyleApplicationLifetime desktop) return;
        var window = new Window { Title = "DropDrive shell regression", Width = 420, Height = 300 };
        desktop.MainWindow = window;
        window.Opened += (_, _) =>
        {
            WindowsIntegration? integration = null;
            try
            {
                var activated = 0; var clicked = 0;
                integration = new WindowsIntegration(window, () => activated++, () => activated++);
                if (!integration.TrayRegistered || !integration.ShortcutRegistered) throw new Exception("Native icon/hotkey registration failed");
                if (!integration.Notify("DropDrive check", "Download complete", false, () => clicked++)) throw new Exception("Notification API rejected the message");
                var handle = window.TryGetPlatformHandle()!.Handle;
                SendMessage(handle, 0x312, 524, 0);
                SendMessage(handle, 0x8000 + 524, 1, 0x405);
                CheckStartupRegistration();
                Dispatcher.UIThread.Post(() =>
                {
                    try { if (activated != 1 || clicked != 1) throw new Exception("Notification/hotkey callbacks did not activate");
                        Console.WriteLine("PASS Windows native tray, notification delivery API/click, global hotkey callback, startup registration"); }
                    catch (Exception error) { Failure = error; }
                    finally { integration.Dispose(); desktop.Shutdown(); }
                });
            }
            catch (Exception error) { Failure = error; integration?.Dispose(); desktop.Shutdown(); }
        };
        base.OnFrameworkInitializationCompleted();
    }
    private static void CheckStartupRegistration()
    {
        if (!OperatingSystem.IsWindows()) return;
        using var key = Registry.CurrentUser.CreateSubKey(@"Software\Microsoft\Windows\CurrentVersion\Run");
        var previous = key.GetValue("DropDrive");
        try
        {
            WindowsIntegration.SetLaunchAtLogin(true);
            if (!WindowsIntegration.IsLaunchAtLoginEnabled()) throw new Exception("Startup registration failed");
            WindowsIntegration.SetLaunchAtLogin(false);
            if (WindowsIntegration.IsLaunchAtLoginEnabled()) throw new Exception("Startup unregister failed");
        }
        finally { if (previous == null) key.DeleteValue("DropDrive", false); else key.SetValue("DropDrive", previous); }
    }
    [DllImport("user32.dll", EntryPoint = "SendMessageW")]
    private static extern nint SendMessage(nint handle, uint message, nuint wParam, nint lParam);
}
