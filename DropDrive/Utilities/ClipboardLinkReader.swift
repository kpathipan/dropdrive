import AppKit

/// Reads only supported links from the system pasteboard for the explicit Paste
/// control, including multi-link extraction and duplicate removal. Merely
/// opening DropDrive never imports these links into the form.
@MainActor
enum ClipboardLinkReader {
    static func links(from pasteboard: NSPasteboard = .general) -> [String] {
        let raw = [
            pasteboard.string(forType: .string),
            pasteboard.string(forType: .URL)
        ]
        .compactMap { $0 }
        .joined(separator: "\n")

        return SupportedLinkExtractor.links(from: raw)
    }
}
