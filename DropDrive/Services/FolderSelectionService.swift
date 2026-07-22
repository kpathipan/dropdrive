import AppKit
import Foundation

protocol FolderSelectionServicing {
    func chooseDestinationFolder() async -> URL?
}

@MainActor
struct FolderSelectionService: FolderSelectionServicing {
    func chooseDestinationFolder() async -> URL? {
        let panel = NSOpenPanel()
        panel.title = "Choose Destination"
        panel.message = "Downloaded files will be saved inside a new folder here."
        panel.prompt = "Choose"
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.allowsMultipleSelection = false
        panel.canCreateDirectories = true

        // The panel stealing focus would otherwise dismiss the popover, so the
        // analysis card the user is mid-way through vanishes as soon as they
        // click "Change…". Pin it for the duration, and bring the app forward
        // so the panel doesn't open behind whatever they were looking at.
        StatusItemController.current?.setPopoverPinned(true)
        defer { StatusItemController.current?.setPopoverPinned(false) }
        NSApp.activate(ignoringOtherApps: true)
        panel.level = .modalPanel

        return panel.runModal() == .OK ? panel.url : nil
    }
}
