import AVFoundation
import Foundation

/// The real engine: an AVQueuePlayer holding the current member and the next available one, so member boundaries
/// play without a gap. Pitch is preserved at every rate with the time-domain algorithm (suited to speech).
@MainActor
public final class AVQueuePlayerEngine: PlaybackEngine {
    public weak var delegate: (any PlaybackEngineDelegate)?
    public let player = AVQueuePlayer()
    public static let pitchAlgorithm: AVAudioTimePitchAlgorithm = .timeDomain
    /// Optional hook for analysis (attach an `AudioTap` to each new item; the Int is the member index). Never used
    /// by the product path.
    public var itemPreparer: ((AVPlayerItem, Int) -> Void)?

    private var entries: [(memberIndex: Int, item: AVPlayerItem)] = []
    private var observers: [any NSObjectProtocol] = []
    private var statusObservations: [NSKeyValueObservation] = []
    private var timeObserver: Any?
    private var desiredRate: Float = 1

    /// Media time between ticks. The service checkpoints at the first tick 4 s of media after the last checkpoint, so
    /// the gap is at most 4 s plus one tick interval plus main-thread latency. With 1 s ticks the soak test measured a
    /// 5,001 ms gap at 3x (over the 5 s crash-loss budget); 0.5 s leaves about half a second of margin.
    public static let tickIntervalSeconds: Double = 0.5

    /// `outputVolume`: the player's output volume (applied after decoding, the time-pitch stage and the analysis taps;
    /// the clock is unaffected). The default, and the product's setting, is full volume; the spike's tests and harness
    /// pass `SpikeAudioOutput.quietVolume` unless `SYLVIA_AUDIBLE_PLAYBACK=1`.
    public init(outputVolume: Float = 1) {
        player.volume = outputVolume
        player.actionAtItemEnd = .advance
        player.automaticallyWaitsToMinimizeStalling = false
        timeObserver = player.addPeriodicTimeObserver(forInterval: CMTime(seconds: Self.tickIntervalSeconds, preferredTimescale: 1_000),
                                                      queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { self?.delegate?.engineDidTick() }
        }
    }

    public var currentMemberIndex: Int? {
        guard let item = player.currentItem else { return nil }
        return entries.first { $0.item === item }?.memberIndex
    }

    public var currentSeconds: Double {
        let t = player.currentTime()
        return t.isNumeric ? t.seconds : 0
    }

    public var isPlaying: Bool { player.rate != 0 }

    /// The output volume (the harness's full-volume toggle changes it while playing).
    public var outputVolume: Float {
        get { player.volume }
        set { player.volume = newValue }
    }

    public var queuedMemberIndices: [Int] {
        let items = player.items()
        return entries.filter { e in items.contains { $0 === e.item } }.map(\.memberIndex)
    }

    /// Incremented by every `setQueue`, so a wait for an earlier queue ends as `.superseded`.
    private var queueGeneration = 0

    public func setQueue(_ items: [EngineItem], startSeconds: Double) async -> QueueOutcome {
        queueGeneration += 1
        let generation = queueGeneration
        player.pause()
        player.removeAllItems()
        entries.removeAll()
        observers.forEach(NotificationCenter.default.removeObserver)
        observers.removeAll()
        statusObservations.removeAll()
        for item in items { append(item) }
        guard let first = entries.first?.item else { return .failed("nothing to queue") }
        // Wait until the first item can be positioned, with no time limit: opening a long native FLAC or Ogg file
        // with precise timing takes time proportional to its length (review R3-01: a fixed 20 s limit reported a
        // valid 7-hour FLAC as undecodable). A decode or file error fails here through the item's own status.
        let opened = await Self.waitUntilReady(first) { [weak self] in self?.queueGeneration == generation }
        guard opened == .ready else { return opened }
        if startSeconds > 0 {
            let finished = await player.seek(to: CMTime(seconds: startSeconds, preferredTimescale: 1_000_000),
                                             toleranceBefore: .zero, toleranceAfter: .zero)
            guard queueGeneration == generation else { return .superseded }
            if !finished { return .failed("the seek to \(startSeconds) s did not complete") }
        }
        return queueGeneration == generation ? .ready : .superseded
    }

    public func append(_ entry: EngineItem) {
        // Opened with the member's timing mode (ADR-0006 decision 2): precise, or estimated for a proved-CBR MP3.
        let item = AVPlayerItem(asset: entry.timing.asset(entry.url))
        item.audioTimePitchAlgorithm = Self.pitchAlgorithm
        itemPreparer?(item, entry.memberIndex)
        entries.append((entry.memberIndex, item))
        let index = entry.memberIndex
        observers.append(NotificationCenter.default.addObserver(forName: AVPlayerItem.didPlayToEndTimeNotification, object: item, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { self?.delegate?.engine(didFinishMember: index) }
        })
        statusObservations.append(item.observe(\.status, options: [.new]) { [weak self] item, _ in
            guard item.status == .failed else { return }
            let message = item.error.map { "\($0.localizedDescription)" } ?? "decode error"
            DispatchQueue.main.async { MainActor.assumeIsolated { self?.delegate?.engine(didFailMember: index, message: message) } }
        })
        if player.canInsert(item, after: nil) { player.insert(item, after: nil) }
    }

    public func play(rate: Float) {
        desiredRate = rate
        player.defaultRate = rate
        player.playImmediately(atRate: rate)
    }

    public func pause() { player.pause() }

    public func setRate(_ rate: Float) {
        desiredRate = rate
        player.defaultRate = rate
        if player.rate != 0 { player.rate = rate }
    }

    public func seek(toSeconds seconds: Double) async -> Bool {
        await player.seek(to: CMTime(seconds: seconds, preferredTimescale: 1_000_000), toleranceBefore: .zero, toleranceAfter: .zero)
    }

    /// Waits until `item` is ready or failed, for as long as `current()` says the wait is still wanted (the queue or
    /// preview it belongs to has not been replaced) and the task is not cancelled. No time limit (review R3-01).
    static func waitUntilReady(_ item: AVPlayerItem, while current: () -> Bool) async -> QueueOutcome {
        while true {
            guard current(), !Task.isCancelled else { return .superseded }
            switch item.status {
            case .readyToPlay: return .ready
            case .failed: return .failed(item.error.map { "\($0.localizedDescription)" } ?? "decode error")
            default:
                do { try await Task.sleep(for: .milliseconds(20)) } catch { return .superseded }
            }
        }
    }
}

/// Plays a retained excerpt, or the source ranges of a pending excerpt, in its own AVQueuePlayer so the main queue
/// is never touched (plan 10.3). A cross-file pending capture plays as one queue: the first range from its start,
/// each later range from the start of its member, every item ending at its range end (`forwardPlaybackEndTime`).
@MainActor
public final class AVPreviewPlayer: PreviewPlayer {
    public let player = AVQueuePlayer()
    public var onFinish: (() -> Void)?
    /// Optional analysis hook, called for each item with its segment index. Never used by the product path.
    public var itemPreparer: ((AVPlayerItem, Int) -> Void)?
    /// The last item's own time when the preview reached its end (diagnostics: where the player says it stopped).
    public private(set) var lastFinishSeconds: Double?
    /// Why the last preview ended early, if it did (an item failed to open or decode).
    public private(set) var lastFailure: String?
    private var endObserver: (any NSObjectProtocol)?
    private var statusObservations: [NSKeyValueObservation] = []
    private var lastItem: AVPlayerItem?
    /// The preview playing now, segment by segment with its item (for `progress`).
    private var current: [(segment: PreviewSegment, item: AVPlayerItem)] = []
    /// Incremented by every `stop()` (and so by every `play`), so callbacks of an earlier preview are ignored.
    private var generation = 0

    /// `outputVolume`: as for `AVQueuePlayerEngine.init(outputVolume:)`; full volume by default.
    public init(outputVolume: Float = 1) {
        player.volume = outputVolume
        player.actionAtItemEnd = .advance
    }

    public var isPlaying: Bool { player.rate != 0 }

    public var outputVolume: Float {
        get { player.volume }
        set { player.volume = newValue }
    }

    /// Seconds played of this preview (the segments before the current one, plus the current item's time past its
    /// segment's start) and its total length. A segment without an end (a retained excerpt file) counts to its item's
    /// duration, so nil until that is known.
    public var progress: (elapsedSeconds: Double, durationSeconds: Double)? {
        guard endObserver != nil, !current.isEmpty else { return nil }
        var lengths: [Double] = []
        for (segment, item) in current {
            let end: Double
            if let e = segment.endSeconds {
                end = e
            } else {
                guard item.duration.isNumeric else { return nil }
                end = item.duration.seconds
            }
            lengths.append(max(0, end - segment.startSeconds))
        }
        let total = lengths.reduce(0, +)
        guard let item = player.currentItem, let k = current.firstIndex(where: { $0.item === item }) else { return (total, total) }
        let t = player.currentTime()
        let within = t.isNumeric ? min(max(0, t.seconds - current[k].segment.startSeconds), lengths[k]) : 0
        return (lengths[..<k].reduce(0, +) + within, total)
    }

    public func play(_ segments: [PreviewSegment]) async -> Bool {
        stop()
        lastFinishSeconds = nil
        lastFailure = nil
        guard PreviewSegment.isPlayable(segments) else { return false }
        let generation = self.generation
        var items: [AVPlayerItem] = []
        for (index, segment) in segments.enumerated() {
            let item = AVPlayerItem(asset: segment.timing.asset(segment.url))
            item.audioTimePitchAlgorithm = AVQueuePlayerEngine.pitchAlgorithm
            if let end = segment.endSeconds { item.forwardPlaybackEndTime = CMTime(seconds: end, preferredTimescale: 1_000_000) }
            itemPreparer?(item, index)
            guard player.canInsert(item, after: nil) else { stop(); return false }
            player.insert(item, after: nil)
            items.append(item)
            current.append((segment, item))
            // A range that cannot be played must not be skipped silently: end the preview instead.
            statusObservations.append(item.observe(\.status, options: [.new]) { [weak self] item, _ in
                guard item.status == .failed else { return }
                let message = item.error.map { "\($0.localizedDescription)" } ?? "item failed"
                DispatchQueue.main.async {
                    MainActor.assumeIsolated {
                        // Only for the preview still playing: a late callback from an earlier preview's item must
                        // not end a newer one.
                        guard let self, self.generation == generation, self.endObserver != nil else { return }
                        self.lastFailure = "segment \(index): \(message)"
                        let finish = self.onFinish
                        self.stop()
                        finish?()
                    }
                }
            })
        }
        guard let first = items.first, let last = items.last else { return false }
        lastItem = last
        endObserver = NotificationCenter.default.addObserver(forName: AVPlayerItem.didPlayToEndTimeNotification, object: last, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated {
                let finish = self?.onFinish
                self?.lastFinishSeconds = self?.lastItem?.currentTime().seconds
                self?.stop()
                finish?()
            }
        }
        // No time limit (review R3-01): a pending range in a long FLAC or Ogg file opens slowly but correctly. A
        // `stop()` (the preview was ended or replaced) ends the wait.
        let opened = await AVQueuePlayerEngine.waitUntilReady(first) { [weak self] in self?.generation == generation }
        guard opened == .ready else {
            if self.generation == generation {
                if case let .failed(message) = opened { lastFailure = "segment 0: \(message)" }
                stop()
            }
            return false
        }
        if segments[0].startSeconds > 0 {
            let finished = await player.seek(to: CMTime(seconds: segments[0].startSeconds, preferredTimescale: 1_000_000),
                                             toleranceBefore: .zero, toleranceAfter: .zero)
            guard self.generation == generation else { return false }
            guard finished else { stop(); return false }
        }
        player.playImmediately(atRate: 1)
        return true
    }

    public func stop() {
        player.pause()
        if let endObserver { NotificationCenter.default.removeObserver(endObserver) }
        endObserver = nil
        statusObservations.removeAll()
        generation += 1
        lastItem = nil
        current.removeAll()
        player.removeAllItems()
    }
}
