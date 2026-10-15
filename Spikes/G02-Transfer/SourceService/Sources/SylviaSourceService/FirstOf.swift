import Foundation
import Synchronization

/// Waits for a task's value for at most a time limit, without cancelling the task when the limit passes
/// (the work goes on; whoever asks next gets its result). Only the first of "value" and "limit" answers.
enum FirstOf {
    static func value<T: Sendable>(of task: Task<T, Never>, within limit: Duration) async -> T? {
        let slot = AnswerSlot<T>()
        return await withCheckedContinuation { (continuation: CheckedContinuation<T?, Never>) in
            slot.set(continuation)
            let timer = Task {
                try? await Task.sleep(for: limit)
                slot.answer(nil)
            }
            Task {
                let value = await task.value
                slot.answer(value)
                timer.cancel()
            }
        }
    }
}

/// Holds one continuation; the first answer resumes it and later answers are ignored.
final class AnswerSlot<T: Sendable>: Sendable {
    private let continuation = Mutex<CheckedContinuation<T?, Never>?>(nil)

    func set(_ value: CheckedContinuation<T?, Never>) { continuation.withLock { $0 = value } }

    func answer(_ value: T?) {
        let taken = continuation.withLock { stored -> CheckedContinuation<T?, Never>? in
            defer { stored = nil }
            return stored
        }
        taken?.resume(returning: value)
    }
}
