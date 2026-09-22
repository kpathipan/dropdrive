using Avalonia;
using Avalonia.Controls;
using DropDrive.Windows.Models;

namespace DropDrive.Windows;

public partial class MainWindow
{
    private readonly HashSet<MediaEntry> _thumbnailRequests = [];
    private readonly HashSet<MediaEntry> _visibleEntries = [];
    private readonly HashSet<MediaEntry> _thumbnailAttempts = [];
    private void FileViewportChanged(object? sender, ScrollChangedEventArgs args) => RefreshVisibleThumbnails();

    private void ClearEntryThumbnails()
    {
        PreviewImage.Source = null;
        _previewEntry = null;
        _visibleEntries.Clear(); _thumbnailAttempts.Clear();
        if (_review == null) return;
        foreach (var entry in _review.Entries)
        { var old = entry.Thumbnail; entry.Thumbnail = null; entry.RefreshThumbnail(); old?.Dispose(); }
    }

    private void RefreshVisibleThumbnails()
    {
        if (_review == null || FileViewport == null || FileCards == null || !FileSelector.IsExpanded) return;
        _visibleEntries.Clear();
        foreach (var check in FileCards.Children.OfType<CheckBox>())
        {
            if (check.DataContext is not MediaEntry entry || entry.Kind is not ("video" or "image")) continue;
            var location = check.TranslatePoint(default, FileViewport);
            if (location is { } p && new Rect(p, check.Bounds.Size).Intersects(new Rect(FileViewport.Viewport)))
                _visibleEntries.Add(entry);
        }
        foreach (var entry in _review.Entries)
        {
            if (_visibleEntries.Contains(entry))
            {
                if (entry.Thumbnail == null && !_thumbnailRequests.Contains(entry) && _thumbnailAttempts.Add(entry))
                    _ = LoadVisibleThumbnailAsync(entry, _review);
            }
            else if (entry != _previewEntry)
            {
                var old = entry.Thumbnail; entry.Thumbnail = null; entry.RefreshThumbnail(); old?.Dispose();
                _thumbnailAttempts.Remove(entry);
            }
        }
    }

    private async Task LoadVisibleThumbnailAsync(MediaEntry entry, DownloadItem review)
    {
        _thumbnailRequests.Add(entry);
        try
        {
            var bitmap = await _thumbnails.GetAsync(entry.ThumbnailUrl, _lifetime.Token, review.DriveAccountId);
            if (_lifetime.IsCancellationRequested || _review != review || (!_visibleEntries.Contains(entry) && entry != _previewEntry))
            { bitmap?.Dispose(); return; }
            if (entry.Thumbnail != null) { bitmap?.Dispose(); return; }
            entry.Thumbnail = bitmap; entry.RefreshThumbnail();
            if (_previewEntry == entry) PreviewImage.Source = bitmap;
        }
        finally { _thumbnailRequests.Remove(entry); }
    }
}
