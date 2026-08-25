import Foundation

/// Balances security-scope acquisition for the app lifetime. Bookmark restore
/// is called frequently by menus and destination rules; starting the same scope
/// on every redraw without stopping it eventually exhausts the process limit.
nonisolated final class SecurityScopedAccessManager: @unchecked Sendable {
    static let shared = SecurityScopedAccessManager()

    private let lock = NSLock()
    private var active: [String: URL] = [:]

    private init() {}

    func retainAccess(to url: URL) -> Bool {
        let key = url.standardizedFileURL.path
        lock.lock()
        defer { lock.unlock() }
        if active[key] != nil { return true }
        guard url.startAccessingSecurityScopedResource() else { return false }
        active[key] = url
        return true
    }

    deinit {
        lock.lock()
        let urls = Array(active.values)
        active.removeAll()
        lock.unlock()
        urls.forEach { $0.stopAccessingSecurityScopedResource() }
    }
}
