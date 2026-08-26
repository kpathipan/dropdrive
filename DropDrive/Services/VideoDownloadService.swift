import CryptoKit
import Foundation

/// Downloads videos from TikTok / YouTube / Facebook links through the bundled
/// yt-dlp binary (with ffmpeg alongside for merging YouTube's separate
/// video/audio tracks). TikTok comes out watermark-free — the same source the
/// "no watermark" websites serve, just without the ads.
struct VideoDownloadService: Sendable {
    struct VideoError: LocalizedError {
        let message: String
        var errorDescription: String? { message }
    }

    nonisolated static func isSupportedLink(_ raw: String) -> Bool {
        toolsAvailable && SupportedLinkExtractor.isPotentialVideoLink(raw)
    }

    nonisolated static var toolsAvailable: Bool { ytDlpURL != nil }

    private nonisolated static var ytDlpURL: URL? {
        Bundle.main.url(forResource: "yt-dlp", withExtension: nil)
    }

    /// YouTube now presents JavaScript challenges before it releases many
    /// formats. yt-dlp delegates those to Deno; keeping it inside the app
    /// bundle means a Finder-launched build does not depend on Homebrew, Node,
    /// or a user's shell PATH.
    private static var denoURL: URL? {
        Bundle.main.url(forResource: "deno", withExtension: nil)
    }

    /// yt-dlp takes the DIRECTORY that contains ffmpeg, not the binary itself.
    private static var ffmpegDirectory: String? {
        Bundle.main.url(forResource: "ffmpeg", withExtension: nil)?
            .deletingLastPathComponent().path
    }

    // MARK: - Fast analysis (oEmbed)

    /// Title/uploader/thumbnail from the platform's oEmbed endpoint — roughly
    /// 0.4s versus the ~12s yt-dlp spends resolving every format. Used to show
    /// the confirm card immediately; `analyze` then fills in duration and size
    /// in the background. Returns nil for platforms without a usable oEmbed
    /// (Instagram's needs a Facebook token), so the caller falls back to yt-dlp.
    func quickAnalyze(_ link: String) async -> DriveLinkAnalysis? {
        guard let endpoint = Self.oEmbedEndpoint(for: link) else { return nil }

        var request = URLRequest(url: endpoint)
        request.timeoutInterval = 6
        guard let (data, response) = try? await URLSession.shared.data(for: request),
              let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let title = json["title"] as? String, !title.isEmpty else {
            return nil
        }

        return DriveLinkAnalysis(
            itemID: LinkIdentity.videoItemID(for: link),
            name: title,
            type: .file,
            isPublic: true,
            requiresAuthentication: false,
            totalBytes: nil,
            fileCount: nil,
            ownerName: json["author_name"] as? String,
            categoryBreakdown: nil,
            isVideo: true,
            thumbnailURL: json["thumbnail_url"] as? String,
            durationSeconds: nil
        )
    }

    private static func oEmbedEndpoint(for link: String) -> URL? {
        guard let url = URL(string: link), let host = url.host?.lowercased() else { return nil }
        let encoded = link.addingPercentEncoding(withAllowedCharacters: .alphanumerics) ?? link

        if host.contains("youtube.com") || host.contains("youtu.be") {
            return URL(string: "https://www.youtube.com/oembed?url=\(encoded)&format=json")
        }
        if host.contains("tiktok.com") {
            return URL(string: "https://www.tiktok.com/oembed?url=\(encoded)")
        }
        return nil
    }

    // MARK: - Full analysis (yt-dlp)

    func analyze(_ link: String) async throws -> DriveLinkAnalysis {
        // The same TikTok challenge the download path works around can block
        // this read too, and this one runs first — so the embed fallback has to
        // live here as well or the link never gets far enough to download.
        //
        // It matters most where there is no confirmation card to fall back on:
        // a link shared from the phone or sent through the right-click Service
        // is analysed here and nowhere else, and a failure there simply dropped
        // it. Pasting a link into the window survived without this only because
        // the card is built from the fast oEmbed lookup instead.
        var output: String
        var usedEmbed = false
        do {
            output = try await Self.analyzeOutput(for: link)
        } catch is CancellationError {
            throw CancellationError()
        } catch {
            guard let embedURL = await Self.tikTokEmbedURL(for: link) else { throw error }
            output = try await Self.analyzeOutput(for: embedURL.absoluteString, isEmbed: true)
            usedEmbed = true
        }

        guard let data = output.data(using: .utf8),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let extractedTitle = json["title"] as? String else {
            throw VideoError(message: tr(
                "Couldn't read this video's details.",
                "อ่านข้อมูลวิดีโอนี้ไม่ได้"
            ))
        }

        // Keep the extracted info so the download doesn't have to redo it —
        // resolving formats is the slow half of a video download (measured
        // ~2x faster end to end when reused).
        //
        // Not for an embed-page read, though. Handing that json to the download
        // would name the file from its "TikTok Embed" title, and skipping the
        // cache costs only the extraction it would have saved: the download
        // then runs its own attempt and falls back to the embed page itself,
        // where it already restores the title the user confirmed.
        if !usedEmbed {
            try? data.write(to: Self.infoCacheURL(for: link))
        }

        // The embed page's own extractor titles every post "TikTok Embed",
        // which would then be the name on the card and on the file. oEmbed
        // still answers for these links, so prefer the real caption and keep
        // the embed title only if that fails too.
        let title = await Self.preferredTitle(rawTitle: extractedTitle, link: link)

        let size = (json["filesize_approx"] as? Int64) ?? (json["filesize"] as? Int64)
        let uploader = (json["uploader"] as? String) ?? (json["channel"] as? String)
        let duration = (json["duration"] as? Double) ?? (json["duration"] as? Int).map(Double.init)

        return DriveLinkAnalysis(
            itemID: LinkIdentity.videoItemID(for: link),
            name: title,
            type: .file,
            isPublic: true,
            requiresAuthentication: false,
            totalBytes: size,
            fileCount: nil,
            ownerName: uploader,
            categoryBreakdown: nil,
            isVideo: true,
            thumbnailURL: json["thumbnail"] as? String,
            durationSeconds: duration
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
        clipSection: String? = nil,
        customName: String? = nil,
        onProgress: @escaping @Sendable (DownloadProgress) -> Void
    ) async throws -> URL {
        // A trimmed clip gets its own suffix so it never collides with (or gets
        // skipped as "already downloaded" because of) the full video.
        let clipSuffix = clipSection == nil ? "" : " (clip)"
        // A typed name replaces yt-dlp's %(title)s. It is escaped first: a "%"
        // in it would otherwise be read as an output-template field and either
        // fail the download or produce a nonsense filename.
        let outputTemplate = customName.map { "\(Self.escapedForOutputTemplate($0))\(clipSuffix).%(ext)s" }
            ?? "%(title).200B\(clipSuffix).%(ext)s"

        var arguments = [
            "--no-warnings", "--no-playlist", "--newline",
            // Some networks advertise IPv6 but never complete the TLS route to
            // the video CDN. yt-dlp then waits/retries on that dead route while
            // URLSession (used by the rest of the app) succeeds over IPv4.
            "--force-ipv4", "--socket-timeout", "30",
            "-P", destination.path,
            "-o", outputTemplate,
            "--no-simulate", "--print", "after_move:filepath",
            "--progress"
        ]
        if let denoURL = Self.denoURL {
            arguments += ["--js-runtimes", "deno:\(denoURL.path)"]
        }
        if let clipSection {
            // "start-end" in seconds; keyframe cuts keep the trim accurate.
            arguments += ["--download-sections", "*\(clipSection)", "--force-keyframes-at-cuts"]
        }
        if asAudio {
            // Extract audio and convert to MP3 via the bundled ffmpeg; -q 0 is
            // the best VBR quality.
            arguments += ["-f", "ba/b", "-x", "--audio-format", "mp3", "--audio-quality", "0"]
        } else {
            // Left to itself yt-dlp picks whatever is highest quality, which on
            // YouTube means AV1 or VP9 audio-in-webm — a file QuickTime, Finder
            // preview, and most editing software all refuse to open, so it just
            // looks like a broken download. Prefer H.264 + AAC in MP4, which
            // plays and edits everywhere on a Mac, and only fall back to other
            // codecs when a video offers nothing else (still forced into an MP4
            // container rather than webm).
            if PreferencesStore.shared.preferCompatibleVideo {
                arguments += [
                    "-f", "bv*[vcodec^=avc1]+ba[acodec^=mp4a]/bv*[ext=mp4]+ba[ext=m4a]/b[ext=mp4]/bv*+ba/b",
                    "--merge-output-format", "mp4"
                ]
            } else {
                // Highest quality available, still packed into MP4 rather than
                // webm so the container at least behaves.
                arguments += ["-f", "bv*+ba/b", "--merge-output-format", "mp4"]
            }
        }
        if let ffmpegDirectory = Self.ffmpegDirectory {
            arguments += ["--ffmpeg-location", ffmpegDirectory]
        }

        let smoother = RateSmoother()
        // yt-dlp's output is parsed on the pipe-reader thread, so the discovered
        // path can't live in a plain captured `var` — that was a genuine data
        // race, and losing the write means a finished download reporting that it
        // can't find its own file.
        let finalPath = PathBox()
        let mergingText = tr("Merging tracks…", "กำลังรวมไฟล์วิดีโอ…")
        let convertingText = tr("Converting to MP3…", "กำลังแปลงเป็น MP3…")

        let handleLine: @Sendable (String) -> Void = { line in
            if line.hasPrefix("/") {
                finalPath.value = line
            } else if let progress = Self.parseProgress(line: line, fileName: title, smoother: smoother) {
                onProgress(progress)
            } else if line.hasPrefix("[Merger]") || line.hasPrefix("[VideoRemuxer]") {
                onProgress(DownloadProgress(currentFileName: mergingText))
            } else if line.hasPrefix("[ExtractAudio]") {
                onProgress(DownloadProgress(currentFileName: convertingText))
            }
        }

        // TikTok's normal watch page is sometimes replaced by its WAF challenge
        // before yt-dlp can read the post. The public embed page carries the
        // same media URL but does not use that challenge. Keep the ordinary
        // extractor as the first choice (it has richer metadata and formats),
        // then retry this narrowly-scoped fallback only when that extraction
        // fails. `--playlist-items 1` is intentional: TikTok's embed markup
        // lists the same video twice for its player, and yt-dlp sees that as a
        // two-item HTML5 playlist.
        func retryTikTokEmbed(after error: Error) async throws -> String {
            guard let embedURL = await Self.tikTokEmbedURL(for: link) else { throw error }

            var fallbackArguments = arguments.filter { $0 != "--no-playlist" }
            if customName == nil,
               let outputIndex = fallbackArguments.firstIndex(of: "-o"),
               fallbackArguments.indices.contains(outputIndex + 1) {
                // The generic embed extractor calls every item "TikTok Embed".
                // Preserve the title the user saw on the confirmation card.
                fallbackArguments[outputIndex + 1] = "\(Self.escapedForOutputTemplate(title))\(clipSuffix).%(ext)s"
            }
            fallbackArguments += ["--playlist-items", "1", embedURL.absoluteString]
            finalPath.value = nil
            return try await Self.run(arguments: fallbackArguments, onProgressLine: handleLine)
        }

        var output: String

        if let cachedInfo = Self.freshInfoCache(for: link) {
            // The resolved formats are only a bridge from analysis to this
            // download. Remove them as soon as they have served that purpose;
            // keeping one json file per video until the hourly temp sweep adds
            // space without making any later action faster.
            defer { try? FileManager.default.removeItem(at: cachedInfo) }
            // Reuse the formats resolved during analysis instead of making
            // yt-dlp extract them all over again.
            do {
                output = try await Self.run(
                    arguments: arguments + ["--load-info-json", cachedInfo.path],
                    onProgressLine: handleLine
                )
            } catch is CancellationError {
                throw CancellationError()
            } catch {
                // Cached URLs expire; fall back to a full extraction once.
                try? FileManager.default.removeItem(at: cachedInfo)
                finalPath.value = nil
                do {
                    output = try await Self.run(arguments: arguments + [link], onProgressLine: handleLine)
                } catch is CancellationError {
                    throw CancellationError()
                } catch {
                    output = try await retryTikTokEmbed(after: error)
                }
            }
        } else {
            do {
                output = try await Self.run(arguments: arguments + [link], onProgressLine: handleLine)
            } catch is CancellationError {
                throw CancellationError()
            } catch {
                output = try await retryTikTokEmbed(after: error)
            }
        }

        let path = finalPath.value ?? output
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

    // MARK: - Extracted-info cache

    /// Where the `-J` output for a link is parked between analysis and download.
    private static func infoCacheURL(for link: String) -> URL {
        let digest = SHA256.hash(data: Data(link.utf8))
            .map { String(format: "%02x", $0) }
            .joined()
            .prefix(32)
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("DropDrive-info", isDirectory: true)
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        return directory.appendingPathComponent("\(digest).json")
    }

    /// The cached info only if it's recent enough to still hold usable media
    /// URLs — platforms sign those with a few hours' expiry, so this stays well
    /// inside that window and the download falls back to a fresh extraction
    /// whenever the cache is missing, stale, or rejected.
    private static func freshInfoCache(for link: String) -> URL? {
        let url = infoCacheURL(for: link)
        guard let modified = try? url.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate,
              Date().timeIntervalSince(modified) < 30 * 60 else {
            return nil
        }
        return url
    }

    /// One `-J` metadata read. `--playlist-items 1` is only for the embed page:
    /// its markup lists the same video twice for the player, which yt-dlp reads
    /// as a two-item playlist, and `--no-playlist` does not apply to it.
    private static func analyzeOutput(for target: String, isEmbed: Bool = false) async throws -> String {
        var arguments = ["-J", "--no-warnings", "--force-ipv4", "--socket-timeout", "30"]
        if let denoURL = Self.denoURL {
            arguments += ["--js-runtimes", "deno:\(denoURL.path)"]
        }
        arguments += isEmbed ? ["--playlist-items", "1"] : ["--no-playlist"]
        return try await run(arguments: arguments + [target], onProgressLine: nil)
    }

    /// The caption a person would recognise, for a post whose extracted title is
    /// the embed page's placeholder.
    private static func preferredTitle(rawTitle: String, link: String) async -> String {
        guard rawTitle.localizedCaseInsensitiveContains("tiktok embed") else { return rawTitle }
        guard let endpoint = oEmbedEndpoint(for: link),
              let (data, response) = try? await URLSession.shared.data(from: endpoint),
              let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let title = json["title"] as? String, !title.isEmpty
        else { return rawTitle }
        return title
    }

    /// TikTok exposes every public post through an embed page as well as its
    /// regular watch page. The embed endpoint is useful only as a fallback:
    /// unlike the watch page it has little metadata, but it remains available
    /// when TikTok presents its anti-bot challenge to the normal extractor.
    private static func tikTokEmbedURL(for link: String) async -> URL? {
        guard let components = URLComponents(string: link),
              let host = components.host?.lowercased(),
              (host == "tiktok.com" || host.hasSuffix(".tiktok.com"))
        else { return nil }

        let pathVideoID = components.path.components(separatedBy: "/").last(where: {
            $0.allSatisfy(\.isNumber) && $0.count >= 10
        })
        let videoID: String?
        if let pathVideoID {
            videoID = pathVideoID
        } else {
            videoID = await tikTokVideoIDFromOEmbed(link)
        }
        guard let videoID else { return nil }
        return URL(string: "https://www.tiktok.com/embed/v2/\(videoID)")
    }

    /// Short `vm.tiktok.com` shares contain no post ID themselves. TikTok's
    /// oEmbed response does, and it is also less restricted than the watch
    /// page, so use it to make the fallback work for both URL shapes.
    private static func tikTokVideoIDFromOEmbed(_ link: String) async -> String? {
        guard let endpoint = oEmbedEndpoint(for: link) else { return nil }
        var request = URLRequest(url: endpoint)
        request.timeoutInterval = 6
        guard let (data, response) = try? await URLSession.shared.data(for: request),
              let http = response as? HTTPURLResponse,
              (200..<300).contains(http.statusCode),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let id = json["embed_product_id"] as? String,
              id.count >= 10,
              id.allSatisfy(\.isNumber)
        else { return nil }
        return id
    }

    /// Removes yt-dlp's partial artifacts (`.part`, `.ytdl`, fragment files) for
    /// this title after a cancel — matched by the title prefix AND a partial
    /// suffix, so finished videos are never touched.
    ///
    /// Matched on the alphanumeric skeleton of the name, not a literal prefix:
    /// yt-dlp's own filename sanitizing swaps `:`, `?`, `/`, `|`, etc. (extremely
    /// common in real titles, e.g. "Title: Subtitle") for lookalike Unicode
    /// characters, so the file on disk rarely starts with the raw title text
    /// verbatim. A literal `hasPrefix` missed those and left `.part`/`.ytdl`
    /// fragments behind after every cancel — exactly the kind of orphaned scratch
    /// file that has filled this user's disk before.
    static func cleanupPartials(title: String, in destination: URL) {
        let contents = (try? FileManager.default.contentsOfDirectory(
            at: destination, includingPropertiesForKeys: nil,
            options: [.skipsSubdirectoryDescendants]
        )) ?? []
        let prefix = Self.alphanumericSkeleton(String(title.prefix(60)))
        guard !prefix.isEmpty else { return }
        for file in contents {
            let name = file.lastPathComponent
            guard Self.alphanumericSkeleton(name).hasPrefix(prefix) else { continue }
            if name.hasSuffix(".part") || name.hasSuffix(".ytdl") || name.contains(".part-Frag") {
                try? FileManager.default.removeItem(at: file)
            }
        }
    }

    /// Strips everything but letters/digits, so filename sanitizing on either
    /// side (raw title vs. what yt-dlp actually wrote) can't break the match.
    private static func alphanumericSkeleton(_ s: String) -> String {
        String(s.unicodeScalars.filter(CharacterSet.alphanumerics.contains))
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
    private nonisolated static func parseProgress(line: String, fileName: String, smoother: RateSmoother) -> DownloadProgress? {
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
            // yt-dlp reports the instantaneous rate of the fragment it happens to
            // be on, which swings hard as fragments start and finish. Smoothed
            // with the same weighting the Drive path uses so the number reads as
            // a speed rather than a flicker.
            bytesPerSecond: smoother.smoothing(speed)
        )
    }

    /// Makes a user-typed name safe to sit inside a yt-dlp `-o` template: "%"
    /// starts a field reference, and "/" would turn the name into a subfolder.
    private nonisolated static func escapedForOutputTemplate(_ name: String) -> String {
        name.replacingOccurrences(of: "%", with: "%%")
            .replacingOccurrences(of: "/", with: "-")
            .replacingOccurrences(of: ":", with: "-")
    }

    private nonisolated static func multiplier(_ unit: String) -> Double {
        switch unit {
        case "KiB": 1024
        case "MiB": 1024 * 1024
        case "GiB": 1024 * 1024 * 1024
        default: 1
        }
    }
}

/// Thread-safe holder for the output path yt-dlp prints, written from the
/// pipe-reader thread and read once the process exits.
private nonisolated final class PathBox: @unchecked Sendable {
    private let lock = NSLock()
    private var stored: String?

    var value: String? {
        get { lock.lock(); defer { lock.unlock() }; return stored }
        set { lock.lock(); stored = newValue; lock.unlock() }
    }
}

/// Exponential moving average over yt-dlp's per-fragment speed readings.
private nonisolated final class RateSmoother: @unchecked Sendable {
    private let lock = NSLock()
    private var smoothed: Double = 0

    func smoothing(_ instant: Double) -> Double {
        lock.lock()
        defer { lock.unlock() }
        guard instant > 0 else { return smoothed }
        smoothed = smoothed == 0 ? instant : smoothed * 0.7 + instant * 0.3
        return smoothed
    }
}

/// Accumulates pipe data and emits complete lines; Process pipes deliver
/// arbitrary chunks, not lines.
private nonisolated final class LineCollector: @unchecked Sendable {
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
