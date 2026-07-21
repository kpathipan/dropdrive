import Foundation
import Observation

/// Answers "is this still on disk, and is it a folder?" without touching the
/// filesystem during a view update.
///
/// The Recent gallery asks that question for every tile, and a SwiftUI body can
/// re-run many times a second — each one previously meant a synchronous
/// `fileExists` (plus a `resourceValues`) on the main thread. Lookups here are
/// dictionary reads; a miss schedules the real check off the main actor and the
/// `@Observable` update re-renders the tiles that were waiting.
@MainActor
@Observable
final class FileStatusCache {
    static let shared = FileStatusCache()

    struct Status {
        let exists: Bool
        let isDirectory: Bool
    }

    private var cache: [String: Status] = [:]
    private var pending: Set<String> = []

    private init() {}

    /// The cached status, or nil while the first check is still in flight.
    /// Callers treat nil as "not known yet" and render optimistically.
    func status(for url: URL) -> Status? {
        let key = url.path
        if let cached = cache[key] { return cached }
        schedule(url)
        return nil
    }

    /// Forgets everything, so tiles re-check after files may have moved (a
    /// download completing, history being cleared).
    func invalidate() {
        cache.removeAll()
    }

    private func schedule(_ url: URL) {
        let key = url.path
        guard !pending.contains(key) else { return }
        pending.insert(key)

        Task.detached(priority: .utility) {
            var isDirectory: ObjCBool = false
            let exists = FileManager.default.fileExists(atPath: key, isDirectory: &isDirectory)
            let status = Status(exists: exists, isDirectory: isDirectory.boolValue)
            await MainActor.run {
                FileStatusCache.shared.store(status, for: key)
            }
        }
    }

    private func store(_ status: Status, for key: String) {
        pending.remove(key)
        cache[key] = status
    }
}
