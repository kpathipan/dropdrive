import Foundation

/// Runs asynchronous work concurrently without letting a large paste fan out
/// into an unbounded request burst. Results retain the input order so review UI
/// never jumps around as faster links finish first.
nonisolated enum BoundedAsyncMap {
    static func run<Input: Sendable, Output: Sendable>(
        _ inputs: [Input],
        limit: Int,
        operation: @escaping @Sendable (Input) async -> Output
    ) async -> [Output] {
        guard !inputs.isEmpty else { return [] }
        let concurrency = max(1, min(limit, inputs.count))
        var pending = Array(inputs.enumerated())[...]
        var ordered = [Output?](repeating: nil, count: inputs.count)

        await withTaskGroup(of: (Int, Output).self) { group in
            func startNext() {
                guard let (index, input) = pending.popFirst() else { return }
                group.addTask { (index, await operation(input)) }
            }

            for _ in 0..<concurrency { startNext() }
            while let (index, output) = await group.next() {
                ordered[index] = output
                startNext()
            }
        }

        // Every input starts exactly once and the group waits for every child,
        // so nil would indicate an internal programming error rather than a
        // recoverable per-link failure (the operation represents those in its
        // own Output type).
        return ordered.compactMap { $0 }
    }
}
