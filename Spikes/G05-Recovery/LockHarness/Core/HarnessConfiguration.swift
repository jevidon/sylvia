import Foundation

/// What a run of the locked-device harness does (T50, G0.5 recovery device checklist step 3; PO-23 option (b),
/// product owner, 22 October 2026). Stage 0 evidence code; never shipped (ADR-0002).
///
/// The protection class is fixed: class C (`completeUntilFirstUserAuthentication`), the class D17 gives every
/// persistent file of Sylvia's library. Any other value is refused when the configuration is made, and every file
/// component of the harness takes its class from a configuration, so nothing in the harness can fall back to a weaker
/// class, or to any other class, when a write fails. The only file with another class is the class-A canary, which
/// exists to detect the lock (`ClassACanary`).
public struct HarnessConfiguration: Sendable {
    /// D17: the class of every persistent file of the library, the log and the session record.
    public static let requiredProtection = FileProtectionType.completeUntilFirstUserAuthentication

    public let protection: FileProtectionType
    /// Seconds between two attempts.
    public let interval: TimeInterval
    /// A pause longer than this between two attempts is logged as a gap: the timer did not fire, so the process was
    /// suspended or stopped (the old XCTest lock probe's rule was 5 s).
    public let gapThreshold: TimeInterval
    /// Attempts between two summary lines.
    public let summaryEvery: Int
    /// Lines held in memory while the log file cannot be written (before the first unlock); older ones are dropped
    /// and counted beyond this bound.
    public let pendingLimit: Int
    /// Player volume: 0.01 (the test volume) unless `SYLVIA_AUDIBLE_PLAYBACK=1`.
    public let volume: Float
    public let volumeReason: String

    public init(protection: FileProtectionType = HarnessConfiguration.requiredProtection,
                interval: TimeInterval = 2, gapThreshold: TimeInterval = 5, summaryEvery: Int = 30,
                pendingLimit: Int = 2_000, environment: [String: String] = [:]) throws {
        guard protection == Self.requiredProtection else {
            throw HarnessError.protectionRefused(protection.rawValue)
        }
        guard interval > 0, gapThreshold > interval, summaryEvery > 0, pendingLimit > 0 else {
            throw HarnessError.invalidConfiguration(
                "interval \(interval) s, gap threshold \(gapThreshold) s, summary every \(summaryEvery), pending limit \(pendingLimit)")
        }
        self.protection = protection
        self.interval = interval
        self.gapThreshold = gapThreshold
        self.summaryEvery = summaryEvery
        self.pendingLimit = pendingLimit
        let selected = HarnessVolume.select(environment: environment)
        self.volume = selected.volume
        self.volumeReason = selected.reason
    }
}

/// How loud the harness plays its keep-alive tone (CLAUDE.md: test audio is quiet). The player's volume is 0.01 unless
/// `SYLVIA_AUDIBLE_PLAYBACK=1` is in the harness's environment, for a person's listening check; the player is never
/// muted (a muted player renders a different signal, G0.4), and the Mac's or phone's own volume is never touched.
public enum HarnessVolume {
    public static let environmentKey = "SYLVIA_AUDIBLE_PLAYBACK"
    public static let quiet: Float = 0.01

    public static func select(environment: [String: String]) -> (volume: Float, reason: String) {
        if environment[environmentKey] == "1" { return (1, "SYLVIA_AUDIBLE_PLAYBACK=1") }
        return (quiet, "test-volume")
    }
}

public enum HarnessError: Error, Equatable, CustomStringConvertible {
    case protectionRefused(String)
    case invalidConfiguration(String)
    case storeNotOpen
    case audio(String)
    case readBackDiffers(String)

    public var description: String {
        switch self {
        case .protectionRefused(let value):
            return "harness: protection class \(value) refused; the harness uses only \(HarnessConfiguration.requiredProtection.rawValue)"
        case .invalidConfiguration(let why): return "harness: invalid configuration: \(why)"
        case .storeNotOpen: return "harness: the library is not open"
        case .audio(let why): return "harness: audio: \(why)"
        case .readBackDiffers(let what): return "harness: read back differs: \(what)"
        }
    }
}
