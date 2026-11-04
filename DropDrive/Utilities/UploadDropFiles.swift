import AppKit
import Foundation

@MainActor enum UploadDropFiles {
    static func files(from pasteboard: NSPasteboard) -> [URL] {
        let urls = (pasteboard.readObjects(forClasses: [NSURL.self], options: [.urlReadingFileURLsOnly: true]) as? [NSURL]) ?? []
        return urls.map { $0 as URL }.filter { url in
            guard url.isFileURL, url.pathExtension.lowercased() != "webloc" else { return false }
            let values = try? url.resourceValues(forKeys: [.isRegularFileKey, .isSymbolicLinkKey])
            return values?.isRegularFile == true && values?.isSymbolicLink != true
        }
    }
}
