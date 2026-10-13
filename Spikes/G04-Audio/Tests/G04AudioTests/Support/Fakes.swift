import Foundation
@testable import G04AudioKit

/// A clock the test moves by hand.
final class ManualClock: PlaybackClock, @unchecked Sendable {
    private let lock = NSLock()
    private var t: TimeInterval = 1_000
    func now() -> TimeInterval { lock.withLock { t } }
    func advance(_ dt: TimeInterval) { lock.withLock { t += dt } }
}

@MainActor
final class SpySession: AudioSessionControlling {
    private(set) var activations = 0
    private(set) var deactivations = 0
    /// "activate" and "deactivate", in order.
    private(set) var events: [String] = []
    var failNext = false
    var failNextDeactivation = false
    func activateForPlayback() throws {
        if failNext { failNext = false; throw DurableFileError.write(path: "session", errno: 1) }
        activations += 1
        events.append("activate")
    }
    func deactivateAfterPlayback() throws {
        if failNextDeactivation { failNextDeactivation = false; throw DurableFileError.write(path: "session", errno: 16) }
        deactivations += 1
        events.append("deactivate")
    }
    /// Whether the last event left the session active.
    var isActive: Bool { events.last == "activate" }
}

/// A deterministic stand-in for AVQueuePlayer: a queue of member items, a media position that advances with the
/// manual clock at the current rate, end-of-item advance, and a tick each time the item's time reaches a multiple of
/// `AVQueuePlayerEngine.tickIntervalSeconds` (0.5 s), as the real engine's periodic time observer fires at multiples of
/// its interval of player time. The fake delivers each tick exactly at the multiple (the real one adds main-thread
/// latency: 4,501 ms was the largest checkpoint gap in the soak test).
@MainActor
final class FakeEngine: PlaybackEngine {
    weak var delegate: (any PlaybackEngineDelegate)?
    let durations: [Int: Double]
    private(set) var queue: [EngineItem] = []
    private(set) var position: Double = 0
    private(set) var playing = false
    private(set) var rate: Float = 1
    private(set) var visited: [Int] = []
    /// The real engine's tick interval (media seconds).
    static let tickInterval = AVQueuePlayerEngine.tickIntervalSeconds
    var failMember: Int?
    /// When true, the end-of-item callback arrives before the queue advances (what AVQueuePlayer does, found by the
    /// real-engine boundary test); when false, after.
    var notifiesBeforeAdvancing = true
    /// Wall seconds of stall still to come: while playing, the media position stands still (no ticks) until this
    /// is used up, as AVPlayer does during a slow first seek or while buffering (review R2-02).
    var stallSeconds: Double = 0

    init(durations: [Int: Double]) { self.durations = durations }

    var currentMemberIndex: Int? { queue.first?.memberIndex }
    var currentSeconds: Double { position }
    var isPlaying: Bool { playing }
    var queuedMemberIndices: [Int] { queue.map(\.memberIndex) }

    /// When true, `setQueue` waits until the test calls `finishOpening` (a slow open: a long native FLAC or Ogg file
    /// with precise timing, review R3-01), or until a later `setQueue` supersedes it.
    var holdsOpening = false
    private var pendingOpen: CheckedContinuation<QueueOutcome, Never>?
    /// Whether a `setQueue` call is waiting for `finishOpening`.
    var isOpening: Bool { pendingOpen != nil }

    func setQueue(_ items: [EngineItem], startSeconds: Double) async -> QueueOutcome {
        // A new queue supersedes one still opening, as AVQueuePlayerEngine does.
        pendingOpen?.resume(returning: .superseded)
        pendingOpen = nil
        playing = false
        queue = items
        position = startSeconds
        if holdsOpening {
            let outcome = await withCheckedContinuation { pendingOpen = $0 }
            guard outcome == .ready else {
                if case .failed = outcome { queue = [] }
                return outcome
            }
        }
        if let f = failMember, items.first?.memberIndex == f { queue = []; return .failed("could not open member") }
        if let i = items.first?.memberIndex, visited.last != i { visited.append(i) }
        return .ready
    }

    /// Ends the open that `setQueue` is waiting for (with `holdsOpening`).
    func finishOpening(_ outcome: QueueOutcome = .ready) {
        let c = pendingOpen
        pendingOpen = nil
        c?.resume(returning: outcome)
    }

    func append(_ item: EngineItem) { queue.append(item) }
    /// Simulates AVPlayerItem.status == .failed for a queued member.
    func failQueued(_ memberIndex: Int) {
        queue.removeAll { $0.memberIndex == memberIndex }
        delegate?.engine(didFailMember: memberIndex, message: "simulated decode failure")
    }
    func play(rate: Float) { self.rate = rate; playing = !queue.isEmpty }
    func pause() { playing = false }
    func setRate(_ rate: Float) { self.rate = rate }
    func seek(toSeconds seconds: Double) async -> Bool { position = seconds; return true }

    /// Moves wall time forward in steps of at most 50 ms, playing at the current rate. Within a step the media advances
    /// continuously: the clock and the position stop exactly where a tick or the end of the item falls, the event is
    /// delivered there, and the rest of the step follows.
    func run(_ seconds: Double, clock: ManualClock) {
        let step = 0.05, eps = 1e-9
        var remaining = seconds
        while remaining > eps {
            var dt = min(step, remaining)
            remaining -= dt
            while dt > eps {
                guard playing, let current = queue.first else {
                    clock.advance(dt)
                    break
                }
                if stallSeconds > eps {
                    let s = min(stallSeconds, dt)
                    stallSeconds -= s
                    clock.advance(s)
                    dt -= s
                    continue
                }
                let r = Double(rate)
                let duration = durations[current.memberIndex] ?? .infinity
                let nextTick = ((position / Self.tickInterval + eps).rounded(.down) + 1) * Self.tickInterval
                let toTick = (nextTick - position) / r, toEnd = (duration - position) / r
                let advance = max(0, min(dt, toTick, toEnd))
                clock.advance(advance)
                position += advance * r
                dt -= advance
                if toEnd <= toTick, advance >= toEnd - eps {
                    position = duration
                    finishItem(current)
                } else if advance >= toTick - eps {
                    position = nextTick
                    delegate?.engineDidTick()
                }
            }
        }
    }

    /// The end of the current item: AVQueuePlayer posts didPlayToEndTime while the finished item is still current
    /// (`notifiesBeforeAdvancing`), then moves to the next item.
    private func finishItem(_ current: EngineItem) {
        if notifiesBeforeAdvancing { delegate?.engine(didFinishMember: current.memberIndex) }
        // The service may have replaced the queue or paused meanwhile; advance only the item that finished.
        if queue.first == current {
            queue.removeFirst()
            if let next = queue.first {
                position = 0
                visited.append(next.memberIndex)
            } else {
                playing = false
            }
        }
        if !notifiesBeforeAdvancing { delegate?.engine(didFinishMember: current.memberIndex) }
    }
}

@MainActor
final class FakePreview: PreviewPlayer {
    var onFinish: (() -> Void)?
    private(set) var isPlaying = false
    private(set) var played: [[PreviewSegment]] = []
    /// What `progress` reports while playing (tests set it).
    var fakeProgress: (elapsedSeconds: Double, durationSeconds: Double)?
    var progress: (elapsedSeconds: Double, durationSeconds: Double)? { isPlaying ? fakeProgress : nil }
    func play(_ segments: [PreviewSegment]) async -> Bool {
        played.append(segments)
        isPlaying = true
        return true
    }
    func stop() { isPlaying = false }
    func finish() {
        isPlaying = false
        onFinish?()
    }
}

/// A multi-member edition (by default three members of 60 s, 90 s and 30 s) with the given members missing.
@MainActor
struct TestEdition {
    let ids: [UUID]
    let durations: [Double]
    let timeline: EditionTimeline
    let missing: Set<Int>

    init(missing: Set<Int> = [], durations: [Double] = [60, 90, 30]) throws {
        self.missing = missing
        self.durations = durations
        ids = durations.map { _ in UUID() }
        timeline = try EditionTimeline(editionID: UUID(), members: zip(ids, durations).enumerated().map {
            EditionMember(assetID: $1.0, fileName: "part\($0 + 1).mp3", durationMs: Int64($1.1 * 1000))
        })
    }

    var resolver: @Sendable (UUID) -> URL? {
        let ids = ids, missing = missing
        return { id in
            guard let i = ids.firstIndex(of: id), !missing.contains(i) else { return nil }
            return URL(fileURLWithPath: "/fake/part\(i + 1).mp3")
        }
    }

    var engineDurations: [Int: Double] { Dictionary(uniqueKeysWithValues: durations.enumerated().map { ($0, $1) }) }
}

/// Builds a service over fakes.
@MainActor
struct Harness {
    let clock = ManualClock()
    let engine: FakeEngine
    let preview = FakePreview()
    let session = SpySession()
    let store: any PositionStore
    let service: PlaybackService
    let edition: TestEdition

    /// `missing`: members not on this device (the resolver returns nil). `deletedFiles`: members the library lists
    /// as on this device whose file is gone.
    init(missing: Set<Int> = [], deletedFiles: Set<Int> = [], store: (any PositionStore)? = nil,
         durations: [Double] = [60, 90, 30]) throws {
        edition = try TestEdition(missing: missing, durations: durations)
        engine = FakeEngine(durations: edition.engineDurations)
        self.store = store ?? InMemoryPositionStore()
        let deletedNames = Set(deletedFiles.map { "part\($0 + 1).mp3" })
        service = PlaybackService(engine: engine, previewPlayer: preview, session: session, positions: self.store, clock: clock,
                                  fileExists: { !deletedNames.contains($0.lastPathComponent) })
    }

    func load(chapters: [UUID: [ChapterInfo]] = [:]) async {
        await service.load(timeline: edition.timeline, chapters: chapters, resolveFile: edition.resolver)
    }

    func run(_ seconds: Double) { engine.run(seconds, clock: clock) }
    var memory: InMemoryPositionStore { store as! InMemoryPositionStore }
}
