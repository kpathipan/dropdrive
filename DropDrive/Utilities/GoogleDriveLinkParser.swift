import Foundation

enum GoogleDriveLinkParser {
    static func folderID(from link: String) -> String? {
        let trimmedLink = link.trimmingCharacters(in: .whitespacesAndNewlines)

        guard let components = URLComponents(string: trimmedLink) else {
            return nil
        }

        if let id = components.queryItems?.first(where: { $0.name == "id" })?.value, !id.isEmpty {
            return id
        }

        let pathComponents = components.path.split(separator: "/").map(String.init)
        guard let folderIndex = pathComponents.firstIndex(of: "folders"),
              pathComponents.indices.contains(folderIndex + 1) else {
            return nil
        }

        let folderID = pathComponents[folderIndex + 1]
        return folderID.isEmpty ? nil : folderID
    }
}
