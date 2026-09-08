import Foundation

/// Watch the actual destination throughout transfer and conversion.
nonisolated enum TransferGuard {
    static let reserveBytes: Int64 = 64 * 1024 * 1024

    static func run<T: Sendable>(destination: URL, operation: @escaping @Sendable () async throws -> T) async throws -> T {
        try check(destination)
        return try await withThrowingTaskGroup(of: T.self) { group in
            group.addTask { try await operation() }
            group.addTask {
                while true {
                    try Task.checkCancellation()
                    try check(destination)
                    try await Task.sleep(for: .seconds(1))
                }
            }
            defer { group.cancelAll() }
            guard let result = try await group.next() else { throw CancellationError() }
            return result
        }
    }

    private static func check(_ destination: URL) throws {
        switch DestinationCapacity.inspect(destination) {
        case .unavailable, .notSelected: throw VideoDownloadPolicy.Failure.destination
        case .available(let free) where free < reserveBytes: throw VideoDownloadPolicy.Failure.space
        default: break
        }
    }
}
