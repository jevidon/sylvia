import Foundation
import MediaPlayer

/// Now Playing information and the standard remote commands (plan 10.1). Play, pause, skip and chapter
/// navigation keep their documented meanings; capture is never mapped onto them (plan 10.5). The bookmark
/// command, whose documented purpose is "remember a media item", is registered only when `enableBookmarkCapture`
/// is called (quick-capture prototype, ADR-0007).
///
/// A command is reported `.success` only when the service acts on it, so the system is never told that an ignored
/// command worked (review R4-03). During a capture preview (plan 10.3) Now Playing shows the preview (its elapsed
/// time and length, playing at 1x); pause and play/pause stop the preview and restore the book paused at its saved
/// place (`PlaybackService.stopPreview`); play is accepted (the preview is already playing); every command that would
/// move the book or change its rate (skip, scrubbing, previous and next track, rate) is disabled while the preview
/// runs and refused with `.commandFailed` if it arrives anyway, because a preview must leave the book's position
/// untouched. Nothing loaded: `.noActionableNowPlayingItem`.
@MainActor
public final class NowPlayingController {
    /// The default skip interval. The skip commands use the intervals of the service (`PlaybackService.skipBackwardSeconds`,
    /// `skipForwardSeconds`), which a listener can change (plan 10.1; review R6-02).
    public static let skipInterval: Double = PlaybackService.skipSeconds
    public static let supportedRates: [NSNumber] = [0.5, 0.75, 1, 1.25, 1.5, 1.75, 2, 2.5, 3]
    /// Commands that start or stop playback (also during a preview).
    public static let transportCommands = ["play", "pause", "togglePlayPause"]
    /// Commands that move the book or change its rate (not during a preview).
    public static let navigationCommands = ["skipForward", "skipBackward", "changePlaybackRate", "changePlaybackPosition", "nextTrack", "previousTrack"]

    /// A remote command as the handlers see it, decoded from the system's event.
    public enum Command: Equatable, Sendable {
        case play, pause, togglePlayPause, skipForward, skipBackward, nextChapter, previousChapter
        case changeRate(Float)
        case changePosition(seconds: Double)
        case bookmark

        /// The registered command's name (as in `registeredCommands`).
        public var name: String {
            switch self {
            case .play: "play"
            case .pause: "pause"
            case .togglePlayPause: "togglePlayPause"
            case .skipForward: "skipForward"
            case .skipBackward: "skipBackward"
            case .nextChapter: "nextTrack"
            case .previousChapter: "previousTrack"
            case .changeRate: "changePlaybackRate"
            case .changePosition: "changePlaybackPosition"
            case .bookmark: "bookmark"
            }
        }
    }

    /// What Now Playing shows and which commands are enabled for the service's current state.
    public struct Snapshot: Equatable, Sendable {
        public var title: String
        public var durationSeconds: Double
        public var elapsedSeconds: Double
        /// 0 when nothing plays.
        public var rate: Double
        public var defaultRate: Double
        public var chapterCount: Int?
        public var chapterNumber: Int?
        public var isPlaying: Bool
        /// A capture preview is playing: the fields describe the preview, not the book.
        public var isPreview: Bool
        public var enabledCommands: Set<String>
        /// The preferred intervals advertised for the skip commands (the current skip intervals of the service).
        public var skipBackwardSeconds: Double
        public var skipForwardSeconds: Double
    }

    private let service: PlaybackService
    private let center: MPRemoteCommandCenter
    private let publishesToSystem: Bool
    private var targets: [(MPRemoteCommand, Any)] = []
    private var bookmarkHandler: (@MainActor () -> Bool)?
    public private(set) var registeredCommands: [String] = []
    public private(set) var performed: [Command] = []
    /// The last snapshot `update()` computed (and published, unless `publishesToSystem` is false).
    public private(set) var published: Snapshot?
    /// The work a seek-type command started (tests await it through `perform`).
    public private(set) var lastCommandTask: Task<Void, Never>?
    public var titleProvider: () -> String = { "Untitled" }
    /// Called for every handled command with the mode it arrived in and the status returned to the system (the harness
    /// logs it for the device run).
    public var onCommand: ((Command, PlaybackService.Mode, MPRemoteCommandHandlerStatus) -> Void)?

    /// `publishesToSystem: false` keeps the controller off the shared `MPNowPlayingInfoCenter` and off the commands'
    /// enabled flags (unit tests, which run in parallel with the real-engine suites).
    public init(service: PlaybackService, center: MPRemoteCommandCenter = .shared(), publishesToSystem: Bool = true) {
        self.service = service
        self.center = center
        self.publishesToSystem = publishesToSystem
    }

    /// Registers the standard transport commands. Returns the names registered.
    @discardableResult
    public func register() -> [String] {
        unregister()
        add(center.playCommand, "play") { _ in .play }
        add(center.pauseCommand, "pause") { _ in .pause }
        add(center.togglePlayPauseCommand, "togglePlayPause") { _ in .togglePlayPause }
        applySkipIntervals()
        add(center.skipForwardCommand, "skipForward") { _ in .skipForward }
        add(center.skipBackwardCommand, "skipBackward") { _ in .skipBackward }
        center.changePlaybackRateCommand.supportedPlaybackRates = Self.supportedRates
        add(center.changePlaybackRateCommand, "changePlaybackRate") { e in
            (e as? MPChangePlaybackRateCommandEvent).map { .changeRate($0.playbackRate) }
        }
        add(center.changePlaybackPositionCommand, "changePlaybackPosition") { e in
            (e as? MPChangePlaybackPositionCommandEvent).map { .changePosition(seconds: $0.positionTime) }
        }
        // Chapter navigation on the track buttons: their documented meaning for audiobooks.
        add(center.nextTrackCommand, "nextTrack") { _ in .nextChapter }
        add(center.previousTrackCommand, "previousTrack") { _ in .previousChapter }
        // Seek-by-holding is not offered; skip covers it.
        center.seekForwardCommand.isEnabled = false
        center.seekBackwardCommand.isEnabled = false
        // MPRemoteCommand.isEnabled defaults to true (observed in the simulator), so commands Sylvia does not offer
        // are disabled explicitly. The bookmark command stays off until the quick-capture prototype opts in.
        for unused in [center.bookmarkCommand, center.likeCommand, center.dislikeCommand, center.ratingCommand,
                       center.changeRepeatModeCommand, center.changeShuffleModeCommand,
                       center.enableLanguageOptionCommand, center.disableLanguageOptionCommand, center.stopCommand] {
            unused.isEnabled = false
        }
        return registeredCommands
    }

    /// Advertises the skip intervals of the service as the preferred intervals of the skip commands (what the Lock
    /// Screen and Control Center show on their skip buttons; plan 10.1 configurable skip intervals, review R6-02).
    private func applySkipIntervals() {
        center.skipBackwardCommand.preferredIntervals = [NSNumber(value: service.skipBackwardSeconds)]
        center.skipForwardCommand.preferredIntervals = [NSNumber(value: service.skipForwardSeconds)]
    }

    /// Quick-capture prototype: the bookmark feedback command. Where (if anywhere) current iOS shows it is not
    /// documented; ADR-0007 lists it as a device check. MPRemoteCommand handlers answer synchronously, so the
    /// handler performs the durable anchor save before it returns, and the command reports `.success` only when
    /// that save succeeded (I-03). The excerpt export continues afterwards.
    public func enableBookmarkCapture(_ handler: @escaping @MainActor () -> Bool) {
        bookmarkHandler = handler
        center.bookmarkCommand.localizedTitle = "Capture the last 30 seconds"
        center.bookmarkCommand.localizedShortTitle = "Capture"
        let target = center.bookmarkCommand.addTarget { [weak self] _ in
            // The system delivers remote-command events on the main thread.
            MainActor.assumeIsolated { self?.performBookmark() ?? .commandFailed }
        }
        center.bookmarkCommand.isEnabled = true
        targets.append((center.bookmarkCommand, target))
        registeredCommands.append("bookmark")
    }

    /// The bookmark command's synchronous path (what the registered target runs).
    public func performBookmark() -> MPRemoteCommandHandlerStatus {
        performed.append(.bookmark)
        guard let bookmarkHandler else { return .commandFailed }
        let status: MPRemoteCommandHandlerStatus = bookmarkHandler() ? .success : .commandFailed
        onCommand?(.bookmark, service.mode, status)
        return status
    }

    public func unregister() {
        for (command, target) in targets {
            command.removeTarget(target)
            command.isEnabled = false
        }
        targets.removeAll()
        registeredCommands.removeAll()
    }

    public func isEnabled(_ name: String) -> Bool {
        command(named: name)?.isEnabled ?? false
    }

    private func command(named name: String) -> MPRemoteCommand? {
        switch name {
        case "play": center.playCommand
        case "pause": center.pauseCommand
        case "togglePlayPause": center.togglePlayPauseCommand
        case "skipForward": center.skipForwardCommand
        case "skipBackward": center.skipBackwardCommand
        case "changePlaybackRate": center.changePlaybackRateCommand
        case "changePlaybackPosition": center.changePlaybackPositionCommand
        case "nextTrack": center.nextTrackCommand
        case "previousTrack": center.previousTrackCommand
        case "bookmark": center.bookmarkCommand
        case "seekForward": center.seekForwardCommand
        case "seekBackward": center.seekBackwardCommand
        default: nil
        }
    }

    /// The single path of every registered system target: decides synchronously whether the service acts on the
    /// command (the system's handler must answer at once), performs it (a seek-type command finishes in
    /// `lastCommandTask`) and returns `.success` only when it was acted on.
    @discardableResult
    public func handle(_ command: Command) -> MPRemoteCommandHandlerStatus {
        if command == .bookmark { return performBookmark() }
        performed.append(command)
        let mode = service.mode
        let status = act(command)
        onCommand?(command, mode, status)
        update()
        return status
    }

    /// `handle`, then waits for the work it started (tests).
    @discardableResult
    public func perform(_ command: Command) async -> MPRemoteCommandHandlerStatus {
        lastCommandTask = nil
        let status = handle(command)
        await lastCommandTask?.value
        update()
        return status
    }

    private func act(_ command: Command) -> MPRemoteCommandHandlerStatus {
        guard service.timeline != nil else { return .noActionableNowPlayingItem }
        if service.mode == .preview {
            switch command {
            case .pause, .togglePlayPause:
                service.stopPreview()
                return service.mode == .main ? .success : .commandFailed
            case .play:
                return .success  // the preview is what plays; nothing to start
            default:
                return .commandFailed  // a preview never moves the book or changes its rate
            }
        }
        switch command {
        case .play:
            service.play()
            return service.isPlayingOrStarting ? .success : .commandFailed
        case .pause:
            service.pause()
            return .success
        case .togglePlayPause:
            let wasPlaying = service.isPlayingOrStarting
            service.togglePlayPause()
            return service.isPlayingOrStarting != wasPlaying ? .success : .commandFailed
        case let .changeRate(r):
            service.setRate(r)
            return .success
        case .skipForward:
            startSeek { await $0.skipForward() }
        case .skipBackward:
            startSeek { await $0.skipBackward() }
        case let .changePosition(s):
            startSeek { await $0.seek(toGlobalMs: Int64((s * 1000).rounded())) }
        case .nextChapter:
            guard let i = service.currentChapterIndex, i + 1 < service.chapters.count else { return .commandFailed }
            startSeek { await $0.nextChapter() }
        case .previousChapter:
            guard service.currentChapterIndex != nil else { return .commandFailed }
            startSeek { await $0.previousChapter() }
        case .bookmark:
            return performBookmark()
        }
        return .success
    }

    private func startSeek(_ body: @escaping @MainActor (PlaybackService) async -> Void) {
        let service = service
        lastCommandTask = Task { @MainActor [weak self] in
            await body(service)
            self?.update()
        }
    }

    /// Now Playing for the service's state: the book (title, duration, elapsed time, rate, chapters), or during a
    /// capture preview the preview (the book's title, the preview's elapsed time and length, rate 1; navigation
    /// commands disabled). Nil when nothing is loaded.
    public func snapshot() -> Snapshot? {
        guard let timeline = service.timeline else { return nil }
        if service.mode == .preview {
            let progress = service.previewProgress
            let playing = service.isPreviewPlaying
            return Snapshot(title: titleProvider(), durationSeconds: progress?.durationSeconds ?? 0,
                            elapsedSeconds: progress?.elapsedSeconds ?? 0, rate: playing ? 1 : 0, defaultRate: 1,
                            chapterCount: nil, chapterNumber: nil, isPlaying: playing, isPreview: true,
                            enabledCommands: Set(Self.transportCommands),
                            skipBackwardSeconds: service.skipBackwardSeconds, skipForwardSeconds: service.skipForwardSeconds)
        }
        let playing = service.status == .playing
        return Snapshot(title: titleProvider(), durationSeconds: Double(timeline.durationMs) / 1000,
                        elapsedSeconds: Double(service.currentGlobalMs) / 1000, rate: playing ? Double(service.rate) : 0,
                        defaultRate: Double(service.rate), chapterCount: service.chapters.count,
                        chapterNumber: service.currentChapterIndex, isPlaying: playing, isPreview: false,
                        enabledCommands: Set(Self.transportCommands + Self.navigationCommands),
                        skipBackwardSeconds: service.skipBackwardSeconds, skipForwardSeconds: service.skipForwardSeconds)
    }

    /// Publishes Now Playing information for the current state and enables the registered commands that apply to it.
    public func update() {
        let snap = snapshot()
        published = snap
        guard publishesToSystem else { return }
        guard let snap else {
            MPNowPlayingInfoCenter.default().nowPlayingInfo = nil
            return
        }
        var info: [String: Any] = [
            MPMediaItemPropertyTitle: snap.title,
            MPMediaItemPropertyPlaybackDuration: snap.durationSeconds,
            MPNowPlayingInfoPropertyElapsedPlaybackTime: snap.elapsedSeconds,
            MPNowPlayingInfoPropertyPlaybackRate: snap.rate,
            MPNowPlayingInfoPropertyDefaultPlaybackRate: snap.defaultRate,
            MPNowPlayingInfoPropertyMediaType: MPNowPlayingInfoMediaType.audio.rawValue,
        ]
        if let n = snap.chapterCount { info[MPNowPlayingInfoPropertyChapterCount] = n }
        if let c = snap.chapterNumber { info[MPNowPlayingInfoPropertyChapterNumber] = c }
        MPNowPlayingInfoCenter.default().nowPlayingInfo = info
        MPNowPlayingInfoCenter.default().playbackState = snap.isPlaying ? .playing : .paused
        // The skip commands advertise the current intervals of the listener (they can change between updates).
        applySkipIntervals()
        // Only commands this controller registered are switched; during a preview the navigation commands are off,
        // so the system shows them unavailable.
        for name in registeredCommands where Self.transportCommands.contains(name) || Self.navigationCommands.contains(name) {
            command(named: name)?.isEnabled = snap.enabledCommands.contains(name)
        }
    }

    private func add(_ command: MPRemoteCommand, _ name: String,
                     _ decode: @escaping @Sendable (MPRemoteCommandEvent) -> Command?) {
        let target = command.addTarget { [weak self] event in
            guard let decoded = decode(event) else { return .commandFailed }
            // The system delivers remote-command events on the main thread; the decision is made there, at once, so
            // the status returned says whether the command was acted on.
            return MainActor.assumeIsolated { self?.handle(decoded) ?? .commandFailed }
        }
        command.isEnabled = true
        targets.append((command, target))
        registeredCommands.append(name)
    }

    /// The status's name in logs.
    public static func statusName(_ status: MPRemoteCommandHandlerStatus) -> String {
        switch status {
        case .success: "success"
        case .noSuchContent: "noSuchContent"
        case .noActionableNowPlayingItem: "noActionableNowPlayingItem"
        case .deviceNotFound: "deviceNotFound"
        case .commandFailed: "commandFailed"
        @unknown default: "status\(status.rawValue)"
        }
    }
}
