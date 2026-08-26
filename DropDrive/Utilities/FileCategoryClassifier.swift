import Foundation

/// Buckets a Drive file into one of the categories shown in the Folder Preview.
/// Images/videos are classified by MIME type (reliable from Drive); documents and
/// archives lean on file extension too, since Drive often reports generic MIME types
/// (e.g. application/octet-stream) for files uploaded rather than created in Drive.
nonisolated enum FileCategoryClassifier {
    private static let documentExtensions: Set<String> = [
        "pdf", "doc", "docx", "rtf", "txt", "odt", "pages",
        "xls", "xlsx", "csv", "numbers",
        "ppt", "pptx", "key", "md"
    ]

    private static let archiveExtensions: Set<String> = [
        "zip", "rar", "7z", "tar", "gz", "bz2", "xz", "tgz"
    ]

    private static let documentMimeTypes: Set<String> = [
        "application/pdf",
        "application/msword",
        "application/vnd.openxmlformats-officedocument.wordprocessingml.document",
        "application/vnd.ms-excel",
        "application/vnd.openxmlformats-officedocument.spreadsheetml.sheet",
        "application/vnd.ms-powerpoint",
        "application/vnd.openxmlformats-officedocument.presentationml.presentation",
        "application/rtf",
        "text/csv"
    ]

    private static let archiveMimeTypes: Set<String> = [
        "application/zip",
        "application/x-zip-compressed",
        "application/x-rar-compressed",
        "application/x-7z-compressed",
        "application/x-tar",
        "application/gzip",
        "application/x-bzip2"
    ]

    static func categorize(mimeType: String, name: String) -> WritableKeyPath<DriveLinkAnalysis.CategoryBreakdown, Int> {
        let ext = (name as NSString).pathExtension.lowercased()

        if mimeType.hasPrefix("image/") {
            return \.images
        }
        if mimeType.hasPrefix("video/") {
            return \.videos
        }
        if archiveMimeTypes.contains(mimeType) || archiveExtensions.contains(ext) {
            return \.archives
        }
        if documentMimeTypes.contains(mimeType) || mimeType.hasPrefix("text/") || documentExtensions.contains(ext) {
            return \.documents
        }
        return \.other
    }

    static func category(mimeType: String, name: String) -> DriveLinkAnalysis.FolderItem.Category {
        let keyPath = categorize(mimeType: mimeType, name: name)
        if keyPath == \DriveLinkAnalysis.CategoryBreakdown.images { return .images }
        if keyPath == \DriveLinkAnalysis.CategoryBreakdown.videos { return .videos }
        if keyPath == \DriveLinkAnalysis.CategoryBreakdown.documents { return .documents }
        if keyPath == \DriveLinkAnalysis.CategoryBreakdown.archives { return .archives }
        return .other
    }
}
