import AppKit
import Foundation

protocol FolderSelectionServicing {
    func chooseDestinationFolder() async -> URL?
}

@MainActor
struct FolderSelectionService: FolderSelectionServicing {
    func chooseDestinationFolder() async -> URL? {
        let panel = NSOpenPanel()
        panel.title = "Choose Download Folder"
        panel.prompt = "Choose"
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.allowsMultipleSelection = false
        panel.canCreateDirectories = true

        return panel.runModal() == .OK ? panel.url : nil
    }
}
