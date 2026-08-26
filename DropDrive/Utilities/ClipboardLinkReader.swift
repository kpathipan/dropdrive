import AppKit

/// Reads only supported links from the system pasteboard. Keeping this in one
/// place makes automatic pickup and the explicit Paste button behave exactly
/// the same, including multi-link extraction and duplicate removal.
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
