import AppKit
import UniformTypeIdentifiers

/// A near-instant, UI-less hand-off: extracts supported links from whatever was
/// shared, then asks the system to open it via DropDrive's `dropdrive://` URL scheme
/// — no App Group or shared container needed. The 1x1 view exists only because
/// the Share extension point
/// requires a view controller; nothing is ever shown for more than an instant.
final class ShareViewController: NSViewController {
    override func loadView() {
        view = NSView(frame: NSRect(x: 0, y: 0, width: 1, height: 1))
    }

    override func viewDidAppear() {
        super.viewDidAppear()
        Task { await handleShare() }
    }

    private func handleShare() async {
        guard let inputItem = extensionContext?.inputItems.first as? NSExtensionItem,
              let attachments = inputItem.attachments else {
            extensionContext?.cancelRequest(withError: ShareExtensionError.noSupportedLink)
            return
        }

        var links: [String] = []
        for attachment in attachments {
            links.append(contentsOf: await Self.supportedLinks(from: attachment))
        }

        let uniqueLinks = ShareLinkExtractor.links(from: links.joined(separator: "\n"))
        guard !uniqueLinks.isEmpty else {
            extensionContext?.cancelRequest(withError: ShareExtensionError.noSupportedLink)
            return
        }

        await openInDropDrive(uniqueLinks)
    }

    private func openInDropDrive(_ links: [String]) async {
        guard let target = ShareLinkExtractor.deepLink(for: links) else {
            extensionContext?.cancelRequest(withError: ShareExtensionError.noSupportedLink)
            return
        }

        await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
            extensionContext?.open(target) { [weak self] _ in
                // `open`'s completion arrives on the main thread, but the closure
                // is `@Sendable`, so touching the context has to say so.
                MainActor.assumeIsolated {
                    self?.extensionContext?.completeRequest(returningItems: nil)
                }
                continuation.resume()
            }
        }
    }

    private static func supportedLinks(from attachment: NSItemProvider) async -> [String] {
        var links: [String] = []
        if attachment.hasItemConformingToTypeIdentifier(UTType.url.identifier),
           let value = try? await attachment.loadItem(forTypeIdentifier: UTType.url.identifier),
           let url = value as? URL {
            links.append(contentsOf: ShareLinkExtractor.links(from: url.absoluteString))
        }

        if attachment.hasItemConformingToTypeIdentifier(UTType.plainText.identifier),
           let value = try? await attachment.loadItem(forTypeIdentifier: UTType.plainText.identifier),
           let text = value as? String {
            links.append(contentsOf: ShareLinkExtractor.links(from: text))
        }

        return links
    }
}

private enum ShareExtensionError: Error {
    case noSupportedLink
}
