import AVFoundation
import Foundation
import Testing

@Suite("Lock harness: log format and the previous run's classification")
struct LogFormatTests {
    @Test("times are UTC with milliseconds")
    func timestamp() {
        #expect(HarnessLog.timestamp(Date(timeIntervalSince1970: 1_792_659_600.125)) == "2026-10-22T09:00:00.125Z")
    }

    @Test("a line splits back into its fields; a value's spaces become underscores; the reason is quoted, single-quoted inside, on one line")
    func lineRoundTrip() {
        let line = HarnessLog.line(Date(timeIntervalSince1970: 1_792_659_600), "attempt",
                                   [("run", "ab12"), ("detail", "two words"), ("empty", ""), ("durability", "journal_mode=wal,synchronous=FULL")],
                                   reason: "save: SQLite error 14: \"capture\" failed\nsecond line")
        #expect(line == "2026-10-22T09:00:00.000Z attempt run=ab12 detail=two_words empty=- durability=journal_mode=wal,synchronous=FULL "
                + "reason=\"save: SQLite error 14: 'capture' failed second line\"")
        let fields = HarnessLog.fields(of: line)
        #expect(fields["time"] == "2026-10-22T09:00:00.000Z")
        #expect(fields["event"] == "attempt")
        #expect(fields["detail"] == "two_words")
        #expect(fields["durability"] == "journal_mode=wal,synchronous=FULL")
        #expect(fields["reason"] == "save: SQLite error 14: 'capture' failed second line")
        let late = HarnessLog.markedWrittenLate(line, at: Date(timeIntervalSince1970: 1_792_659_660))
        #expect(HarnessLog.fields(of: late)["written-late"] == "2026-10-22T09:01:00.000Z")
        #expect(HarnessLog.fields(of: late)["reason"] == fields["reason"])
        #expect(HarnessLog.fields(of: HarnessLog.markedWrittenLate("2026-10-22T09:00:00.000Z event name=x", at: .distantPast))["written-late"] != nil)
    }

    @Test("an error's code names it and the errors under it")
    @MainActor
    func errorCode() {
        #expect(HarnessLog.code(SimulatedDevice.classKeyUnavailable) == "NSCocoaErrorDomain:513/NSPOSIXErrorDomain:1")
        #expect(HarnessLog.code(NSError(domain: NSPOSIXErrorDomain, code: Int(EIO))) == "NSPOSIXErrorDomain:5")
    }

    @Test("a reason never carries an absolute path")
    @MainActor
    func reasonWithoutPaths() {
        let reason = HarnessLog.reason(SimulatedDevice.classKeyUnavailable)
        #expect(!reason.contains("/private"))
        #expect(reason.contains("harness.log"))
        let swiftError = HarnessError.invalidConfiguration("at /private/var/mobile/Containers/Data/Application/X/Library/a.sqlite now")
        #expect(HarnessLog.reason(swiftError) == "harness: invalid configuration: at …/a.sqlite now")
    }

    @Test("paths are cut to their last component; other slashes are kept", arguments: [
        ("open /private/var/mobile/Containers/Data/X/Library/library.sqlite failed", "open …/library.sqlite failed"),
        ("(/Users/someone/Git/sylvia/a.txt)", "(…/a.txt)"),
        ("\"/var/folders/xy/T/g05/x.bin\" missing", "\"…/x.bin\" missing"),
        ("path=/a/b", "path=…/b"),
        ("1/2 and and/or and /single", "1/2 and and/or and /single"),
    ])
    func scrubPaths(input: String, expected: String) {
        #expect(HarnessLog.scrubPaths(input) == expected)
    }

    @Test("the previous run: none, stopped cleanly, ended by a restart, ended in the same boot, boot unknown")
    func classification() {
        let start = Date(timeIntervalSince1970: 1_792_659_600)
        var record = SessionRecord(run: "r1", bootTime: start.addingTimeInterval(-3_600), startedAt: start, interval: 2, acknowledged: 0)
        record.lastRecordAt = start.addingTimeInterval(300)
        #expect(PreviousSession.classify(nil, currentBoot: start) == .none)
        let restartBoot = start.addingTimeInterval(345)
        #expect(PreviousSession.classify(record, currentBoot: restartBoot) == .endedByRestart(record, boot: restartBoot))
        #expect(PreviousSession.classify(record, currentBoot: record.bootTime) == .endedWithoutStop(record, boot: record.bootTime!))
        #expect(PreviousSession.classify(record, currentBoot: record.lastRecordAt) == .endedWithoutStop(record, boot: record.lastRecordAt),
                "a boot no later than the last record is the same boot")
        #expect(PreviousSession.classify(record, currentBoot: nil) == .endedBootUnknown(record))
        let fields = Dictionary(uniqueKeysWithValues: PreviousSession.classify(record, currentBoot: restartBoot).fields)
        #expect(fields["lastRecordToBoot"] == "45.0")
        #expect(fields["result"] == "ended-by-restart")
        var stopped = record
        stopped.stoppedCleanly = true
        #expect(PreviousSession.classify(stopped, currentBoot: restartBoot) == .stoppedCleanly(stopped))
    }
}

@Suite("Lock harness: the quiet tone")
struct ToneTests {
    @Test("one second of 16-bit mono PCM at 44.1 kHz in a RIFF/WAVE header")
    func header() {
        let data = QuietTone.wavData()
        #expect(data.count == 44 + 44_100 * 2)
        #expect(String(decoding: data[0..<4], as: UTF8.self) == "RIFF")
        #expect(String(decoding: data[8..<16], as: UTF8.self) == "WAVEfmt ")
        #expect(String(decoding: data[36..<40], as: UTF8.self) == "data")
        func u32(_ at: Int) -> UInt32 { data[at..<(at + 4)].enumerated().reduce(0) { $0 | UInt32($1.element) << (8 * UInt32($1.offset)) } }
        func u16(_ at: Int) -> UInt16 { UInt16(data[at]) | UInt16(data[at + 1]) << 8 }
        #expect(u32(4) == UInt32(data.count - 8))
        #expect(u16(20) == 1 && u16(22) == 1)
        #expect(u32(24) == 44_100)
        #expect(u16(34) == 16)
        #expect(u32(40) == 44_100 * 2)
    }

    @Test("441 Hz at -26 dBFS: 100 samples a cycle, so the second loops without a click")
    func samples() {
        let samples = QuietTone.samples()
        #expect(samples.count == 44_100)
        let peak = samples.map { abs(Int($0)) }.max() ?? 0
        #expect(peak <= Int((0.05 * Double(Int16.max)).rounded()))
        #expect(peak >= Int((0.049 * Double(Int16.max)).rounded()))
        #expect(samples[0] == 0)
        #expect((0..<(samples.count - QuietTone.samplesPerCycle)).allSatisfy { samples[$0] == samples[$0 + QuietTone.samplesPerCycle] })
        #expect(samples.count % QuietTone.samplesPerCycle == 0, "the loop's end meets its start")
    }

    @Test("the player plays the tone at the test volume 0.01, unmuted, in the playback category, and stops (simulator; plays through the Mac's output at 1 %)")
    @MainActor
    func playsQuietly() async throws {
        let player = TonePlayer()
        #expect(player.category == nil)
        try player.start(volume: HarnessVolume.quiet)
        defer { player.stop() }
        #expect(player.isPlaying)
        #expect(player.playerVolume == 0.01)
        #expect(player.category == AVAudioSession.Category.playback.rawValue, "the session's category, read back (review R2-H-03)")
        try await Task.sleep(for: .milliseconds(300))
        #expect(player.isPlaying)
        player.stop()
        #expect(!player.isPlaying)
        #expect(player.playerVolume == nil)
        #expect(player.category == nil)
    }
}
