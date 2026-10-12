import Darwin
import Foundation
import Synchronization
import Testing
@_spi(Testing) import SylviaSourceService
@_spi(Testing) import SylviaTransferClient
import SylviaTransferCore
@_spi(Testing) import SylviaBackgroundTransfer

/// Waits until a stopped ("killed") coordinator has finished handling what its session delivered after `invalidate()`
/// (cancellations, and parts whose files were already committed): its event log has not grown for `quiet`.
/// A real process death stops this at once; in a test the old coordinator keeps running, so a test that compares
/// "verified before the stop" with what the relaunch keeps must wait for it (found in round 2: after a fixed
/// 500 ms the 5 GiB test once read 161 verified parts from the log while 162 were journalled).
func waitUntilQuiet(_ coordinator: BackgroundTransferCoordinator, quiet: Duration = .seconds(1), atMost: Duration = .seconds(60)) async throws {
    let deadline = ContinuousClock.now + atMost
    var count = coordinator.log.allEntries().count
    var since = ContinuousClock.now
    while ContinuousClock.now < deadline {
        try await Task.sleep(for: .milliseconds(50))
        let now = coordinator.log.allEntries().count
        if now != count {
            count = now
            since = ContinuousClock.now
        } else if ContinuousClock.now - since >= quiet {
            return
        }
    }
    Issue.record("the stopped coordinator kept logging for \(atMost)")
}

/// Waits until the coordinator has requested part `index` (its `part_requested` event). "N parts verified and one
/// task outstanding" is not enough: a part is journalled in `didFinishDownloadingTo` while its task still counts as
/// outstanding until `didCompleteWithError`, so that state is also seen before the next part is requested.
func waitForPartRequest(_ coordinator: BackgroundTransferCoordinator, index: Int, seconds: Int = 30) async throws {
    let deadline = ContinuousClock.now + .seconds(seconds)
    while ContinuousClock.now < deadline {
        if coordinator.log.allEntries().contains(where: { $0.event == "part_requested" && $0.fields["part"]?.hasSuffix(":\(index)") == true }) {
            return
        }
        try await Task.sleep(for: .milliseconds(20))
    }
    Issue.record("part \(index) was not requested in \(seconds) s")
}

/// Round 2 review findings for the background client, on the host against the in-process source (same suite as
/// `BackgroundClientHostTests`, so the suite stays serialized). Environment: host (macOS), in-process source on
/// 127.0.0.1, real TLS, 1 MiB parts; coordinator session kind: in-process download tasks.
extension BackgroundClientHostTests {
    static func options(window: Int = 1, configure: (inout BackgroundTransferCoordinator.Options) -> Void = { _ in }) -> BackgroundTransferCoordinator.Options {
        var options = BackgroundTransferCoordinator.Options()
        options.window = window
        options.retryBaseDelay = 0.05
        configure(&options)
        return options
    }

    /// Holds the body of every part from part `index` on until the returned closure is called.
    func installHold(_ setup: Setup, fromPart index: Int) -> @Sendable () -> Void {
        let hold = Mutex(true)
        let start = Int64(index * Harness.mib)
        setup.harness.faults.bodyProgress.withLock {
            $0 = { _, offset, _ in
                while offset >= start, hold.withLock({ $0 }) { try? await Task.sleep(for: .milliseconds(20)) }
            }
        }
        return { hold.withLock { $0 = false } }
    }

    /// Review finding R2-01. A phone locked after its first unlock reports `isProtectedDataAvailable == false`
    /// (class A), yet its class C stores and its after-first-unlock token are readable, and background transfers
    /// must run. Here the coordinator is relaunched as for background session events (completion handler set)
    /// with protected data reported unavailable and every store readable: it must start, reconcile, request the
    /// missing parts and finish, not defer.
    @Test func lockedAfterFirstUnlockStillStartsReconcilesAndRequestsParts() async throws {
        let setup = try await setUp()
        defer { await setup.harness.cleanUp() }
        let options = Self.options()
        let release = installHold(setup, fromPart: 3)
        let first = try await coordinator(setup, options: options)
        let jobID = try await first.startJob(sourceID: setup.paired.sourceID, itemID: setup.itemID, title: "book")
        _ = try await wait(first, jobID) { $0.verifiedParts >= 3 }
        first.invalidate()  // the system ends the suspended app while the phone is locked
        try await Task.sleep(for: .milliseconds(300))
        release()
        let entriesBefore = first.log.allEntries().count
        let requestsBefore = setup.harness.service.requestLog.count

        let relaunched = try BackgroundTransferCoordinator(
            kind: .inProcess, root: setup.root, credentials: setup.credentials, options: options, appState: { "background_relaunch" },
            protectedDataAvailable: { false })
        let released = Mutex(0)
        relaunched.setBackgroundEventsCompletion { released.withLock { $0 += 1 } }
        let summary = await relaunched.start()
        #expect(summary.deferredReason == nil, "launch deferred while the stores were readable: \(summary.deferredReason ?? "")")
        #expect(summary.keptVerifiedParts == 3)
        #expect(summary.enqueued == 1)
        let view = try await wait(relaunched, jobID) { $0.job.state == .imported }
        #expect(try importedBytes(relaunched, version: view.job.itemVersionID) == Data(Self.original))
        #expect(setup.harness.service.requestLog.count > requestsBefore, "no part was requested after the relaunch")
        let events = relaunched.log.allEntries().dropFirst(entriesBefore)
        #expect(!events.contains { $0.event == "start_deferred" || $0.event == "background_events_released" })
        let start = try #require(events.first { $0.event == "coordinator_start" })
        #expect(start.fields["protected_data_available"] == "false")
        // In-process sessions never deliver background events; the handler is not released by a launch that ran.
        #expect(released.withLock { $0 } == 0)
        let counts = requestsPerOffset(setup.harness)
        #expect(counts.filter { $0.key < Int64(3 * Harness.mib) }.values.allSatisfy { $0 == 1 }, "a part verified before the relaunch was fetched again")
        relaunched.invalidate()
        Self.writeLog("locked-after-first-unlock", setup, relaunched, [
            "relaunch with protected data reported unavailable (as on a phone locked after its first unlock) and every store readable",
            "result: not deferred; kept \(summary.keptVerifiedParts) verified parts, enqueued \(summary.enqueued), imported once; coordinator_start protected_data_available=false",
        ])
    }

    /// Review finding R2-02. For a background session the system writes the whole body before the app sees it; on
    /// a full phone that write fails and the task ends with an error (no `didFinishDownloadingTo`). Injected here as
    /// the task's error, in the three shapes: an NSURLError file error carrying ENOSPC, a file error while the
    /// volume has less free space than a part, and a file error with space to spare.
    @Test(arguments: ["enospc-underlying", "cannot-create-low-space", "cannot-write-space-left"])
    func systemDownloadThatCannotBeStoredIsLocalStorageNotNetwork(_ shape: String) async throws {
        let setup = try await setUp()
        defer { await setup.harness.cleanUp() }
        let partThree = 3
        let injecting = Mutex(true)
        let lowSpace = Mutex(false)
        let error: NSError = switch shape {
        case "enospc-underlying":
            NSError(domain: NSURLErrorDomain, code: NSURLErrorCannotWriteToFile, userInfo: [
                NSUnderlyingErrorKey: NSError(domain: NSPOSIXErrorDomain, code: Int(ENOSPC)),
            ])
        case "cannot-create-low-space": NSError(domain: NSURLErrorDomain, code: NSURLErrorCannotCreateFile)
        default: NSError(domain: NSURLErrorDomain, code: NSURLErrorCannotWriteToFile)
        }
        let options = Self.options { options in
            options.availableCapacity = { _ in lowSpace.withLock { $0 } ? 512 * 1_024 : 1 << 40 }
            options.injectedTaskError = { descriptor in
                guard descriptor.partIndex == partThree, injecting.withLock({ $0 }) else { return nil }
                if shape == "cannot-create-low-space" { lowSpace.withLock { $0 = true } }
                return error
            }
        }
        let coordinator = try await coordinator(setup, options: options)
        defer { coordinator.invalidate() }
        let jobID = try await coordinator.startJob(sourceID: setup.paired.sourceID, itemID: setup.itemID, title: "book")
        let paused = try await wait(coordinator, jobID) { $0.job.state == .paused }
        let failures = coordinator.log.allEntries().filter { $0.event == "part_failed" }.compactMap { $0.fields["failure"] }
        let partRequests = requestsPerOffset(setup.harness)[Int64(partThree * Harness.mib)] ?? 0
        switch shape {
        case "cannot-write-space-left":
            // Retried (it may be transient), then storage_unavailable; never source_unreachable.
            #expect(paused.job.pauseReason == .storageUnavailable)
            #expect(failures.count == options.maxAttemptsPerPart && failures.allSatisfy { $0 == "localWriteFailed(\"system_download\")" })
            #expect(partRequests == options.maxAttemptsPerPart)
        default:
            // A full phone pauses at once: one request, no repeated 1 MiB downloads.
            #expect(paused.job.pauseReason == .insufficientSpace)
            #expect(failures == ["localStorageFull"])
            #expect(partRequests == 1)
        }
        #expect(paused.verifiedParts == 3)
        #expect(paused.job.pauseReason != .sourceUnreachable)
        // The person frees space (or the store recovers) and resumes: only the missing parts are fetched.
        injecting.withLock { $0 = false }
        lowSpace.withLock { $0 = false }
        coordinator.resume(jobID: jobID)
        let view = try await wait(coordinator, jobID) { $0.job.state == .imported }
        #expect(try importedBytes(coordinator, version: view.job.itemVersionID) == Data(Self.original))
        #expect(requestsPerOffset(setup.harness).filter { $0.key < Int64(3 * Harness.mib) }.values.allSatisfy { $0 == 1 })
        Self.writeLog("system-download-not-stored-\(shape)", setup, coordinator, [
            "injected task error for part 3 (as when the system cannot write the body): \(error.domain) \(error.code)\(shape == "enospc-underlying" ? " with underlying POSIX ENOSPC" : "")\(shape == "cannot-create-low-space" ? "; free space reported as 512 KiB" : "")",
            "result: paused \(paused.job.pauseReason?.rawValue ?? "none") after \(partRequests) request(s) for part 3; failures \(failures); resumed and imported",
        ])
    }

    /// Review finding R2-02 (reservation before each request): space used by another app in the middle of a
    /// transfer pauses the job with insufficient_space before the next part is requested.
    @Test func spaceUsedElsewhereMidTransferPausesBeforeTheNextRequest() async throws {
        let setup = try await setUp()
        defer { await setup.harness.cleanUp() }
        let lowSpace = Mutex(false)
        let options = Self.options { $0.availableCapacity = { _ in lowSpace.withLock { $0 } ? 2 * Int64(Harness.mib) : 1 << 40 } }
        let release = installHold(setup, fromPart: 3)
        let coordinator = try await coordinator(setup, options: options)
        defer { coordinator.invalidate() }
        let jobID = try await coordinator.startJob(sourceID: setup.paired.sourceID, itemID: setup.itemID, title: "book")
        _ = try await wait(coordinator, jobID) { $0.verifiedParts >= 3 }
        try await waitForPartRequest(coordinator, index: 3)  // part 3 is held at the source from now on
        lowSpace.withLock { $0 = true }  // another app filled the phone while part 3 was arriving
        release()
        let paused = try await wait(coordinator, jobID) { $0.job.state == .paused }
        #expect(paused.job.pauseReason == .insufficientSpace)
        #expect(paused.verifiedParts == 4)
        try await Task.sleep(for: .milliseconds(300))
        #expect(requestsPerOffset(setup.harness)[Int64(4 * Harness.mib)] == nil, "part 4 was requested although the phone was full")
        #expect(coordinator.log.allEntries().contains { $0.event == "space_check_failed" })
        lowSpace.withLock { $0 = false }
        coordinator.resume(jobID: jobID)
        let view = try await wait(coordinator, jobID) { $0.job.state == .imported }
        #expect(try importedBytes(coordinator, version: view.job.itemVersionID) == Data(Self.original))
        Self.writeLog("space-used-mid-transfer", setup, coordinator, [
            "free space reported as 2 MiB after part 3 (less than the 3 MiB left plus one part): paused insufficient_space with no request for part 4; resumed with space and imported",
        ])
    }

    /// A free TCP port on the loopback that nothing listens on.
    static func closedLoopbackPort() throws -> Int {
        let fd = socket(AF_INET, SOCK_STREAM, 0)
        try #require(fd >= 0)
        defer { close(fd) }
        var address = sockaddr_in()
        address.sin_family = sa_family_t(AF_INET)
        address.sin_addr.s_addr = inet_addr("127.0.0.1")
        address.sin_port = 0
        let bound = withUnsafePointer(to: &address) { $0.withMemoryRebound(to: sockaddr.self, capacity: 1) { bind(fd, $0, socklen_t(MemoryLayout<sockaddr_in>.size)) } }
        try #require(bound == 0)
        var length = socklen_t(MemoryLayout<sockaddr_in>.size)
        _ = withUnsafeMutablePointer(to: &address) { $0.withMemoryRebound(to: sockaddr.self, capacity: 1) { getsockname(fd, $0, &length) } }
        return Int(UInt16(bigEndian: address.sin_port))
    }

    /// Review finding R2-03. A Mac that cannot be reached because iOS local network privacy refuses the app is
    /// told apart from an unreachable Mac: after the retries the job pauses as source_unreachable, the network
    /// path is checked, and a denial changes the reason to local_network_denied with its Settings next step.
    /// The denial itself happens only on a device, so the check's answer is substituted here (`denied`); the
    /// probe's other answers run for real in `LocalNetworkProbeTests`.
    @Test(arguments: [true, false])
    func unreachableSourceIsClassifiedByTheLocalNetworkCheck(_ denied: Bool) async throws {
        let setup = try await setUp()
        defer { await setup.harness.cleanUp() }
        let probed = Mutex<[String]>([])
        let options = Self.options { options in
            options.localNetworkDenied = { endpoint in
                probed.withLock { $0.append("\(endpoint.host):\(endpoint.port)") }
                return denied
            }
        }
        let release = installHold(setup, fromPart: 3)
        let coordinator = try await coordinator(setup, options: options)
        defer { coordinator.invalidate() }
        let jobID = try await coordinator.startJob(sourceID: setup.paired.sourceID, itemID: setup.itemID, title: "book")
        _ = try await wait(coordinator, jobID) { $0.verifiedParts >= 3 }
        try await waitForPartRequest(coordinator, index: 3)  // part 3 is held at the source from now on
        // From now on the Mac's address refuses connections (as a denied local network looks to URLSession).
        var moved = setup.paired
        let closedPort = try Self.closedLoopbackPort()
        moved.endpoints = [.init(host: "127.0.0.1", port: closedPort)]
        try coordinator.sources.upsert(moved)
        release()
        let expected: PauseReason = denied ? .localNetworkDenied : .sourceUnreachable
        let paused = try await wait(coordinator, jobID) { $0.job.state == .paused && $0.job.pauseReason == expected }
        try await Task.sleep(for: .milliseconds(200))
        #expect(coordinator.job(jobID)?.job.pauseReason == expected)
        #expect(paused.verifiedParts == 4)
        let events = coordinator.log.allEntries()
        let failures = events.filter { $0.event == "part_failed" }.compactMap { $0.fields["failure"] }
        #expect(failures.count == options.maxAttemptsPerPart && failures.allSatisfy { $0.hasPrefix("transport") })
        #expect(events.contains { $0.event == "local_network_checked" && $0.fields["denied"] == String(denied) })
        #expect(events.contains { $0.event == "pause_reason_refined" } == denied)
        #expect(probed.withLock { $0 } == ["127.0.0.1:\(closedPort)"])
        if denied { #expect(paused.job.pauseReason?.nextStep.contains("Settings > Privacy & Security > Local Network") == true) }
        // Starting another job while the Mac is unreachable: the error says why.
        do {
            _ = try await coordinator.startJob(sourceID: setup.paired.sourceID, itemID: setup.itemID, title: "book")
            Issue.record("a job started although the Mac was unreachable")
        } catch {
            #expect((error == .localNetworkDenied) == denied, "startJob threw \(error)")
        }
        Self.writeLog("local-network-check-\(denied ? "denied" : "not-denied")", setup, coordinator, [
            "after part 3 the source's address is a closed loopback port; local network check answer substituted: denied=\(denied)",
            "result: \(failures.count) transport failures for part 4, then paused \(expected.rawValue)\(denied ? " (refined from source_unreachable)" : ""); startJob error \(denied ? "localNetworkDenied" : "unchanged")",
        ])
    }

    /// Gate gap (plan 15.1 pull-first inbox): the Mac's "send to device" reaches the phone through
    /// /v1/device-inbox; listing marks the entry observed by phone; the job's receipts name the entry, so the
    /// Mac shows downloaded to phone and then imported into Sylvia.
    @Test func deviceInboxEntryIsObservedDownloadedAndImported() async throws {
        let setup = try await setUp()
        defer { await setup.harness.cleanUp() }
        let coordinator = try await coordinator(setup)
        defer { coordinator.invalidate() }
        let queued = try await setup.harness.service.send(itemID: setup.itemID, toDevice: setup.paired.deviceID)
        #expect(queued.state == .queuedOnMac)
        let inbox = try await coordinator.inbox(sourceID: setup.paired.sourceID)
        let entry = try #require(inbox.first)
        #expect(inbox.count == 1 && entry.queueEntryID == queued.queueEntryID && entry.state == .observedByPhone)
        #expect(await setup.harness.service.queue.entries().first?.state == .observedByPhone)
        let jobID = try await coordinator.startJob(
            sourceID: setup.paired.sourceID, itemID: entry.itemID, title: entry.title, queueEntryID: entry.queueEntryID)
        let view = try await wait(coordinator, jobID) { $0.job.state == .imported && $0.job.receiptsAcknowledged }
        #expect(view.job.queueEntryID == entry.queueEntryID)
        #expect(try importedBytes(coordinator, version: view.job.itemVersionID) == Data(Self.original))
        let onMac = try #require(await setup.harness.service.queue.entries().first)
        #expect(onMac.state == .importedIntoSylvia)
        let acknowledgements = coordinator.log.allEntries().filter { $0.event == "receipt_acknowledged" }
        #expect(acknowledgements.map { $0.fields["entry_state"] } == ["downloaded_to_phone", "imported_into_sylvia"])
        #expect(acknowledgements.allSatisfy { $0.fields["queue_entry"] == entry.queueEntryID })
        // The job record keeps the entry across a relaunch (receipts retried after a crash still name it).
        let stored = try #require(coordinator.jobStore.loadAll().jobs.first { $0.jobID == jobID })
        #expect(stored.queueEntryID == entry.queueEntryID)
        Self.writeLog("device-inbox", setup, coordinator, [
            "Mac: send(item, device) -> entry \(queued.queueEntryID) queued_on_mac; phone: inbox lists it (observed_by_phone)",
            "result: job with the entry imported once; receipts acknowledged with entry states downloaded_to_phone, imported_into_sylvia; Mac entry now \(onMac.state.rawValue)",
        ])
    }
}
