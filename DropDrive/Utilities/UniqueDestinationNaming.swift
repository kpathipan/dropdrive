import Foundation

/// Prevents accidental overwrites: if a destination path already exists on disk,
/// finds the next available "name (1)", "name (2)"... variant, preserving the
/// original extension.
enum UniqueDestinationNaming {
    static func uniqueURL(for url: URL, fileManager: FileManager = .default) -> URL {
        guard fileManager.fileExists(atPath: url.path) else { return url }

        let directory = url.deletingLastPathComponent()
        let extensionPart = url.pathExtension
        let baseName = extensionPart.isEmpty ? url.lastPathComponent : String(url.lastPathComponent.dropLast(extensionPart.count + 1))

        var attempt = 1
        while true {
            let candidateName = extensionPart.isEmpty ? "\(baseName) (\(attempt))" : "\(baseName) (\(attempt)).\(extensionPart)"
            let candidateURL = directory.appendingPathComponent(candidateName)
            if !fileManager.fileExists(atPath: candidateURL.path) {
                return candidateURL
            }
            attempt += 1
        }
    }
}
