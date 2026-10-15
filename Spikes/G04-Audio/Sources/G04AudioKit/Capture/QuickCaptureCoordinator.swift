import Foundation

/// Connects the player's current position to the capture transaction for every capture entry point: the
/// in-player button, and the quick-capture prototypes (App Intent from a control, the Action button or a
/// shortcut; the bookmark remote command). It returns only after the anchor and note are durable, so a caller can
/// acknowledge "Moment saved · preserving audio" truthfully; the excerpt is preserved afterwards (plan 10.2).
@MainActor
public final class QuickCaptureCoordinator {
    /// Where a capture request comes from, which decides what counts as a moment to capture (review R6-01).
    public enum Entry: Equatable, Sendable {
        /// The labelled Capture button in the player: the listener sees the book and its position, so it captures the
        /// preceding 30 seconds there whether or not the book has played since it was loaded.
        case player
        /// A quick-capture surface outside the player (the App Intent behind the control, the Action button, an App
        /// Shortcut or Siri; the remote bookmark command). It captures only a moment heard in this process: main
        /// playback has played since the edition was loaded (it plays now, or was paused after playing). A process the
        /// system launched to perform the intent restores the book paused and has played nothing, so it has nothing to
        /// capture, whether the restore finished before the intent arrived or not: the answer never depends on that race.
        case surface
    }

    public enum Outcome: Equatable, Sendable {
        case saved(CaptureRecord)
        /// No moment to capture: nothing is loaded, or (for a quick-capture surface) the loaded book has not played in
        /// this process. Nothing was written.
        case nothingPlaying
        /// The durable write failed. Nothing is acknowledged.
        case notSaved(String)
    }

    /// A request from the same surface within this many seconds of wall time, at a position no further away than
    /// that time at the fastest rate allows, is the same capture (a re-delivered App Intent, a double press). It
    /// reuses the first request's idempotency key, so the store returns the existing record and never duplicates it.
    public static let repeatWindowSeconds: TimeInterval = 2
    static var repeatPositionToleranceMs: Int64 {
        Int64(repeatWindowSeconds * Double(PlaybackService.rateRange.upperBound) * 1000) + 500
    }

    private let playback: PlaybackService
    private let captures: CaptureService
    private let clock: any PlaybackClock
    public private(set) var exportTasks: [UUID: Task<Void, Never>] = [:]
    /// Wall time of each durable anchor save in `captureNow`, in seconds (plan 19.2 "acknowledged capture save").
    /// Repeats answered from the existing record are not saves and are not counted.
    public private(set) var saveDurations: [Double] = []
    private var lastRequest: [String: (key: String, time: TimeInterval, globalMs: Int64)] = [:]

    public init(playback: PlaybackService, captures: CaptureService, clock: any PlaybackClock = SystemPlaybackClock()) {
        self.playback = playback
        self.captures = captures
        self.clock = clock
    }

    /// A new idempotency key for one request from `origin`. The in-player Capture button passes one per tap: each tap
    /// is a deliberate capture, so two quick taps at the same place make two captures (review R3-04); the repeat
    /// window is only for entry points without a request identity (App Intents, the remote bookmark command).
    public static func requestKey(origin: String) -> String { "\(origin)#\(UUID().uuidString)" }

    /// Captures the preceding 30 seconds at the current position and returns once the anchor and note are durable.
    /// Synchronous, so a caller that must answer synchronously (an MPRemoteCommand handler) can still acknowledge
    /// only after the save. `origin` records the surface and process. The excerpt export starts afterwards.
    /// `idempotencyKey`: a caller that has a request identity passes it (the in-player button: one per tap, from
    /// `requestKey(origin:)`; a re-sent request: the same key again); otherwise the repeat window applies.
    /// `entry`: the in-player button (`.player`) or a quick-capture surface (`.surface`), which captures only a moment
    /// heard in this process (review R6-01).
    public func captureNow(origin: String, entry: Entry, note: String? = nil, idempotencyKey: String? = nil) -> Outcome {
        guard let timeline = playback.timeline else { return .nothingPlaying }
        if entry == .surface, !playback.hasPlayedSinceLoad { return .nothingPlaying }
        let position = playback.currentGlobalMs
        let now = clock.now()
        let key: String
        var isRepeat = false
        if let idempotencyKey {
            key = idempotencyKey
        } else if let last = lastRequest[origin], now - last.time <= Self.repeatWindowSeconds,
                  abs(position - last.globalMs) <= Self.repeatPositionToleranceMs {
            key = last.key
            isRepeat = true
        } else {
            key = Self.requestKey(origin: origin)
        }
        let started = ProcessInfo.processInfo.systemUptime
        do {
            let record = try captures.captureAudio(timeline: timeline, atGlobalMs: position, note: note,
                                                   idempotencyKey: key, origin: origin)
            if !isRepeat {
                saveDurations.append(ProcessInfo.processInfo.systemUptime - started)
                if idempotencyKey == nil { lastRequest[origin] = (key, now, position) }
            }
            startExport(record.id)
            return .saved(record)
        } catch {
            return .notSaved("\(error)")
        }
    }

    /// Resumes the exports of captures left pending by an earlier process (terminated or crashed between the anchor
    /// write and the export result), so none stays "Moment saved · preserving audio" with nothing running. Call at
    /// launch. Returns the capture IDs resumed.
    @discardableResult
    public func resumeInterruptedExports() async -> [UUID] {
        let ids = (try? await captures.interruptedExports()) ?? []
        for id in ids { startExport(id) }
        return ids
    }

    /// Whether an export started here is still running for the capture.
    public func isExporting(_ id: UUID) -> Bool { exportTasks[id] != nil }

    /// Waits for the excerpt export started by `captureNow` or `resumeInterruptedExports` (tests and the harness's
    /// status line). Returns at once when none is running.
    public func waitForExport(_ id: UUID) async { await exportTasks[id]?.value }

    private func startExport(_ id: UUID) {
        guard exportTasks[id] == nil else { return }
        let service = captures
        exportTasks[id] = Task { [weak self] in
            _ = try? await service.preserveExcerpt(id)
            self?.exportTasks[id] = nil
        }
    }
}
