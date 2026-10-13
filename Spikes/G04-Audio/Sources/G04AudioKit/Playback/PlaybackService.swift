import Foundation
import Observation

/// A chapter on the global timeline of an edition.
public struct TimelineChapter: Equatable, Sendable {
    public var title: String
    public var startGlobalMs: Int64
    public var endGlobalMs: Int64
}

/// The single application-owned playback service (plan 10.1). It owns the edition timeline, the queue of member
/// files, position checkpoints, interruption policy and capture preview. Canonical positions are file-local
/// (`AudioPoint`); global milliseconds are derived from the current timeline revision for display and seeking.
@MainActor
@Observable
public final class PlaybackService: PlaybackEngineDelegate {
    public enum Status: Equatable, Sendable {
        case idle
        case paused
        case playing
        /// The member at the current position is being opened and positioned (load, a seek into another member, a
        /// reorder, the return from a preview). Not an error and with no time limit: with precise timing, opening a
        /// long native FLAC or Ogg file takes time proportional to its length (review R3-01). `play()` meanwhile
        /// records the wish to play, and playback starts when the member is ready.
        case preparing(memberIndex: Int)
        /// The member at the current position is not on this device (its source is unavailable); only its segment
        /// is blocked (plan 10.1).
        case segmentUnavailable(memberIndex: Int)
        /// The member's file should be here but is not, or it cannot be decoded (plan 10.1 error states).
        case failed(memberIndex: Int, PlaybackFailure)
    }

    public enum PlaybackFailure: Equatable, Sendable {
        /// The library says the file is on this device, but it is gone.
        case missingFile
        /// The file is present but the system cannot open or decode it.
        case decodeError(String)
    }

    public enum Mode: Equatable, Sendable { case main, preview }

    public enum PauseReason: Sendable { case user, interruption, routeChange }

    /// What preview saved and restores (plan 10.3).
    public struct MainContext: Equatable, Sendable {
        public var point: AudioPoint
        public var wasPlaying: Bool
        public var rate: Float
    }

    /// Periodic checkpoints: every 5 s of wall time (plan 10.1) and, at fast rates, every 4 s of media time. The
    /// player ticks every 0.5 s of media time (`AVQueuePlayerEngine.tickIntervalSeconds`), so a checkpoint is written
    /// at most 4.5 s of media after the last one, under the 5 s budget even at 3x, where five wall seconds would be
    /// 15 s of book (ADR-0006 decision 8).
    public static let checkpointIntervalSeconds: TimeInterval = 5
    public static let checkpointIntervalMediaMs: Int64 = 4_000
    public static let rateRange: ClosedRange<Float> = 0.5...3.0
    public static let skipSeconds: Double = 15
    /// Within this many seconds of a chapter start, "previous chapter" goes to the chapter before.
    public static let previousChapterThresholdMs: Int64 = 3_000
    /// Furthest position (plan 10.1, 12): main playback is observed as contiguous listening runs. A run that starts
    /// at or behind the frontier (within `frontierToleranceMs`) moves the frontier as it plays past it. A run that
    /// starts ahead of the frontier (after a forward seek, skip or chapter jump) becomes the frontier once it has been
    /// listened to contiguously for `frontierAdoptionMs` of media time; a jump alone, or a few seconds of listening
    /// after it (seek-to-end, T28), never moves it.
    public static let frontierToleranceMs: Int64 = 1_500
    public static let frontierAdoptionMs: Int64 = 30_000

    // Dependencies
    @ObservationIgnored private let engine: any PlaybackEngine
    @ObservationIgnored private let previewPlayer: any PreviewPlayer
    @ObservationIgnored private let session: any AudioSessionControlling
    @ObservationIgnored private let positions: any PositionStore
    @ObservationIgnored private let clock: any PlaybackClock
    @ObservationIgnored private var resolveFile: (UUID) -> URL? = { _ in nil }
    @ObservationIgnored private var memberChapters: [UUID: [ChapterInfo]] = [:]

    // State
    public private(set) var timeline: EditionTimeline?
    public private(set) var chapters: [TimelineChapter] = []
    public private(set) var status: Status = .idle
    public private(set) var mode: Mode = .main
    public private(set) var rate: Float = 1
    public private(set) var furthestGlobalMs: Int64 = 0
    public private(set) var listenedMs: Int64 = 0
    public private(set) var lastCheckpointError: String?
    /// The last audio session deactivation error, if the last release failed.
    public private(set) var lastSessionError: String?
    /// Whether this service has activated the audio session and not released it since (an interruption counts as a
    /// release: the system deactivates the session when it begins).
    @ObservationIgnored public private(set) var sessionActive = false
    /// Position while the engine has no current item (blocked, idle or before load).
    @ObservationIgnored private var parkedPoint: AudioPoint?
    @ObservationIgnored private var furthestPoint: AudioPoint?
    @ObservationIgnored private var lastCheckpointGlobalMs: Int64 = 0
    @ObservationIgnored private var lastCheckpointTime: TimeInterval = 0
    @ObservationIgnored private var lastTickGlobalMs: Int64?
    @ObservationIgnored private var lastTickTime: TimeInterval?
    @ObservationIgnored private var listenedRemainder: TimeInterval = 0
    /// The current contiguous listening run: where it started (global ms) and how much media time of it was played.
    @ObservationIgnored private var runStartGlobalMs: Int64 = 0
    @ObservationIgnored private var runListenedMediaMs: Int64 = 0
    @ObservationIgnored private var resumeAfterInterruption = false
    /// Whether main playback should run once the member being prepared is ready: the user pressed play while it was
    /// opening, or it was playing when a seek or reorder replaced the queue. Cleared by any pause.
    @ObservationIgnored public private(set) var playWhenReady = false
    /// Incremented by every `position(at:)`, so an earlier positioning that a later one replaced changes nothing.
    @ObservationIgnored private var positionGeneration = 0
    /// Members found missing or undecodable while queued ahead of the current one.
    @ObservationIgnored private var failedMembers: [Int: PlaybackFailure] = [:]
    @ObservationIgnored public private(set) var savedMainContext: MainContext?

    @ObservationIgnored private let fileExists: (URL) -> Bool

    /// `fileExists` is injectable so tests over a fake engine can use placeholder URLs.
    public init(engine: any PlaybackEngine, previewPlayer: any PreviewPlayer, session: any AudioSessionControlling,
                positions: any PositionStore, clock: any PlaybackClock = SystemPlaybackClock(),
                fileExists: @escaping (URL) -> Bool = { FileManager.default.fileExists(atPath: $0.path) }) {
        self.engine = engine
        self.previewPlayer = previewPlayer
        self.session = session
        self.positions = positions
        self.clock = clock
        self.fileExists = fileExists
        engine.delegate = self
    }

    // MARK: Loading

    /// Loads an edition. `resolveFile` maps a member's asset ID to its local file, or nil when the member is not on
    /// this device. Resumes from the stored checkpoint when there is one. Never activates the audio session; if another
    /// edition was loaded, whatever it was playing (main playback or a capture preview) stops first
    /// (`leaveCurrentEdition`).
    public func load(timeline: EditionTimeline, chapters memberChapters: [UUID: [ChapterInfo]] = [:],
                     resolveFile: @escaping (UUID) -> URL?) async {
        leaveCurrentEdition()
        self.timeline = timeline
        self.resolveFile = resolveFile
        self.memberChapters = memberChapters
        self.chapters = Self.globalChapters(timeline, memberChapters)
        status = .idle
        mode = .main
        savedMainContext = nil
        resumeAfterInterruption = false
        playWhenReady = false
        failedMembers = [:]
        lastTickGlobalMs = nil
        lastTickTime = nil
        var start = AudioPoint(assetID: timeline.members[0].assetID, ms: 0)
        furthestPoint = start
        furthestGlobalMs = 0
        listenedMs = 0
        if let saved = try? positions.load(editionID: timeline.editionID) {
            if (try? timeline.globalMs(of: saved.last)) != nil { start = saved.last }
            if let g = try? timeline.globalMs(of: saved.furthest) {
                furthestPoint = saved.furthest
                furthestGlobalMs = g
            }
            listenedMs = saved.listenedMs
        }
        // A seek, reorder or another load while the member opens replaces this positioning; it then owns the state.
        guard await position(at: start) != .superseded else { return }
        if status == .idle { status = .paused }
        let g = currentGlobalMs
        startRun(at: g)
        lastCheckpointGlobalMs = g
        lastCheckpointTime = clock.now()
        // Play was pressed while the member was opening.
        if playWhenReady {
            playWhenReady = false
            play()
        }
    }

    /// Ends the loaded edition before another one is loaded (ADR-0006 decision 16; review R5-02). Whatever played is
    /// over: a capture preview stops (its player would otherwise keep playing over the new edition, with the audio
    /// session released under it), and main playback stops with its listening counted. The outgoing edition's last
    /// checkpoint is then written at its main point (the saved main context during a preview, which never changes
    /// progress), so it resumes where its listener left it, and the session is released.
    private func leaveCurrentEdition() {
        var outgoing: AudioPoint?
        if mode == .preview {
            previewPlayer.onFinish = nil
            previewPlayer.stop()
            mode = .main
            outgoing = savedMainContext?.point
            savedMainContext = nil
        } else {
            haltMain()
            outgoing = currentPoint
        }
        engine.pause()
        playWhenReady = false
        if let outgoing { checkpoint(.editionChange, at: outgoing) }
        releaseSession()
    }

    /// Whether main playback is running or will start as soon as the member being prepared is ready.
    public var isPlayingOrStarting: Bool {
        if status == .playing { return true }
        if case .preparing = status { return playWhenReady }
        return false
    }

    public var isPreparing: Bool {
        if case .preparing = status { return true }
        return false
    }

    // MARK: Position

    public var currentPoint: AudioPoint? {
        guard let timeline else { return nil }
        if let i = engine.currentMemberIndex, i < timeline.members.count, parkedPoint == nil {
            let ms = Int64((engine.currentSeconds * 1000).rounded())
            return AudioPoint(assetID: timeline.members[i].assetID, ms: min(max(ms, 0), timeline.members[i].durationMs))
        }
        return parkedPoint
    }

    public var currentGlobalMs: Int64 {
        guard let timeline, let p = currentPoint, let g = try? timeline.globalMs(of: p) else { return 0 }
        return g
    }

    public var currentChapterIndex: Int? {
        let g = currentGlobalMs
        return chapters.lastIndex { $0.startGlobalMs <= g }
    }

    // MARK: Transport

    public func play() {
        guard timeline != nil, mode == .main else { return }
        resumeAfterInterruption = false
        if case .preparing = status {
            // The member is still opening: remember the wish; playback starts when it is ready. The audio session is
            // not activated yet, so another app keeps playing until there is audio to play.
            playWhenReady = true
            return
        }
        if case .segmentUnavailable = status { return }
        if case .failed = status { return }
        // Nothing is queued (for example after the end of the edition): never claim playback.
        guard parkedPoint == nil, engine.currentMemberIndex != nil else { return }
        guard activateSession() else { return }
        lastTickGlobalMs = currentGlobalMs
        lastTickTime = clock.now()
        engine.play(rate: rate)
        status = .playing
    }

    /// Pauses main playback. A user pause also releases the audio session (other apps are told they may resume); a
    /// pause for an interruption or a lost output device does not (review R2-06). During a preview a user pause (from the
    /// app, headphones, the Lock Screen or Control Center) stops the preview instead (`stopPreview`, review R4-03).
    public func pause(reason: PauseReason = .user) {
        if mode == .preview {
            if reason == .user { stopPreview() }
            return
        }
        pauseMain(reason, releasingSession: reason == .user)
    }

    private func pauseMain(_ reason: PauseReason, releasingSession: Bool) {
        guard mode == .main else { return }
        if reason == .user { resumeAfterInterruption = false }
        playWhenReady = false  // a pause while the member opens cancels the wish to play
        haltMain()
        switch reason {
        case .user: checkpoint(.pause)
        case .interruption: checkpoint(.interruption)
        case .routeChange: checkpoint(.routeChange)
        }
        if releasingSession { releaseSession() }
    }

    private func activateSession() -> Bool {
        do {
            try session.activateForPlayback()
        } catch {
            lastCheckpointError = "audio session: \(error)"
            return false
        }
        sessionActive = true
        return true
    }

    /// Deactivates the session (notifying other apps) when this service holds it. A failure is recorded, not
    /// retried: the next `play()` activates it again either way.
    private func releaseSession() {
        guard sessionActive else { return }
        sessionActive = false
        do {
            try session.deactivateAfterPlayback()
            lastSessionError = nil
        } catch {
            lastSessionError = "\(error)"
        }
    }

    /// Stops main playback and accounts the listening up to now, without writing a checkpoint.
    private func haltMain() {
        let wasPlaying = status == .playing
        if wasPlaying { accountProgress() }
        engine.pause()
        if wasPlaying { status = .paused }
        lastTickTime = nil
    }

    /// Play/pause. During a preview it stops the preview (the preview is what is playing; review R4-03).
    public func togglePlayPause() {
        if mode == .preview {
            stopPreview()
            return
        }
        isPlayingOrStarting ? pause() : play()
    }

    /// Seeks on the global timeline (zero tolerance). A seek never advances the furthest position itself; it starts a
    /// new listening run (see `frontierAdoptionMs`).
    public func seek(toGlobalMs target: Int64) async {
        guard let timeline, mode == .main else { return }
        if status == .playing { accountProgress() }
        let clamped = min(max(target, 0), timeline.durationMs)
        let wasPlaying = isPlayingOrStarting
        guard let located = try? timeline.locate(globalMs: clamped) else { return }
        if engine.currentMemberIndex == located.memberIndex, parkedPoint == nil, !isPreparing {
            _ = await engine.seek(toSeconds: Double(located.point.ms) / 1000)
        } else {
            // Replacing the queue leaves the engine paused while the member opens; playback resumes below when it is
            // ready, unless the user paused meanwhile (which clears `playWhenReady`).
            playWhenReady = wasPlaying
            guard await position(at: located.point) != .superseded else { return }
        }
        lastTickGlobalMs = currentGlobalMs
        lastTickTime = clock.now()
        startRun(at: currentGlobalMs)
        var stoppedAtBlock = false
        if wasPlaying {
            switch status {
            case .playing: if !engine.isPlaying { engine.play(rate: rate) }
            case .paused:
                // The new member is ready (it was opened by `position(at:)`). Resume unless paused meanwhile.
                if playWhenReady { resumeEngine() }
            default:
                engine.pause()  // the target segment is unavailable or failed: never claim playback
                stoppedAtBlock = true
            }
        }
        playWhenReady = false
        checkpoint(.seek)
        if stoppedAtBlock { releaseSession() }
    }

    /// Starts the engine after a member was (re)opened: without a new activation when the session is still held
    /// (a seek or reorder while playing), otherwise through `play()`.
    private func resumeEngine() {
        playWhenReady = false
        guard sessionActive else {
            play()
            return
        }
        lastTickGlobalMs = currentGlobalMs
        lastTickTime = clock.now()
        engine.play(rate: rate)
        status = .playing
    }

    public func skip(bySeconds seconds: Double) async {
        await seek(toGlobalMs: currentGlobalMs + Int64(seconds * 1000))
    }

    public func setRate(_ newRate: Float) {
        guard mode == .main else { return }  // preview plays at 1x; the main rate is restored with the context
        let r = min(max(newRate, Self.rateRange.lowerBound), Self.rateRange.upperBound)
        if status == .playing { accountProgress() }
        rate = r
        engine.setRate(r)
    }

    public func nextChapter() async {
        guard let i = currentChapterIndex, i + 1 < chapters.count else { return }
        await seek(toGlobalMs: chapters[i + 1].startGlobalMs)
    }

    public func previousChapter() async {
        guard let i = currentChapterIndex else { return }
        let g = currentGlobalMs
        if g - chapters[i].startGlobalMs > Self.previousChapterThresholdMs || i == 0 {
            await seek(toGlobalMs: chapters[i].startGlobalMs)
        } else {
            await seek(toGlobalMs: chapters[i - 1].startGlobalMs)
        }
    }

    /// Applies a confirmed new member order: a new timeline revision. The current position and the furthest
    /// position stay on the same file-local points; their global values are recomputed (plan 10.1).
    public func reorder(_ order: [UUID]) async throws {
        guard let timeline else { return }
        let point = currentPoint
        let wasPlaying = isPlayingOrStarting
        let next = try timeline.reordered(order)
        // Playback continues after the reorder, so the session is kept (releasing it would let another app start).
        if wasPlaying { pauseMain(.user, releasingSession: false) }
        self.timeline = next
        failedMembers = [:]  // indices refer to the old order; position(at:) finds failures again
        self.chapters = Self.globalChapters(next, memberChapters)
        if let fp = furthestPoint, let g = try? next.globalMs(of: fp) { furthestGlobalMs = g }
        // Recorded before opening, so a seek that replaces this positioning knows playback should continue, and a
        // pause while the member opens cancels it.
        playWhenReady = wasPlaying
        if let point { guard await position(at: point) != .superseded else { return } }
        // Global positions changed meaning: the run continues from the same file-local point, renumbered. Whether it
        // started behind the frontier is re-judged in the new order; the listened media time is kept.
        let listened = runListenedMediaMs
        startRun(at: currentGlobalMs)
        runListenedMediaMs = listened
        checkpoint(.reorder)
        if playWhenReady {
            playWhenReady = false
            play()
        }
    }

    // MARK: Lifecycle and audio session events

    public enum LifecycleEvent: Sendable { case willResignActive, didEnterBackground, willTerminate }

    public func handleLifecycle(_ event: LifecycleEvent) {
        if status == .playing { accountProgress() }
        checkpoint(.lifecycle)
    }

    /// The system began an interruption (call, alarm, another app's audio). The system has already paused output.
    public func interruptionBegan() {
        // The system deactivates the session when an interruption begins; nothing is left to release.
        sessionActive = false
        if mode == .preview {
            endPreview(restoringPlayback: false)
            resumeAfterInterruption = false
            return
        }
        let wasPlaying = isPlayingOrStarting
        pause(reason: .interruption)
        resumeAfterInterruption = wasPlaying
    }

    /// Resume only when the system says so and the user was playing when the interruption began (plan 10.1).
    public func interruptionEnded(shouldResume: Bool) {
        let resume = shouldResume && resumeAfterInterruption
        resumeAfterInterruption = false
        if resume { play() }
    }

    /// Headphones or another output were removed: pause, never continue on the speaker (plan 10.1, T19).
    public func outputDeviceRemoved() {
        resumeAfterInterruption = false
        if mode == .preview {
            endPreview(restoringPlayback: false)
            return
        }
        if isPlayingOrStarting { pause(reason: .routeChange) }
    }

    // MARK: Preview (plan 10.3)

    /// Previews one file (a retained excerpt, or one source range).
    public func beginPreview(url: URL, startSeconds: Double = 0, endSeconds: Double? = nil) async -> Bool {
        await beginPreview([PreviewSegment(url: url, startSeconds: startSeconds, endSeconds: endSeconds)])
    }

    /// The preview of a capture whose excerpt is still pending: its file-local source ranges, in order, as segments
    /// of the member files (several for a cross-file capture), each opened with its member's timing mode. Nil when any
    /// member is not on this device.
    public func previewSegments(for ranges: [AudioRange]) -> [PreviewSegment]? {
        guard !ranges.isEmpty else { return nil }
        var segments: [PreviewSegment] = []
        for r in ranges {
            guard let url = resolveFile(r.assetID), fileExists(url) else { return nil }
            let timing = timeline.flatMap { t in t.index(of: r.assetID).map { t.members[$0].timing } } ?? .precise
            segments.append(PreviewSegment(url: url, startSeconds: Double(r.startMs) / 1000, endSeconds: Double(r.endMs) / 1000, timing: timing))
        }
        return segments
    }

    /// Saves the main context, pauses main playback and plays only the excerpt (or the source ranges while the
    /// excerpt is pending, back to back across files). Preview never changes the position, furthest position or
    /// listening totals. Segments after the first must start at 0 (`PreviewSegment.isPlayable`).
    public func beginPreview(_ segments: [PreviewSegment]) async -> Bool {
        // Not while the main member is still opening: the main context to restore is not established yet.
        guard mode == .main, !isPreparing, currentPoint != nil, PreviewSegment.isPlayable(segments) else { return false }
        let wasPlaying = status == .playing
        // Pause first, then read the point once: the saved context, the preview-start checkpoint and the point main
        // returns to are the same position. (AVPlayer's current time can still move between two reads right after
        // pause(), so the point is never read twice.)
        if wasPlaying { haltMain() }
        guard let point = currentPoint else { return false }
        if wasPlaying { checkpoint(.previewStart, at: point) }
        let context = MainContext(point: point, wasPlaying: wasPlaying, rate: rate)
        savedMainContext = context
        mode = .preview
        previewPlayer.onFinish = { [weak self] in self?.endPreview(restoringPlayback: true) }
        _ = activateSession()
        let ok = await previewPlayer.play(segments)
        if !ok { endPreview(restoringPlayback: true) }
        return ok
    }

    /// The listener stopped the preview (pause or play/pause from the app, headphones, the Lock Screen or Control
    /// Center; review R4-03): the preview ends, the main context is restored paused (main does not resume, even if it
    /// was playing before the preview, because the listener asked for silence), and the audio session is released as
    /// after any user pause, so an app whose audio the preview interrupted may resume. Progress is untouched, as for
    /// every preview end.
    public func stopPreview() {
        guard mode == .preview else { return }
        endPreview(restoringPlayback: false)
        releaseSession()
    }

    /// Whether the preview player is playing now (false outside a preview).
    public var isPreviewPlaying: Bool { mode == .preview && previewPlayer.isPlaying }

    /// Seconds played of the running preview and its length (Now Playing shows them during a preview).
    public var previewProgress: (elapsedSeconds: Double, durationSeconds: Double)? {
        mode == .preview ? previewPlayer.progress : nil
    }

    /// Ends preview and restores the saved main context. `restoringPlayback` resumes main playback when it was
    /// playing before the preview; after an interruption or route change it stays paused. A preview that ends
    /// normally without resuming main playback releases the audio session (review R2-06); after an interruption
    /// (already released by the system) or a lost output device it is kept, as for main playback.
    public func endPreview(restoringPlayback: Bool) {
        guard mode == .preview else { return }
        previewPlayer.onFinish = nil
        previewPlayer.stop()
        mode = .main
        let context = savedMainContext
        savedMainContext = nil
        guard let context else {
            if restoringPlayback { releaseSession() }
            return
        }
        rate = context.rate
        let resume = restoringPlayback && context.wasPlaying
        // The main engine was paused, not moved. If anything moved it anyway, put it back before resuming, so
        // playback never resumes from the wrong place.
        if currentPoint != context.point {
            restoreTask = Task {
                guard await self.position(at: context.point) != .superseded else { return }
                self.lastTickGlobalMs = self.currentGlobalMs
                self.lastTickTime = self.clock.now()
                self.finishPreviewRestore(resume: resume, restoringPlayback: restoringPlayback)
            }
            return
        }
        lastTickGlobalMs = currentGlobalMs
        lastTickTime = clock.now()
        finishPreviewRestore(resume: resume, restoringPlayback: restoringPlayback)
    }

    /// Resumes main playback when the preview interrupted it; when main does not play afterwards (it was paused, or
    /// it cannot resume) a preview that ended normally releases the session.
    private func finishPreviewRestore(resume: Bool, restoringPlayback: Bool) {
        if resume { play() }
        if restoringPlayback, status != .playing { releaseSession() }
    }

    /// The repositioning started by `endPreview` when the main engine had moved (tests await it).
    @ObservationIgnored public private(set) var restoreTask: Task<Void, Never>?

    // MARK: PlaybackEngineDelegate

    public func engine(didFinishMember memberIndex: Int) {
        guard let timeline, mode == .main else { return }
        accountProgress()
        let next = memberIndex + 1
        if next >= timeline.members.count {
            parkedPoint = AudioPoint(assetID: timeline.members[memberIndex].assetID, ms: timeline.members[memberIndex].durationMs)
            status = .paused
            checkpoint(.itemChange)
            releaseSession()  // the end of the edition: playback stopped for good
            return
        }
        if resolveFile(timeline.members[next].assetID) == nil {
            // The queue stops before a missing member; park at its start and block only that segment.
            engine.pause()
            parkedPoint = AudioPoint(assetID: timeline.members[next].assetID, ms: 0)
            status = .segmentUnavailable(memberIndex: next)
            checkpoint(.blocked)
            releaseSession()
            return
        }
        _ = playableURL(next)  // records a file that has gone missing since it was queued
        if let failure = failedMembers[next] {
            // The next member's file is gone or did not decode: stop at its start; earlier audio was unaffected.
            engine.pause()
            parkedPoint = AudioPoint(assetID: timeline.members[next].assetID, ms: 0)
            status = .failed(memberIndex: next, failure)
            checkpoint(.blocked)
            releaseSession()
            return
        }
        parkedPoint = nil
        enqueueFollowing(after: next)
        lastTickGlobalMs = currentGlobalMs
        lastTickTime = clock.now()
        // AVQueuePlayer posts didPlayToEndTime before it makes the next item current, so the engine may still
        // report the finished member at its end. The checkpoint names the member that plays now (the same global
        // position), so a relaunch resumes in the new file.
        let nextPoint = AudioPoint(assetID: timeline.members[next].assetID, ms: 0)
        checkpoint(.itemChange, at: engine.currentMemberIndex == next ? nil : nextPoint)
    }

    public func engine(didFailMember memberIndex: Int, message: String) {
        guard engine.currentMemberIndex == memberIndex else {
            // A queued later member failed while the current one plays: keep playing and block only that segment
            // when playback reaches it.
            failedMembers[memberIndex] = .decodeError(message)
            return
        }
        engine.pause()
        status = .failed(memberIndex: memberIndex, .decodeError(message))
        checkpoint(.blocked)
        releaseSession()
    }

    public func engineDidTick() {
        guard mode == .main, status == .playing else { return }
        accountProgress()
        let g = currentGlobalMs
        let mediaDue = abs(g - lastCheckpointGlobalMs) >= Self.checkpointIntervalMediaMs
        let wallDue = clock.now() - lastCheckpointTime >= Self.checkpointIntervalSeconds
        if mediaDue || wallDue { checkpoint(.periodic) }
    }

    // MARK: Internals

    /// Puts the engine at a file-local point, queueing that member and the next available one. While the member opens
    /// the status is `.preparing` and the position is the target point (a checkpoint written meanwhile, for example
    /// at a lifecycle event, records it). When it is ready the status is `.paused` (callers resume playback); when
    /// the system fails to open it, `.failed(decodeError)`; a later positioning that replaced this one
    /// (`.superseded`) leaves everything to that one.
    @discardableResult
    private func position(at point: AudioPoint) async -> QueueOutcome {
        positionGeneration += 1
        let generation = positionGeneration
        guard let timeline, let index = timeline.index(of: point.assetID) else { return .failed("not in the edition") }
        guard let url = resolveFile(point.assetID) else {
            engine.pause()
            parkedPoint = point
            status = .segmentUnavailable(memberIndex: index)
            return .failed("not on this device")
        }
        guard fileExists(url) else {
            engine.pause()
            parkedPoint = point
            status = .failed(memberIndex: index, .missingFile)
            return .failed("missing file")
        }
        failedMembers[index] = nil
        // Each member opens with the timing mode its import chose (ADR-0006 decision 2).
        var items = [EngineItem(memberIndex: index, url: url, timing: timeline.members[index].timing)]
        if let next = engineItem(index + 1) { items.append(next) }
        parkedPoint = point
        status = .preparing(memberIndex: index)
        let outcome = await engine.setQueue(items, startSeconds: Double(point.ms) / 1000)
        guard generation == positionGeneration, outcome != .superseded else { return .superseded }
        switch outcome {
        case .ready:
            parkedPoint = nil
            status = .paused
        case let .failed(message):
            parkedPoint = point
            playWhenReady = false
            status = .failed(memberIndex: index, .decodeError(message))
        case .superseded:
            return .superseded
        }
        return outcome
    }

    /// The queue item for member `index` when it can be queued (`playableURL`), with the member's timing mode.
    private func engineItem(_ index: Int) -> EngineItem? {
        guard let timeline, let url = playableURL(index) else { return nil }
        return EngineItem(memberIndex: index, url: url, timing: timeline.members[index].timing)
    }

    /// The URL of member `index` when it can be queued: present in the library, on disk, and not known to fail.
    private func playableURL(_ index: Int) -> URL? {
        guard let timeline, index < timeline.members.count, failedMembers[index] == nil,
              let url = resolveFile(timeline.members[index].assetID) else { return nil }
        guard fileExists(url) else {
            failedMembers[index] = .missingFile
            return nil
        }
        return url
    }

    private func enqueueFollowing(after current: Int) {
        let n = current + 1
        guard !engine.queuedMemberIndices.contains(n), let item = engineItem(n) else { return }
        engine.append(item)
    }

    /// Adds listening time (wall time while the media advanced) and advances the furthest position from observed
    /// contiguous main playback only.
    private func accountProgress() {
        let now = clock.now()
        let g = currentGlobalMs
        if mode == .main, status == .playing, let t0 = lastTickTime, let g0 = lastTickGlobalMs {
            let dt = max(0, now - t0)
            let expected = Double(rate) * dt * 1000
            let delta = g - g0
            if delta >= 0, Double(delta) <= expected + Double(Self.frontierToleranceMs) {
                // Listening time is wall time during which the media advanced (plan 12: observed playback
                // intervals): the media advanced by `delta` at `rate`, so it played for delta / rate of wall time,
                // never more than the wall time that passed. A stall while `status == .playing` (a slow first seek
                // before the first audio, buffering) leaves the position still and adds nothing (review R2-02).
                listenedRemainder += min(dt * 1000, Double(delta) / Double(rate))
                let whole = listenedRemainder.rounded(.down)
                listenedMs += Int64(whole)
                listenedRemainder -= whole
                // Contiguous playback since the last tick: it extends the current run.
                runListenedMediaMs += delta
                let startedAtFrontier = runStartGlobalMs <= furthestGlobalMs + Self.frontierToleranceMs
                let sustained = runListenedMediaMs >= Self.frontierAdoptionMs
                if (startedAtFrontier || sustained), g > furthestGlobalMs {
                    furthestGlobalMs = g
                    furthestPoint = currentPoint
                }
            } else {
                // A jump the service did not make (the engine moved on its own): a new run starts here. How long
                // was heard before the jump is unknown, so this interval adds no listening time.
                startRun(at: g)
            }
        }
        lastTickTime = now
        lastTickGlobalMs = g
    }

    private func startRun(at globalMs: Int64) {
        runStartGlobalMs = globalMs
        runListenedMediaMs = 0
    }

    /// Writes a checkpoint at `explicit` when given, otherwise at the current point (the saved main point during
    /// preview).
    private func checkpoint(_ reason: CheckpointReason, at explicit: AudioPoint? = nil) {
        guard let timeline, mode == .main || reason == .previewStart || reason == .lifecycle else { return }
        // During preview the main context is what we persist.
        let point = explicit ?? (mode == .preview ? savedMainContext?.point : nil) ?? currentPoint
        guard let point, let g = try? timeline.globalMs(of: point) else { return }
        let fp = furthestPoint ?? point
        let c = PlaybackCheckpoint(editionID: timeline.editionID, timelineRevision: timeline.revision,
                                   last: point, lastGlobalMs: g, furthest: fp, furthestGlobalMs: furthestGlobalMs,
                                   listenedMs: listenedMs, reason: reason)
        do {
            try positions.save(c)
            lastCheckpointError = nil
        } catch {
            lastCheckpointError = "\(error)"
        }
        lastCheckpointGlobalMs = g
        lastCheckpointTime = clock.now()
    }

    static func globalChapters(_ timeline: EditionTimeline, _ memberChapters: [UUID: [ChapterInfo]]) -> [TimelineChapter] {
        var result: [TimelineChapter] = []
        for (i, m) in timeline.members.enumerated() {
            let base = timeline.starts[i]
            if let list = memberChapters[m.assetID], !list.isEmpty {
                for c in list {
                    result.append(TimelineChapter(title: c.title, startGlobalMs: base + c.startMs,
                                                  endGlobalMs: base + min(c.endMs, m.durationMs)))
                }
            } else {
                result.append(TimelineChapter(title: m.fileName, startGlobalMs: base, endGlobalMs: base + m.durationMs))
            }
        }
        return result
    }
}
