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

        return panel.runModal() == .OK ? panel.url : nil
    }
}
