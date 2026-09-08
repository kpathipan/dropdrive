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
            "Choose where to save your downloads. A source folder with the same name will use this folder directly.",
            "เลือกที่บันทึกไฟล์ หากโฟลเดอร์ต้นทางชื่อเดียวกับแฟ้มนี้ จะบันทึกลงในแฟ้มนี้โดยไม่สร้างซ้ำ"
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
