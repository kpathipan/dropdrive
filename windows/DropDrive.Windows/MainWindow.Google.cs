using Avalonia.Controls;
using Avalonia.Interactivity;
using Avalonia.Layout;
using DropDrive.Windows.Services;

namespace DropDrive.Windows;

public partial class MainWindow
{
    private bool _signingIn;
    private CancellationTokenSource? _signInCancellation;
    private void RefreshGoogleAccounts()
    {
        AccountCount.Text = _googleAccounts.Accounts.Count.ToString();
        AccountCount.IsVisible = _googleAccounts.Accounts.Count > 0;
        ToolTip.SetTip(AccountButton, Locale.Choose("บัญชี Google · ไม่จำเป็นต้องล็อกอิน", "Google accounts · Optional"));
        GoogleAccountList.Children.Clear();
        GooglePublicHint.Text = Locale.Choose("ไม่ล็อกอินก็โหลดไฟล์สาธารณะได้ ล็อกอินเพื่อเพิ่มสิทธิ์เข้าถึงไฟล์ส่วนตัว", "Public files work without signing in. Add accounts to access private files.");
        if (!_googleAccounts.IsConfigured) GooglePublicHint.Text += Locale.Choose(" · รุ่นทดสอบนี้ยังไม่ได้ตั้งค่า OAuth", " · OAuth is not configured in this test build");
        if (_googleAccounts.RestoreError != null && _googleAccounts.Accounts.Count == 0)
            GooglePublicHint.Text += Locale.Choose(" · อ่านบัญชีที่บันทึกไว้ไม่ได้ กรุณาเชื่อมต่อใหม่", " · Saved accounts could not be read. Please reconnect.");
        foreach (var account in _googleAccounts.Accounts)
        {
            var row = new StackPanel { Spacing = 4, Margin = new Avalonia.Thickness(0, 5) };
            row.Children.Add(new TextBlock { Text = account.Email, TextTrimming = Avalonia.Media.TextTrimming.CharacterEllipsis, FontSize = 11 });
            row.Children.Add(new TextBlock { Text = account.NeedsReconnect ? Locale.Choose("ต้องเชื่อมต่อใหม่", "Reconnect required") : account.IsDefault ? Locale.Choose("บัญชีเริ่มต้น", "Default account") : account.Name, FontSize = 10, Opacity = 0.65 });
            var actions = new StackPanel { Orientation = Orientation.Horizontal, Spacing = 8 };
            var primary = new Button { Content = Locale.Choose("ใช้เป็นค่าเริ่มต้น", "Set default"), IsEnabled = !_signingIn && !account.IsDefault };
            primary.Classes.Add("link"); primary.Click += async (_, _) => { try { await _googleAccounts.SetDefaultAsync(account.Id, _lifetime.Token); RefreshGoogleAccounts(); } catch (Exception) { SetStatus("บันทึกบัญชีไม่ได้ กรุณาลองใหม่"); } };
            var remove = new Button { Content = Locale.Choose("นำออกจากแอป", "Remove from app"), IsEnabled = !_signingIn };
            remove.Classes.Add("link"); remove.Click += (_, _) => RemoveGoogleAccount(account.Id);
            actions.Children.Add(primary); actions.Children.Add(remove); row.Children.Add(actions); GoogleAccountList.Children.Add(row);
        }
        GoogleSignInButton.Content = Locale.Choose(_signingIn ? "กำลังเชื่อมต่อ…" : "เพิ่มบัญชี Google", _signingIn ? "Connecting…" : "Add Google account");
        GoogleSignInButton.IsEnabled = !_signingIn && _googleAccounts.IsConfigured;
        GoogleCancelButton.IsVisible = _signingIn;
    }
    private void ShowGoogleAccounts(object? sender, RoutedEventArgs e)
    { ShowPage(SettingsPage); GoogleSection.IsExpanded = true; GoogleSection.BringIntoView(); }
    private async void AddGoogleAccount(object? sender, RoutedEventArgs e)
    {
        if (_signingIn) return;
        _signingIn = true; _signInCancellation = CancellationTokenSource.CreateLinkedTokenSource(_lifetime.Token); RefreshGoogleAccounts();
        try
        {
            await _googleAccounts.SignInAsync(_signInCancellation.Token);
            SetStatus(Locale.Choose("เชื่อมต่อแล้ว กำลังตรวจสิทธิ์ไฟล์ใหม่…", "Connected. Refreshing file access…"));
            // Re-analyze the same failed job; never enqueue it twice or ask the
            // user to sign in a second time to refresh the UI.
            foreach (var item in _downloads.Where(i => i.IsDrive && (i.Status == "Failed" || i == _review)).ToArray())
            {
                try
                {
                    using var timeout = CancellationTokenSource.CreateLinkedTokenSource(_lifetime.Token); timeout.CancelAfter(TimeSpan.FromSeconds(45));
                    RefreshDriveReview(item, await _analysisService.AnalyzeAsync(item.Url, timeout.Token));
                }
                catch (Exception error) when (error is not OutOfMemoryException) { item.Detail = error.Message; }
            }
            SaveQueue(); UpdateQueueSummary();
        }
        catch (OperationCanceledException) { SetStatus(Locale.Choose("ยกเลิกการเชื่อมต่อ ใช้งานไฟล์สาธารณะได้ตามปกติ", "Sign-in cancelled. Public downloads remain available.")); }
        catch (Exception error) when (error is not OutOfMemoryException) { SetStatus(error.Message); }
        finally { _signingIn = false; _signInCancellation.Dispose(); _signInCancellation = null; RefreshGoogleAccounts(); }
    }
    private void CancelGoogleSignIn(object? sender, RoutedEventArgs e) => _signInCancellation?.Cancel();
    public void RefreshDriveReview(Models.DownloadItem item, MediaAnalysis analysis)
    {
        if (item.IsActive || item.Status == "Analyzing" || !_downloads.Contains(item)) return;
        // Keep completed/resumable children when refreshing permissions. Replacing
        // every child here would download successful files again after reconnecting.
        var oldEntries = item.Entries;
        var unselected = oldEntries.Where(e => !e.Selected).Select(CollectionReceipt.EntryKey).ToHashSet();
        foreach (var entry in analysis.Entries ?? [])
        {
            entry.Selected = !unselected.Contains(CollectionReceipt.EntryKey(entry));
            var previous = oldEntries.FirstOrDefault(old => CollectionReceipt.EntryKey(old) == CollectionReceipt.EntryKey(entry)
                && old.Title == entry.Title && old.RelativeFolder == entry.RelativeFolder
                && CollectionReceipt.Version(old) == CollectionReceipt.Version(entry));
            entry.Transfer = previous?.Transfer;
            if (entry.Transfer is { } child)
            {
                child.DriveAccountId = analysis.AccountId;
                child.DriveMimeType = entry.MimeType; child.DriveResourceKey = entry.ResourceKey;
                child.ExpectedMd5 = entry.ExpectedMd5;
            }
        }
        foreach (var old in oldEntries)
            if (old.Transfer is { } transfer && !(analysis.Entries ?? []).Any(e => ReferenceEquals(e.Transfer, transfer)))
            {
                if (transfer.Status != "Complete") transfer.Status = "Paused";
                DownloadService.CleanupPartials(transfer); // Never deletes completed outputs.
            }
        ApplyAnalysis(item, analysis);
        item.Thumbnail = null;
        if (_review == null || _review == item) OpenReview(item);
    }
    private async void RemoveGoogleAccount(string id)
    {
        if (_downloads.Any(i => i.DriveAccountId == id && i.IsActive)) { SetStatus("พักงานที่ใช้บัญชีนี้ก่อนนำบัญชีออก"); return; }
        try { await _googleAccounts.RemoveAsync(id, _lifetime.Token); RefreshGoogleAccounts(); SetStatus(Locale.Choose("นำบัญชีออกจากแอปแล้ว ไฟล์ที่ดาวน์โหลดไม่ถูกลบ", "Account removed. Downloaded files are unchanged.")); }
        catch (Exception error) when (error is not OutOfMemoryException) { SetStatus("นำบัญชีออกไม่ได้ กรุณาลองใหม่"); }
    }
}
