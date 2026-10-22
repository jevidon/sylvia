import Foundation

// Every decision point of the harness reads its inputs through these protocols, so the simulator, which cannot lock,
// can drive each state the device run goes through: unlocked, locked after the first unlock, and before the first
// unlock after a restart (`Tests/SimulatedDevice.swift`). The production implementations are in `HarnessFiles.swift`,
// `LibraryHarnessStore.swift`, `TonePlayer.swift` and, for UIKit and BackgroundTasks, the app target.

/// Wall-clock time for every timestamp and interval the harness records or decides on (gaps, time since boot).
@MainActor
public protocol HarnessClock: AnyObject {
    func now() -> Date
}

/// `UIApplication.isProtectedDataAvailable`: whether class-A data is available. It is false whenever a phone with a
/// passcode is locked, after the first unlock too, so it never decides whether class-C data can be used (plan 18.1,
/// A18): the harness records it with every attempt and tries its class-C writes whatever it says.
@MainActor
public protocol ProtectedDataSource: AnyObject {
    var isProtectedDataAvailable: Bool { get }
}

/// When the device last booted (`kern.boottime`), to tell a restart from a process that ended in the same boot.
@MainActor
public protocol BootTimeSource: AnyObject {
    func bootTime() -> Date?
}

/// The application's state as a word: active, inactive or background.
@MainActor
public protocol AppStateSource: AnyObject {
    var stateName: String { get }
}

/// The quiet tone that keeps the process running while the phone is locked (UIBackgroundModes audio).
@MainActor
public protocol KeepAlivePlayer: AnyObject {
    /// Starts playing at `volume` (0.01 unless SYLVIA_AUDIBLE_PLAYBACK=1); never mutes.
    func start(volume: Float) throws
    func stop()
    var isPlaying: Bool { get }
    /// Interruptions, resumptions and route changes, as words for the log.
    var onEvent: (@MainActor (String) -> Void)? { get set }
}

public enum SaveResult: String, Sendable, Equatable {
    case saved
    case alreadySaved = "already-saved"
}

public enum ReadBack: String, Sendable, Equatable {
    /// The capture is present once, with its exact quotation and note.
    case equal
    case differs
    case missing
}

/// What a full check of the library found.
public struct VerifyReport: Sendable, Equatable {
    public var acknowledged: Int
    public var libraryCaptures: Int
    public var integrity: [String]
    public var foreignKeyViolations: Int
    public var failures: [String]

    public init(acknowledged: Int, libraryCaptures: Int, integrity: [String], foreignKeyViolations: Int, failures: [String]) {
        self.acknowledged = acknowledged
        self.libraryCaptures = libraryCaptures
        self.integrity = integrity
        self.foreignKeyViolations = foreignKeyViolations
        self.failures = failures
    }

    /// Every acknowledged item present exactly once with its exact content, the database intact, no orphan rows.
    public var passed: Bool { failures.isEmpty && integrity == ["ok"] && foreignKeyViolations == 0 }
}

/// The class-C library under test: the G0.5 recovery spike's `LibraryStore`, with D17's class and durability.
@MainActor
public protocol HarnessStore: AnyObject {
    var isOpen: Bool { get }
    /// Opens the library, creating it for a new installation; returns the durability settings read back. A library
    /// that exists but cannot be read is an error: nothing is created, removed or replaced.
    func open() throws -> String
    func close()
    /// Commits capture `item` durably (the spike's `saveCapture`, WAL with synchronous=FULL and fullfsync).
    func save(item: Int) throws -> SaveResult
    func readBack(item: Int) throws -> ReadBack
    /// Checks that items 0..<acknowledged are present exactly once with exact content, and the database's integrity.
    func verify(acknowledged: Int) throws -> VerifyReport
}

/// The harness's log file (class C, appended and flushed line by line).
@MainActor
public protocol LogSink: AnyObject {
    func append(_ lines: [String]) throws
    func readTail(maxLines: Int) throws -> [String]
    var fileURL: URL { get }
}

/// Where every line also goes, whatever the log file can do: the unified system log, which keeps lines recorded
/// before the first unlock, when the class-C log file cannot be written.
@MainActor
public protocol LogMirror: AnyObject {
    func mirror(_ line: String)
}

/// The run's record (class C), read at the next launch to tell a restart from a stop or a crash.
@MainActor
public protocol SessionStore: AnyObject {
    /// `nil` when there is no record.
    func load() throws -> SessionRecord?
    func save(_ record: SessionRecord) throws
}

/// A class-A file whose readability tells whether the phone is locked (unreadable about 10 s after it locks).
@MainActor
public protocol CanaryProbe: AnyObject {
    /// Creates the canary unless it exists; true when it was created now.
    func ensureCreated() throws -> Bool
    func isReadable() -> Bool
}

/// A class-C file the harness rewrites and reads back on every attempt, besides the library.
@MainActor
public protocol FileProbe: AnyObject {
    /// Writes `text` with the class and reads it back; true when the bytes read are the bytes written.
    func writeAndRead(_ text: String) throws -> Bool
}

public struct ProtectionItem: Sendable, Equatable {
    public var name: String
    public var expected: String
    /// The class read back, `none-reported`, or `unreadable(<code>)`.
    public var actual: String
    public var matches: Bool

    public init(name: String, expected: String, actual: String, matches: Bool) {
        self.name = name
        self.expected = expected
        self.actual = actual
        self.matches = matches
    }
}

public struct ProtectionReport: Sendable, Equatable {
    public var items: [ProtectionItem]
    /// False in the iOS Simulator, whose readback is not faithful (G0.5 recovery finding F3): there the report is
    /// recorded but not evaluated.
    public var evaluated: Bool

    public init(items: [ProtectionItem], evaluated: Bool) {
        self.items = items
        self.evaluated = evaluated
    }

    public var mismatches: [ProtectionItem] { evaluated ? items.filter { !$0.matches } : [] }

    /// `ok`, `differs:<name>=<class>;...`, or `simulator-unverified`.
    public var compact: String {
        guard evaluated else { return "simulator-unverified" }
        let bad = mismatches
        if bad.isEmpty { return "ok" }
        return "differs:" + bad.map { "\($0.name)=\($0.actual)" }.joined(separator: ";")
    }

    /// `name=class` for every item, for the full report after a restart.
    public var detail: [(String, String)] { items.map { ($0.name, $0.actual) } }
}

/// Reads back the class of the harness's and the library's files and directories.
@MainActor
public protocol ProtectionInspector: AnyObject {
    /// `full` adds the directories, the installation record and the class-A canary to the files checked every attempt.
    func inspect(full: Bool) -> ProtectionReport
}

/// Asks iOS for a background refresh launch (BGAppRefreshTask): the only way the harness can be launched while no
/// one opens it, for example after a restart and before the first unlock. iOS decides whether and when it runs.
@MainActor
public protocol RefreshScheduler: AnyObject {
    /// Returns what happened, for the log.
    func schedule() -> String
}

/// Everything the controller reads or writes through.
@MainActor
public struct HarnessEnvironment {
    public var clock: any HarnessClock
    public var protectedData: any ProtectedDataSource
    public var bootTime: any BootTimeSource
    public var appState: any AppStateSource
    public var player: any KeepAlivePlayer
    public var store: any HarnessStore
    public var sink: any LogSink
    public var mirror: any LogMirror
    public var sessions: any SessionStore
    public var canary: any CanaryProbe
    public var probe: any FileProbe
    public var inspector: any ProtectionInspector
    public var scheduler: any RefreshScheduler
    /// "device" or "simulator", recorded at launch: protection results from the simulator are not evidence.
    public var platform: String

    public init(clock: any HarnessClock, protectedData: any ProtectedDataSource, bootTime: any BootTimeSource,
                appState: any AppStateSource, player: any KeepAlivePlayer, store: any HarnessStore, sink: any LogSink,
                mirror: any LogMirror, sessions: any SessionStore, canary: any CanaryProbe, probe: any FileProbe,
                inspector: any ProtectionInspector, scheduler: any RefreshScheduler, platform: String) {
        self.clock = clock
        self.protectedData = protectedData
        self.bootTime = bootTime
        self.appState = appState
        self.player = player
        self.store = store
        self.sink = sink
        self.mirror = mirror
        self.sessions = sessions
        self.canary = canary
        self.probe = probe
        self.inspector = inspector
        self.scheduler = scheduler
        self.platform = platform
    }
}
