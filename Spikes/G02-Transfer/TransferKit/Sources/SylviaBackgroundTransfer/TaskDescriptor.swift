import Foundation
import SylviaTransferCore

/// What a background download task is for, carried in `URLSessionTask.taskDescription` so the app can
/// reattach the system's outstanding tasks to its persisted jobs after a relaunch (plan 15.5: "stable
/// task descriptions containing a job/part ID, not secrets").
///
/// Format (ASCII, space separated, exactly five fields):
///
///     sylvia-xfer/1 job=<uuid> asset=<uuid> part=<index> attempt=<n>
///
/// Only identifiers and counters: never a token, secret, title, path or host. Anything that does not
/// parse exactly is treated as foreign and cancelled during reconciliation.
public struct TaskDescriptor: Hashable, Sendable, CustomStringConvertible {
    public static let prefix = "sylvia-xfer/1"
    public static let maximumAttempt = 1_000

    public var jobID: String
    public var assetID: String
    public var partIndex: Int
    public var attempt: Int

    public init(jobID: String, assetID: String, partIndex: Int, attempt: Int) {
        self.jobID = jobID
        self.assetID = assetID
        self.partIndex = partIndex
        self.attempt = attempt
    }

    public var encoded: String {
        "\(Self.prefix) job=\(jobID) asset=\(assetID) part=\(partIndex) attempt=\(attempt)"
    }

    public var description: String { encoded }

    /// The part this task fetches, independent of the attempt.
    public var partKey: PartKey { PartKey(assetID: assetID, index: partIndex) }

    public static func parse(_ text: String?) -> TaskDescriptor? {
        guard let text, text.utf8.count <= 200 else { return nil }
        let fields = text.split(separator: " ", omittingEmptySubsequences: false)
        guard fields.count == 5, fields[0] == prefix else { return nil }
        func value(_ field: Substring, _ name: String) -> String? {
            let prefix = name + "="
            guard field.hasPrefix(prefix) else { return nil }
            return String(field.dropFirst(prefix.count))
        }
        guard let job = value(fields[1], "job"), CanonicalID.isValid(job),
            let asset = value(fields[2], "asset"), CanonicalID.isValid(asset),
            let partText = value(fields[3], "part"), let part = strictInt(partText),
            part < TransferProtocol.maximumPartsPerAsset,
            let attemptText = value(fields[4], "attempt"), let attempt = strictInt(attemptText),
            attempt >= 1, attempt <= maximumAttempt
        else { return nil }
        return TaskDescriptor(jobID: job, assetID: asset, partIndex: part, attempt: attempt)
    }

    /// Decimal digits only, no sign, no leading zeros (except "0").
    private static func strictInt(_ text: String) -> Int? {
        guard !text.isEmpty, text.utf8.count <= 6, text.utf8.allSatisfy({ $0 >= 48 && $0 <= 57 }),
            text == "0" || !text.hasPrefix("0")
        else { return nil }
        return Int(text)
    }
}

/// One part of one asset.
public struct PartKey: Hashable, Sendable, Comparable, Codable, CustomStringConvertible {
    public var assetID: String
    public var index: Int

    public init(assetID: String, index: Int) {
        self.assetID = assetID
        self.index = index
    }

    public var description: String { "\(assetID):\(index)" }

    public static func < (lhs: PartKey, rhs: PartKey) -> Bool {
        (lhs.assetID, lhs.index) < (rhs.assetID, rhs.index)
    }
}
