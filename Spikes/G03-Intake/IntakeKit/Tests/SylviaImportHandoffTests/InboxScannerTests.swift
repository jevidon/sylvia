import Foundation
@testable import SylviaImportHandoff
import SylviaIntakeCore
import Testing

@Suite("main-app inbox scan, commit journal and cleanup policy", .removesTemporaryFiles)
struct InboxScannerTests {
    func handoff(_ box: Sandbox, seed: UInt64 = 1, length: UInt64 = 150_000) throws -> HandoffReceipt {
        try HandoffSession.run(environment: box.environment(),
                               files: [(try box.source("book-\(seed).epub", length: length, seed: seed), "org.idpf.epub-container")]).get()
    }

    @Test("a complete handoff is verified, moved into private staging and journaled once; rescans are no-ops")
    func acceptAndIdempotent() throws {
        let box = try Sandbox()
        let receipt = try handoff(box)
        let first = try box.scanner().scan()
        #expect(first.acceptedJobs.count == 1)
        #expect(box.inboxEntries().isEmpty)
        let staged = box.staging.appendingPathComponent("Staged/\(receipt.handoffID.uuidString)")
        let manifest = try HandoffManifest.decode(Data(contentsOf: staged.appendingPathComponent(HandoffManifest.fileName)))
        #expect(try FileDigest.sha256(of: staged.appendingPathComponent(manifest.items[0].storedPath)).sha256 == manifest.items[0].sha256)
        for _ in 0..<3 {
            let again = try box.scanner().scan()
            #expect(again == InboxScanReport())
        }
        let jobs = try box.journal().jobs
        #expect(jobs.count == 1)
        #expect(jobs[0].state == .staged && jobs[0].route == .shareExtension && jobs[0].handoffID == receipt.handoffID)
    }

    @Test("process death after each accept step, then a fresh scan: exactly one staged job, bytes intact",
          arguments: AcceptStep.allCases)
    func crashBetweenAcceptSteps(step: AcceptStep) throws {
        let box = try Sandbox()
        let receipt = try handoff(box)
        #expect(throws: SimulatedProcessDeath.self) {
            _ = try box.scanner(hook: { reached in if reached == step { throw SimulatedProcessDeath(step: .renameManifest) } }).scan()
        }
        let recovered = try box.scanner().scan()   // new process: journal reloaded from disk
        let jobs = try box.journal().jobs
        #expect(jobs.count == 1, "after a crash at \(step.rawValue)")
        #expect(jobs.first?.state == .staged)
        #expect(box.inboxEntries().isEmpty)
        if step == .intentRecorded || step == .moved {
            #expect(recovered.recoveredJobs.count == 1)
        }
        let staged = box.staging.appendingPathComponent("Staged/\(receipt.handoffID.uuidString)")
        let item = try #require(jobs.first?.items.first)
        #expect(try FileDigest.sha256(of: staged.appendingPathComponent(item.relativePath)).sha256 == item.sha256)
        #expect(try box.scanner().scan() == InboxScanReport())
    }

    @Test("bytes changed after the manifest was written: rejected, quarantined, never journaled")
    func tamperedBytes() throws {
        let box = try Sandbox()
        let receipt = try handoff(box)
        let item = box.inbox.appendingPathComponent("\(receipt.handoffID.uuidString)/items/0.epub")
        let h = try FileHandle(forWritingTo: item)
        try h.seek(toOffset: 10)
        try h.write(contentsOf: Data([0xEE]))
        try h.close()
        let report = try box.scanner().scan()
        #expect(report.acceptedJobs.isEmpty)
        #expect(report.rejected.count == 1)
        #expect(box.inboxEntries().isEmpty)
        #expect(try box.journal().jobs.isEmpty)
        #expect(FileManager.default.fileExists(atPath: box.staging.appendingPathComponent("Rejected").path))
    }

    @Test("forged or damaged manifests are rejected", arguments: ["traversal", "idMismatch", "extraFile", "symlink", "truncatedJSON", "sizeLie"])
    func forgedManifests(kind: String) throws {
        let box = try Sandbox()
        let receipt = try handoff(box)
        let dir = box.inbox.appendingPathComponent(receipt.handoffID.uuidString)
        let manifestURL = dir.appendingPathComponent(HandoffManifest.fileName)
        var manifest = try HandoffManifest.decode(Data(contentsOf: manifestURL))
        switch kind {
        case "traversal": manifest.items[0].storedPath = "items/../../../escape"
        case "idMismatch": manifest.handoffID = UUID()
        case "sizeLie": manifest.items[0].byteCount += 1; manifest.totalBytes += 1
        case "extraFile": try Data("x".utf8).write(to: dir.appendingPathComponent("items/9.txt"))
        case "symlink":
            let target = dir.appendingPathComponent("items/0.epub")
            let moved = box.sources.appendingPathComponent("outside.epub")
            try FileManager.default.moveItem(at: target, to: moved)
            try FileManager.default.createSymbolicLink(at: target, withDestinationURL: moved)
        default: break
        }
        try FileManager.default.removeItem(at: manifestURL)
        if kind == "truncatedJSON" {
            try manifest.encoded().prefix(40).write(to: manifestURL)
        } else {
            try manifest.encoded().write(to: manifestURL)
        }
        let report = try box.scanner().scan()
        #expect(report.acceptedJobs.isEmpty, "\(kind) was accepted")
        #expect(report.rejected.count == 1)
        #expect(try box.journal().jobs.isEmpty)
    }

    @Test("cleanup policy: an incomplete directory is kept while fresh and removed once stale; strays likewise")
    func cleanupPolicy() throws {
        let box = try Sandbox()
        let incomplete = box.inbox.appendingPathComponent(UUID().uuidString + "/items", isDirectory: true)
        try FileManager.default.createDirectory(at: incomplete, withIntermediateDirectories: true)
        try Data(count: 1000).write(to: incomplete.appendingPathComponent("0.epub"))
        try Data("{".utf8).write(to: incomplete.deletingLastPathComponent().appendingPathComponent("handoff.json.tmp-1"))
        try Data("stray".utf8).write(to: box.inbox.appendingPathComponent("stray.txt"))
        let now = Date()
        let fresh = try box.scanner(now: { now }).scan()
        #expect(fresh.inProgress.count == 1 && fresh.abandonedRemoved.isEmpty)
        #expect(box.inboxEntries().count == 2)
        let justUnder = try box.scanner(now: { now.addingTimeInterval(CleanupPolicy().abandonAfter - 60) }).scan()
        #expect(justUnder.abandonedRemoved.isEmpty)
        let stale = try box.scanner(now: { now.addingTimeInterval(CleanupPolicy().abandonAfter + 60) }).scan()
        #expect(stale.abandonedRemoved.count == 2)
        #expect(box.inboxEntries().isEmpty)
        let cleanups = try box.journal().cleanups
        #expect(Set(cleanups.map(\.reason)) == ["abandoned_incomplete", "unexpected_entry"])
        #expect(cleanups.first { $0.reason == "abandoned_incomplete" }?.byteCount == 1001)
    }

    @Test("a directory with a modification time in the future is never treated as stale")
    func futureTimestamp() throws {
        let box = try Sandbox()
        let dir = box.inbox.appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        try FileManager.default.setAttributes([.modificationDate: Date().addingTimeInterval(86_400)], ofItemAtPath: dir.path)
        let report = try box.scanner(now: { Date() }).scan()
        #expect(report.inProgress.count == 1)
    }

    @Test("the same bytes shared twice: the second job needs review as a duplicate of the first")
    func duplicates() throws {
        let box = try Sandbox()
        _ = try handoff(box, seed: 5)
        _ = try handoff(box, seed: 5)
        _ = try handoff(box, seed: 6)
        let report = try box.scanner().scan()
        #expect(report.acceptedJobs.count == 3)
        let jobs = try box.journal().jobs
        #expect(jobs.filter { $0.state == .staged }.count == 2)
        let review = jobs.filter { $0.state == .needsReview }
        #expect(review.count == 1)
        #expect(review.first?.duplicateOf != nil)
    }

    @Test("the extension commits between the staleness check and the claim: the handoff is kept and imported")
    func commitLandsDuringAbandon() throws {
        let box = try Sandbox()
        let receipt = try handoff(box)
        let name = receipt.handoffID.uuidString
        let manifestURL = box.inbox.appendingPathComponent("\(name)/\(HandoffManifest.fileName)")
        let held = box.sources.appendingPathComponent("held-handoff.json")
        try FileManager.default.moveItem(at: manifestURL, to: held)
        let later = Date().addingTimeInterval(CleanupPolicy().abandonAfter + 60)
        let scanner = InboxScanner(inbox: box.inbox, stagingRoot: box.staging, journal: try box.journal(), now: { later },
                                   beforeAbandon: { _ in try? FileManager.default.moveItem(at: held, to: manifestURL) })
        let report = try scanner.scan()
        #expect(report.abandonedRemoved.isEmpty, "a handoff whose manifest landed must never be deleted")
        #expect(report.inProgress == [name])
        #expect(box.inboxEntries() == [name])
        let next = try box.scanner().scan()
        #expect(next.acceptedJobs.count == 1)
        #expect(try box.journal().jobs.first?.state == .staged)
    }

    @Test("a live extension whose directory was claimed as abandoned cannot commit and claims nothing")
    func extensionAfterClaimFails() throws {
        let box = try Sandbox()
        let session = HandoffSession(environment: box.environment())
        let source = try box.source("slow.epub", length: 120_000, seed: 9)
        try session.addItem(copying: source, originalFilename: "slow.epub", contentType: "org.idpf.epub-container",
                            preferredExtension: "epub", representation: .fileURL, providerTypeIdentifier: "public.file-url",
                            expectedLength: nil)
        let later = Date().addingTimeInterval(CleanupPolicy().abandonAfter + 60)
        let report = try box.scanner(now: { later }).scan()
        #expect(report.abandonedRemoved == [session.handoffID.uuidString])
        // The extension carries on with a second item, or goes straight to its commit: both fail.
        let second = try box.source("second.epub", length: 50_000, seed: 10)
        #expect(throws: (any Error).self) {
            try session.addItem(copying: second, originalFilename: "second.epub", contentType: "org.idpf.epub-container",
                                preferredExtension: "epub", representation: .fileURL, providerTypeIdentifier: "public.file-url",
                                expectedLength: nil)
        }
        #expect(throws: (any Error).self) { _ = try session.commit() }
        session.discard()
        #expect(box.manifests().isEmpty)
        #expect(box.inboxEntries().isEmpty)
        #expect(try box.scanner().scan().acceptedJobs.isEmpty)
        #expect(try box.journal().jobs.isEmpty)
    }

    @Test("a crash between a claim and its deletion: a claimed handoff with a manifest is restored, others removed")
    func interruptedClaimRecovery() throws {
        let box = try Sandbox()
        let receipt = try handoff(box)
        let name = receipt.handoffID.uuidString
        let abandoned = box.staging.appendingPathComponent("Abandoned", isDirectory: true)
        try FileManager.default.createDirectory(at: abandoned, withIntermediateDirectories: true)
        try FileManager.default.moveItem(at: box.inbox.appendingPathComponent(name),
                                         to: abandoned.appendingPathComponent("\(name)-\(UUID().uuidString)"))
        let junk = abandoned.appendingPathComponent("\(UUID().uuidString)-\(UUID().uuidString)/items", isDirectory: true)
        try FileManager.default.createDirectory(at: junk, withIntermediateDirectories: true)
        try Data(count: 10).write(to: junk.appendingPathComponent("0.pdf"))
        let report = try box.scanner().scan()
        #expect(report.acceptedJobs.count == 1)
        #expect(try FileManager.default.contentsOfDirectory(atPath: abandoned.path).isEmpty)
    }

    @Test("rejected handoffs are kept for the retention period, then removed with a cleanup record")
    func rejectedRetention() throws {
        let box = try Sandbox()
        let receipt = try handoff(box)
        let item = box.inbox.appendingPathComponent("\(receipt.handoffID.uuidString)/items/0.epub")
        let h = try FileHandle(forWritingTo: item)
        try h.write(contentsOf: Data([0xEE]))
        try h.close()
        let now = Date()
        #expect(try box.scanner(now: { now }).scan().rejected.count == 1)
        let rejected = box.staging.appendingPathComponent("Rejected")
        #expect(try FileManager.default.contentsOfDirectory(atPath: rejected.path).count == 1)
        let early = try box.scanner(now: { now.addingTimeInterval(CleanupPolicy().rejectedRetention - 60) }).scan()
        #expect(early.expiredRejectionsRemoved.isEmpty)
        let late = try box.scanner(now: { now.addingTimeInterval(CleanupPolicy().rejectedRetention + 60) }).scan()
        #expect(late.expiredRejectionsRemoved.count == 1)
        #expect(try FileManager.default.contentsOfDirectory(atPath: rejected.path).isEmpty)
        #expect(try box.journal().cleanups.contains { $0.reason == "rejected_expired" })
        #expect(try box.journal().jobs.isEmpty)
    }

    /// An extension whose commit failed after its manifest rename deletes its directory (HandoffSession.discard).
    /// If that deletion overlaps a scan after verification, the scan must not stage a partial handoff.
    @Test("items removed between verification and the move: job failed_final, quarantined, nothing staged",
          arguments: [AcceptStep.verified, AcceptStep.intentRecorded])
    func itemsRemovedAfterVerification(step: AcceptStep) throws {
        let box = try Sandbox()
        let receipt = try handoff(box)
        let item = box.inbox.appendingPathComponent("\(receipt.handoffID.uuidString)/items/0.epub")
        let report = try box.scanner(hook: { reached in
            if reached == step { try FileManager.default.removeItem(at: item) }
        }).scan()
        #expect(report.acceptedJobs.isEmpty)
        #expect(report.rejected.count == 1)
        let jobs = try box.journal().jobs
        #expect(jobs.count == 1 && jobs.first?.state == .failedFinal)
        #expect(try FileManager.default.contentsOfDirectory(atPath: box.staging.appendingPathComponent("Staged").path).isEmpty)
        #expect(try FileManager.default.contentsOfDirectory(atPath: box.staging.appendingPathComponent("Rejected").path).count == 1)
        #expect(box.inboxEntries().isEmpty)
        #expect(try box.scanner().scan() == InboxScanReport(), "a failed job is not retried on every scan")
    }

    @Test("recovery after a crash: items that no longer match end the job as failed_final instead of retrying forever",
          arguments: [AcceptStep.intentRecorded, AcceptStep.moved])
    func recoveryWithDamagedItems(step: AcceptStep) throws {
        let box = try Sandbox()
        let receipt = try handoff(box)
        let name = receipt.handoffID.uuidString
        #expect(throws: SimulatedProcessDeath.self) {
            _ = try box.scanner(hook: { reached in if reached == step { throw SimulatedProcessDeath(step: .renameManifest) } }).scan()
        }
        // Damage the bytes wherever the crash left them: in the inbox (intent recorded) or in staging (moved).
        let base = step == .moved ? box.staging.appendingPathComponent("Staged/\(name)") : box.inbox.appendingPathComponent(name)
        let item = base.appendingPathComponent("items/0.epub")
        try FileManager.default.removeItem(at: item)
        let report = try box.scanner().scan()
        #expect(report.recoveredJobs.isEmpty)
        #expect(report.rejected.count == 1)
        #expect(try box.journal().jobs.map(\.state) == [.failedFinal])
        #expect(try FileManager.default.contentsOfDirectory(atPath: box.staging.appendingPathComponent("Staged").path).isEmpty)
        #expect(box.inboxEntries().isEmpty)
        #expect(try box.scanner().scan() == InboxScanReport())
    }
}
