import Foundation

/// The record of one run (`session.json`, class C), rewritten after every attempt and read at the next launch.
public struct SessionRecord: Codable, Sendable, Equatable {
    public var run: String
    /// The device's boot time when the run started.
    public var bootTime: Date?
    public var startedAt: Date
    /// When the run last recorded an attempt (or started, or stopped).
    public var lastRecordAt: Date
    public var interval: TimeInterval
    public var attempts: Int
    /// Items 0..<acknowledged are acknowledged: each was committed and read back with its exact content. Counts every
    /// run's items, since a run continues the library the previous one left.
    public var acknowledged: Int
    /// Attempts of this run that were not acknowledged, or whose class-C file or protection check failed.
    public var failures: Int
    /// Attempts made while `isProtectedDataAvailable` was false (the phone locked).
    public var lockedAttempts: Int
    public var lockedFailures: Int
    /// Attempts made while the class-A canary was unreadable.
    public var classAUnreadable: Int
    public var gaps: Int
    public var longestGap: TimeInterval
    public var stoppedCleanly: Bool

    public init(run: String, bootTime: Date?, startedAt: Date, interval: TimeInterval, acknowledged: Int) {
        self.run = run
        self.bootTime = bootTime
        self.startedAt = startedAt
        self.lastRecordAt = startedAt
        self.interval = interval
        self.attempts = 0
        self.acknowledged = acknowledged
        self.failures = 0
        self.lockedAttempts = 0
        self.lockedFailures = 0
        self.classAUnreadable = 0
        self.gaps = 0
        self.longestGap = 0
        self.stoppedCleanly = false
    }

    /// The counters, as log fields.
    public var counterFields: [(String, String)] {
        [("run", run), ("attempts", "\(attempts)"), ("acknowledged", "\(acknowledged)"), ("failures", "\(failures)"),
         ("lockedAttempts", "\(lockedAttempts)"), ("lockedFailures", "\(lockedFailures)"),
         ("classAUnreadable", "\(classAUnreadable)"), ("gaps", "\(gaps)"), ("longestGap", HarnessLog.seconds(longestGap))]
    }
}

/// How the previous run ended, as the next launch reads it.
public enum PreviousSession: Equatable, Sendable {
    /// No record: the first launch of this installation.
    case none
    /// The record exists but could not be read (class C before the first unlock, or damaged).
    case unreadable(code: String, reason: String)
    case stoppedCleanly(SessionRecord)
    /// The device booted after the run's last record: the restart ended it.
    case endedByRestart(SessionRecord, boot: Date)
    /// The run was not stopped and the device has not booted since its last record: the process ended in this boot
    /// (force quit, a crash, or iOS ended it). A crash report, if any, is in the device's crash logs.
    case endedWithoutStop(SessionRecord, boot: Date)
    /// The run was not stopped and the boot time is unknown.
    case endedBootUnknown(SessionRecord)

    public static func classify(_ record: SessionRecord?, currentBoot: Date?) -> PreviousSession {
        guard let record else { return .none }
        if record.stoppedCleanly { return .stoppedCleanly(record) }
        guard let currentBoot else { return .endedBootUnknown(record) }
        return currentBoot > record.lastRecordAt ? .endedByRestart(record, boot: currentBoot)
                                                 : .endedWithoutStop(record, boot: currentBoot)
    }

    public var record: SessionRecord? {
        switch self {
        case .none, .unreadable: return nil
        case .stoppedCleanly(let r), .endedByRestart(let r, _), .endedWithoutStop(let r, _), .endedBootUnknown(let r): return r
        }
    }

    public var result: String {
        switch self {
        case .none: return "none"
        case .unreadable: return "unreadable"
        case .stoppedCleanly: return "stopped-cleanly"
        case .endedByRestart: return "ended-by-restart"
        case .endedWithoutStop: return "ended-without-stop"
        case .endedBootUnknown: return "ended-boot-unknown"
        }
    }

    /// The fields of the `previous-session` line.
    public var fields: [(String, String)] {
        var out: [(String, String)] = [("result", result)]
        if let record {
            out += record.counterFields
            out.append(("lastRecord", HarnessLog.timestamp(record.lastRecordAt)))
        }
        switch self {
        case .endedByRestart(let r, let boot):
            out += [("boot", HarnessLog.timestamp(boot)), ("lastRecordToBoot", HarnessLog.seconds(boot.timeIntervalSince(r.lastRecordAt)))]
        case .endedWithoutStop(_, let boot):
            out.append(("boot", HarnessLog.timestamp(boot)))
        case .unreadable(let code, _):
            out.append(("error", code))
        default:
            break
        }
        return out
    }
}
