import Foundation

/// Pairs URLSession's opaque resume-data blob with the destination file name it
/// belongs to, so a later resume attempt can confirm the blob still matches the file
/// it's about to be applied to before trusting it.
nonisolated struct ResumeEnvelope: Codable, Sendable {
    let fileName: String
    let data: Data
}

/// Persists resume envelopes to disk, keyed by queue item id. UserDefaults isn't
/// appropriate for this (binary, can be several KB, one per queued item), so these
/// live in Application Support instead.
nonisolated enum ResumeEnvelopeStore {
    // `let`, not `var`: it was only ever assigned once by its own initializer,
    // and as a `var` it counted as mutable global state the moment this type
    // stopped being main-actor isolated.
    private static let directory: URL? = {
        guard let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first else {
            return nil
        }
        let dir = base.appendingPathComponent("DropDrive/ResumeData", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }()

    private static func fileURL(for id: UUID) -> URL? {
        directory?.appendingPathComponent(id.uuidString + ".resumedata")
    }

    static func save(_ envelope: ResumeEnvelope, for id: UUID) {
        guard let url = fileURL(for: id), let data = try? JSONEncoder().encode(envelope) else { return }
        try? data.write(to: url, options: .atomic)
    }

    static func load(for id: UUID) -> ResumeEnvelope? {
        guard let url = fileURL(for: id), let data = try? Data(contentsOf: url) else { return nil }
        return try? JSONDecoder().decode(ResumeEnvelope.self, from: data)
    }

    static func clear(for id: UUID) {
        guard let url = fileURL(for: id) else { return }
        try? FileManager.default.removeItem(at: url)
    }
}
