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
    /// Bumped by `invalidate()`. A check that was already in flight belongs to
    /// the previous generation and its answer is thrown away — see below.
    private var generation = 0

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
    ///
    /// In-flight checks are abandoned too, not just the stored answers. A tile
    /// rendered while its file was still downloading schedules a check that
    /// answers "missing"; the download then finishes and invalidates the cache,
    /// and that stale answer used to land afterwards — writing "missing" into
    /// the freshly cleared cache and, because `pending` still held the key, with
    /// no way for anything to ask again. The just-finished download showed up in
    /// Recent greyed out and un-openable for the rest of the session.
    func invalidate() {
        generation += 1
        cache.removeAll()
        pending.removeAll()
    }

    private func schedule(_ url: URL) {
        let key = url.path
        guard !pending.contains(key) else { return }
        pending.insert(key)
        let requested = generation

        Task.detached(priority: .utility) {
            var isDirectory: ObjCBool = false
            let exists = FileManager.default.fileExists(atPath: key, isDirectory: &isDirectory)
            let status = Status(exists: exists, isDirectory: isDirectory.boolValue)
            await MainActor.run {
                FileStatusCache.shared.store(status, for: key, generation: requested)
            }
        }
    }

    private func store(_ status: Status, for key: String, generation storedGeneration: Int) {
        guard storedGeneration == generation else { return }
        pending.remove(key)
        cache[key] = status
    }
}
