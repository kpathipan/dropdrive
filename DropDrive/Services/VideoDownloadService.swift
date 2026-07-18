import Foundation

/// Downloads videos from TikTok / YouTube / Facebook links through the bundled
/// yt-dlp binary (with ffmpeg alongside for merging YouTube's separate
/// video/audio tracks). TikTok comes out watermark-free — the same source the
/// "no watermark" websites serve, just without the ads.
struct VideoDownloadService {
    struct VideoError: LocalizedError {
        let message: String
        var errorDescription: String? { message }
    }

    /// Hosts routed to yt-dlp instead of the Google Drive pipeline.
    private static let videoHosts = [
        "tiktok.com", "youtube.com", "youtu.be", "facebook.com", "fb.watch"
    ]

    static func isSupportedLink(_ raw: String) -> Bool {
        guard toolsAvailable,
              let url = URL(string: raw.trimmingCharacters(in: .whitespacesAndNewlines)),
              let host = url.host?.lowercased() else { return false }
        return videoHosts.contains { host == $0 || host.hasSuffix(".\($0)") }
    }

    static var toolsAvailable: Bool { ytDlpURL != nil }

    private static var ytDlpURL: URL? {
        Bundle.main.url(forResource: "yt-dlp", withExtension: nil)
    }

    /// yt-dlp takes the DIRECTORY that contains ffmpeg, not the binary itself.
    private static var ffmpegDirectory: String? {
        Bundle.main.url(forResource: "ffmpeg", withExtension: nil)?
            .deletingLastPathComponent().path
    }

    // MARK: - Analysis

    func analyze(_ link: String) async throws -> DriveLinkAnalysis {
        let output = try await Self.run(
            arguments: ["-J", "--no-warnings", "--no-playlist", link],
            onProgressLine: nil
        )

        guard let data = output.data(using: .utf8),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let title = json["title"] as? String else {
            throw VideoError(message: tr(
                "Couldn't read this video's details.",
                "อ่านข้อมูลวิดีโอนี้ไม่ได้"
            ))
        }

        let size = (json["filesize_approx"] as? Int64) ?? (json["filesize"] as? Int64)
        let uploader = (json["uploader"] as? String) ?? (json["channel"] as? String)

        return DriveLinkAnalysis(
            itemID: "video:\(link)",
            name: title,
            type: .file,
            isPublic: true,
            requiresAuthentication: false,
            totalBytes: size,
            fileCount: nil,
            ownerName: uploader,
            categoryBreakdown: nil,
            isVideo: true
        )
    }

    // MARK: - Download

    /// Downloads into `destination`, reporting yt-dlp's own progress lines as
    /// DownloadProgress updates, and returns the final file's URL (printed by
    /// yt-dlp itself via `--print after_move:filepath`, so container remuxes and
    /// merges are already accounted for).
    func download(
        link: String,
        title: String,
        destination: URL,
        asAudio: Bool = false,
        onProgress: @escaping @Sendable (DownloadProgress) -> Void
    ) async throws -> URL {
        var arguments = [
            "--no-warnings", "--no-playlist", "--newline",
            "-P", destination.path,
            "-o", "%(title).200B.%(ext)s",
            "--no-simulate", "--print", "after_move:filepath",
            "--progress"
        ]
        if asAudio {
            // Extract audio and convert to MP3 via the bundled ffmpeg; -q 0 is
            // the best VBR quality.
            arguments += ["-f", "ba/b", "-x", "--audio-format", "mp3", "--audio-quality", "0"]
        } else {
            arguments += ["-f", "bv*+ba/b"]
        }
        if let ffmpegDirectory = Self.ffmpegDirectory {
            arguments += ["--ffmpeg-location", ffmpegDirectory]
        }
        arguments.append(link)

        var finalPath: String?
        let output = try await Self.run(arguments: arguments) { line in
            if line.hasPrefix("/") {
                finalPath = line
            } else if let progress = Self.parseProgress(line: line, fileName: title) {
                onProgress(progress)
            } else if line.hasPrefix("[Merger]") || line.hasPrefix("[VideoRemuxer]") {
                onProgress(DownloadProgress(currentFileName: tr("Merging tracks…", "กำลังรวมไฟล์วิดีโอ…")))
            } else if line.hasPrefix("[ExtractAudio]") {
                onProgress(DownloadProgress(currentFileName: tr("Converting to MP3…", "กำลังแปลงเป็น MP3…")))
            }
        }

        let path = finalPath ?? output
            .split(separator: "\n")
            .last(where: { $0.hasPrefix("/") })
            .map(String.init)

        guard let path, FileManager.default.fileExists(atPath: path) else {
            throw VideoError(message: tr(
                "The video finished but the file couldn't be located.",
                "ดาวน์โหลดจบแต่หาไฟล์ปลายทางไม่เจอ"
            ))
        }
        return URL(fileURLWithPath: path)
    }

    /// Removes yt-dlp's partial artifacts (`.part`, `.ytdl`, fragment files) for
    /// this title after a cancel — matched by the title prefix AND a partial
    /// suffix, so finished videos are never touched.
    static func cleanupPartials(title: String, in destination: URL) {
        let contents = (try? FileManager.default.contentsOfDirectory(
            at: destination, includingPropertiesForKeys: nil,
            options: [.skipsSubdirectoryDescendants]
        )) ?? []
        let prefix = String(title.prefix(60))
        for file in contents {
            let name = file.lastPathComponent
            guard name.hasPrefix(prefix) else { continue }
            if name.hasSuffix(".part") || name.hasSuffix(".ytdl") || name.contains(".part-Frag") {
                try? FileManager.default.removeItem(at: file)
            }
        }
    }

    // MARK: - Process plumbing

    /// Runs yt-dlp, streaming stdout lines to `onProgressLine`, and returns the
    /// full stdout. Task cancellation terminates the process. A non-zero exit
    /// surfaces the last stderr line as the error message.
    private static func run(
        arguments: [String],
        onProgressLine: (@Sendable (String) -> Void)?
    ) async throws -> String {
        guard let ytDlpURL else {
            throw VideoError(message: tr(
                "Video engine is missing from this build.",
                "บิลด์นี้ไม่มีเครื่องยนต์ดาวน์โหลดวิดีโอ"
            ))
        }

        let process = Process()
        process.executableURL = ytDlpURL
        process.arguments = arguments
        // yt-dlp writes state (extractor caches etc.) to HOME; keep it out of
        // the user's real dotfiles.
        var environment = ProcessInfo.processInfo.environment
        environment["XDG_CACHE_HOME"] = NSTemporaryDirectory() + "dropdrive-ytdlp-cache"
        process.environment = environment

        let stdoutPipe = Pipe()
        let stderrPipe = Pipe()
        process.standardOutput = stdoutPipe
        process.standardError = stderrPipe

        let collector = LineCollector(onLine: onProgressLine)
        stdoutPipe.fileHandleForReading.readabilityHandler = { handle in
            collector.ingest(handle.availableData)
        }
        let errorCollector = LineCollector(onLine: nil)
        stderrPipe.fileHandleForReading.readabilityHandler = { handle in
            errorCollector.ingest(handle.availableData)
        }

        return try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { continuation in
                process.terminationHandler = { process in
                    stdoutPipe.fileHandleForReading.readabilityHandler = nil
                    stderrPipe.fileHandleForReading.readabilityHandler = nil
                    collector.finish()
                    errorCollector.finish()

                    if process.terminationStatus == 0 {
                        continuation.resume(returning: collector.text)
                    } else if process.terminationReason == .uncaughtSignal {
                        continuation.resume(throwing: CancellationError())
                    } else {
                        let lastError = errorCollector.text
                            .split(separator: "\n")
                            .last(where: { $0.contains("ERROR") }) ?? "yt-dlp failed"
                        continuation.resume(throwing: VideoError(message: String(lastError)))
                    }
                }
                do {
                    try process.run()
                } catch {
                    continuation.resume(throwing: error)
                }
            }
        } onCancel: {
            process.terminate()
        }
    }

    /// "[download]  45.2% of ~  12.34MiB at    2.34MiB/s ETA 00:12"
    private static func parseProgress(line: String, fileName: String) -> DownloadProgress? {
        guard line.hasPrefix("[download]"), line.contains("%") else { return nil }
        let pattern = /\[download\]\s+(?<pct>[\d.]+)% of ~?\s*(?<size>[\d.]+)(?<unit>KiB|MiB|GiB)(?:\s+at\s+(?<speed>[\d.]+)(?<sunit>KiB|MiB|GiB)\/s)?/
        guard let match = line.firstMatch(of: pattern),
              let pct = Double(match.pct),
              let size = Double(match.size) else { return nil }

        let totalBytes = Int64(size * Self.multiplier(String(match.unit)))
        let downloaded = Int64(Double(totalBytes) * pct / 100)
        var speed: Double = 0
        if let s = match.speed, let su = match.sunit, let value = Double(s) {
            speed = value * Self.multiplier(String(su))
        }
        return DownloadProgress(
            currentFileName: fileName,
            completedFiles: 0,
            totalFiles: 1,
            bytesDownloaded: downloaded,
            totalBytes: totalBytes,
            bytesPerSecond: speed
        )
    }

    private static func multiplier(_ unit: String) -> Double {
        switch unit {
        case "KiB": 1024
        case "MiB": 1024 * 1024
        case "GiB": 1024 * 1024 * 1024
        default: 1
        }
    }
}

/// Accumulates pipe data and emits complete lines; Process pipes deliver
/// arbitrary chunks, not lines.
private final class LineCollector: @unchecked Sendable {
    private let lock = NSLock()
    private var buffer = Data()
    private var collected = ""
    private let onLine: (@Sendable (String) -> Void)?

    init(onLine: (@Sendable (String) -> Void)?) {
        self.onLine = onLine
    }

    var text: String {
        lock.lock()
        defer { lock.unlock() }
        return collected
    }

    func ingest(_ data: Data) {
        guard !data.isEmpty else { return }
        lock.lock()
        buffer.append(data)
        var lines: [String] = []
        while let newline = buffer.firstIndex(of: UInt8(ascii: "\n")) {
            let lineData = buffer[buffer.startIndex..<newline]
            buffer.removeSubrange(buffer.startIndex...newline)
            if let line = String(data: lineData, encoding: .utf8) {
                collected += line + "\n"
                lines.append(line.trimmingCharacters(in: .whitespaces))
            }
        }
        lock.unlock()
        for line in lines where !line.isEmpty {
            onLine?(line)
        }
    }

    func finish() {
        lock.lock()
        let remainder = String(data: buffer, encoding: .utf8) ?? ""
        buffer.removeAll()
        if !remainder.isEmpty { collected += remainder }
        lock.unlock()
        let trimmed = remainder.trimmingCharacters(in: .whitespaces)
        if !trimmed.isEmpty { onLine?(trimmed) }
    }
}
