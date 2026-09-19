using System.Runtime.InteropServices;
using Avalonia.Controls;
using Avalonia.Threading;
using Microsoft.Win32;

namespace DropDrive.Windows.Services;

// One native notification-area icon, bound to the existing app window. No
// background helper app, scheduled task, elevation or second installation.
public sealed class WindowsIntegration : IDisposable
{
    private readonly nint _window;
    private readonly nint _icon;
    private readonly SubclassProc _callback;
    private readonly Action _show;
    private readonly Action _context;
    private Action? _notificationClick;
    private readonly uint _taskbarCreated;
    private bool _disposed;
    public bool ShortcutRegistered { get; }
    public bool TrayRegistered { get; private set; }
    public WindowsIntegration(Window window, Action show, Action context)
    {
        if (!OperatingSystem.IsWindows()) throw new PlatformNotSupportedException();
        _show = show; _context = context;
        _window = window.TryGetPlatformHandle()?.Handle ?? throw new InvalidOperationException("No window handle");
        _callback = Dispatch;
        if (!SetWindowSubclass(_window, _callback, 524, 0)) throw new InvalidOperationException("Cannot attach Windows integration");
        _icon = LoadImage(0, Path.Combine(AppContext.BaseDirectory, "Assets", "dropdrive.ico"), 1, 32, 32, 0x10);
        _taskbarCreated = RegisterWindowMessage("TaskbarCreated");
        AddTray();
        ShortcutRegistered = RegisterHotKey(_window, 524, 0x4000 | 2 | 4, 0x44); // Ctrl+Shift+D; no auto-repeat
    }
    private IconData Data(uint flags) => new() { Size = (uint)Marshal.SizeOf<IconData>(), Window = _window,
        Id = 1, Flags = flags, Message = 0x8000 + 524, Icon = _icon, Tip = "DropDrive", Info = "", Title = "" };
    private void AddTray() { var data = Data(1 | 2 | 4); TrayRegistered = ShellNotifyIcon(0, ref data); }
    public bool Notify(string title, string message, bool sound, Action clicked)
    {
        if (_disposed || !TrayRegistered) return false;
        _notificationClick = clicked;
        var data = Data(0x10);
        data.Title = title.Length > 63 ? title[..63] : title;
        data.Info = message.Length > 255 ? message[..255] : message;
        data.InfoFlags = 1u | (sound ? 0u : 0x10u);
        return ShellNotifyIcon(1, ref data);
    }
    private nint Dispatch(nint hwnd, uint message, nuint wParam, nint lParam, nuint id, nuint data)
    {
        if (message == _taskbarCreated) AddTray();
        if (message == 0x312 && wParam == 524) Dispatcher.UIThread.Post(_show);
        if (message == 0x8000 + 524)
        {
            if ((long)lParam == 0x405) Dispatcher.UIThread.Post(_notificationClick ?? _show);
            else if ((long)lParam is 0x202 or 0x203) Dispatcher.UIThread.Post(_show);
            else if ((long)lParam == 0x205) Dispatcher.UIThread.Post(_context);
        }
        return DefSubclassProc(hwnd, message, wParam, lParam);
    }
    public static bool IsLaunchAtLoginEnabled()
    {
        if (!OperatingSystem.IsWindows()) return false;
        using var key = Registry.CurrentUser.OpenSubKey(@"Software\Microsoft\Windows\CurrentVersion\Run");
        return key?.GetValue("DropDrive") is string value && value == StartupCommand();
    }
    public static string StartupCommand() => $"\"{Environment.ProcessPath}\" --background";
    public static void KeepAwake(bool active)
    {
        if (OperatingSystem.IsWindows()) SetThreadExecutionState(active ? 0x80000001u : 0x80000000u);
    }
    public static void SetLaunchAtLogin(bool enabled)
    {
        if (!OperatingSystem.IsWindows()) return;
        using var key = Registry.CurrentUser.CreateSubKey(@"Software\Microsoft\Windows\CurrentVersion\Run");
        if (enabled) key.SetValue("DropDrive", StartupCommand());
        else key.DeleteValue("DropDrive", false);
    }
    public static void RegisterProtocol()
    {
        if (!OperatingSystem.IsWindows()) return;
        using var key = Registry.CurrentUser.CreateSubKey(@"Software\Classes\dropdrive");
        key.SetValue("", "URL:DropDrive"); key.SetValue("URL Protocol", "");
        using var command = key.CreateSubKey(@"shell\open\command");
        command.SetValue("", $"\"{Environment.ProcessPath}\" \"%1\"");
    }
    public void Dispose()
    {
        if (_disposed) return; _disposed = true;
        var data = Data(0); ShellNotifyIcon(2, ref data);
        UnregisterHotKey(_window, 524); RemoveWindowSubclass(_window, _callback, 524);
        if (_icon != 0) DestroyIcon(_icon);
    }
    [StructLayout(LayoutKind.Sequential, CharSet = CharSet.Unicode)]
    private struct IconData
    {
        public uint Size; public nint Window; public uint Id, Flags, Message; public nint Icon;
        [MarshalAs(UnmanagedType.ByValTStr, SizeConst = 128)] public string Tip;
        public uint State, StateMask;
        [MarshalAs(UnmanagedType.ByValTStr, SizeConst = 256)] public string Info;
        public uint Timeout;
        [MarshalAs(UnmanagedType.ByValTStr, SizeConst = 64)] public string Title;
        public uint InfoFlags; public Guid Guid; public nint BalloonIcon;
    }
    [UnmanagedFunctionPointer(CallingConvention.Winapi)]
    private delegate nint SubclassProc(nint window, uint message, nuint wParam, nint lParam, nuint id, nuint data);
    [DllImport("comctl32.dll")] private static extern bool SetWindowSubclass(nint hwnd, SubclassProc callback, nuint id, nuint data);
    [DllImport("comctl32.dll")] private static extern bool RemoveWindowSubclass(nint hwnd, SubclassProc callback, nuint id);
    [DllImport("comctl32.dll")] private static extern nint DefSubclassProc(nint hwnd, uint msg, nuint wParam, nint lParam);
    [DllImport("shell32.dll", EntryPoint = "Shell_NotifyIconW", CharSet = CharSet.Unicode)] private static extern bool ShellNotifyIcon(uint message, ref IconData data);
    [DllImport("user32.dll", EntryPoint = "LoadImageW", CharSet = CharSet.Unicode)] private static extern nint LoadImage(nint instance, string name, uint type, int x, int y, uint flags);
    [DllImport("user32.dll")] private static extern bool DestroyIcon(nint icon);
    [DllImport("user32.dll")] private static extern bool RegisterHotKey(nint hwnd, int id, uint modifiers, uint key);
    [DllImport("user32.dll")] private static extern bool UnregisterHotKey(nint hwnd, int id);
    [DllImport("kernel32.dll")] private static extern uint SetThreadExecutionState(uint flags);
    [DllImport("user32.dll", EntryPoint = "RegisterWindowMessageW", CharSet = CharSet.Unicode)] private static extern uint RegisterWindowMessage(string message);
}
