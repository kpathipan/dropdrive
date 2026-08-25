import AppKit
import UniformTypeIdentifiers

/// A near-instant, UI-less hand-off: extracts a supported link from whatever was
/// shared, then asks the system to open it via DropDrive's `dropdrive://` URL scheme
/// — no App Group or shared container needed, the same mechanism the browser
/// extension uses. The 1x1 view exists only because the Share extension point
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

        for attachment in attachments {
            if let link = await Self.supportedLink(from: attachment) {
                await openInDropDrive(link)
                return
            }
        }

        extensionContext?.cancelRequest(withError: ShareExtensionError.noSupportedLink)
    }

    private func openInDropDrive(_ link: String) async {
        // NOT `.urlQueryAllowed`: that set permits `&`, `=` and `?`, which are
        // exactly the characters that have to be escaped to survive being a
        // query *value*. A Drive link carrying `&resourcekey=…` was split into
        // separate query items by the app's own URLComponents parse, and only
        // the part before the first `&` was kept — so the resource key was
        // dropped and Drive answered 404 for a link that works.
        let unreserved = CharacterSet(charactersIn: "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789-._~")
        let encoded = link.addingPercentEncoding(withAllowedCharacters: unreserved) ?? link
        guard let target = URL(string: "dropdrive://download?url=\(encoded)") else {
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

    private static func supportedLink(from attachment: NSItemProvider) async -> String? {
        if attachment.hasItemConformingToTypeIdentifier(UTType.url.identifier),
           let value = try? await attachment.loadItem(forTypeIdentifier: UTType.url.identifier),
           let url = value as? URL, looksLikeSupportedLink(url.absoluteString) {
            return url.absoluteString
        }

        if attachment.hasItemConformingToTypeIdentifier(UTType.plainText.identifier),
           let value = try? await attachment.loadItem(forTypeIdentifier: UTType.plainText.identifier),
           let text = value as? String, looksLikeSupportedLink(text) {
            return text
        }

        return nil
    }

    /// A light-weight check, deliberately not a full re-implementation of the main
    /// app's link parser (which lives in a different target) — the real parsing and
    /// validation happens once DropDrive itself receives the link.
    private static func looksLikeSupportedLink(_ text: String) -> Bool {
        guard let components = URLComponents(string: text.trimmingCharacters(in: .whitespacesAndNewlines)),
              let host = components.host?.lowercased() else {
            return false
        }
        let supportedHosts = [
            "drive.google.com", "docs.google.com", "youtube.com", "youtu.be",
            "tiktok.com", "instagram.com", "instagr.am", "facebook.com", "fb.watch"
        ]
        return supportedHosts.contains { host == $0 || host.hasSuffix(".\($0)") }
    }
}

private enum ShareExtensionError: Error {
    case noSupportedLink
}
