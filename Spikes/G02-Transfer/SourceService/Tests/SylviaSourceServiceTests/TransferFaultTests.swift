import Foundation
import Synchronization
import Testing
@_spi(Testing) import SylviaSourceService
@_spi(Testing) import SylviaTransferClient
import SylviaTransferCore

/// T38-T40 with deterministic fault injection. Environment: host (macOS), in-process source on an
/// ephemeral loopback port, real TLS, the TransferKit engine as the client, 1 MiB parts.
@Suite("Transfer faults and recovery (T38, T39, T40)", .serialized)
struct TransferFaultTests {
    static let size = 6 * Harness.mib + 4321  // 7 parts
    static let original = Harness.bytes(seed: 21, count: size)

    struct Setup {
        let harness: Harness
        let client: SourceClient
        let itemID: String
        let staging: URL
    }

    func setUp(files: [String: [UInt8]]? = nil, title: String = "book") async throws -> Setup {
        let harness = try await Harness.make(files: files ?? ["book.epub": Self.original])
        let (client, _, _) = try await harness.pairDevice()
        let itemID = try await harness.itemID(titled: title)
        let staging = harness.root.deletingLastPathComponent().appendingPathComponent("phone-staging")
        return Setup(harness: harness, client: client, itemID: itemID, staging: staging)
    }

    func engine(_ setup: Setup, client: SourceClient? = nil, events: EventLog, options: TransferEngine.Options = .init(),
                hook: (@Sendable (TransferEngine.Event) async -> Void)? = nil) -> TransferEngine {
        TransferEngine(client: client ?? setup.client, itemID: setup.itemID, stagingRoot: setup.staging, options: options) { event in
            events.record(event)
            await hook?(event)
        }
    }

    /// Content requests per part offset, from the source's request log.
    func requestsPerOffset(_ harness: Harness) -> [Int64: Int] {
        var counts: [Int64: Int] = [:]
        for entry in harness.service.requestLog where entry.path.hasSuffix("/content") {
            if let range = entry.range, let first = Int64(range.dropFirst(6).split(separator: "-").first ?? "") {
                counts[first, default: 0] += 1
            }
        }
        return counts
    }

    static func readyBytes(_ outcome: TransferEngine.Outcome) throws -> [Data] {
        guard case .ready(_, let assets) = outcome else {
            Issue.record("expected ready, got \(outcome)")
            return []
        }
        return try assets.map { try Data(contentsOf: $0.url) }
    }

    static func log(_ name: String, _ setup: Setup, _ events: EventLog, _ extra: String = "") {
        var lines = ["host (macOS), in-process source, 1 MiB parts, asset \(size) bytes", extra]
        lines += setup.harness.service.requestLog.map { "request \($0.method) \($0.path) range=\($0.range ?? "-") -> \($0.status)\($0.fault.map { " fault=\($0)" } ?? "")" }
        lines += events.all.map { "event \($0)" }
        Evidence.write("faults/\(name).log", lines.filter { !$0.isEmpty }.joined(separator: "\n") + "\n")
    }

    // MARK: Baseline

    @Test func cleanTransferVerifiesEveryPartAndTheWholeFile() async throws {
        let setup = try await setUp()
        defer { await setup.harness.cleanUp() }
        let events = EventLog()
        let outcome = await engine(setup, events: events).run()
        #expect(try Self.readyBytes(outcome) == [Data(Self.original)])
        #expect(requestsPerOffset(setup.harness).values.allSatisfy { $0 == 1 })
        #expect(events.count { if case .partVerified = $0 { true } else { false } } == 7)
        #expect(events.count { if case .assetFinalized = $0 { true } else { false } } == 1)
        Self.log("clean-transfer", setup, events)
    }

    @Test func groupItemTransfersEveryMemberInOrder() async throws {
        let first = Harness.bytes(seed: 31, count: 2 * Harness.mib + 1)
        let second = Harness.bytes(seed: 32, count: 77)
        let setup = try await setUp(files: ["Book/01.mp3": first, "Book/02.mp3": second], title: "Book")
        defer { await setup.harness.cleanUp() }
        let outcome = await engine(setup, events: EventLog()).run()
        #expect(try Self.readyBytes(outcome) == [Data(first), Data(second)])
    }

    // MARK: T40: unsafe responses are never appended

    struct FaultCase: Sendable, CustomTestStringConvertible {
        let name: String
        let fault: ContentFault
        let expected: PartFailure
        let refreshesManifest: Bool
        var testDescription: String { name }
    }

    static let faultCases: [FaultCase] = [
        .init(name: "200 to a range request", fault: .ignoreRange, expected: .rangeIgnored, refreshesManifest: false),
        .init(name: "412", fault: .preconditionFailed, expected: .preconditionFailed, refreshesManifest: true),
        .init(name: "416", fault: .rangeNotSatisfiable, expected: .rangeNotSatisfiable, refreshesManifest: true),
        .init(name: "wrong part digest", fault: .corruptByte(at: 4096), expected: .digestMismatch, refreshesManifest: false),
        .init(name: "changed ETag", fault: .wrongETag, expected: .etagChanged, refreshesManifest: true),
        .init(name: "short 206", fault: .shortRange(by: 100), expected: .contentRangeMismatch, refreshesManifest: false),
        .init(name: "gzip encoding", fault: .gzipEncoding, expected: .unexpectedContentEncoding, refreshesManifest: false),
    ]

    @Test(arguments: faultCases)
    func faultOnOnePartRecoversWithoutAppendingInvalidBytes(_ faultCase: FaultCase) async throws {
        let setup = try await setUp()
        defer { await setup.harness.cleanUp() }
        let target = Int64(3 * Harness.mib)  // part 3
        setup.harness.faults.add { info in info.range?.lowerBound == target && info.attempt == 1 ? faultCase.fault : nil }
        let events = EventLog()
        let outcome = await engine(setup, events: events).run()
        #expect(try Self.readyBytes(outcome) == [Data(Self.original)], "\(faultCase.name)")
        #expect(events.all.contains(.partFailed(assetID: try #require(outcome.assetIDs.first), index: 3, failure: faultCase.expected)))
        let counts = requestsPerOffset(setup.harness)
        #expect(counts[target] == 2, "the faulty part is fetched again")
        // Parts verified before the fault are never fetched again; with two in flight, at most the
        // neighbouring part can be re-requested after a manifest refresh.
        for (offset, count) in counts where offset != target {
            #expect(count == 1, "part at \(offset) fetched \(count) times (\(faultCase.name))")
        }
        let manifestRequests = setup.harness.service.requestLog.filter { $0.path.hasSuffix("/manifest") }.count
        #expect(manifestRequests == (faultCase.refreshesManifest ? 2 : 1), "\(faultCase.name)")
        Self.log("fault-\(faultCase.name.replacingOccurrences(of: " ", with: "-"))", setup, events)
    }

    @Test func connectionDropMidPartRetriesOnlyThatPart() async throws {
        let setup = try await setUp()
        defer { await setup.harness.cleanUp() }
        let target = Int64(2 * Harness.mib)
        setup.harness.faults.add { info in info.range?.lowerBound == target && info.attempt == 1 ? .dropAfter(bytes: 300_000) : nil }
        let events = EventLog()
        let outcome = await engine(setup, events: events).run()
        #expect(try Self.readyBytes(outcome) == [Data(Self.original)])
        let failure = events.all.compactMap { event -> PartFailure? in
            if case .partFailed(_, 2, let failure) = event { failure } else { nil }
        }.first
        if case .transport = failure {} else { Issue.record("expected a transport failure, got \(String(describing: failure))") }
        let counts = requestsPerOffset(setup.harness)
        #expect(counts[target] == 2)
        #expect(counts.filter { $0.key != target }.values.allSatisfy { $0 == 1 })
        Self.log("connection-drop-mid-part", setup, events)
    }

    @Test func persistentFaultPausesAndKeepsVerifiedParts() async throws {
        let setup = try await setUp()
        defer { await setup.harness.cleanUp() }
        let target = Int64(5 * Harness.mib)
        let enabled = Mutex(true)
        setup.harness.faults.add { info in enabled.withLock { $0 } && info.range?.lowerBound == target ? .corruptByte(at: 10) : nil }
        var options = TransferEngine.Options()
        options.concurrency = 1
        let events = EventLog()
        let first = await engine(setup, events: events, options: options).run()
        guard case .paused(let reason, let progress) = first else { Issue.record("expected paused, got \(first)"); return }
        #expect(reason == .repeatedPartFailure)
        // Every part except the failing one was verified: the engine keeps going around a bad part.
        #expect(progress.verifiedBytes == Int64(Self.size - Harness.mib))
        #expect(!reason.nextStep.isEmpty)
        // The fault clears (for example the disk recovered); a new engine resumes from the journal.
        enabled.withLock { $0 = false }
        let before = requestsPerOffset(setup.harness)
        let second = await engine(setup, events: events, options: options).run()
        #expect(try Self.readyBytes(second) == [Data(Self.original)])
        let after = requestsPerOffset(setup.harness)
        for offset in stride(from: Int64(0), to: target, by: Harness.mib) {
            #expect(after[offset] == before[offset], "verified part at \(offset) must not be fetched again")
        }
        #expect(events.all.contains { if case .resumed(_, 6) = $0 { true } else { false } })
        Self.log("persistent-fault-then-resume", setup, events)
    }

    @Test func interruptedEngineResumesWithoutRefetchingVerifiedParts() async throws {
        let setup = try await setUp()
        defer { await setup.harness.cleanUp() }
        var options = TransferEngine.Options()
        options.concurrency = 1
        let events = EventLog()
        let verified = Mutex(0)
        let interrupted = engine(setup, events: events, options: options) { event in
            if case .partVerified = event, verified.withLock({ $0 += 1; return $0 }) == 3 {
                withUnsafeCurrentTask { $0?.cancel() }
            }
        }
        let task = Task { await interrupted.run() }
        let first = await task.value
        guard case .paused(.cancelled, let progress) = first else { Issue.record("expected cancelled, got \(first)"); return }
        #expect(progress.verifiedBytes >= 3 * Int64(Harness.mib))
        let second = await engine(setup, events: events, options: options).run()
        #expect(try Self.readyBytes(second) == [Data(Self.original)])
        #expect(requestsPerOffset(setup.harness).values.allSatisfy { $0 <= 2 })
        for offset in [0, 1, 2].map({ Int64($0 * Harness.mib) }) {
            #expect(requestsPerOffset(setup.harness)[offset] == 1)
        }
        Self.log("interrupted-engine-resume", setup, events)
    }

    // MARK: T39: source mutation never yields a mixed-version file

    @Test func mutationOfALaterRegionKeepsIdenticalPartsAndYieldsTheNewVersion() async throws {
        let setup = try await setUp()
        defer { await setup.harness.cleanUp() }
        let source = setup.harness.root.appendingPathComponent("book.epub")
        var modified = Self.original
        for index in (5 * Harness.mib + 10)..<(5 * Harness.mib + 20) { modified[index] ^= 0xA5 }  // only part 5 changes
        let patch = Array(modified[(5 * Harness.mib + 10)..<(5 * Harness.mib + 20)])
        let mutated = Mutex(false)
        var options = TransferEngine.Options()
        options.concurrency = 1
        let events = EventLog()
        let outcome = await engine(setup, events: events, options: options) { event in
            if case .partVerified(_, 2) = event, !mutated.withLock({ $0 }) {
                mutated.withLock { $0 = true }
                try? Self.overwriteInPlace(source, offset: 5 * Harness.mib + 10, bytes: patch)
            }
        }.run()
        let bytes = try Self.readyBytes(outcome)
        #expect(bytes == [Data(modified)])
        #expect(bytes != [Data(Self.original)])
        let change = events.all.first { if case .versionChanged = $0 { true } else { false } }
        guard case .versionChanged(let from, let to, let kept, let discarded)? = change else { Issue.record("no version change"); return }
        #expect(from != to)
        #expect(kept == 3 && discarded == 0)  // parts 0-2 had identical bytes in the new version
        #expect(requestsPerOffset(setup.harness)[0] == 1)
        #expect(setup.harness.service.requestLog.contains { $0.status == 412 })
        Self.log("mutation-later-region", setup, events)
    }

    @Test func mutationOfAnAlreadyVerifiedRegionRefetchesThatPart() async throws {
        let setup = try await setUp()
        defer { await setup.harness.cleanUp() }
        let source = setup.harness.root.appendingPathComponent("book.epub")
        var modified = Self.original
        modified[Harness.mib + 1] ^= 0xFF  // part 1
        let patch = [modified[Harness.mib + 1]]
        let mutated = Mutex(false)
        var options = TransferEngine.Options()
        options.concurrency = 1
        let events = EventLog()
        let outcome = await engine(setup, events: events, options: options) { event in
            if case .partVerified(_, 3) = event, !mutated.withLock({ $0 }) {
                mutated.withLock { $0 = true }
                try? Self.overwriteInPlace(source, offset: Harness.mib + 1, bytes: patch)
            }
        }.run()
        #expect(try Self.readyBytes(outcome) == [Data(modified)])
        let change = events.all.first { if case .versionChanged = $0 { true } else { false } }
        guard case .versionChanged(_, _, let kept, let discarded)? = change else { Issue.record("no version change"); return }
        #expect(kept == 3 && discarded == 1)  // parts 0, 2, 3 kept; part 1 discarded
        #expect(requestsPerOffset(setup.harness)[Int64(Harness.mib)] == 2)
        Self.log("mutation-verified-region", setup, events)
    }

    @Test func mutationWhileAPartIsStreamingServesOnlyTheSnapshot() async throws {
        let setup = try await setUp()
        defer { await setup.harness.cleanUp() }
        let source = setup.harness.root.appendingPathComponent("book.epub")
        let target = Int64(4 * Harness.mib)
        var modified = Self.original
        for index in Int(target)..<Int(target) + Harness.mib { modified[index] = 0 }  // rewrite all of part 4 in place
        let mutated = Mutex(false)
        setup.harness.faults.bodyProgress.withLock {
            $0 = { _, offset, sent in
                // After the first chunk of part 4 has been sent, rewrite the original in place.
                guard offset == target, sent >= 262_144, !mutated.withLock({ $0 }) else { return }
                mutated.withLock { $0 = true }
                try? Self.overwriteInPlace(source, offset: Int(target), bytes: Array(repeating: 0, count: Harness.mib))
            }
        }
        var options = TransferEngine.Options()
        options.concurrency = 1
        let events = EventLog()
        let outcome = await engine(setup, events: events, options: options).run()
        // The streamed part came from the immutable clone: it verified against the old manifest.
        let assetID = try #require(outcome.assetIDs.first)
        #expect(events.all.contains(.partVerified(assetID: assetID, index: 4)))
        // The change was then detected, and the result is entirely the new version.
        #expect(try Self.readyBytes(outcome) == [Data(modified)])
        #expect(events.all.contains { if case .versionChanged = $0 { true } else { false } })
        #expect(mutated.withLock { $0 })
        #expect(await setup.harness.service.library.snapshotsWereCloned(itemID: setup.itemID) == true)
        Self.log("mutation-while-streaming", setup, events)
    }

    // MARK: Slow preparation

    @Test func slowPreparationAnswersPreparingAndTheClientWaits() async throws {
        // Preparation (clone, then hash) takes longer than the source waits before answering 503 `preparing`.
        let harness = try await Harness.make(files: ["book.epub": Self.original], preparationResponseLimit: .milliseconds(300))
        defer { await harness.cleanUp() }
        await harness.service.library.setAfterSnapshotHook { _ in try? await Task.sleep(for: .seconds(1.5)) }
        let (client, _, _) = try await harness.pairDevice()
        let itemID = try await harness.itemID(titled: "book")
        let setup = Setup(harness: harness, client: client, itemID: itemID,
                          staging: harness.root.deletingLastPathComponent().appendingPathComponent("phone-staging"))
        var options = TransferEngine.Options()
        options.preparationPollInterval = .milliseconds(200)
        let events = EventLog()
        let outcome = await engine(setup, events: events, options: options).run()
        #expect(try Self.readyBytes(outcome) == [Data(Self.original)])
        #expect(events.count { $0 == .sourcePreparing } >= 1)
        let manifestStatuses = harness.service.requestLog.filter { $0.path.hasSuffix("/manifest") }.map(\.status)
        #expect(manifestStatuses.first == 503 && manifestStatuses.last == 200)
        // Every poll joined the one preparation: a single snapshot version exists.
        let versions = try FileManager.default.contentsOfDirectory(atPath: harness.state.appendingPathComponent("snapshots").path)
        #expect(versions.count == 1)
        #expect(manifestStatuses.count >= 2)
        Self.log("slow-preparation", setup, events, "preparation delayed 1.5 s after the clone; the source answers 503 preparing after 0.3 s")

        // And when preparation outlasts the phone's patience, the job pauses instead of failing.
        let other = try await Harness.make(files: ["book.epub": Self.original], preparationResponseLimit: .milliseconds(100))
        defer { await other.cleanUp() }
        await other.service.library.setAfterSnapshotHook { _ in try? await Task.sleep(for: .seconds(2)) }
        let (otherClient, _, _) = try await other.pairDevice()
        let otherItem = try await other.itemID(titled: "book")
        var impatient = TransferEngine.Options()
        impatient.preparationPollInterval = .milliseconds(100)
        impatient.maxPreparationWait = .milliseconds(500)
        let paused = await TransferEngine(
            client: otherClient, itemID: otherItem,
            stagingRoot: other.root.deletingLastPathComponent().appendingPathComponent("phone-staging"), options: impatient
        ).run()
        guard case .paused(.sourcePreparing, let progress) = paused else { Issue.record("expected sourcePreparing, got \(paused)"); return }
        #expect(progress.verifiedBytes == 0)
    }

    // MARK: Final digest, revocation, identity change, unreachable source

    @Test func finalDigestMismatchIsNeverHandedOff() async throws {
        let setup = try await setUp()
        defer { await setup.harness.cleanUp() }
        setup.harness.faults.setCorruptManifestFullDigest(true)
        let events = EventLog()
        let outcome = await engine(setup, events: events).run()
        guard case .paused(.finalDigestMismatch, let progress) = outcome else { Issue.record("expected finalDigestMismatch, got \(outcome)"); return }
        #expect(progress.verifiedBytes == 0)
        #expect(!events.all.contains { if case .assetFinalized = $0 { true } else { false } })
        let verified = try FileManager.default.subpathsOfDirectory(atPath: setup.staging.path).filter { $0.hasSuffix("verified.bin") }
        #expect(verified.isEmpty)
        Self.log("final-digest-mismatch", setup, events)
    }

    @Test func revocationMidTransferPausesAndKeepsVerifiedBytes() async throws {
        let setup = try await setUp()
        defer { await setup.harness.cleanUp() }
        let devices = await setup.harness.service.pairing.pairedDevices()
        let deviceID = try #require(devices.first?.deviceID)
        let revoked = Mutex(false)
        var options = TransferEngine.Options()
        options.concurrency = 1
        let events = EventLog()
        let outcome = await engine(setup, events: events, options: options) { event in
            if case .partVerified(_, 1) = event, !revoked.withLock({ $0 }) {
                revoked.withLock { $0 = true }
                _ = try? await setup.harness.service.revoke(deviceID: deviceID)
            }
        }.run()
        guard case .paused(.reauthenticationRequired, let progress) = outcome else { Issue.record("expected reauthenticationRequired, got \(outcome)"); return }
        #expect(progress.verifiedBytes >= 2 * Int64(Harness.mib))
        Self.log("revoked-mid-transfer", setup, events)
    }

    @Test func sourceIdentityChangeMidTransferPausesForRepairing() async throws {
        let initial = try await setUp()
        var setup = initial
        let events = EventLog()
        var options = TransferEngine.Options()
        options.concurrency = 1
        let firstEngine = engine(initial, events: events, options: options) { event in
            if case .partVerified(_, 1) = event { withUnsafeCurrentTask { $0?.cancel() } }
        }
        let stop = Task {
            await firstEngine.run()
        }
        _ = await stop.value
        try setup.harness.identityStore.rotateKeyKeepingSourceID()
        let relaunched = try await setup.harness.restarted()
        defer { await relaunched.cleanUp() }
        setup = Setup(harness: relaunched, client: setup.client, itemID: setup.itemID, staging: setup.staging)
        let outcome = await engine(setup, events: events, options: options).run()
        #expect(outcome == .paused(.sourceIdentityChanged, TransferProgress(totalBytes: 0)))
        #expect(relaunched.service.decryptedBytesReceived == 0)
        #expect(relaunched.service.requestCount == 0)
    }

    @Test func unreachableSourcePausesThenResumesAfterRestart() async throws {
        let setup = try await setUp()
        let events = EventLog()
        var options = TransferEngine.Options()
        options.concurrency = 1
        let stopped = Mutex(false)
        let outcome = await engine(setup, events: events, options: options) { event in
            if case .partVerified(_, 2) = event, !stopped.withLock({ $0 }) {
                stopped.withLock { $0 = true }
                await setup.harness.service.stop()  // the Mac sleeps or quits
            }
        }.run()
        guard case .paused(.sourceUnreachable, let progress) = outcome else { Issue.record("expected sourceUnreachable, got \(outcome)"); return }
        #expect(progress.verifiedBytes == 3 * Int64(Harness.mib))
        let relaunched = try await setup.harness.restarted()
        defer { await relaunched.cleanUp() }
        let resumed = await engine(setup, events: events, options: options).run()
        #expect(try Self.readyBytes(resumed) == [Data(Self.original)])
        #expect(requestsPerOffset(relaunched).keys.min() == Int64(3 * Harness.mib))  // only the remaining parts
        Self.log("unreachable-then-resume", Setup(harness: relaunched, client: setup.client, itemID: setup.itemID, staging: setup.staging), events)
    }

    static func overwriteInPlace(_ url: URL, offset: Int, bytes: [UInt8]) throws {
        let handle = try FileHandle(forUpdating: url)  // same inode: an in-place edit, not a replacement
        try handle.seek(toOffset: UInt64(offset))
        try handle.write(contentsOf: Data(bytes))
        try handle.synchronize()
        try handle.close()
    }
}

extension TransferEngine.Outcome {
    var assetIDs: [String] {
        switch self {
        case .ready(let manifest, _): manifest.assets.map(\.assetID)
        case .paused: []
        }
    }
}
