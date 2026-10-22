import Foundation
import Testing

private let classC = HarnessConfiguration.requiredProtection.rawValue

/// Every state the device run takes the harness through, on the simulator: unlocked, locked after the first unlock,
/// a restart, a launch before the first unlock, the first unlock, and the launch after it; and the failures a device
/// can produce (a suspended timer, a read-back that differs or fails, another class read back, no tone). The phone is
/// `SimulatedDevice`; nothing here is evidence of what a device does (device checklist step 3 is).
@MainActor
@Suite("Lock harness: state transitions on a simulated phone")
struct ControllerTests {
    /// The log is honest: an attempt line says `readback=equal` only for an item the library holds with its exact
    /// content, and `acknowledged` grows by one exactly on those lines.
    func expectHonest(_ rig: Rig, from initial: Int = 0, sourceLocation: SourceLocation = #_sourceLocation) {
        var acknowledged = initial
        for line in rig.fileLines("attempt") {
            let item = Int(line["item"] ?? "") ?? -1
            if line["readback"] == "equal" {
                #expect(rig.store.committed[item] == true, "line claims item \(item) equal", sourceLocation: sourceLocation)
                #expect(item == acknowledged, "acknowledged out of order at item \(item)", sourceLocation: sourceLocation)
                acknowledged += 1
            }
            #expect(line["acknowledged"] == "\(acknowledged)", "acknowledged field \(line["acknowledged"] ?? "-")",
                    sourceLocation: sourceLocation)
        }
    }

    @Test("first launch: the launch is recorded, there is no previous run, nothing is opened, a refresh is asked for")
    func firstLaunch() throws {
        let rig = Rig()
        let controller = try rig.newProcess()
        controller.launch()
        let launch = try #require(rig.fileLines("launch").first)
        #expect(launch["platform"] == "simulated-device")
        #expect(launch["state"] == nil, "no application state at launch: it reads background until a scene connects (H-03)")
        #expect(launch["protectedDataAvailable"] == "true")
        #expect(launch["classA"] == "absent", "no canary before the first Start: absent, not unreadable (H-04)")
        #expect(launch["protection"] == classC)
        #expect(launch["sinceBoot"] == "86400.0")
        #expect(launch["boot"] == "2026-10-21T09:00:00.000Z")
        #expect(rig.fileLines("previous-session").first?["result"] == "none")
        #expect(rig.fileLines("verify").isEmpty)
        #expect(rig.store.openAttempts == 0)
        #expect(rig.scheduler.calls == 1)
        #expect(controller.runState == .idle)
        #expect(rig.mirror.lines == rig.sink.lines, "every line also goes to the unified log")
    }

    @Test("start: the tone at the test volume 0.01, the library opened with D17's durability, the canary made, the run recorded")
    func start() throws {
        let rig = Rig()
        let controller = try rig.newProcess()
        controller.launch()
        controller.start()
        #expect(controller.runState == .running)
        #expect(rig.player.startedVolumes == [0.01])
        let start = try #require(rig.fileLines("start").first)
        #expect(start["volume"] == "0.01")
        #expect(start["volumeReason"] == "test-volume")
        #expect(start["audio"] == "playing")
        #expect(start["audioCategory"] == "AVAudioSessionCategoryPlayback", "the category read back (review R2-H-03)")
        #expect(start["protection"] == classC)
        #expect(start["durability"] == "journal_mode=wal,synchronous=FULL,fullfsync=1,checkpoint_fullfsync=1")
        #expect(start["store"] == "open")
        #expect(start["canary"] == "created")
        #expect(start["session"] == "ok")
        #expect(start["item"] == "0")
        #expect(rig.sessions.stored?.run == start["run"])
        #expect(rig.sessions.stored?.stoppedCleanly == false)
        #expect(rig.sessions.stored?.bootTime == rig.device.boot)
    }

    @Test("SYLVIA_AUDIBLE_PLAYBACK=1 plays at full volume; any other value plays at 0.01", arguments: [
        ("1", Float(1)), ("0", Float(0.01)), ("yes", Float(0.01)), ("", Float(0.01)),
    ])
    func volume(value: String, expected: Float) throws {
        let rig = Rig()
        let controller = try rig.newProcess(environment: value.isEmpty ? [:] : ["SYLVIA_AUDIBLE_PLAYBACK": value])
        controller.launch()
        controller.start()
        #expect(rig.player.startedVolumes == [expected])
    }

    @Test("attempts while unlocked: each saved, read back equal, its file written and read, classes ok, acknowledged")
    func attemptsUnlocked() throws {
        let rig = Rig()
        let controller = try rig.newProcess()
        controller.launch()
        controller.start()
        rig.ticks(controller, 3)
        let attempts = rig.fileLines("attempt")
        #expect(attempts.count == 3)
        for (index, line) in attempts.enumerated() {
            #expect(line["n"] == "\(index + 1)")
            #expect(line["item"] == "\(index)")
            #expect(line["t"] == HarnessLog.seconds(Double(2 * (index + 1))))
            #expect(line["protectedDataAvailable"] == "true")
            #expect(line["classA"] == "readable")
            #expect(line["save"] == "saved")
            #expect(line["readback"] == "equal")
            #expect(line["file"] == "ok")
            #expect(line["classes"] == "ok")
            #expect(line["session"] == "ok")
            #expect(line["error"] == nil)
        }
        #expect(rig.store.committed.keys.sorted() == [0, 1, 2])
        #expect(rig.sessions.stored?.acknowledged == 3)
        #expect(rig.sessions.stored?.attempts == 3)
        expectHonest(rig)
    }

    @Test("locked after the first unlock for 5 minutes: class A unreadable, protected data unavailable, every class-C attempt still acknowledged")
    func lockedAfterFirstUnlock() throws {
        let rig = Rig()
        let controller = try rig.newProcess()
        controller.launch()
        controller.start()
        rig.ticks(controller, 3)
        rig.device.lock = .lockedAfterFirstUnlock
        rig.device.stateName = "background"
        controller.protectedDataWillBecomeUnavailable()
        rig.ticks(controller, 150)
        rig.device.lock = .unlocked
        rig.device.stateName = "active"
        controller.protectedDataDidBecomeAvailable()
        rig.ticks(controller, 2)

        let locked = rig.fileLines("attempt").filter { $0["protectedDataAvailable"] == "false" }
        #expect(locked.count == 150)
        #expect(locked.allSatisfy { $0["classA"] == "unreadable" && $0["save"] == "saved" && $0["readback"] == "equal"
            && $0["file"] == "ok" && $0["classes"] == "ok" && $0["app"] == "background" })
        let record = try #require(controller.record)
        #expect(record.attempts == 155)
        #expect(record.acknowledged == 155)
        #expect(record.lockedAttempts == 150)
        #expect(record.lockedFailures == 0)
        #expect(record.classAUnreadable == 150)
        #expect(record.failures == 0)
        #expect(record.gaps == 0)
        let events = rig.fileLines("event").map { $0["name"] ?? "" }
        #expect(events == ["protected-data-will-become-unavailable", "protected-data-did-become-available"])
        #expect(rig.fileLines("gap").isEmpty)
        #expect(!rig.sink.lines.contains { $0.contains("written-late=") }, "class C stays writable while locked")
        #expect(rig.fileLines("summary").map { $0["attempts"] } == ["30", "60", "90", "120", "150"])
        expectHonest(rig)
    }

    @Test("restart, then a background launch before the first unlock: recorded in the unified log and kept, nothing written, created or changed")
    func backgroundLaunchBeforeFirstUnlock() throws {
        let rig = Rig()
        let first = try rig.newProcess()
        first.launch()
        first.start()
        rig.ticks(first, 5)
        rig.device.lock = .lockedAfterFirstUnlock
        rig.ticks(first, 10)
        let fileLinesBefore = rig.sink.lines
        let recordBefore = rig.sessions.stored
        let committedBefore = rig.store.committed

        rig.device.restart(offFor: 40)
        let second = try rig.newProcess()
        second.launch()
        let passed = second.backgroundRefresh()

        #expect(!passed)
        #expect(rig.sink.lines == fileLinesBefore, "the class-C log file cannot be written before the first unlock")
        #expect(rig.sessions.stored == recordBefore)
        #expect(rig.store.committed == committedBefore)
        #expect(!rig.store.isOpen)
        #expect(second.runState == .idle)
        let launch = try #require(rig.mirrorLines("launch").last)
        #expect(launch["state"] == nil)
        #expect(launch["protectedDataAvailable"] == "false")
        #expect(launch["classA"] == "unreadable")
        #expect(launch["sinceBoot"] == "20.0")
        let previous = try #require(rig.mirrorLines("previous-session").last)
        #expect(previous["result"] == "unreadable")
        #expect(previous["error"] == "NSCocoaErrorDomain:513/NSPOSIXErrorDomain:1")
        let verifies = rig.mirrorLines("verify")
        #expect(verifies.count == 2)
        #expect(verifies.allSatisfy { $0["result"] == "could-not-read" && $0["error"] == "NSCocoaErrorDomain:513/NSPOSIXErrorDomain:1" })
        #expect(rig.mirrorLines("file-probe").last?["file"] == "failed")
        #expect(rig.mirrorLines("event").contains { $0["name"] == "log-file-unwritable" })
        #expect(second.pendingLineCount > 0)
        #expect(!rig.mirror.lines.contains { $0.contains("/private/var") }, "no path in any line")
    }

    @Test("the first unlock: the lines kept before it are written in order, each marked written-late, then the run's check passes")
    func firstUnlockWritesKeptLines() throws {
        let rig = Rig()
        let first = try rig.newProcess()
        first.launch()
        first.start()
        rig.ticks(first, 4)
        rig.device.restart(offFor: 40)
        let second = try rig.newProcess()
        second.launch()
        second.backgroundRefresh()
        let kept = rig.mirror.lines.suffix(second.pendingLineCount)
        let countBefore = rig.sink.lines.count

        rig.device.advance(60)
        rig.device.lock = .unlocked
        rig.device.stateName = "active"
        second.protectedDataDidBecomeAvailable()

        #expect(second.pendingLineCount == 0)
        let written = Array(rig.sink.lines.dropFirst(countBefore))
        let late = written.filter { $0.contains(" written-late=") }
        #expect(late.count == kept.count)
        #expect(late.map { $0.replacing(/\s+written-late=\S+/, with: "") } == Array(kept), "the same lines, in the order they were recorded")
        for line in late {
            let fields = HarnessLog.fields(of: line)
            let recorded = try #require(fields["time"])
            let writtenAt = try #require(fields["written-late"])
            #expect(recorded == "2026-10-22T09:01:08.000Z", "recorded before the first unlock, 20 s after the boot")
            #expect(writtenAt == "2026-10-22T09:02:08.000Z", "written at the first unlock")
        }
        let after = written.filter { !$0.contains(" written-late=") }.map(HarnessLog.fields(of:))
        #expect(after.map { $0["event"] ?? "" } == ["event", "event", "previous-session", "verify", "verify-classes"])
        #expect(after.prefix(2).map { $0["name"] } == ["log-file-writable-again", "protected-data-did-become-available"])
        #expect(after.first?["writtenLate"] == "\(late.count)")
        // The record that was unreadable at the launch is read now, once, and the library checked.
        #expect(after[2]["when"] == "protected-data-available")
        #expect(after[2]["result"] == "ended-by-restart")
        #expect(after[3]["result"] == "ok")
        #expect(after[3]["acknowledged"] == "4")
        #expect(second.record?.acknowledged == 4)
        second.protectedDataDidBecomeAvailable()
        #expect(rig.fileLines("previous-session").map { $0["result"] } == ["none", "unreadable", "ended-by-restart"],
                "the first process's launch, the second's (written late) and its one recheck: no second recheck")

        let third = try rig.newProcess()
        third.launch()
        let previous = try #require(rig.fileLines("previous-session").last)
        #expect(previous["when"] == "launch")
        #expect(previous["result"] == "ended-by-restart")
        #expect(rig.fileLines("verify").last?["result"] == "ok")
        #expect(rig.fileLines("verify").last?["acknowledged"] == "4")
    }

    @Test("opened after the first unlock: the run ended by the restart, its counters reported, every acknowledged item verified")
    func openedAfterFirstUnlock() throws {
        let rig = Rig()
        let first = try rig.newProcess()
        first.launch()
        first.start()
        let run = try #require(first.record?.run)
        rig.ticks(first, 5)
        rig.device.lock = .lockedAfterFirstUnlock
        rig.ticks(first, 150)
        rig.device.restart(offFor: 40)
        rig.device.advance(120)
        rig.device.lock = .unlocked
        rig.device.stateName = "active"

        let second = try rig.newProcess()
        second.launch()
        let previous = try #require(rig.fileLines("previous-session").last)
        #expect(previous["result"] == "ended-by-restart")
        #expect(previous["run"] == run)
        #expect(previous["attempts"] == "155")
        #expect(previous["acknowledged"] == "155")
        #expect(previous["failures"] == "0")
        #expect(previous["lockedAttempts"] == "150")
        #expect(previous["lockedFailures"] == "0")
        #expect(previous["gaps"] == "0")
        #expect(previous["lastRecordToBoot"] == "40.0")
        let verify = try #require(rig.fileLines("verify").last)
        #expect(verify["result"] == "ok")
        #expect(verify["run"] == run)
        #expect(verify["acknowledged"] == "155")
        #expect(verify["libraryCaptures"] == "155")
        #expect(verify["extra"] == "0")
        #expect(verify["integrity"] == "ok")
        #expect(verify["foreignKeyViolations"] == "0")
        #expect(verify["failures"] == "0")
        #expect(verify["classes"] == "ok")
        #expect(rig.fileLines("verify-classes").last?["library.sqlite"] == classC)
        #expect(rig.inspector.inspections.last == true, "the check after a launch reads every file and directory")
        #expect(!rig.store.isOpen, "closed again: no run is active")
        #expect(second.record?.acknowledged == 155)
        second.start()
        #expect(rig.fileLines("start").last?["item"] == "155", "a new run continues the library")
    }

    @Test("a run that ended in the same boot without Stop is reported as ended-without-stop, not as a restart")
    func endedWithoutStop() throws {
        let rig = Rig()
        let first = try rig.newProcess()
        first.launch()
        first.start()
        rig.ticks(first, 3)
        rig.device.advance(100)
        let second = try rig.newProcess()
        second.launch()
        let previous = try #require(rig.fileLines("previous-session").last)
        #expect(previous["result"] == "ended-without-stop")
        #expect(previous["lastRecordToBoot"] == nil)
        #expect(rig.fileLines("verify").last?["result"] == "ok")
    }

    @Test("Stop: the tone stops, the run is recorded as stopped, a summary and a full check follow; the next launch reads stopped-cleanly")
    func stopAndRelaunch() throws {
        let rig = Rig()
        let controller = try rig.newProcess()
        controller.launch()
        controller.start()
        rig.ticks(controller, 4)
        rig.device.advance(1)
        controller.stop()
        #expect(controller.runState == .stopped)
        #expect(rig.player.stops == 1)
        #expect(!rig.player.isPlaying)
        #expect(!rig.store.isOpen)
        let stop = try #require(rig.fileLines("stop").last)
        #expect(stop["attempts"] == "4")
        #expect(stop["acknowledged"] == "4")
        #expect(stop["session"] == "ok")
        #expect(rig.sessions.stored?.stoppedCleanly == true)
        #expect(rig.fileLines("verify").last?["result"] == "ok")
        controller.tick()
        #expect(rig.fileLines("attempt").count == 4, "no attempt after Stop")

        rig.device.advance(30)
        let next = try rig.newProcess()
        next.launch()
        #expect(rig.fileLines("previous-session").last?["result"] == "stopped-cleanly")
    }

    @Test("a pause longer than the gap threshold is recorded as a gap; the threshold itself is not", arguments: [
        (5.0, false), (5.1, true), (30.0, true),
    ])
    func gap(pause: Double, isGap: Bool) throws {
        let rig = Rig()
        let controller = try rig.newProcess()
        controller.launch()
        controller.start()
        rig.ticks(controller, 2)
        rig.device.advance(pause)
        controller.tick()
        rig.ticks(controller, 2)
        let gaps = rig.fileLines("gap")
        #expect(gaps.count == (isGap ? 1 : 0))
        if isGap {
            #expect(gaps.first?["seconds"] == HarnessLog.seconds(pause))
            #expect(gaps.first?["after"] == "#2")
            #expect(controller.record?.gaps == 1)
            #expect(abs((controller.record?.longestGap ?? 0) - pause) < 0.001)
        }
        #expect(rig.fileLines("attempt").count == 5)
    }

    @Test("a read-back that differs is a failure: the item is never acknowledged, and the run keeps recording")
    func readBackDiffers() throws {
        let rig = Rig()
        rig.store.corrupt = [1]
        let controller = try rig.newProcess()
        controller.launch()
        controller.start()
        rig.ticks(controller, 3)
        let attempts = rig.fileLines("attempt")
        #expect(attempts.map { $0["readback"] } == ["equal", "differs", "differs"])
        #expect(attempts.map { $0["save"] } == ["saved", "saved", "already-saved"])
        #expect(attempts.allSatisfy { $0["item"] == ($0["n"] == "1" ? "0" : "1") })
        #expect(attempts[1]["reason"]?.contains("readback: item 1 differs") == true)
        #expect(controller.record?.acknowledged == 1)
        #expect(controller.record?.failures == 2)
        expectHonest(rig)
    }

    @Test("a save that committed but whose read-back failed is acknowledged once, at the retry, as already-saved")
    func readBackFailsThenRetry() throws {
        let rig = Rig()
        let controller = try rig.newProcess()
        controller.launch()
        controller.start()
        rig.store.readBackFailuresLeft = 1
        rig.ticks(controller, 2)
        let attempts = rig.fileLines("attempt")
        #expect(attempts[0]["save"] == "saved")
        #expect(attempts[0]["readback"] == "failed")
        #expect(attempts[0]["error"] == "readback:NSPOSIXErrorDomain:5")
        #expect(attempts[0]["acknowledged"] == "0")
        #expect(attempts[1]["item"] == "0")
        #expect(attempts[1]["save"] == "already-saved")
        #expect(attempts[1]["readback"] == "equal")
        #expect(attempts[1]["acknowledged"] == "1")
        #expect(rig.store.committed.count == 1, "no duplicate")
        expectHonest(rig)
    }

    @Test("another class read back is recorded as a failure, and nothing tries to change it")
    func classMismatch() throws {
        let rig = Rig()
        rig.inspector.mismatch = ProtectionItem(name: "library.sqlite-shm", expected: classC,
                                                actual: "NSFileProtectionCompleteUnlessOpen", matches: false)
        let controller = try rig.newProcess()
        controller.launch()
        controller.start()
        rig.ticks(controller, 1)
        let attempt = try #require(rig.fileLines("attempt").first)
        #expect(attempt["classes"] == "differs:library.sqlite-shm=NSFileProtectionCompleteUnlessOpen")
        #expect(attempt["readback"] == "equal")
        #expect(controller.record?.acknowledged == 1, "the save itself was durable and exact")
        #expect(controller.record?.failures == 1)
        controller.stop()
        #expect(rig.fileLines("verify").last?["result"] == "FAILED")
    }

    @Test("class C unavailable while a run is active: each attempt fails safely, the same item is retried, the lines are kept and written late in order")
    func classCUnavailableWhileRunning() throws {
        let rig = Rig()
        let controller = try rig.newProcess()
        controller.launch()
        controller.start()
        rig.ticks(controller, 2)
        rig.device.lock = .beforeFirstUnlock
        rig.ticks(controller, 3)
        #expect(controller.pendingLineCount == 4, "the unwritable-file event and three attempts")
        let failed = rig.mirrorLines("attempt").suffix(3)
        #expect(failed.allSatisfy { $0["save"] == "failed" && $0["item"] == "2" && $0["acknowledged"] == "2"
            && $0["readback"] == "not-attempted" && $0["file"] == "failed" && $0["session"] == "failed" })
        #expect(failed.first?["error"] == "save:NSCocoaErrorDomain:513/NSPOSIXErrorDomain:1,file:NSCocoaErrorDomain:513/NSPOSIXErrorDomain:1,session:NSCocoaErrorDomain:513/NSPOSIXErrorDomain:1")
        #expect(controller.record?.failures == 3)

        rig.device.lock = .unlocked
        rig.ticks(controller, 2)
        let attempts = rig.fileLines("attempt")
        #expect(attempts.count == 7)
        #expect(attempts.map { $0["item"] } == ["0", "1", "2", "2", "2", "2", "3"])
        #expect(attempts[5]["save"] == "saved")
        #expect(attempts.filter { $0["written-late"] != nil }.count == 3)
        #expect(rig.store.committed.keys.sorted() == [0, 1, 2, 3])
        #expect(controller.pendingLineCount == 0)
        expectHonest(rig)
    }

    @Test("a write of the run's record that fails while locked fails the attempt: counted on the screen at once, and saved with the next record that can be written (review H-02)")
    func sessionWriteFailsWhileLocked() throws {
        let rig = Rig()
        rig.sessions.failWhileLocked = true
        let controller = try rig.newProcess()
        controller.launch()
        controller.start()
        rig.ticks(controller, 3)
        rig.device.lock = .lockedAfterFirstUnlock
        rig.device.stateName = "background"
        controller.protectedDataWillBecomeUnavailable()
        rig.ticks(controller, 150)

        let locked = rig.fileLines("attempt").filter { $0["protectedDataAvailable"] == "false" }
        #expect(locked.count == 150)
        #expect(locked.allSatisfy { $0["session"] == "failed" && $0["save"] == "saved" && $0["readback"] == "equal"
            && $0["file"] == "ok" && $0["classes"] == "ok" && $0["error"] == "session:NSPOSIXErrorDomain:28" })
        let inMemory = try #require(controller.record)
        #expect(inMemory.failures == 150)
        #expect(inMemory.lockedAttempts == 150)
        #expect(inMemory.lockedFailures == 150)
        #expect(inMemory.acknowledged == 153, "each capture itself was durable and exact")
        #expect(controller.statusLine.contains("150 failed, 150 while locked (150 failed)"))
        #expect(rig.sessions.stored?.attempts == 3, "no record could be written while locked")
        #expect(rig.sessions.stored?.lockedFailures == 0)

        rig.device.lock = .unlocked
        rig.device.stateName = "active"
        controller.protectedDataDidBecomeAvailable()
        rig.ticks(controller, 1)
        let stored = try #require(rig.sessions.stored)
        #expect(stored.attempts == 154)
        #expect(stored.failures == 150, "the next record written carries the failures")
        #expect(stored.lockedAttempts == 150)
        #expect(stored.lockedFailures == 150)
        controller.stop()
        let stop = try #require(rig.fileLines("stop").last)
        #expect(stop["failures"] == "150")
        #expect(stop["lockedFailures"] == "150")
        expectHonest(rig)
    }

    @Test("a failed write of the record in an attempt that failed anyway is one failure, not two")
    func sessionWriteFailsInAFailedAttempt() throws {
        let rig = Rig()
        rig.store.corrupt = [0]
        rig.sessions.failWhileLocked = true
        let controller = try rig.newProcess()
        controller.launch()
        controller.start()
        rig.device.lock = .lockedAfterFirstUnlock
        rig.ticks(controller, 2)
        #expect(rig.fileLines("attempt").allSatisfy { $0["readback"] == "differs" && $0["session"] == "failed" })
        #expect(controller.record?.failures == 2)
        #expect(controller.record?.lockedFailures == 2)
    }

    @Test("a check without a readable run record is library-only, never ok or passed: no acknowledged item could be checked (review H-07)")
    func checkWithoutRecordIsLibraryOnly() throws {
        let rig = Rig()
        let first = try rig.newProcess()
        first.launch()
        first.start()
        rig.ticks(first, 5)
        first.stop()
        rig.sessions.damaged = true
        rig.store.corrupt = [2]
        rig.store.committed[2] = false
        rig.device.advance(30)

        let second = try rig.newProcess()
        second.launch()
        let previous = try #require(rig.fileLines("previous-session").last)
        #expect(previous["result"] == "unreadable")
        #expect(previous["error"] == "NSCocoaErrorDomain:4864")
        let verify = try #require(rig.fileLines("verify").last)
        #expect(verify["result"] == "library-only")
        #expect(verify["acknowledged"] == "unknown")
        #expect(verify["extra"] == "unknown")
        #expect(verify["reason"]?.contains("no run record: no acknowledged item was checked") == true)
        #expect(second.statusLine == "Idle. No run recorded. Last check: library only (no run record, so no item was checked).")
        #expect(second.verifyNow(), "the checks it could make passed")
        #expect(rig.fileLines("verify").last?["result"] == "library-only")

        rig.store.integrity = ["row 3 missing from index"]
        #expect(!second.verifyNow())
        #expect(rig.fileLines("verify").last?["result"] == "FAILED")
        #expect(second.statusLine.hasSuffix("Last check: FAILED."))
    }

    @Test("a canary that could not be made is absent, never counted as unreadable: a missing canary cannot detect the lock (review H-04)")
    func absentCanaryIsNotCountedAsLocked() throws {
        let rig = Rig()
        let controller = try rig.newProcess()
        controller.launch()
        rig.device.lock = .lockedAfterFirstUnlock
        controller.start()
        #expect(rig.fileLines("start").last?["canary"] == "failed")
        rig.ticks(controller, 5)
        #expect(rig.fileLines("attempt").allSatisfy { $0["classA"] == "absent" && $0["save"] == "saved" })
        #expect(controller.record?.classAUnreadable == 0)
        #expect(controller.record?.lockedAttempts == 5)
        rig.device.lock = .unlocked
        controller.stop()
        controller.start()
        #expect(rig.fileLines("start").last?["canary"] == "created")
        rig.device.lock = .lockedAfterFirstUnlock
        rig.ticks(controller, 3)
        #expect(rig.fileLines("attempt").suffix(3).allSatisfy { $0["classA"] == "unreadable" })
        #expect(controller.record?.classAUnreadable == 3)
    }

    @Test("a library that cannot be opened: the start and each attempt record the open's error, the open is tried again at every attempt, and the run continues once it opens")
    func libraryUnavailableAtStart() throws {
        let rig = Rig()
        let controller = try rig.newProcess()
        controller.launch()
        rig.device.lock = .beforeFirstUnlock
        controller.start()
        let start = try #require(rig.mirrorLines("start").last)
        #expect(start["store"] == "failed")
        #expect(start["canary"] == "failed")
        #expect(start["session"] == "failed")
        #expect(start["error"] == "canary:NSCocoaErrorDomain:513/NSPOSIXErrorDomain:1,open:NSCocoaErrorDomain:513/NSPOSIXErrorDomain:1,session:NSCocoaErrorDomain:513/NSPOSIXErrorDomain:1")
        #expect(controller.runState == .running)
        rig.ticks(controller, 2)
        let failed = rig.mirrorLines("attempt")
        #expect(failed.allSatisfy { $0["save"] == "failed" && $0["readback"] == "not-attempted" && $0["item"] == "0"
            && $0["error"]?.hasPrefix("open:NSCocoaErrorDomain:513") == true })
        #expect(rig.store.openAttempts == 3)
        rig.device.lock = .unlocked
        rig.ticks(controller, 1)
        let attempt = try #require(rig.fileLines("attempt").last)
        #expect(attempt["save"] == "saved")
        #expect(attempt["readback"] == "equal")
        #expect(attempt["item"] == "0")
        #expect(rig.store.opens == 1)
        expectHonest(rig)
    }

    @Test("a Start after a launch that could not read the last run's record reads it then, and continues the library")
    func startAfterUnreadableLaunch() throws {
        let rig = Rig()
        let first = try rig.newProcess()
        first.launch()
        first.start()
        rig.ticks(first, 3)
        rig.device.restart(offFor: 40)
        let second = try rig.newProcess()
        second.launch()
        #expect(second.record == nil)
        rig.device.lock = .unlocked
        second.start()
        #expect(rig.fileLines("start").last?["item"] == "3")
        rig.ticks(second, 1)
        #expect(rig.fileLines("attempt").last?["item"] == "3")
        #expect(rig.fileLines("attempt").last?["save"] == "saved")
        second.protectedDataDidBecomeAvailable()
        #expect(rig.fileLines("previous-session").count == 2, "the run's start replaced the launch's recheck")
    }

    @Test("an expired background refresh is recorded")
    func refreshExpired() throws {
        let rig = Rig()
        let controller = try rig.newProcess()
        controller.launch()
        controller.backgroundRefreshExpired()
        #expect(rig.fileLines("event").last?["name"] == "background-refresh-expired")
    }

    @Test("a tone that cannot start is recorded; the run still makes its attempts")
    func toneFails() throws {
        let rig = Rig()
        rig.player.startError = HarnessError.audio("AVAudioPlayer did not start")
        let controller = try rig.newProcess()
        controller.launch()
        controller.start()
        let start = try #require(rig.fileLines("start").first)
        #expect(start["audio"] == "failed")
        #expect(start["audioCategory"] == "-", "no category read back from a player that did not start")
        #expect(start["error"]?.hasPrefix("audio:") == true)
        #expect(start["reason"]?.contains("AVAudioPlayer did not start") == true)
        rig.ticks(controller, 1)
        #expect(rig.fileLines("attempt").first?["save"] == "saved")
    }

    @Test("interruptions and resumptions of the tone are recorded")
    func audioEvents() throws {
        let rig = Rig()
        let controller = try rig.newProcess()
        controller.launch()
        controller.start()
        rig.player.onEvent?("interruption-began")
        rig.player.onEvent?("interruption-ended resumed=true")
        let details = rig.fileLines("event").filter { $0["name"] == "audio" }.map { $0["detail"] }
        #expect(details == ["interruption-began", "interruption-ended_resumed=true"])
    }

    @Test("a background refresh while locked after the first unlock reads the library and writes class C")
    func backgroundRefreshWhileLocked() throws {
        let rig = Rig()
        let controller = try rig.newProcess()
        controller.launch()
        controller.start()
        rig.ticks(controller, 3)
        controller.stop()
        rig.device.lock = .lockedAfterFirstUnlock
        rig.device.stateName = "background"
        #expect(controller.backgroundRefresh())
        let refresh = try #require(rig.fileLines("background-refresh").last)
        #expect(refresh["protectedDataAvailable"] == "false")
        #expect(refresh["classA"] == "unreadable")
        #expect(rig.fileLines("verify").last?["result"] == "ok")
        #expect(rig.fileLines("verify").last?["acknowledged"] == "3")
        #expect(rig.fileLines("file-probe").last?["file"] == "ok")
        #expect(rig.scheduler.calls == 2)
    }

    @Test("the app's state changes and its termination are recorded")
    func lifecycleEvents() throws {
        let rig = Rig()
        let controller = try rig.newProcess()
        controller.launch()
        controller.appStateChanged(to: "background")
        controller.willTerminate()
        #expect(rig.fileLines("event").map { $0["name"] } == ["app-state", "will-terminate"])
        #expect(rig.fileLines("event").first?["state"] == "background")
    }

    @Test("launch is recorded once per process")
    func launchOnce() throws {
        let rig = Rig()
        let controller = try rig.newProcess()
        controller.launch()
        controller.launch()
        #expect(rig.fileLines("launch").count == 1)
    }

    @Test("lines beyond the limit kept for the log file are counted as dropped; the earliest are kept; all reach the unified log")
    func pendingLimit() throws {
        let rig = Rig()
        let controller = HarnessController(configuration: try HarnessConfiguration(pendingLimit: 3), environment: rig.environment,
                                           autoTick: false)
        rig.device.lock = .beforeFirstUnlock
        controller.launch()
        controller.appStateChanged(to: "background")
        controller.appStateChanged(to: "background")
        #expect(controller.pendingLineCount == 3)
        #expect(controller.droppedLineCount == rig.mirror.lines.count - 3)
        rig.device.lock = .unlocked
        controller.protectedDataDidBecomeAvailable()
        let late = rig.sink.lines.filter { $0.contains(" written-late=") }
        #expect(late.count == 3)
        #expect(HarnessLog.fields(of: late[0])["event"] == "launch")
        #expect(rig.fileLines("event").contains { $0["name"] == "log-file-writable-again" && $0["dropped"] == "\(controller.droppedLineCount)" })
    }

    @Test("the configuration accepts class C only", arguments: [
        FileProtectionType.complete, .completeUnlessOpen, FileProtectionType(rawValue: "NSFileProtectionCompleteWhenUserInactive"),
    ])
    func refusesOtherClasses(protection: FileProtectionType) {
        #expect(throws: HarnessError.protectionRefused(protection.rawValue)) {
            try HarnessConfiguration(protection: protection)
        }
    }

    @Test("the default configuration: class C, an attempt every 2 s, gaps above 5 s, the test volume")
    func defaults() throws {
        let configuration = try HarnessConfiguration()
        #expect(configuration.protection == .completeUntilFirstUserAuthentication)
        #expect(configuration.interval == 2)
        #expect(configuration.gapThreshold == 5)
        #expect(configuration.volume == 0.01)
        #expect(throws: HarnessError.self) { try HarnessConfiguration(interval: 5, gapThreshold: 5) }
    }
}
