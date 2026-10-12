import Foundation
import Testing
import SylviaTransferCore
@testable import SylviaBackgroundTransfer

@Suite("Task descriptors carry IDs only (15.5)")
struct TaskDescriptorTests {
    let job = "11111111-2222-4333-8444-555555555555"
    let asset = "aaaaaaaa-bbbb-4ccc-8ddd-eeeeeeeeeeee"

    @Test func roundTrips() {
        let descriptor = TaskDescriptor(jobID: job, assetID: asset, partIndex: 12, attempt: 3)
        #expect(descriptor.encoded == "sylvia-xfer/1 job=\(job) asset=\(asset) part=12 attempt=3")
        #expect(TaskDescriptor.parse(descriptor.encoded) == descriptor)
    }

    @Test(arguments: [
        nil, "", "sylvia-xfer/2 job=11111111-2222-4333-8444-555555555555 asset=aaaaaaaa-bbbb-4ccc-8ddd-eeeeeeeeeeee part=1 attempt=1",
        "sylvia-xfer/1 job=11111111-2222-4333-8444-555555555555 asset=aaaaaaaa-bbbb-4ccc-8ddd-eeeeeeeeeeee part=1",
        "sylvia-xfer/1 job=11111111-2222-4333-8444-555555555555 asset=aaaaaaaa-bbbb-4ccc-8ddd-eeeeeeeeeeee part=-1 attempt=1",
        "sylvia-xfer/1 job=11111111-2222-4333-8444-555555555555 asset=aaaaaaaa-bbbb-4ccc-8ddd-eeeeeeeeeeee part=01 attempt=1",
        "sylvia-xfer/1 job=11111111-2222-4333-8444-555555555555 asset=aaaaaaaa-bbbb-4ccc-8ddd-eeeeeeeeeeee part=1 attempt=0",
        "sylvia-xfer/1 job=11111111-2222-4333-8444-555555555555 asset=AAAAAAAA-BBBB-4CCC-8DDD-EEEEEEEEEEEE part=1 attempt=1",
        "sylvia-xfer/1 job=11111111-2222-4333-8444-555555555555 asset=aaaaaaaa-bbbb-4ccc-8ddd-eeeeeeeeeeee part=1 attempt=1 token=x",
        "sylvia-xfer/1  job=11111111-2222-4333-8444-555555555555 asset=aaaaaaaa-bbbb-4ccc-8ddd-eeeeeeeeeeee part=1 attempt=1",
        "sylvia-xfer/1 asset=aaaaaaaa-bbbb-4ccc-8ddd-eeeeeeeeeeee job=11111111-2222-4333-8444-555555555555 part=1 attempt=1",
        "sylvia-xfer/1 job=../../etc asset=aaaaaaaa-bbbb-4ccc-8ddd-eeeeeeeeeeee part=1 attempt=1",
        "sylvia-xfer/1 job=11111111-2222-4333-8444-555555555555 asset=aaaaaaaa-bbbb-4ccc-8ddd-eeeeeeeeeeee part=99999 attempt=1",
    ] as [String?])
    func rejectsAnythingElse(_ text: String?) {
        #expect(TaskDescriptor.parse(text) == nil)
    }
}

@Suite("Launch reconciliation planner (6.4, 15.5, T41)")
struct ReconciliationPlannerTests {
    typealias Planner = ReconciliationPlanner
    let jobA = "11111111-0000-4000-8000-00000000000a"
    let jobB = "11111111-0000-4000-8000-00000000000b"
    let asset = "aaaaaaaa-0000-4000-8000-000000000001"

    func parts(_ count: Int) -> [PartKey] { (0..<count).map { PartKey(assetID: asset, index: $0) } }
    func task(_ id: Int, job: String, part: Int, attempt: Int = 1) -> Planner.OutstandingTask {
        .init(taskIdentifier: id, taskDescription: TaskDescriptor(jobID: job, assetID: asset, partIndex: part, attempt: attempt).encoded)
    }

    @Test func refetchesOnlyMissingPartsAndAdoptsRunningTasks() {
        let job = Planner.JobSnapshot(
            jobID: jobA, state: .downloading, parts: parts(8), verified: Set(parts(8).prefix(3)), credential: .available)
        let plan = Planner.plan(jobs: [job], tasks: [task(10, job: jobA, part: 3), task(11, job: jobA, part: 4)], window: 4)
        #expect(plan.adopt.keys.sorted() == [10, 11])
        #expect(plan.cancel.isEmpty)
        // Window 4: two adopted, two new; verified parts 0-2 never requested again.
        #expect(plan.enqueue[jobA] == [PartKey(assetID: asset, index: 5), PartKey(assetID: asset, index: 6)])
        #expect(plan.finalize.isEmpty && plan.block.isEmpty)
    }

    @Test func cancelsForeignUnknownVerifiedAndDuplicateTasks() {
        let job = Planner.JobSnapshot(jobID: jobA, state: .downloading, parts: parts(4), verified: [PartKey(assetID: asset, index: 0)], credential: .available)
        let tasks: [Planner.OutstandingTask] = [
            .init(taskIdentifier: 1, taskDescription: nil),
            .init(taskIdentifier: 2, taskDescription: "some other library's task"),
            task(3, job: jobB, part: 1),                 // job not on disk any more
            task(4, job: jobA, part: 0),                 // verified while the app was away
            task(5, job: jobA, part: 9),                 // not in the current manifest (version changed)
            task(6, job: jobA, part: 1, attempt: 1),     // superseded by attempt 2
            task(7, job: jobA, part: 1, attempt: 2),
            task(8, job: jobA, part: 2, attempt: 3),
            task(9, job: jobA, part: 2, attempt: 2),     // older than 8
        ]
        let plan = Planner.plan(jobs: [job], tasks: tasks, window: 4)
        #expect(plan.cancel == [1: .foreign, 2: .foreign, 3: .unknownJob, 4: .partAlreadyVerified, 5: .partNotInManifest, 6: .duplicate, 9: .duplicate])
        #expect(plan.adopt.keys.sorted() == [7, 8])
        #expect(plan.enqueue[jobA] == [PartKey(assetID: asset, index: 3)])
    }

    /// The `.locked` case is the planner's defensive rule for a Keychain that refuses while the job store is
    /// readable. Before the first unlock both are unreadable and the coordinator does not plan at all (its
    /// launch is deferred; host test `unreadableStoresDeferLaunchWithoutCancellingOrOverwriting`).
    @Test func revokedOrLockedCredentialBlocksWithoutTouchingVerifiedParts() {
        let revoked = Planner.JobSnapshot(jobID: jobA, state: .downloading, parts: parts(4), verified: Set(parts(2)), credential: .missing)
        let locked = Planner.JobSnapshot(jobID: jobB, state: .downloading, parts: parts(4), verified: [], credential: .locked)
        let plan = Planner.plan(jobs: [revoked, locked], tasks: [task(1, job: jobA, part: 2), task(2, job: jobB, part: 0)], window: 4)
        #expect(plan.block == [jobA: .reauthenticationRequired, jobB: .deviceLocked])
        #expect(plan.cancel == [1: .jobBlocked, 2: .jobBlocked])
        #expect(plan.enqueue.isEmpty && plan.adopt.isEmpty && plan.finalize.isEmpty)
        // The planner never deletes anything: verified parts stay on disk for after re-pairing or unlocking.
    }

    @Test func pausedAndFinishedJobsGetNoTasks() {
        let jobs: [Planner.JobSnapshot] = [
            .init(jobID: jobA, state: .paused, parts: parts(2), verified: [], credential: .available),
            .init(jobID: jobB, state: .imported, parts: parts(2), verified: Set(parts(2)), credential: .available),
        ]
        let plan = Planner.plan(jobs: jobs, tasks: [task(1, job: jobA, part: 0), task(2, job: jobB, part: 1)], window: 4)
        #expect(plan.cancel == [1: .jobNotDownloading, 2: .jobNotDownloading])
        #expect(plan.enqueue.isEmpty && plan.importReady.isEmpty)
    }

    @Test func completeAssemblingAndReadyJobsAreFinishedNotRefetched() {
        let jobs: [Planner.JobSnapshot] = [
            .init(jobID: jobA, state: .downloading, parts: parts(3), verified: Set(parts(3)), credential: .available),
            .init(jobID: jobB, state: .assembling, parts: parts(3), verified: Set(parts(3)), credential: .available),
            .init(jobID: "11111111-0000-4000-8000-00000000000c", state: .readyForImport, parts: parts(1), verified: Set(parts(1)), credential: .missing),
            .init(jobID: "11111111-0000-4000-8000-00000000000d", state: .refreshing, parts: parts(1), verified: [], credential: .available),
        ]
        let plan = Planner.plan(jobs: jobs, tasks: [], window: 4)
        #expect(plan.finalize == [jobA, jobB])
        // Import needs no credential: the bytes are already verified on the phone.
        #expect(plan.importReady == ["11111111-0000-4000-8000-00000000000c"])
        #expect(plan.refresh == ["11111111-0000-4000-8000-00000000000d"])
        #expect(plan.enqueue.isEmpty)
    }

    @Test func unreadableManifestBlocksAndCancels() {
        let job = Planner.JobSnapshot(jobID: jobA, state: .downloading, parts: nil, verified: [], credential: .available)
        let plan = Planner.plan(jobs: [job], tasks: [task(1, job: jobA, part: 0)], window: 4)
        #expect(plan.block == [jobA: .manifestInvalid])
        #expect(plan.cancel == [1: .jobBlocked])
    }

    @Test func windowIsNeverExceededAndAllPartsEventuallyCovered() {
        // Simulated launches: each launch verifies whatever was outstanding; parts never repeat.
        var verified: Set<PartKey> = []
        var requested: [PartKey] = []
        var outstanding: [Planner.OutstandingTask] = []
        for launch in 0..<60 {
            let job = Planner.JobSnapshot(jobID: jobA, state: .downloading, parts: parts(17), verified: verified, credential: .available)
            let plan = Planner.plan(jobs: [job], tasks: outstanding, window: 3)
            if verified.count == 17 {
                #expect(plan.finalize == [jobA])
                break
            }
            let new = plan.enqueue[jobA] ?? []
            #expect(new.count + plan.adopt.count <= 3)
            requested += new
            // Half the outstanding tasks finished while the app was away.
            let adopted = plan.adopt.values.map(\.partKey).sorted()
            for key in adopted.prefix(1) { verified.insert(key) }
            outstanding = (adopted.dropFirst() + new).enumerated().map { index, key in
                task(launch * 100 + index, job: jobA, part: key.index)
            }
        }
        #expect(verified.count == 17)
        #expect(Set(requested).count == requested.count)  // no part requested twice
    }
}

@Suite("Received versus verified wording (15.5)")
struct ProgressTextTests {
    @Test func plansExampleAndRoundingNeverClaimsCompletion() {
        #expect(ProgressText.verified(.init(totalBytes: 5_200_000_000, receivedBytes: 3_400_000_000, verifiedBytes: 3_100_000_000)) == "3.1 of 5.2 GB verified")
        #expect(ProgressText.received(.init(totalBytes: 5_200_000_000, receivedBytes: 3_400_000_000, verifiedBytes: 3_100_000_000)) == "3.4 of 5.2 GB received")
        // One byte short of complete is never shown as complete.
        #expect(ProgressText.fraction(5_199_999_999, of: 5_200_000_000) == "5.1 of 5.2 GB")
        #expect(ProgressText.fraction(5_249_999_999, of: 5_250_000_000) == "5.2 of 5.3 GB")
        #expect(ProgressText.fraction(5_200_000_000, of: 5_200_000_000) == "5.2 of 5.2 GB")
        #expect(ProgressText.fraction(138_400_000, of: 138_412_345) == "138.3 of 138.4 MB")
        #expect(ProgressText.fraction(0, of: 512) == "0 of 512 bytes")
    }

    @Test func receivedAndVerifiedAreDistinct() {
        let progress = TransferProgress(totalBytes: 138_000_000, receivedBytes: 138_000_000, verifiedBytes: 120_000_000)
        #expect(ProgressText.received(progress) == "138.0 of 138.0 MB received")
        #expect(ProgressText.verified(progress) == "120.0 of 138.0 MB verified")
    }
}
