import Foundation

// Deterministic extractor responses for integration tests of the real service.
// This executable only replaces yt-dlp inside the temporary test bundle.
if CommandLine.arguments.contains("-J") {
    print("""
    {"id":"fixture","title":"Source fixture","url":"https://example.invalid/media.mp4","ext":"mp4","duration":3,"extractor":"Instagram","formats":[]}
    """)
} else {
    FileHandle.standardError.write(Data("ERROR: HTTP Error 503: Service Unavailable\n".utf8))
    exit(1)
}
