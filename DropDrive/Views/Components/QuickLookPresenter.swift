import AppKit
import Quartz

/// Drives the shared Quick Look panel directly (assigning data source/delegate
/// rather than relying on responder-chain discovery, which the menu-bar popover
/// doesn't participate in). Used for Space-to-preview and the hover eye button.
final class QuickLookPresenter: NSObject, QLPreviewPanelDataSource, QLPreviewPanelDelegate {
    static let shared = QuickLookPresenter()

    private var urls: [URL] = []
    private var index = 0

    func preview(_ url: URL) {
        preview([url], startingAt: 0)
    }

    func preview(_ urls: [URL], startingAt index: Int) {
        // An empty list would clamp the index to 0 and leave the panel indexing
        // into nothing if it ever asked for an item.
        guard !urls.isEmpty else { return }
        self.urls = urls
        self.index = max(0, min(index, urls.count - 1))
        guard let panel = QLPreviewPanel.shared() else { return }
        panel.dataSource = self
        panel.delegate = self
        panel.reloadData()
        panel.currentPreviewItemIndex = self.index
        panel.makeKeyAndOrderFront(nil)
    }

    func numberOfPreviewItems(in panel: QLPreviewPanel!) -> Int { urls.count }

    func previewPanel(_ panel: QLPreviewPanel!, previewItemAt index: Int) -> QLPreviewItem! {
        urls[index] as NSURL
    }
}
