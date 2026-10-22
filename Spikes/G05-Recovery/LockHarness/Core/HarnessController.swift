import Foundation
import Observation

/// The locked-device harness (T50; G0.5 recovery device checklist step 3; PO-23 option (b), product owner, 22 October
/// 2026). While a run is active it plays a quiet tone, so iOS keeps the process running with the phone locked
/// (UIBackgroundModes audio), and every `interval` seconds it makes one attempt: a durable capture save in the spike's
/// class-C library (D17: WAL, synchronous=FULL, fullfsync), its read-back, a class-C file write and read-back, and a
/// readback of the files' protection classes. Each attempt, event and check becomes one line in a class-C log file
/// (`HarnessLog`), which the harness can write while the phone is locked after the first unlock, and in the unified
/// system log.
///
/// Rules the tests hold it to (`Tests/ControllerTests.swift`):
/// * An item counts as acknowledged only after its save returned (the commit is durable) and its read-back found the
///   exact content; a failed attempt is recorded with its error and the same item is tried again at the next attempt.
/// * `isProtectedDataAvailable` and the class-A canary are recorded, never used to decide whether to try a class-C
///   write (plan 18.1, A18).
/// * Every file component was built from a `HarnessConfiguration`, which accepts class C only, so every class the
///   harness asks for or sets is class C (the class-A canary aside): there is no fallback to another class, and a
///   failed write is never retried with one.
/// * A line that cannot be written (the log file is class C, unreadable before the first unlock) is kept, in order,
///   and written with `written-late=<time>` once the file can be written; it goes to the unified log at once.
/// * A pause between attempts longer than the gap threshold is recorded as a `gap`: the process was suspended.
@MainActor
@Observable
public final class HarnessController {
    public enum RunState: String, Sendable {
        case idle, running, stopped
    }

    public static let recentLimit = 500

    public private(set) var runState: RunState = .idle
    /// The newest lines, oldest first: the log file's last lines at launch, then every line since.
    public private(set) var recentLines: [String] = []
    /// Lines recorded but not yet written to the log file.
    public private(set) var pendingLineCount = 0
    /// Lines that could not be kept for the log file beyond `HarnessConfiguration.pendingLimit` (they are in the
    /// unified log).
    public private(set) var droppedLineCount = 0
    /// The current or last run.
    public private(set) var record: SessionRecord?
    public private(set) var lastVerifyResult = "not run"

    public let configuration: HarnessConfiguration
    @ObservationIgnored private let environment: HarnessEnvironment
    @ObservationIgnored private let autoTick: Bool
    @ObservationIgnored private var pending: [String] = []
    @ObservationIgnored private var sinkFailing = false
    @ObservationIgnored private var lastAttemptAt: Date?
    @ObservationIgnored private var tickTask: Task<Void, Never>?
    @ObservationIgnored private var launched = false

    /// `autoTick` false leaves the attempts to the caller (tests call `tick()` with their own clock).
    public init(configuration: HarnessConfiguration, environment: HarnessEnvironment, autoTick: Bool = true) {
        self.configuration = configuration
        self.environment = environment
        self.autoTick = autoTick
        environment.player.onEvent = { [weak self] text in self?.audioEvent(text) }
    }

    public var logFileURL: URL { environment.sink.fileURL }

    public var statusLine: String {
        var text: String
        switch (runState, record) {
        case (.running, let r?):
            text = "Running \(r.run): attempt \(r.attempts), \(r.acknowledged) acknowledged, \(r.failures) failed, "
                + "\(r.lockedAttempts) while locked (\(r.lockedFailures) failed), \(r.gaps) gaps."
        case (.stopped, let r?):
            text = "Stopped \(r.run) after \(r.attempts) attempts: \(r.acknowledged) acknowledged, \(r.failures) failed, "
                + "\(r.lockedAttempts) while locked (\(r.lockedFailures) failed), \(r.gaps) gaps."
        case (_, let r?):
            text = "Idle. Last run \(r.run): \(r.attempts) attempts, \(r.acknowledged) acknowledged."
        default:
            text = "Idle. No run recorded."
        }
        text += " Last check: \(lastVerifyResult)."
        if pendingLineCount > 0 { text += " \(pendingLineCount) lines wait for the log file." }
        return text
    }

    // MARK: Launch

    /// Records the launch, how the previous run ended, and a full check of the library it left. Called once per
    /// process, from the app delegate, for a launch in the foreground or in the background alike.
    public func launch(state: String? = nil) {
        guard !launched else { return }
        launched = true
        if let tail = try? environment.sink.readTail(maxLines: Self.recentLimit) {
            recentLines = tail
        }
        let now = environment.clock.now()
        let boot = environment.bootTime.bootTime()
        emit("launch", [
            ("platform", environment.platform),
            ("state", state ?? environment.appState.stateName),
            ("protectedDataAvailable", "\(environment.protectedData.isProtectedDataAvailable)"),
            ("classA", environment.canary.isReadable() ? "readable" : "unreadable"),
            ("boot", boot.map(HarnessLog.timestamp) ?? "unknown"),
            ("sinceBoot", boot.map { HarnessLog.seconds(now.timeIntervalSince($0)) } ?? "unknown"),
            ("interval", HarnessLog.seconds(configuration.interval)),
            ("gapThreshold", HarnessLog.seconds(configuration.gapThreshold)),
            ("protection", configuration.protection.rawValue),
        ])
        let previous: PreviousSession
        var reason: String?
        do {
            previous = PreviousSession.classify(try environment.sessions.load(), currentBoot: boot)
        } catch {
            previous = .unreadable(code: HarnessLog.code(error), reason: HarnessLog.reason(error))
            reason = HarnessLog.reason(error)
        }
        emit("previous-session", previous.fields, reason: reason)
        record = previous.record
        switch previous {
        case .none:
            break
        case .unreadable:
            verify(acknowledged: nil, run: nil, closeAfter: true)
        default:
            verify(acknowledged: previous.record?.acknowledged, run: previous.record?.run, closeAfter: true)
        }
        emit("refresh", [("result", environment.scheduler.schedule())])
    }

    // MARK: Run

    public func start() {
        guard runState != .running else { return }
        let now = environment.clock.now()
        var errors: [(String, any Error)] = []

        let canary: String
        do { canary = try environment.canary.ensureCreated() ? "created" : "present" } catch {
            canary = "failed"
            errors.append(("canary", error))
        }
        var durability = "-"
        let store: String
        do {
            durability = try environment.store.open().replacing(" ", with: ",")
            store = "open"
        } catch {
            store = "failed"
            errors.append(("open", error))
        }
        let audio: String
        do {
            try environment.player.start(volume: configuration.volume)
            audio = environment.player.isPlaying ? "playing" : "not-playing"
        } catch {
            audio = "failed"
            errors.append(("audio", error))
        }

        let run = String(UUID().uuidString.prefix(8)).lowercased()
        let newRecord = SessionRecord(run: run, bootTime: environment.bootTime.bootTime(), startedAt: now,
                                      interval: configuration.interval, acknowledged: record?.acknowledged ?? 0)
        record = newRecord
        runState = .running
        lastAttemptAt = nil
        let session = saveRecord(newRecord, errors: &errors)

        var fields: [(String, String)] = [
            ("run", run), ("item", "\(newRecord.acknowledged)"), ("interval", HarnessLog.seconds(configuration.interval)),
            ("volume", String(format: "%.2f", configuration.volume)), ("volumeReason", configuration.volumeReason),
            ("audio", audio), ("protection", configuration.protection.rawValue), ("durability", durability),
            ("store", store), ("canary", canary), ("session", session),
        ]
        fields += errorFields(errors)
        emit("start", fields, reason: errorReason(errors))
        if autoTick { startTicker() }
    }

    /// One attempt. Every outcome is recorded; nothing here is skipped because the phone is locked.
    public func tick() {
        guard runState == .running, var r = record else { return }
        let now = environment.clock.now()
        if let last = lastAttemptAt {
            let elapsed = now.timeIntervalSince(last)
            if elapsed > configuration.gapThreshold {
                r.gaps += 1
                r.longestGap = max(r.longestGap, elapsed)
                emit("gap", [("run", r.run), ("seconds", HarnessLog.seconds(elapsed)), ("after", "#\(r.attempts)"),
                             ("app", environment.appState.stateName)])
            }
        }
        lastAttemptAt = now
        r.attempts += 1
        let protectedData = environment.protectedData.isProtectedDataAvailable
        let classA = environment.canary.isReadable()
        let item = r.acknowledged
        var errors: [(String, any Error)] = []
        var notes: [String] = []

        var save = "failed"
        var readBack = "not-attempted"
        var acknowledgedNow = false
        do {
            if !environment.store.isOpen { _ = try environment.store.open() }
            save = try environment.store.save(item: item).rawValue
            do {
                let result = try environment.store.readBack(item: item)
                readBack = result.rawValue
                acknowledgedNow = result == .equal
                if result != .equal { notes.append("readback: item \(item) \(result.rawValue)") }
            } catch {
                readBack = "failed"
                errors.append(("readback", error))
            }
        } catch {
            errors.append(("save", error))
        }

        var file = "failed"
        do {
            file = try environment.probe.writeAndRead("attempt \(r.attempts) of run \(r.run)") ? "ok" : "differs"
            if file == "differs" { notes.append("file: the bytes read back differ") }
        } catch {
            errors.append(("file", error))
        }
        let classes = environment.inspector.inspect(full: false)

        if acknowledgedNow { r.acknowledged += 1 }
        let failed = !acknowledgedNow || file != "ok" || !classes.mismatches.isEmpty
        if failed { r.failures += 1 }
        if !protectedData {
            r.lockedAttempts += 1
            if failed { r.lockedFailures += 1 }
        }
        if !classA { r.classAUnreadable += 1 }
        r.lastRecordAt = now
        record = r
        let session = saveRecord(r, errors: &errors)

        var fields: [(String, String)] = [
            ("run", r.run), ("n", "\(r.attempts)"), ("t", HarnessLog.seconds(now.timeIntervalSince(r.startedAt))),
            ("app", environment.appState.stateName), ("protectedDataAvailable", "\(protectedData)"),
            ("classA", classA ? "readable" : "unreadable"), ("item", "\(item)"), ("save", save), ("readback", readBack),
            ("file", file), ("classes", classes.compact), ("session", session), ("acknowledged", "\(r.acknowledged)"),
        ]
        fields += errorFields(errors)
        let reason = ([errorReason(errors)].compactMap { $0 } + notes).joined(separator: "; ")
        emit("attempt", fields, reason: reason.isEmpty ? nil : reason)
        if r.attempts % configuration.summaryEvery == 0 {
            emit("summary", r.counterFields)
        }
    }

    public func stop() {
        guard runState == .running, var r = record else { return }
        tickTask?.cancel()
        tickTask = nil
        environment.player.stop()
        r.stoppedCleanly = true
        r.lastRecordAt = environment.clock.now()
        record = r
        runState = .stopped
        var errors: [(String, any Error)] = []
        let session = saveRecord(r, errors: &errors)
        emit("stop", r.counterFields + [("session", session)] + errorFields(errors), reason: errorReason(errors))
        verify(acknowledged: r.acknowledged, run: r.run, closeAfter: false)
        environment.store.close()
    }

    /// A full check of the library: every acknowledged item present once with exact content, integrity, foreign keys
    /// and the class of every file and directory (`verify-classes`). Returns whether it passed.
    @discardableResult
    public func verifyNow() -> Bool {
        verify(acknowledged: record?.acknowledged, run: record?.run, closeAfter: runState != .running)
    }

    /// A background refresh launch (BGAppRefreshTask), which iOS may run while the phone is locked, before or after
    /// the first unlock. Records what it can read and write; returns whether everything it tried succeeded.
    @discardableResult
    public func backgroundRefresh() -> Bool {
        emit("background-refresh", [
            ("app", environment.appState.stateName),
            ("protectedDataAvailable", "\(environment.protectedData.isProtectedDataAvailable)"),
            ("classA", environment.canary.isReadable() ? "readable" : "unreadable"),
            ("runState", runState.rawValue),
        ])
        var passed = true
        if runState != .running {
            passed = verify(acknowledged: record?.acknowledged, run: record?.run, closeAfter: true)
        }
        do {
            let ok = try environment.probe.writeAndRead("background refresh")
            emit("file-probe", [("file", ok ? "ok" : "differs")])
            passed = passed && ok
        } catch {
            emit("file-probe", [("file", "failed"), ("error", HarnessLog.code(error))], reason: HarnessLog.reason(error))
            passed = false
        }
        emit("refresh", [("result", environment.scheduler.schedule())])
        return passed
    }

    // MARK: Events

    public func protectedDataWillBecomeUnavailable() {
        emit("event", [("name", "protected-data-will-become-unavailable"),
                       ("protectedDataAvailable", "\(environment.protectedData.isProtectedDataAvailable)"),
                       ("app", environment.appState.stateName)])
    }

    /// Also the moment buffered lines can first be written after a restart (the first unlock).
    public func protectedDataDidBecomeAvailable() {
        emit("event", [("name", "protected-data-did-become-available"),
                       ("protectedDataAvailable", "\(environment.protectedData.isProtectedDataAvailable)"),
                       ("app", environment.appState.stateName)])
    }

    public func appStateChanged(to state: String) {
        emit("event", [("name", "app-state"), ("state", state)])
    }

    public func audioEvent(_ detail: String) {
        emit("event", [("name", "audio"), ("detail", detail), ("playing", "\(environment.player.isPlaying)")])
    }

    public func willTerminate() {
        emit("event", [("name", "will-terminate"), ("runState", runState.rawValue)])
    }

    // MARK: Internals

    @discardableResult
    private func verify(acknowledged: Int?, run: String?, closeAfter: Bool) -> Bool {
        let wasOpen = environment.store.isOpen
        defer { if closeAfter && !wasOpen { environment.store.close() } }
        do {
            if !wasOpen { _ = try environment.store.open() }
            let report = try environment.store.verify(acknowledged: acknowledged ?? 0)
            let classes = environment.inspector.inspect(full: true)
            let passed = report.passed && classes.mismatches.isEmpty
            lastVerifyResult = passed ? "passed" : "FAILED"
            var reasons = report.failures.prefix(5).map { $0 }
            if report.integrity != ["ok"] { reasons.append("integrity: " + report.integrity.prefix(3).joined(separator: "; ")) }
            emit("verify", [
                ("result", passed ? "ok" : "FAILED"), ("run", run ?? "-"),
                ("acknowledged", acknowledged.map(String.init) ?? "unknown"),
                ("libraryCaptures", "\(report.libraryCaptures)"),
                ("extra", acknowledged.map { "\(report.libraryCaptures - $0)" } ?? "unknown"),
                ("integrity", report.integrity == ["ok"] ? "ok" : "FAILED"),
                ("foreignKeyViolations", "\(report.foreignKeyViolations)"), ("failures", "\(report.failures.count)"),
                ("classes", classes.compact),
            ], reason: reasons.isEmpty ? nil : reasons.joined(separator: "; "))
            emit("verify-classes", classes.detail)
            return passed
        } catch {
            lastVerifyResult = "could not read the library"
            emit("verify", [
                ("result", "could-not-read"), ("run", run ?? "-"),
                ("protectedDataAvailable", "\(environment.protectedData.isProtectedDataAvailable)"),
                ("error", HarnessLog.code(error)),
            ], reason: HarnessLog.reason(error))
            return false
        }
    }

    private func saveRecord(_ record: SessionRecord, errors: inout [(String, any Error)]) -> String {
        do {
            try environment.sessions.save(record)
            return "ok"
        } catch {
            errors.append(("session", error))
            return "failed"
        }
    }

    private func errorFields(_ errors: [(String, any Error)]) -> [(String, String)] {
        errors.isEmpty ? [] : [("error", errors.map { "\($0.0):\(HarnessLog.code($0.1))" }.joined(separator: ","))]
    }

    private func errorReason(_ errors: [(String, any Error)]) -> String? {
        errors.isEmpty ? nil : errors.map { "\($0.0): \(HarnessLog.reason($0.1))" }.joined(separator: "; ")
    }

    private func startTicker() {
        tickTask?.cancel()
        let interval = configuration.interval
        tickTask = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(interval))
                guard !Task.isCancelled, let self, self.runState == .running else { return }
                self.tick()
            }
        }
    }

    /// Records a line: in the unified log at once, in the log file as soon as it can be written.
    private func emit(_ event: String, _ fields: [(String, String)], reason: String? = nil) {
        let now = environment.clock.now()
        let line = HarnessLog.line(now, event, fields, reason: reason)
        environment.mirror.mirror(line)
        appendRecent(line)
        persist(line, at: now)
    }

    private func persist(_ line: String, at now: Date) {
        let late = pending.map { HarnessLog.markedWrittenLate($0, at: now) }
        let recovered: String? = sinkFailing
            ? HarnessLog.line(now, "event", [("name", "log-file-writable-again"), ("writtenLate", "\(pending.count)"),
                                             ("dropped", "\(droppedLineCount)")])
            : nil
        do {
            try environment.sink.append(late + (recovered.map { [$0] } ?? []) + [line])
            if let recovered {
                environment.mirror.mirror(recovered)
                appendRecent(recovered)
            }
            sinkFailing = false
            pending.removeAll()
        } catch {
            // Kept in the order the lines were recorded and mirrored: the line, then the note that the file could
            // not take it.
            enqueue(line)
            if !sinkFailing {
                sinkFailing = true
                let note = HarnessLog.line(now, "event", [("name", "log-file-unwritable"), ("error", HarnessLog.code(error))],
                                           reason: HarnessLog.reason(error))
                environment.mirror.mirror(note)
                appendRecent(note)
                enqueue(note)
            }
        }
        pendingLineCount = pending.count
    }

    private func enqueue(_ line: String) {
        if pending.count < configuration.pendingLimit {
            pending.append(line)
        } else {
            droppedLineCount += 1
        }
    }

    private func appendRecent(_ line: String) {
        recentLines.append(line)
        if recentLines.count > Self.recentLimit { recentLines.removeFirst(recentLines.count - Self.recentLimit) }
    }
}
