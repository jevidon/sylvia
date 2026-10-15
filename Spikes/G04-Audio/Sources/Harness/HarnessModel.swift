import AVFoundation
import Foundation
import G04AudioKit
import Observation
import UIKit

/// The G0.4 harness: one playback service, one capture service and the quick-capture prototypes wired together.
/// It plays the audio files copied into `Documents/G04Book/` (device checklist: a long book for T18), ordered as
/// the importer proposes (embedded tags, then natural file names), or else the two committed LibriVox excerpts.
/// Every checkpoint and every capture is appended to a log in `Documents/` for the device run. Stage 0 chrome only.
@MainActor
@Observable
final class HarnessModel {
    static let shared = HarnessModel()

    static let editionID = UUID(uuidString: "6A0F4D0B-3F43-4C39-9E0B-0D4A2B9C0401")!
    static let demoMembers: [(UUID, String)] = [
        (UUID(uuidString: "6A0F4D0B-3F43-4C39-9E0B-0D4A2B9C0411")!, "meditations-01-first180s"),
        (UUID(uuidString: "6A0F4D0B-3F43-4C39-9E0B-0D4A2B9C0412")!, "meditations-02-first150s"),
    ]
    static let audioExtensions: Set<String> = ["mp3", "m4a", "m4b", "aac", "flac", "wav", "caf", "ogg", "opus"]

    let playback: PlaybackService
    let nowPlaying: NowPlayingController
    let captures: CaptureService
    let coordinator: QuickCaptureCoordinator
    @ObservationIgnored private var sessionObserver: AudioSessionObserver?
    @ObservationIgnored private let sources = SourceTable()
    @ObservationIgnored private let log: HarnessLog
    @ObservationIgnored private var nowPlayingTimer: Timer?
    private(set) var records: [CaptureRecord] = []
    private(set) var lastMessage: String?
    private(set) var bookmarkCommandEnabled = false
    private(set) var editionTitle = "-"
    /// Whether the harness plays at full volume. Quiet (1 % volume) unless `SYLVIA_AUDIBLE_PLAYBACK=1` or the
    /// full-volume toggle is on (`SpikeAudioOutput`): automated runs on a shared Mac stay quiet, and a person turns
    /// full volume on for listening checks (device checklist). The engines default to full volume; the harness injects
    /// the quiet volume.
    private(set) var audiblePlayback: Bool
    @ObservationIgnored private let engine: AVQueuePlayerEngine
    @ObservationIgnored private let previewPlayer: AVPreviewPlayer
    @ObservationIgnored private let store: FileCaptureStore

    init() {
        let fm = FileManager.default
        let support = (try? fm.url(for: .applicationSupportDirectory, in: .userDomainMask, appropriateFor: nil, create: true))
            ?? fm.temporaryDirectory
        let documents = (try? fm.url(for: .documentDirectory, in: .userDomainMask, appropriateFor: nil, create: true)) ?? support
        let root = support.appendingPathComponent("G04Harness", isDirectory: true)
        let harnessLog = HarnessLog(directory: documents)
        log = harnessLog
        store = try! FileCaptureStore(directory: root.appendingPathComponent("Captures"))
        // Every activation and release of the audio session is logged (device checklist step 15: another app's audio
        // resumes after the harness pauses).
        let session = SystemAudioSession()
        session.onEvent = { harnessLog.write("session", $0) }
        let output = SpikeAudioOutput.harnessIsAudible(environment: ProcessInfo.processInfo.environment, defaults: .standard)
        audiblePlayback = output.audible
        engine = AVQueuePlayerEngine(outputVolume: SpikeAudioOutput.volume(audible: output.audible))
        previewPlayer = AVPreviewPlayer(outputVolume: SpikeAudioOutput.volume(audible: output.audible))
        playback = PlaybackService(engine: engine, previewPlayer: previewPlayer, session: session,
                                   positions: LoggingPositionStore(FilePositionStore(directory: root), log: harnessLog))
        let table = sources
        // The export opens each source with the timing mode its import chose (ADR-0006 decision 2).
        captures = CaptureService(store: store, exporter: AACExcerptExporter(), resolveSource: { table.url($0) },
                                  resolveTiming: { table.timing($0) })
        coordinator = QuickCaptureCoordinator(playback: playback, captures: captures)
        nowPlaying = NowPlayingController(service: playback)
        // Every remote command (headphones, Lock Screen, Control Center) with the mode it arrived in and the status
        // returned to the system: device checklist steps 7 and 7.3 (commands during a preview, review R4-03).
        nowPlaying.onCommand = { command, mode, status in
            harnessLog.write("remote", "command=\(command.name) mode=\(mode) status=\(NowPlayingController.statusName(status))")
        }
        sessionObserver = AudioSessionObserver(service: playback)
        // The scene phase covers inactive and background; termination of a running app is only announced here.
        let service = playback
        terminateObserver = NotificationCenter.default.addObserver(forName: UIApplication.willTerminateNotification, object: nil, queue: .main) { _ in
            MainActor.assumeIsolated { service.handleLifecycle(.willTerminate) }
        }
        log.write("launch", "process=\(Bundle.main.bundleIdentifier ?? "-") state=\(UIApplication.shared.applicationState.rawValue) protectedDataAvailable=\(UIApplication.shared.isProtectedDataAvailable)")
        log.write("output", "volume=\(engine.outputVolume) preview_volume=\(previewPlayer.outputVolume) reason=\(output.reason.rawValue)")
    }

    /// The harness's full-volume toggle (persisted for later launches; a launch argument `-g04AudiblePlayback NO|YES`
    /// overrides the persisted value).
    func setAudiblePlayback(_ audible: Bool) {
        audiblePlayback = audible
        engine.outputVolume = SpikeAudioOutput.volume(audible: audible)
        previewPlayer.outputVolume = SpikeAudioOutput.volume(audible: audible)
        UserDefaults.standard.set(audible, forKey: SpikeAudioOutput.harnessDefaultsKey)
        log.write("output", "volume=\(engine.outputVolume) preview_volume=\(previewPlayer.outputVolume) reason=toggle")
    }

    func start() async {
        guard playback.timeline == nil else { return }
        let book: ([EditionMember], [UUID: URL], String)
        if let documents = await bookFromDocuments() { book = documents } else { book = await demoBook() }
        let (members, urls, title) = book
        for m in members {
            if let url = urls[m.assetID] { sources.set(m.assetID, url, timing: m.timing) }
        }
        guard let timeline = try? EditionTimeline(editionID: Self.editionID, members: members) else {
            lastMessage = "edition unavailable"
            return
        }
        editionTitle = title
        nowPlaying.titleProvider = { title }
        await playback.load(timeline: timeline, resolveFile: { [sources] in sources.url($0) })
        nowPlaying.register()
        nowPlaying.update()
        // Harness simplification: refresh Now Playing every 2 s so state changes from interruptions show up. The
        // product updates it on every state transition instead.
        nowPlayingTimer = Timer.scheduledTimer(withTimeInterval: 2, repeats: true) { _ in
            MainActor.assumeIsolated { HarnessModel.shared.nowPlaying.update() }
        }
        log.write("loaded", "edition=\(title) members=\(members.count) duration_ms=\(timeline.durationMs) position_ms=\(playback.currentGlobalMs) furthest_ms=\(playback.furthestGlobalMs)")
        // The timing mode the import chose for each member (no file names: they can be titles).
        for (i, m) in members.enumerated() {
            log.write("member", "index=\(i) duration_ms=\(m.durationMs) timing=\(m.timing.rawValue)")
        }
        if let warning = incompleteEditionText { log.write("edition-incomplete", warning) }
        refresh()
        // Captures an earlier process left pending (terminated or crashed before the export result): export them now
        // so none stays "Moment saved · preserving audio" with nothing running (review R1-05).
        let resumed = await coordinator.resumeInterruptedExports()
        for id in resumed {
            log.write("export-resumed", "id=\(id)")
            Task {
                await coordinator.waitForExport(id)
                refresh()
                logExport(id)
            }
        }
        // Process-kill trial (Scripts/ci.d/60-g04-audio.sh, simulator): `-g04AutoPlay YES` starts playback right after
        // loading and logs the player's position every 0.5 s, so a script can play, SIGKILL the process, relaunch and
        // compare the resumed position with where playback really was. Harness only.
        if UserDefaults.standard.bool(forKey: "g04AutoPlay") {
            playback.play()
            log.write("autoplay", "status=\(playback.status) position_ms=\(playback.currentGlobalMs)")
            positionTimer = Timer.scheduledTimer(withTimeInterval: 0.5, repeats: true) { _ in
                MainActor.assumeIsolated {
                    let p = HarnessModel.shared.playback
                    HarnessModel.shared.log.write("position", "global_ms=\(p.currentGlobalMs) status=\(p.status)")
                }
            }
        }
    }

    @ObservationIgnored private var positionTimer: Timer?
    @ObservationIgnored private var terminateObserver: (any NSObjectProtocol)?

    /// Whether the harness offers Retry: the export failed, or it is pending with no export running in this process.
    func canRetry(_ record: CaptureRecord) -> Bool {
        record.canRetryExport || (record.kind == .audio && record.excerpt == .pending && !coordinator.isExporting(record.id))
    }

    /// Audio files in Documents/G04Book/ in the importer's proposed order, with stable asset IDs per file name.
    private func bookFromDocuments() async -> ([EditionMember], [UUID: URL], String)? {
        guard let docs = try? FileManager.default.url(for: .documentDirectory, in: .userDomainMask, appropriateFor: nil, create: false) else { return nil }
        let dir = docs.appendingPathComponent("G04Book", isDirectory: true)
        guard let files = try? FileManager.default.contentsOfDirectory(at: dir, includingPropertiesForKeys: nil),
              case let audio = files.filter({ Self.audioExtensions.contains($0.pathExtension.lowercased()) }), !audio.isEmpty else { return nil }
        var reports: [(URL, AssetReport)] = []
        for url in audio {
            if let r = try? await AssetInspector.inspect(url), r.isPlayable, r.preciseDurationMs != nil { reports.append((url, r)) }
        }
        guard !reports.isEmpty else { return nil }
        let proposal = MemberOrdering.propose(reports.map {
            MemberCandidate(fileName: $0.0.lastPathComponent, trackNumber: $0.1.trackNumber, trackTotal: $0.1.trackTotal, discNumber: $0.1.discNumber)
        })
        var members: [EditionMember] = [], urls: [UUID: URL] = [:]
        for i in proposal.order {
            let (url, report) = reports[i]
            let id = UUID(uuidString: Self.stableID(url.lastPathComponent)) ?? UUID()
            members.append(EditionMember(assetID: id, fileName: url.lastPathComponent, durationMs: report.preciseDurationMs!,
                                         timing: report.timing))
            urls[id] = url
        }
        return (members, urls, "G04Book (\(members.count) files)")
    }

    private func demoBook() async -> ([EditionMember], [UUID: URL], String) {
        var members: [EditionMember] = [], urls: [UUID: URL] = [:]
        for (id, name) in Self.demoMembers {
            guard let url = Bundle.main.url(forResource: name, withExtension: "mp3"),
                  let report = try? await AssetInspector.inspect(url), let ms = report.preciseDurationMs else { continue }
            members.append(EditionMember(assetID: id, fileName: "\(name).mp3", durationMs: ms, timing: report.timing))
            urls[id] = url
        }
        return (members, urls, "Meditations (G0.4 demo)")
    }

    /// A UUID derived from a file name, so a relaunch maps the same file to the same asset (and checkpoint).
    static func stableID(_ name: String) -> String {
        var h: UInt64 = 0xcbf2_9ce4_8422_2325
        var bytes: [UInt8] = []
        for round in 0..<2 {
            for b in Array(name.utf8) + [UInt8(round)] { h = (h ^ UInt64(b)) &* 0x100_0000_01b3 }
            withUnsafeBytes(of: h.bigEndian) { bytes += $0 }
        }
        bytes[6] = (bytes[6] & 0x0f) | 0x40
        bytes[8] = (bytes[8] & 0x3f) | 0x80
        let hex = bytes.map { String(format: "%02x", $0) }.joined()
        let p = Array(hex)
        return "\(String(p[0..<8]))-\(String(p[8..<12]))-\(String(p[12..<16]))-\(String(p[16..<20]))-\(String(p[20..<32]))"
    }

    func refresh() {
        records = ((try? store.all()) ?? []).reversed()
    }

    /// The in-player capture button and every quick-capture surface end here. The in-player button passes a key per
    /// tap; the intent and the bookmark command pass none, so the coordinator's repeat window applies to them.
    /// `entry`: `.player` for the in-player button, `.surface` for the intent and the bookmark command, which capture only
    /// a moment heard in this process (review R6-01).
    func quickCapture(origin: String, entry: QuickCaptureCoordinator.Entry, idempotencyKey: String? = nil) -> QuickCaptureReply {
        let wasPlaying = playback.status == .playing
        let loaded = playback.timeline != nil
        let played = playback.hasPlayedSinceLoad
        let outcome = coordinator.captureNow(origin: origin, entry: entry, idempotencyKey: idempotencyKey)
        refresh()
        let app = UIApplication.shared
        var detail = "origin=\(origin) process=\(Bundle.main.bundleIdentifier ?? "-") app_state=\(app.applicationState.rawValue) protectedDataAvailable=\(app.isProtectedDataAvailable) was_playing=\(wasPlaying)"
        switch outcome {
        case let .saved(record):
            let id = record.id
            let protection = (try? store.recordURL(for: id).resourceValues(forKeys: [.fileProtectionKey]).fileProtection).map { $0.rawValue } ?? "none reported"
            detail += " result=saved id=\(id) ranges=\(record.ranges.map { "\($0.startMs)-\($0.endMs)" }.joined(separator: ",")) record_protection=\(protection)"
            Task {
                await coordinator.waitForExport(id)
                refresh()
                logExport(id)
            }
        case let .notSaved(reason):
            lastMessage = reason
            detail += " result=not_saved reason=\(reason)"
        case .nothingPlaying:
            // loaded= says on which side of the start-up race a cold-launched intent arrived (the answer is the same).
            detail += " result=nothing_to_capture loaded=\(loaded) played_since_load=\(played)"
        }
        log.write("capture", detail)
        return Self.reply(outcome)
    }

    /// The export outcome of a capture, with the protection class the retained excerpt reads back (device checklist
    /// step 9: class C, set explicitly by the exporter; the simulator reads back class C whatever was set).
    private func logExport(_ id: UUID) {
        let state = (try? store.record(id))?.map { SpikePhrases.phrase($0.statusKey) } ?? "-"
        let excerpt = store.excerptURL(for: id)
        let protection = FileManager.default.fileExists(atPath: excerpt.path)
            ? ((try? excerpt.resourceValues(forKeys: [.fileProtectionKey]).fileProtection).map { $0.rawValue } ?? "none reported")
            : "no file"
        log.write("export", "id=\(id) status=\(state) excerpt_protection=\(protection)")
    }

    /// What a quick-capture surface is told. Acknowledged only for a durable save, with the phrase of the record's
    /// status key ("Moment saved · preserving audio"). The vocabulary has no key for "nothing is loaded" or for "the
    /// moment was not saved" (`save.failed` promises text that a capture does not have); the harness shows the
    /// proposed keys themselves (open question in the G0.4 report), never an invented phrase.
    static func reply(_ outcome: QuickCaptureCoordinator.Outcome) -> QuickCaptureReply {
        switch outcome {
        case let .saved(record):
            QuickCaptureReply(acknowledged: true, message: SpikePhrases.phrase(record.statusKey))
        case .nothingPlaying:
            QuickCaptureReply(acknowledged: false, message: SpikePhrases.phrase(ProposedVocabularyKey.audioNothingToCapture))
        case .notSaved:
            QuickCaptureReply(acknowledged: false, message: SpikePhrases.phrase(ProposedVocabularyKey.audioMomentNotSaved))
        }
    }

    func bookmark() async {
        guard let timeline = playback.timeline else { return }
        do {
            _ = try captures.bookmark(timeline: timeline, atGlobalMs: playback.currentGlobalMs, note: nil, idempotencyKey: UUID().uuidString)
        } catch {
            lastMessage = SpikePhrases.phrase(ProposedVocabularyKey.audioMomentNotSaved)
        }
        refresh()
    }

    func retry(_ id: UUID) async {
        _ = try? await captures.retry(id)
        refresh()
    }

    func setRange(_ id: UUID, startMs: Int64, endMs: Int64) async {
        guard let timeline = playback.timeline else { return }
        do {
            _ = try await captures.setRange(id, timeline: timeline, globalStartMs: startMs, globalEndMs: endMs)
            _ = try await captures.preserveExcerpt(id)
            lastMessage = nil
        } catch {
            lastMessage = "\(error)"
        }
        refresh()
    }

    /// Previews the retained excerpt, or, while it is pending or not preserved, the capture's source ranges.
    func preview(_ record: CaptureRecord) async {
        let segments: [PreviewSegment]?
        if case .saved = record.excerpt {
            segments = [PreviewSegment(url: store.excerptURL(for: record.id))]
        } else {
            segments = playback.previewSegments(for: record.ranges)
        }
        guard let segments, await playback.beginPreview(segments) else {
            lastMessage = "preview unavailable"
            return
        }
        // Now Playing shows the preview while it runs (the 2 s timer keeps it current; review R4-03).
        nowPlaying.update()
    }

    func toggleBookmarkCommand() {
        if bookmarkCommandEnabled {
            nowPlaying.register()
            bookmarkCommandEnabled = false
        } else {
            nowPlaying.enableBookmarkCapture { [weak self] in
                self?.quickCapture(origin: "remote-bookmark-command", entry: .surface).acknowledged ?? false
            }
            bookmarkCommandEnabled = true
        }
        log.write("bookmark-command", "enabled=\(bookmarkCommandEnabled)")
    }

    // MARK: Playback settings (plan 10.1; review R6-02; device checklist step 17)

    /// Switches the skip intervals between 15 s both ways (the default) and 10 s back / 30 s forward, so the device
    /// run can check that the Lock Screen and Control Center skip buttons follow the setting.
    func toggleSkipIntervals() {
        let isDefault = playback.skipBackwardSeconds == PlaybackService.skipSeconds && playback.skipForwardSeconds == PlaybackService.skipSeconds
        if isDefault {
            playback.setSkipIntervals(backward: 10, forward: 30)
        } else {
            playback.setSkipIntervals(backward: PlaybackService.skipSeconds, forward: PlaybackService.skipSeconds)
        }
        nowPlaying.update()
        log.write("settings", "skip_backward_s=\(Int(playback.skipBackwardSeconds)) skip_forward_s=\(Int(playback.skipForwardSeconds))")
    }

    func setSleepTimer(_ timer: PlaybackService.SleepTimer?) {
        playback.setSleepTimer(timer)
        let detail: String
        switch timer {
        case .none: detail = "set=off"
        case let .after(seconds): detail = "set=after_\(Int(seconds))s"
        case .endOfChapter: detail = "set=end_of_chapter stop_ms=\(playback.sleepStopGlobalMs ?? -1)"
        }
        log.write("sleep-timer", "\(detail) position_ms=\(playback.currentGlobalMs)")
    }

    /// The rewind after a long pause with values for a quick device check (after a pause of at least 1 minute, 10 s
    /// back). The product default is a product-owner decision (ADR-0006).
    static let checklistResumeRewind = PlaybackService.ResumeRewind(afterPauseSeconds: 60, rewindSeconds: 10)

    func toggleResumeRewind() {
        playback.setResumeRewind(playback.resumeRewind == nil ? Self.checklistResumeRewind : nil)
        let detail = playback.resumeRewind.map { "resume_rewind=after_\(Int($0.afterPauseSeconds))s_back_\(Int($0.rewindSeconds))s" } ?? "resume_rewind=off"
        log.write("settings", detail)
    }

    /// The incomplete-edition warning (plan 10.1): the members that cannot play here and why (no file names).
    var incompleteEditionText: String? {
        guard playback.isEditionIncomplete, let timeline = playback.timeline else { return nil }
        let members = playback.unavailableMemberIndices.map { i in
            "\(i + 1) \(playback.unavailableMembers[timeline.members[i].assetID]?.rawValue ?? "-")"
        }
        return "\(SpikePhrases.phrase(ProposedVocabularyKey.audioEditionIncomplete)) members \(members.joined(separator: ", "))"
    }
}

/// Asset ID to local file and its timing mode, shared with the capture service's resolvers.
final class SourceTable: @unchecked Sendable {
    private let lock = NSLock()
    private var urls: [UUID: URL] = [:]
    private var timings: [UUID: AssetTiming] = [:]
    func set(_ id: UUID, _ url: URL, timing: AssetTiming) {
        lock.withLock {
            urls[id] = url
            timings[id] = timing
        }
    }
    func url(_ id: UUID) -> URL? { lock.withLock { urls[id] } }
    func timing(_ id: UUID) -> AssetTiming { lock.withLock { timings[id] ?? .precise } }
}

/// Append-only text log in Documents (`g04-harness.log`), one line per event with a UTC timestamp and the
/// device's protected-data state, for the device checklist. It holds positions and states only, never notes.
final class HarnessLog: @unchecked Sendable {
    private let url: URL
    private let lock = NSLock()
    private let formatter = ISO8601DateFormatter()
    init(directory: URL) {
        url = directory.appendingPathComponent("g04-harness.log")
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
    }
    func write(_ event: String, _ detail: String) {
        lock.withLock {
            let line = "\(formatter.string(from: Date())) \(event) \(detail)\n"
            // The log is evidence, not product data: written with the same class as the stores so that it is
            // writable while the phone is locked (after first unlock). It is only ever appended to: an existing log
            // that cannot be opened is never replaced (that would destroy evidence); the line goes to the console
            // instead, marked so the gap is visible.
            if append(line) { return }
            do {
                try Data(line.utf8).write(to: url, options: [.withoutOverwriting, .completeFileProtectionUntilFirstUserAuthentication])
            } catch {
                // Created by someone else meanwhile, or not writable: try appending once more, else report the gap.
                if !append(line) { NSLog("g04-harness-log-unwritable %@", line) }
            }
        }
    }

    private func append(_ line: String) -> Bool {
        guard let h = try? FileHandle(forWritingTo: url) else { return false }
        defer { try? h.close() }
        do {
            try h.seekToEnd()
            try h.write(contentsOf: Data(line.utf8))
            return true
        } catch {
            NSLog("g04-harness-log-unwritable %@", line)
            return true  // the file exists; never fall back to replacing it
        }
    }
}

/// Logs every checkpoint (reason and position) before passing it to the durable store.
@MainActor
final class LoggingPositionStore: PositionStore {
    private let inner: any PositionStore
    private let log: HarnessLog
    init(_ inner: any PositionStore, log: HarnessLog) {
        self.inner = inner
        self.log = log
    }
    func save(_ checkpoint: PlaybackCheckpoint) throws {
        do {
            try inner.save(checkpoint)
            log.write("checkpoint", "reason=\(checkpoint.reason.rawValue) last_ms=\(checkpoint.lastGlobalMs) furthest_ms=\(checkpoint.furthestGlobalMs) listened_ms=\(checkpoint.listenedMs) protectedDataAvailable=\(UIApplication.shared.isProtectedDataAvailable)")
        } catch {
            log.write("checkpoint-failed", "reason=\(checkpoint.reason.rawValue) error=\(error)")
            throw error
        }
    }
    func load(editionID: UUID) throws -> PlaybackCheckpoint? { try inner.load(editionID: editionID) }
}
