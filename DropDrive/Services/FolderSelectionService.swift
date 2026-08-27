import AppKit
import Foundation

protocol FolderSelectionServicing {
    func chooseDestinationFolder() async -> URL?
}

@MainActor
struct FolderSelectionService: FolderSelectionServicing {
    func chooseDestinationFolder() async -> URL? {
        let panel = NSOpenPanel()
        panel.title = tr("Choose Destination", "เลือกโฟลเดอร์ปลายทาง")
        panel.message = tr(
            "Downloaded files will be saved inside a new folder here.",
            "ไฟล์ที่ดาวน์โหลดจะถูกเก็บในโฟลเดอร์ใหม่ที่นี่"
        )
        panel.prompt = tr("Choose", "เลือก")
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.allowsMultipleSelection = false
        panel.canCreateDirectories = true

        // The panel and the menu-bar window otherwise overlap. Temporarily fold
        // DropDrive back into its icon, retaining the same SwiftUI controller so
        // every selected file and field returns when the panel finishes.
        let statusItem = StatusItemController.current
        let shouldRestorePopover = statusItem?.hidePopoverForExternalPanel() ?? false
        defer { statusItem?.restorePopoverAfterExternalPanel(if: shouldRestorePopover) }
        await Task.yield()
        NSApp.activate(ignoringOtherApps: true)
        panel.level = .modalPanel

        return panel.runModal() == .OK ? panel.url : nil
    }
}
