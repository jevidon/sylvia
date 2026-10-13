import Foundation

/// Monotonic time source, injectable so checkpoint and listening-time rules are unit-testable.
public protocol PlaybackClock: Sendable {
    /// Seconds on a monotonic clock.
    func now() -> TimeInterval
}

public struct SystemPlaybackClock: PlaybackClock {
    public init() {}
    public func now() -> TimeInterval { ProcessInfo.processInfo.systemUptime }
}

/// Why a checkpoint was written (plan 10.1: every five seconds while playing and on pause, seek, interruption,
/// item change and lifecycle transitions).
public enum CheckpointReason: String, Codable, Sendable {
    case periodic, pause, seek, interruption, routeChange, itemChange, lifecycle, previewStart, reorder, blocked
    /// Another edition was loaded: the outgoing edition's last position (review R5-02).
    case editionChange
}

/// The persisted playback state of one edition. `last` and `furthest` are separate (plan 10.1); listening time
/// counts main playback only (plan 10.3).
public struct PlaybackCheckpoint: Codable, Equatable, Sendable {
    public var editionID: UUID
    public var timelineRevision: Int
    public var last: AudioPoint
    public var lastGlobalMs: Int64
    public var furthest: AudioPoint
    public var furthestGlobalMs: Int64
    public var listenedMs: Int64
    public var reason: CheckpointReason
}

@MainActor
public protocol PositionStore: AnyObject {
    func save(_ checkpoint: PlaybackCheckpoint) throws
    func load(editionID: UUID) throws -> PlaybackCheckpoint?
}

/// Keeps every write, so tests can check when and why checkpoints happened.
@MainActor
public final class InMemoryPositionStore: PositionStore {
    public private(set) var history: [PlaybackCheckpoint] = []
    public var failWrites = false
    public init() {}
    public func save(_ checkpoint: PlaybackCheckpoint) throws {
        if failWrites { throw DurableFileError.write(path: "memory", errno: 28) }
        history.append(checkpoint)
    }
    public func load(editionID: UUID) throws -> PlaybackCheckpoint? { history.last { $0.editionID == editionID } }
}

/// One durable JSON file per edition.
@MainActor
public final class FilePositionStore: PositionStore {
    public let directory: URL
    public init(directory: URL) { self.directory = directory }
    private func url(_ id: UUID) -> URL { directory.appendingPathComponent("position-\(id.uuidString).json") }
    public func save(_ checkpoint: PlaybackCheckpoint) throws {
        try DurableFile.write(try JSONEncoder().encode(checkpoint), to: url(checkpoint.editionID))
    }
    public func load(editionID: UUID) throws -> PlaybackCheckpoint? {
        guard let data = try? Data(contentsOf: url(editionID)) else { return nil }
        return try JSONDecoder().decode(PlaybackCheckpoint.self, from: data)
    }
}

/// The audio session as the playback service needs it. Only `PlaybackService.play` and preview activate it (plan
/// 10.1: importing a book must not interrupt another app's audio), and the service releases it when playback stops
/// for good, so an app whose audio playback interrupted is told it may resume (review R2-06).
@MainActor
public protocol AudioSessionControlling: AnyObject {
    func activateForPlayback() throws
    /// Deactivates the session with `.notifyOthersOnDeactivation`. Called after a user pause, the end of a preview
    /// that does not resume main playback, the end of the edition and a stop at a blocked segment; never after an
    /// interruption (the system has already deactivated it) or the loss of the output device (another app must not
    /// start on the speaker).
    func deactivateAfterPlayback() throws
}

/// A queue item for the engine: which member, which file, and how to open it (the member's timing mode).
public struct EngineItem: Equatable, Sendable {
    public var memberIndex: Int
    public var url: URL
    public var timing: AssetTiming
    public init(memberIndex: Int, url: URL, timing: AssetTiming = .precise) {
        self.memberIndex = memberIndex
        self.url = url
        self.timing = timing
    }
}

@MainActor
public protocol PlaybackEngineDelegate: AnyObject {
    /// The engine finished `memberIndex` and moved to the next queued item, if any.
    func engine(didFinishMember memberIndex: Int)
    func engine(didFailMember memberIndex: Int, message: String)
    /// Periodic progress while playing (every `AVQueuePlayerEngine.tickIntervalSeconds`, 0.5 s, of media time).
    func engineDidTick()
}

/// How replacing the engine's queue ended.
public enum QueueOutcome: Equatable, Sendable {
    /// The first item is ready and positioned.
    case ready
    /// The first item failed to open or decode (the message is the system's), or the positioning seek failed.
    case failed(String)
    /// A later `setQueue` replaced this queue (or the waiting task was cancelled) before it was ready. Not an error:
    /// whoever replaced it owns the state now.
    case superseded
}

/// The media player under the playback service. The real one wraps AVQueuePlayer; tests use a deterministic fake.
@MainActor
public protocol PlaybackEngine: AnyObject {
    var delegate: (any PlaybackEngineDelegate)? { get set }
    /// Replaces the queue and positions the first item at `startSeconds` (zero-tolerance seek). Waits for the first
    /// item with no time limit: with precise timing, opening a native FLAC or Ogg file takes time proportional to its
    /// length (tens of seconds for a 10-hour FLAC on the simulator; review R3-01), so only the system's own failure
    /// is a failure. A slow open is reported by the service as `.preparing`, never as a decode error.
    func setQueue(_ items: [EngineItem], startSeconds: Double) async -> QueueOutcome
    func append(_ item: EngineItem)
    func play(rate: Float)
    func pause()
    func setRate(_ rate: Float)
    /// Zero-tolerance seek inside the current item.
    func seek(toSeconds seconds: Double) async -> Bool
    var currentMemberIndex: Int? { get }
    var currentSeconds: Double { get }
    var isPlaying: Bool { get }
    var queuedMemberIndices: [Int] { get }
}

/// One piece of a preview: a file and the part of it to play (to its end when `endSeconds` is nil), opened with the
/// file's timing mode (a pending source range uses its member's; a retained excerpt is an AAC file, precise).
public struct PreviewSegment: Equatable, Sendable {
    public var url: URL
    public var startSeconds: Double
    public var endSeconds: Double?
    public var timing: AssetTiming
    public init(url: URL, startSeconds: Double = 0, endSeconds: Double? = nil, timing: AssetTiming = .precise) {
        self.url = url
        self.startSeconds = startSeconds
        self.endSeconds = endSeconds
        self.timing = timing
    }

    /// A preview plays its segments back to back. Every segment after the first must start at 0: the source ranges
    /// of a cross-file capture always do (each later range starts at the beginning of the next member), and a later
    /// segment that starts elsewhere cannot be positioned before it becomes current without an audible jump.
    public static func isPlayable(_ segments: [PreviewSegment]) -> Bool {
        guard let first = segments.first, first.startSeconds >= 0 else { return false }
        return segments.dropFirst().allSatisfy { $0.startSeconds == 0 }
            && segments.allSatisfy { s in s.endSeconds.map { $0 > s.startSeconds } ?? true }
    }
}

/// Plays a retained excerpt, or the source ranges of a pending excerpt (several files for a cross-file capture),
/// for capture preview (plan 10.3).
@MainActor
public protocol PreviewPlayer: AnyObject {
    var onFinish: (() -> Void)? { get set }
    /// Plays the segments in order; `onFinish` runs when the last one reaches its end.
    func play(_ segments: [PreviewSegment]) async -> Bool
    func stop()
    var isPlaying: Bool { get }
    /// Seconds of the preview played so far and its total length (the sum of its segments), for Now Playing while a
    /// preview runs; nil when nothing is previewed or the length is not known yet.
    var progress: (elapsedSeconds: Double, durationSeconds: Double)? { get }
}
