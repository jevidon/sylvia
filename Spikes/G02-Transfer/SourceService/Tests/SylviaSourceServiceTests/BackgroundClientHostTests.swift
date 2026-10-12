import Foundation
import Synchronization
import Testing
@_spi(Testing) import SylviaSourceService
@_spi(Testing) import SylviaTransferClient
import SylviaTransferCore
@_spi(Testing) import SylviaBackgroundTransfer

/// The iOS background-download coordinator, run on the host against the in-process source (G0.2 part 2).
///
/// Environment: host (macOS). The coordinator uses its `.inProcess` session kind: the same download
/// tasks, task descriptions, pinned task-level trust answer, synchronous move, verified-only journal,
/// assembly and importer as the background session, but tasks end with the process. The real background
/// session (tasks that outlive the app, relaunch) is exercised on the simulator by the iOS harness.
@Suite("Background client on the host (15.4, 15.5, T38-T41)", .serialized)
struct BackgroundClientHostTests {
    static let size = 6 * Harness.mib + 4321  // 7 parts of 1 MiB
    static let original = Harness.bytes(seed: 41, count: size)

    struct Setup {
        let harness: Harness
        let paired: PairedSource
        let token: String
        let credentials: InMemoryCredentialStore
        let root: URL
        let itemID: String
    }

    func setUp(files: [String: [UInt8]]? = nil) async throws -> Setup {
        let harness = try await Harness.make(files: files ?? ["book.epub": Self.original])
        let (_, paired, token) = try await harness.pairDevice(name: "Host background client")
        let credentials = InMemoryCredentialStore()
        try credentials.saveToken(token, sourceID: paired.sourceID)
        let root = harness.root.deletingLastPathComponent().appendingPathComponent("phone-\(UUID().uuidString)")
        let itemID = try await harness.itemID(titled: "book")
        return Setup(harness: harness, paired: paired, token: token, credentials: credentials, root: root, itemID: itemID)
    }

    func coordinator(_ setup: Setup, options: BackgroundTransferCoordinator.Options = .init()) async throws -> BackgroundTransferCoordinator {
        let coordinator = try BackgroundTransferCoordinator(
            kind: .inProcess, root: setup.root, credentials: setup.credentials, options: options, appState: { "host_test" })
        try coordinator.sources.upsert(setup.paired)
        await coordinator.start()
        return coordinator
    }

    /// Waits until the job satisfies `predicate` (at most `seconds`).
    @discardableResult
    func wait(
        _ coordinator: BackgroundTransferCoordinator, _ jobID: String, seconds: Double = 30,
        until predicate: (BackgroundTransferCoordinator.JobView) -> Bool
    ) async throws -> BackgroundTransferCoordinator.JobView {
        let deadline = ContinuousClock.now + .seconds(seconds)
        while ContinuousClock.now < deadline {
            if let view = coordinator.job(jobID), predicate(view) { return view }
            try await Task.sleep(for: .milliseconds(20))
        }
        let view = coordinator.job(jobID)
        Issue.record("timed out; job is \(String(describing: view?.job.state)) \(String(describing: view?.job.pauseReason))")
        return try #require(view)
    }

    func requestsPerOffset(_ harness: Harness) -> [Int64: Int] {
        var counts: [Int64: Int] = [:]
        for entry in harness.service.requestLog where entry.path.hasSuffix("/content") {
            if let range = entry.range, let first = Int64(range.dropFirst(6).split(separator: "-").first ?? "") {
                counts[first, default: 0] += 1
            }
        }
        return counts
    }

    func importedBytes(_ coordinator: BackgroundTransferCoordinator, version: String) throws -> Data {
        let record = try #require(coordinator.importer.record(itemVersionID: version))
        #expect(record.completions == 1)
        let asset = try #require(record.assets.first)
        return try Data(contentsOf: coordinator.importer.destination(importID: record.importID, assetID: asset.assetID))
    }

    static func writeLog(_ name: String, _ setup: Setup, _ coordinator: BackgroundTransferCoordinator, _ notes: [String]) {
        var lines = ["environment: host (macOS), in-process source on 127.0.0.1, real TLS, 1 MiB parts; coordinator session kind: in-process download tasks"]
        lines += notes
        lines += setup.harness.service.requestLog.map {
            "source request \($0.method) \($0.path.replacingOccurrences(of: setup.itemID, with: "<item>")) range=\($0.range ?? "-") -> \($0.status)\($0.fault.map { " fault=\($0)" } ?? "")"
        }
        lines += coordinator.log.allEntries().map { entry in
            "client event \(entry.event) " + entry.fields.sorted { $0.key < $1.key }.map { "\($0.key)=\($0.value)" }.joined(separator: " ")
        }
        Evidence.write("background-host/\(name).log", lines.joined(separator: "\n") + "\n")
    }

    // MARK: Tests

    @Test func fullTransferVerifiesImportsOnceAndSendsReceipts() async throws {
        let setup = try await setUp()
        defer { await setup.harness.cleanUp() }
        let coordinator = try await coordinator(setup)
        defer { coordinator.invalidate() }
        let jobID = try await coordinator.startJob(sourceID: setup.paired.sourceID, itemID: setup.itemID, title: "book")
        let view = try await wait(coordinator, jobID) { $0.job.state == .imported && $0.job.receiptsAcknowledged }
        #expect(try importedBytes(coordinator, version: view.job.itemVersionID) == Data(Self.original))
        #expect(requestsPerOffset(setup.harness).count == 7)
        #expect(requestsPerOffset(setup.harness).values.allSatisfy { $0 == 1 })
        let events = coordinator.log.allEntries()
        #expect(events.filter { $0.event == "part_verified" }.count == 7)
        #expect(events.filter { $0.event == "trust_challenge" }.allSatisfy { $0.fields["result"] == "matched" && $0.fields["level"] == "task" })
        #expect(events.filter { $0.event == "receipt_acknowledged" }.count == 2)
        // The token never appears in the event log or the job folder.
        let logText = try String(contentsOf: coordinator.log.url, encoding: .utf8)
        #expect(!logText.contains(setup.token))
        // Staging is gone after the import; the imported file is the only copy.
        #expect(!FileManager.default.fileExists(atPath: coordinator.jobStore.stagingRoot(jobID).path))
        Self.writeLog("full-transfer", setup, coordinator, ["result: imported once, every part requested once, 2 receipts acknowledged"])
    }

    @Test func wrongPartDigestIsRefetchedAndNeverJournalled() async throws {
        let setup = try await setUp()
        defer { await setup.harness.cleanUp() }
        setup.harness.faults.add { info in
            info.range?.lowerBound == Int64(2 * Harness.mib) && info.attempt == 1 ? .corruptByte(at: 1234) : nil
        }
        let coordinator = try await coordinator(setup)
        defer { coordinator.invalidate() }
        let jobID = try await coordinator.startJob(sourceID: setup.paired.sourceID, itemID: setup.itemID, title: "book")
        let view = try await wait(coordinator, jobID) { $0.job.state == .imported }
        #expect(try importedBytes(coordinator, version: view.job.itemVersionID) == Data(Self.original))
        let counts = requestsPerOffset(setup.harness)
        #expect(counts[Int64(2 * Harness.mib)] == 2)
        #expect(counts.filter { $0.key != Int64(2 * Harness.mib) }.values.allSatisfy { $0 == 1 })
        let failures = coordinator.log.allEntries().filter { $0.event == "part_failed" }
        #expect(failures.count == 1 && failures.first?.fields["failure"] == "digestMismatch")
        Self.writeLog("wrong-part-digest", setup, coordinator, ["fault: part 2 first response has one flipped byte"])
    }

    @Test(arguments: [
        ("range-ignored", ContentFault.ignoreRange, 2), ("precondition-412", .preconditionFailed, 2),
        ("range-416", .rangeNotSatisfiable, 2), ("etag-changed", .wrongETag, 2), ("gzip", .gzipEncoding, 2),
        ("short-206", .shortRange(by: 10), 2), ("dropped-mid-part", .dropAfter(bytes: 70_000), 2),
    ])
    func badResponsesNeverReachVerifiedBytes(_ name: String, _ fault: ContentFault, _ expectedRequests: Int) async throws {
        let setup = try await setUp()
        defer { await setup.harness.cleanUp() }
        setup.harness.faults.add { info in
            info.range?.lowerBound == Int64(3 * Harness.mib) && info.attempt == 1 ? fault : nil
        }
        let coordinator = try await coordinator(setup)
        defer { coordinator.invalidate() }
        let jobID = try await coordinator.startJob(sourceID: setup.paired.sourceID, itemID: setup.itemID, title: "book")
        let view = try await wait(coordinator, jobID) { $0.job.state == .imported }
        #expect(try importedBytes(coordinator, version: view.job.itemVersionID) == Data(Self.original))
        #expect(requestsPerOffset(setup.harness)[Int64(3 * Harness.mib)] == expectedRequests)
        Self.writeLog("fault-\(name)", setup, coordinator, ["fault: \(fault) on the first response for part 3"])
    }

    @Test func sourceChangedMidTransferYieldsTheNewVersionNeverAMix() async throws {
        let setup = try await setUp()
        defer { await setup.harness.cleanUp() }
        var changed = Self.original
        for index in (5 * Harness.mib)..<(5 * Harness.mib + 100) { changed[index] ^= 0x5A }
        let file = setup.harness.root.appendingPathComponent("book.epub")
        let mutated = Mutex(false)
        let replacement = changed
        // The Mac user saves a new version while part 4 is being requested.
        setup.harness.faults.add { info in
            if info.range?.lowerBound == Int64(4 * Harness.mib), mutated.withLock({ let was = $0; $0 = true; return !was }) {
                try? Data(replacement).write(to: file)
            }
            return nil
        }
        let coordinator = try await coordinator(setup, options: { var o = BackgroundTransferCoordinator.Options(); o.window = 1; return o }())
        defer { coordinator.invalidate() }
        let jobID = try await coordinator.startJob(sourceID: setup.paired.sourceID, itemID: setup.itemID, title: "book")
        let firstVersion = try #require(coordinator.job(jobID)?.job.itemVersionID)
        let view = try await wait(coordinator, jobID) { $0.job.state == .imported }
        #expect(view.job.itemVersionID != firstVersion)
        #expect(try importedBytes(coordinator, version: view.job.itemVersionID) == Data(changed))
        let events = coordinator.log.allEntries()
        let change = try #require(events.first { $0.event == "version_changed" })
        // Parts verified before the change (0-3, and 4 if its old bytes were served before the change was
        // noticed) are byte-identical in the new version and are kept; the changed region is part 5.
        #expect(["4", "5"].contains(change.fields["kept_parts"] ?? ""))
        #expect(change.fields["discarded_parts"] == "0")
        #expect(events.contains { $0.event == "manifest_refresh_needed" && $0.fields["failure"] == "preconditionFailed" })
        Self.writeLog("source-changed-mid-transfer", setup, coordinator, ["mutation: bytes 5 MiB to 5 MiB+100 changed while part 4 was requested"])
    }

    @Test func revokedCredentialBlocksKeepsVerifiedBytesAndSurvivesRelaunch() async throws {
        let setup = try await setUp()
        defer { await setup.harness.cleanUp() }
        let service = setup.harness.service
        let deviceID = setup.paired.deviceID
        let revoked = Mutex(false)
        // The Mac owner revokes this phone while part 3 is streaming.
        setup.harness.faults.bodyProgress.withLock {
            $0 = { _, start, _ in
                if start == Int64(3 * Harness.mib), revoked.withLock({ let was = $0; $0 = true; return !was }) {
                    _ = try? await service.revoke(deviceID: deviceID)
                }
            }
        }
        var options = BackgroundTransferCoordinator.Options()
        options.window = 1
        let first = try await coordinator(setup, options: options)
        let jobID = try await first.startJob(sourceID: setup.paired.sourceID, itemID: setup.itemID, title: "book")
        let paused = try await wait(first, jobID) { $0.job.state == .paused }
        #expect(paused.job.pauseReason == .reauthenticationRequired)
        #expect(paused.verifiedParts >= 3)
        let verifiedBefore = paused.verifiedParts
        first.invalidate()

        // Relaunch: the job stays blocked, nothing is requested, verified bytes are still there.
        let requestsBefore = setup.harness.service.requestLog.count
        let second = try await coordinator(setup, options: options)
        let summary = try #require(second.lastReconciliation)
        #expect(summary.enqueued == 0 && summary.keptVerifiedParts == verifiedBefore)
        try await Task.sleep(for: .milliseconds(300))
        #expect(setup.harness.service.requestLog.count == requestsBefore)
        #expect(second.job(jobID)?.verifiedParts == verifiedBefore)

        // Without a credential at all (the app deleted it), resuming blocks again instead of requesting.
        try setup.credentials.deleteToken(sourceID: setup.paired.sourceID)
        second.resume(jobID: jobID)
        #expect(second.job(jobID)?.job.pauseReason == .reauthenticationRequired)
        #expect(setup.harness.service.requestLog.count == requestsBefore)

        // Pair again (new invitation, new token): resume fetches only the missing parts.
        let (_, repaired, token) = try await setup.harness.pairDevice(name: "Host background client again")
        try setup.credentials.saveToken(token, sourceID: repaired.sourceID)
        try second.sources.upsert(repaired)
        second.resume(jobID: jobID)
        let done = try await wait(second, jobID) { $0.job.state == .imported }
        #expect(try importedBytes(second, version: done.job.itemVersionID) == Data(Self.original))
        let authorized = setup.harness.service.requestLog.filter { $0.path.hasSuffix("/content") && $0.status == 206 }
        var verifiedTwice: [Int64: Int] = [:]
        for entry in authorized { if let range = entry.range, let first = Int64(range.dropFirst(6).split(separator: "-").first ?? "") { verifiedTwice[first, default: 0] += 1 } }
        #expect(verifiedTwice.values.allSatisfy { $0 == 1 }, "a part verified before the revocation was fetched again")
        second.invalidate()
        Self.writeLog("revoked-credential", setup, second, [
            "revocation by the Mac owner while part 3 streamed; relaunch kept \(verifiedBefore) verified parts and requested nothing; re-pairing resumed",
        ])
    }

    @Test func relaunchKeepsVerifiedPartsAndRequestsOnlyMissingOnes() async throws {
        let setup = try await setUp()
        defer { await setup.harness.cleanUp() }
        // Slow the body of part 4 so the "app" can be killed while it is in flight.
        let stop = Mutex(false)
        setup.harness.faults.bodyProgress.withLock {
            $0 = { _, start, _ in
                if start >= Int64(4 * Harness.mib), stop.withLock({ $0 }) == false { try? await Task.sleep(for: .milliseconds(200)) }
            }
        }
        var options = BackgroundTransferCoordinator.Options()
        options.window = 1
        let first = try await coordinator(setup, options: options)
        let jobID = try await first.startJob(sourceID: setup.paired.sourceID, itemID: setup.itemID, title: "book")
        _ = try await wait(first, jobID) { $0.verifiedParts >= 4 }
        first.invalidate()  // the process dies: in-process tasks are gone, a part body may be half written
        stop.withLock { $0 = true }
        try await waitUntilQuiet(first)
        let firstEntries = first.log.allEntries()
        let verifiedAtStop = Set(firstEntries.filter { $0.event == "part_verified" }.compactMap { $0.fields["part"] })

        let second = try await coordinator(setup, options: options)
        let summary = try #require(second.lastReconciliation)
        #expect(summary.keptVerifiedParts == verifiedAtStop.count)
        #expect(summary.enqueued == 1)
        let view = try await wait(second, jobID) { $0.job.state == .imported }
        #expect(try importedBytes(second, version: view.job.itemVersionID) == Data(Self.original))
        // Both coordinators share one event file; only entries written after the relaunch count here.
        let requestedAfter = Set(second.log.allEntries().dropFirst(firstEntries.count).filter { $0.event == "part_requested" }.compactMap { $0.fields["part"] })
        #expect(requestedAfter.isDisjoint(with: verifiedAtStop), "a verified part was requested again after relaunch")
        #expect(verifiedAtStop.count + requestedAfter.count == 7)
        Self.writeLog("relaunch-reconciliation", setup, second, [
            "first coordinator invalidated after \(verifiedAtStop.count) verified parts; second coordinator: kept \(summary.keptVerifiedParts), enqueued \(summary.enqueued)",
        ])
        second.invalidate()
    }

    /// Found in review: at relaunch the session may deliver a task's completion before `allTasks` answers, and
    /// still list that task. Adopting it would hold its part's slot forever (the job would never finish). Here a
    /// task for part 6 fails its digest and completes before reconciliation, and is then listed as outstanding.
    @Test func taskCompletedBeforeReconciliationIsNotAdopted() async throws {
        let setup = try await setUp()
        defer { await setup.harness.cleanUp() }
        let lastPart = Int64(6 * Harness.mib)
        setup.harness.faults.add { info in
            info.range?.lowerBound == lastPart && info.attempt == 1 ? .corruptByte(at: 99) : nil
        }
        var options = BackgroundTransferCoordinator.Options()
        options.window = 1
        let first = try await coordinator(setup, options: options)
        let jobID = try await first.startJob(sourceID: setup.paired.sourceID, itemID: setup.itemID, title: "book")
        _ = try await wait(first, jobID) { $0.verifiedParts >= 2 }
        first.invalidate()  // the process dies with part 6 never requested
        try await Task.sleep(for: .milliseconds(100))
        #expect(requestsPerOffset(setup.harness)[lastPart] == nil)

        let second = try BackgroundTransferCoordinator(
            kind: .inProcess, root: setup.root, credentials: setup.credentials, options: options, appState: { "host_test" })
        let token = setup.token
        let summary = await second.start(beforeReconciliation: { session in
            // Stands in for a task the system ran while the app was not running: part 6, attempt 1.
            guard let job = second.job(jobID)?.job, let manifest = try? second.jobStore.loadManifest(for: job),
                let asset = manifest.assets.first, let part = asset.parts.last,
                let base = second.sources.source(job.sourceID)?.endpoints.first?.baseURL()
            else { return [] }
            var request = URLRequest(url: base.appendingPathComponent("v1/assets/\(asset.assetID)/content"))
            request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
            request.setValue("bytes=\(part.offset)-\(part.offset + part.length - 1)", forHTTPHeaderField: "Range")
            request.setValue(asset.etag, forHTTPHeaderField: "If-Match")
            request.setValue("identity", forHTTPHeaderField: "Accept-Encoding")
            let task = session.downloadTask(with: request)
            task.taskDescription = TaskDescriptor(jobID: jobID, assetID: asset.assetID, partIndex: part.index, attempt: 1).encoded
            task.resume()
            let deadline = ContinuousClock.now + .seconds(20)
            while ContinuousClock.now < deadline,
                !second.log.allEntries().contains(where: { $0.event == "part_failed" && $0.fields["part"] == "\(asset.assetID):\(part.index)" })
            {
                try? await Task.sleep(for: .milliseconds(20))
            }
            return [task]
        })
        #expect(summary.completedBeforeReconciliation == 1)
        #expect(summary.adopted == 0)
        let view = try await wait(second, jobID) { $0.job.state == .imported }
        #expect(try importedBytes(second, version: view.job.itemVersionID) == Data(Self.original))
        #expect(requestsPerOffset(setup.harness)[lastPart] == 2)
        second.invalidate()
        Self.writeLog("completed-before-reconciliation", setup, second, [
            "part 6 (first response corrupted) completed before launch reconciliation and was listed again; not adopted, refetched once",
        ])
    }

    /// Review findings R1-04 and R2-01. Before the first unlock after a restart the job store's class C files
    /// cannot be read. The relaunched coordinator must then act on nothing: no session (so no outstanding task is
    /// listed, adopted or cancelled), no job paused or rewritten, no store written. chmod 000 stands in for the
    /// data-protection refusal, store by store, while `protectedDataAvailable` reports false (it is only logged);
    /// a background relaunch's completion handler is released at once when the launch defers; finally the files
    /// are readable again (the unlock) and the job finishes from its verified parts.
    @Test func unreadableStoresDeferLaunchWithoutCancellingOrOverwriting() async throws {
        let setup = try await setUp()
        defer { await setup.harness.cleanUp() }
        let hold = Mutex(true)
        setup.harness.faults.bodyProgress.withLock {
            $0 = { _, start, _ in
                while start >= Int64(3 * Harness.mib), hold.withLock({ $0 }) { try? await Task.sleep(for: .milliseconds(20)) }
            }
        }
        var options = BackgroundTransferCoordinator.Options()
        options.window = 1
        let first = try await coordinator(setup, options: options)
        // The stores hold more than this job: another paired Mac and an earlier import.
        var otherMac = setup.paired
        otherMac.sourceID = CanonicalID.make()
        otherMac.sourceName = "Other Mac"
        try first.sources.upsert(otherMac)
        let earlierFile = setup.root.appendingPathComponent("earlier.bin")
        try Data("earlier import".utf8).write(to: earlierFile)
        _ = try first.importer.importVerified(
            jobID: CanonicalID.make(), itemID: CanonicalID.make(), itemVersionID: CanonicalID.make(),
            assets: [.init(assetID: CanonicalID.make(), url: earlierFile, sha256: SHA256Hex.digest(Data("earlier import".utf8)), length: 14)])
        let jobID = try await first.startJob(sourceID: setup.paired.sourceID, itemID: setup.itemID, title: "book")
        _ = try await wait(first, jobID) { $0.verifiedParts >= 3 }
        first.invalidate()  // the phone restarts with parts 0-2 verified
        try await Task.sleep(for: .milliseconds(300))  // the cancelled task's last journal write lands first
        hold.withLock { $0 = false }

        let sourcesURL = first.sources.url
        let ledgerURL = first.importer.ledgerURL
        let jobURL = first.jobStore.directory(jobID).appendingPathComponent("job.json")
        let files = [sourcesURL, ledgerURL, jobURL]
        let before = try files.map { try Data(contentsOf: $0) }
        let requestsBefore = setup.harness.service.requestLog.count
        defer { for url in files { chmod(url.path, 0o644) } }

        let unlocked = Mutex(false)
        let second = try BackgroundTransferCoordinator(
            kind: .inProcess, root: setup.root, credentials: setup.credentials, options: options, appState: { "host_test" },
            protectedDataAvailable: { unlocked.withLock { $0 } })
        let sessions = Mutex(0)
        let hook: @Sendable (URLSession) async -> [URLSessionDownloadTask] = { _ in
            sessions.withLock { $0 += 1 }
            return []
        }
        var reasons: [String] = []
        // The files refuse reads: every store, then only the ledger and the job, then only the job record.
        // The first start is a background relaunch for session events: its completion handler is released.
        for url in files { #expect(chmod(url.path, 0) == 0) }
        let released = Mutex(0)
        second.setBackgroundEventsCompletion { released.withLock { $0 += 1 } }
        reasons.append(await second.start(beforeReconciliation: hook).deferredReason ?? "none")
        let releaseDeadline = ContinuousClock.now + .seconds(5)
        while released.withLock({ $0 }) == 0, ContinuousClock.now < releaseDeadline { try await Task.sleep(for: .milliseconds(20)) }
        #expect(released.withLock { $0 } == 1, "the background-events completion was not called when the launch deferred")
        #expect(chmod(sourcesURL.path, 0o644) == 0)
        reasons.append(await second.start(beforeReconciliation: hook).deferredReason ?? "none")
        #expect(chmod(ledgerURL.path, 0o644) == 0)
        reasons.append(await second.start(beforeReconciliation: hook).deferredReason ?? "none")
        #expect(reasons == ["sources_not_accessible", "imports_unreadable", "job_store_not_accessible"])
        #expect(released.withLock { $0 } == 1)
        #expect(second.log.allEntries().filter { $0.event == "start_deferred" }.allSatisfy { $0.fields["protected_data_available"] == "false" })

        // While deferred: no session was created, nothing was listed, cancelled or requested, and nothing
        // can be written over the stores that could not be read.
        #expect(sessions.withLock { $0 } == 0)
        #expect(second.jobViews().isEmpty)
        try await Task.sleep(for: .milliseconds(300))
        #expect(setup.harness.service.requestLog.count == requestsBefore)
        do {
            _ = try await second.startJob(sourceID: setup.paired.sourceID, itemID: setup.itemID, title: "book")
            Issue.record("a job was started while launch was deferred")
        } catch {}
        #expect(chmod(sourcesURL.path, 0) == 0)
        #expect(!second.sources.reload())
        #expect(throws: StoreUnreadable.self) { try second.sources.upsert(otherMac) }
        for url in files { #expect(chmod(url.path, 0o644) == 0) }
        #expect(try files.map { try Data(contentsOf: $0) } == before, "a store was written while launch was deferred")

        // The first unlock: launch runs, keeps the verified parts and finishes the job; both pairings and the
        // earlier import are still there.
        unlocked.withLock { $0 = true }
        let summary = await second.start(beforeReconciliation: hook)
        #expect(summary.deferredReason == nil)
        #expect(sessions.withLock { $0 } == 1)
        #expect(summary.keptVerifiedParts >= 3)
        let view = try await wait(second, jobID) { $0.job.state == .imported }
        #expect(try importedBytes(second, version: view.job.itemVersionID) == Data(Self.original))
        #expect(Set(second.sources.all.map(\.sourceID)) == [setup.paired.sourceID, otherMac.sourceID])
        #expect(second.importer.records.count == 2)
        let counts = requestsPerOffset(setup.harness)
        #expect(counts.filter { $0.key < Int64(3 * Harness.mib) }.values.allSatisfy { $0 == 1 }, "a part verified before the restart was fetched again")
        second.invalidate()
        Self.writeLog("unreadable-stores-deferred", setup, second, [
            "launch deferred, in order: \(reasons.joined(separator: ", ")); no session, no request, stores byte-identical",
            "then readable: kept \(summary.keptVerifiedParts) verified parts, imported once, 2 paired sources and 2 imports kept",
        ])
    }

    /// Review finding R1-05, with a real full volume: the phone's store is on a 32 MB APFS disk image that is
    /// filled while the transfer runs. The part that cannot be written pauses the job at once with
    /// insufficient_space (not source_unreachable, no repeated downloads); resuming while the disk is still full
    /// is refused by the space reservation without a request; after space is freed the job finishes.
    @Test func fullPhoneStoragePausesWithInsufficientSpaceNotSourceUnreachable() async throws {
        let setup = try await setUp()
        defer { await setup.harness.cleanUp() }
        let volume = try DiskImage(megabytes: 32)
        defer { volume.detach() }
        let hold = Mutex(true)
        setup.harness.faults.bodyProgress.withLock {
            $0 = { _, start, _ in
                while start >= Int64(3 * Harness.mib), hold.withLock({ $0 }) { try? await Task.sleep(for: .milliseconds(20)) }
            }
        }
        var options = BackgroundTransferCoordinator.Options()
        options.window = 1
        options.maxAttemptsPerPart = 4
        let phone = volume.mountPoint.appendingPathComponent("phone", isDirectory: true)
        let coordinator = try BackgroundTransferCoordinator(
            kind: .inProcess, root: phone, credentials: setup.credentials, options: options, appState: { "host_test" })
        try coordinator.sources.upsert(setup.paired)
        await coordinator.start()
        let jobID = try await coordinator.startJob(sourceID: setup.paired.sourceID, itemID: setup.itemID, title: "book")
        _ = try await wait(coordinator, jobID) { $0.verifiedParts >= 3 }
        try await waitForPartRequest(coordinator, index: 3)  // part 3 is held at the source from now on
        // Fill the volume so a 1 MiB part no longer fits, leaving room for the small job and journal files.
        let filler = try volume.fill(leaving: 1_536 * 1_024)
        let freeAfterFill = volume.availableBytes
        hold.withLock { $0 = false }
        let paused = try await wait(coordinator, jobID) { $0.job.state == .paused }
        #expect(paused.job.pauseReason == .insufficientSpace)
        #expect(paused.verifiedParts == 3)
        let failures = coordinator.log.recentEntries.filter { $0.event == "part_failed" }
        #expect(failures.map { $0.fields["failure"] } == ["localStorageFull"])
        #expect(requestsPerOffset(setup.harness)[Int64(3 * Harness.mib)] == 1, "the part was downloaded again although the disk was full")

        // Resume while still full: refused by the reservation, nothing requested.
        let requestsBefore = setup.harness.service.requestLog.count
        coordinator.resume(jobID: jobID)
        #expect(coordinator.job(jobID)?.job.pauseReason == .insufficientSpace)
        try await Task.sleep(for: .milliseconds(300))
        #expect(setup.harness.service.requestLog.count == requestsBefore)
        #expect(coordinator.log.recentEntries.contains { $0.event == "space_check_failed" })

        // Space freed: resume finishes from the verified parts.
        try FileManager.default.removeItem(at: filler)
        coordinator.resume(jobID: jobID)
        let view = try await wait(coordinator, jobID) { $0.job.state == .imported }
        #expect(try importedBytes(coordinator, version: view.job.itemVersionID) == Data(Self.original))
        let counts = requestsPerOffset(setup.harness)
        #expect(counts.filter { $0.key < Int64(3 * Harness.mib) }.values.allSatisfy { $0 == 1 })
        coordinator.invalidate()
        Self.writeLog("full-phone-storage", setup, coordinator, [
            "phone store on a 32 MB APFS disk image (hdiutil); filled after 3 verified parts to \(freeAfterFill) free bytes",
            "result: paused insufficient_space after one request for the part that did not fit; resume while full refused by the reservation without a request; finished after space was freed",
        ])
    }

    /// Plan 15.4 reservation when a job is created: less free space than the bytes still to arrive plus one
    /// part per outstanding task pauses the job with insufficient_space before any part is requested.
    @Test func newJobWithoutEnoughFreeSpacePausesBeforeAnyRequest() async throws {
        let setup = try await setUp()
        defer { await setup.harness.cleanUp() }
        let capacity = Mutex<Int64>(Int64(Self.size))  // less than the asset plus the window
        var options = BackgroundTransferCoordinator.Options()
        options.availableCapacity = { _ in capacity.withLock { $0 } }
        let coordinator = try await coordinator(setup, options: options)
        defer { coordinator.invalidate() }
        let jobID = try await coordinator.startJob(sourceID: setup.paired.sourceID, itemID: setup.itemID, title: "book")
        #expect(coordinator.job(jobID)?.job.pauseReason == .insufficientSpace)
        try await Task.sleep(for: .milliseconds(300))
        #expect(requestsPerOffset(setup.harness).isEmpty)
        let check = try #require(coordinator.log.allEntries().first { $0.event == "space_check_failed" })
        #expect(check.fields["required_bytes"] == String(Int64(Self.size) + 4 * Int64(Harness.mib)))
        capacity.withLock { $0 = 1 << 40 }
        coordinator.resume(jobID: jobID)
        let view = try await wait(coordinator, jobID) { $0.job.state == .imported }
        #expect(try importedBytes(coordinator, version: view.job.itemVersionID) == Data(Self.original))
        Self.writeLog("space-reservation", setup, coordinator, [
            "free space reported as \(Self.size) bytes: job paused insufficient_space with no request; resumed with space and imported",
        ])
    }

    /// A local write error other than a full disk (here the part folder refuses writes) is retried, and when it
    /// persists the job pauses with storage_unavailable, never source_unreachable (review finding R1-05).
    @Test func persistentLocalWriteErrorPausesWithStorageUnavailable() async throws {
        let setup = try await setUp()
        defer { await setup.harness.cleanUp() }
        let hold = Mutex(true)
        setup.harness.faults.bodyProgress.withLock {
            $0 = { _, start, _ in
                while start >= Int64(2 * Harness.mib), hold.withLock({ $0 }) { try? await Task.sleep(for: .milliseconds(20)) }
            }
        }
        var options = BackgroundTransferCoordinator.Options()
        options.window = 1
        options.retryBaseDelay = 0.05
        let coordinator = try await coordinator(setup, options: options)
        defer { coordinator.invalidate() }
        let jobID = try await coordinator.startJob(sourceID: setup.paired.sourceID, itemID: setup.itemID, title: "book")
        _ = try await wait(coordinator, jobID) { $0.verifiedParts >= 2 }
        let assetFolder = try #require(
            FileManager.default.contentsOfDirectory(at: coordinator.jobStore.stagingRoot(jobID), includingPropertiesForKeys: nil).first)
        let incoming = assetFolder.appendingPathComponent("incoming", isDirectory: true)
        #expect(chmod(incoming.path, 0o500) == 0)
        defer { chmod(incoming.path, 0o755) }
        hold.withLock { $0 = false }
        let paused = try await wait(coordinator, jobID) { $0.job.state == .paused }
        #expect(paused.job.pauseReason == .storageUnavailable)
        let failures = coordinator.log.allEntries().filter { $0.event == "part_failed" }.compactMap { $0.fields["failure"] }
        #expect(failures.count == options.maxAttemptsPerPart && failures.allSatisfy { $0.hasPrefix("localWriteFailed") })
        #expect(chmod(incoming.path, 0o755) == 0)
        coordinator.resume(jobID: jobID)
        let view = try await wait(coordinator, jobID) { $0.job.state == .imported }
        #expect(try importedBytes(coordinator, version: view.job.itemVersionID) == Data(Self.original))
        Self.writeLog("local-write-error", setup, coordinator, [
            "part folder made read-only after 2 verified parts: \(failures.count) attempts failed with \(Set(failures).sorted()); paused storage_unavailable; resumed after the folder was writable and imported",
        ])
    }

    @Test func changedSourceKeyPausesBeforeAnyRequestIsSent() async throws {
        let setup = try await setUp()
        defer { await setup.harness.cleanUp() }
        var options = BackgroundTransferCoordinator.Options()
        options.window = 1
        let first = try await coordinator(setup, options: options)
        let jobID = try await first.startJob(sourceID: setup.paired.sourceID, itemID: setup.itemID, title: "book")
        _ = try await wait(first, jobID) { $0.verifiedParts >= 2 }
        first.invalidate()
        // A part request the first coordinator sent just before it stopped may still reach the source; count
        // from after it has (found when this test failed once in this review's runs: the request for part 3
        // was logged after the count was taken).
        try await Task.sleep(for: .milliseconds(300))
        // The stored pin no longer matches the Mac's key (as if the Mac's identity had been replaced).
        var forged = setup.paired
        forged.spkiSHA256 = SHA256Hex.digest(Data("another key".utf8))
        let bytesBefore = setup.harness.service.decryptedBytesReceived
        let requestsBefore = setup.harness.service.requestLog.count
        let coordinator = try BackgroundTransferCoordinator(kind: .inProcess, root: setup.root, credentials: setup.credentials, options: options)
        try coordinator.sources.upsert(forged)
        await coordinator.start()
        let view = try await wait(coordinator, jobID) { $0.job.state == .paused }
        #expect(view.job.pauseReason == .sourceIdentityChanged)
        #expect(view.verifiedParts >= 2)
        // Refused in the handshake: no request (and so no token) reached the source.
        #expect(setup.harness.service.requestLog.count == requestsBefore)
        #expect(setup.harness.service.decryptedBytesReceived == bytesBefore)
        #expect(coordinator.log.allEntries().contains { $0.event == "trust_challenge" && $0.fields["result"] == "mismatched" })
        coordinator.invalidate()
        Self.writeLog("changed-source-key", setup, coordinator, ["pin replaced before relaunch; decrypted bytes at the source unchanged: \(bytesBefore)"])
    }
}
