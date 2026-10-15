import Foundation
import Synchronization
import Testing
@_spi(Testing) import SylviaSourceService
@_spi(Testing) import SylviaTransferClient
import SylviaTransferCore
@_spi(Testing) import SylviaBackgroundTransfer

/// Waits until the source's request log has not grown for `quiet` (a response that was held when its client
/// went away is logged when the source gives up on it).
func waitForSourceToSettle(_ harness: Harness, quiet: Duration = .milliseconds(500), atMost: Duration = .seconds(30)) async throws {
    let deadline = ContinuousClock.now + atMost
    var count = harness.service.requestLog.count
    var since = ContinuousClock.now
    while ContinuousClock.now < deadline {
        try await Task.sleep(for: .milliseconds(50))
        let now = harness.service.requestLog.count
        if now != count {
            count = now
            since = ContinuousClock.now
        } else if ContinuousClock.now - since >= quiet {
            return
        }
    }
    Issue.record("the source kept logging requests for \(atMost)")
}

/// Round 3 review findings for the background client, on the host against the in-process source (same suite as
/// `BackgroundClientHostTests`, so the suite stays serialized). Environment: host (macOS), in-process source on
/// 127.0.0.1, real TLS, 1 MiB parts; coordinator session kind: in-process download tasks.
extension BackgroundClientHostTests {
    /// Review finding R3-01. Launch reconciliation runs at every launch, including each background relaunch for
    /// session events, and requests the missing parts itself. It used to do so without the plan 15.4 reservation
    /// that every other request passes. A relaunch on a phone with too little free space must pause the job with
    /// insufficient_space and send no request; after space is freed, resume fetches only the missing parts.
    @Test func relaunchWithTooLittleSpacePausesBeforeAnyRequest() async throws {
        let setup = try await setUp()
        defer { await setup.harness.cleanUp() }
        let lowSpace = Mutex(false)
        // 2 MiB free is less than the 3 MiB + 4321 bytes still to arrive plus one part for the window's one task (window 1).
        let options = Self.options { $0.availableCapacity = { _ in lowSpace.withLock { $0 } ? 2 * Int64(Harness.mib) : 1 << 40 } }
        let release = installHold(setup, fromPart: 3)
        let first = try await coordinator(setup, options: options)
        let jobID = try await first.startJob(sourceID: setup.paired.sourceID, itemID: setup.itemID, title: "book")
        _ = try await wait(first, jobID) { $0.verifiedParts >= 3 }
        try await waitForPartRequest(first, index: 3)  // held at the source
        first.invalidate()  // the system ends the app; another app then fills the phone
        release()
        try await waitUntilQuiet(first)
        try await waitForSourceToSettle(setup.harness)
        lowSpace.withLock { $0 = true }
        let entriesBefore = first.log.allEntries().count
        let requestsBefore = setup.harness.service.requestLog.count

        let relaunched = try BackgroundTransferCoordinator(
            kind: .inProcess, root: setup.root, credentials: setup.credentials, options: options, appState: { "background_relaunch" })
        defer { relaunched.invalidate() }
        let summary = await relaunched.start()
        #expect(summary.deferredReason == nil)
        #expect(summary.keptVerifiedParts == 3)
        #expect(summary.enqueued == 0, "the launch requested \(summary.enqueued) part(s) without the space for them")
        #expect(summary.blocked[jobID] == PauseReason.insufficientSpace.rawValue)
        let paused = try #require(relaunched.job(jobID))
        #expect(paused.job.state == .paused)
        #expect(paused.job.pauseReason == .insufficientSpace)
        #expect(paused.verifiedParts == 3)
        #expect(paused.outstandingTasks == 0)
        try await Task.sleep(for: .milliseconds(500))
        let requestsAfterRelaunch = setup.harness.service.requestLog.count - requestsBefore
        #expect(requestsAfterRelaunch == 0, "the relaunch sent \(requestsAfterRelaunch) request(s) although the phone was full")
        let events = relaunched.log.allEntries().dropFirst(entriesBefore)
        #expect(!events.contains { $0.event == "part_requested" })
        let check = try #require(events.first { $0.event == "space_check_failed" })
        let reconciliation = try #require(events.first { $0.event == "launch_reconciliation" })
        #expect(reconciliation.fields["blocked_\(jobID)"] == PauseReason.insufficientSpace.rawValue)
        #expect(reconciliation.fields["enqueued"] == "0")

        // The person frees space and resumes: only the missing parts are fetched, each once.
        lowSpace.withLock { $0 = false }
        relaunched.resume(jobID: jobID)
        let view = try await wait(relaunched, jobID) { $0.job.state == .imported }
        #expect(try importedBytes(relaunched, version: view.job.itemVersionID) == Data(Self.original))
        let counts = requestsPerOffset(setup.harness)
        #expect(counts.filter { $0.key < Int64(3 * Harness.mib) }.values.allSatisfy { $0 == 1 }, "a part verified before the relaunch was fetched again")
        Self.writeLog("relaunch-low-space", setup, relaunched, [
            "relaunch (as for background session events) after 3 verified parts, with free space reported as 2 MiB (less than the \(Self.size - 3 * Harness.mib) bytes still to arrive plus one part for the window's one task)",
            "result: launch_reconciliation enqueued=\(summary.enqueued), blocked=\(summary.blocked[jobID] ?? "none"); space_check_failed required_bytes=\(check.fields["required_bytes"] ?? "?") available_bytes=\(check.fields["available_bytes"] ?? "?"); \(requestsAfterRelaunch) request(s) after the relaunch",
            "then free space restored and resume: imported once; parts verified before the relaunch requested once in total",
        ])
    }
}
