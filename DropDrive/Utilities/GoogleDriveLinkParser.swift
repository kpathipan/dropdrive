import Foundation

enum GoogleDriveLinkParser {
    /// Extracts a Drive item ID (file or folder) from a variety of Google Drive link formats:
    /// - .../drive/folders/<id>
    /// - .../file/d/<id>/...
    /// - ...?id=<id>
    static func itemID(from link: String) -> String? {
        let trimmedLink = link.trimmingCharacters(in: .whitespacesAndNewlines)

        guard let components = URLComponents(string: trimmedLink) else {
            return nil
        }

        if let id = components.queryItems?.first(where: { $0.name == "id" })?.value, !id.isEmpty {
            return id
        }

        let pathComponents = components.path.split(separator: "/").map(String.init)

        if let folderIndex = pathComponents.firstIndex(of: "folders"),
           pathComponents.indices.contains(folderIndex + 1) {
            let id = pathComponents[folderIndex + 1]
            return id.isEmpty ? nil : id
        }

        if let fileIndex = pathComponents.firstIndex(of: "d"),
           pathComponents.indices.contains(fileIndex + 1) {
            let id = pathComponents[fileIndex + 1]
            return id.isEmpty ? nil : id
        }

        return nil
    }
}
