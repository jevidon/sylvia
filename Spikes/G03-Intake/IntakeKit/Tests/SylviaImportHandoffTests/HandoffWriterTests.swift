import Foundation
@testable import SylviaImportHandoff
import SylviaIntakeCore
import Testing

/// Fault cases: (step, occurrence). Chunk steps fail in the middle of the first file; per-item steps also fail on
/// the second file, after the first one was fully copied and synced.
let faultCases: [(HandoffWriteStep, Int)] = HandoffWriteStep.allCases.map { ($0, $0 == .readChunk || $0 == .writeChunk ? 3 : 1) }
    + [(.checkSpace, 2), (.openSource, 2), (.createDestination, 2), (.readChunk, 7), (.writeChunk, 7),
       (.syncItem, 2), (.closeItem, 2), (.verifyItem, 2)]

@Suite("share-extension write sequence (T07)", .removesTemporaryFiles)
struct HandoffWriterTests {
    func twoFiles(_ box: Sandbox) throws -> [(url: URL, contentType: String)] {
        [(try box.source("Walden.epub", length: 300_001, seed: 1), "org.idpf.epub-container"),
         (try box.source("Meditations.mp3", length: 200_003, seed: 2), "public.mp3")]
    }

    @Test("happy path: receipt only after the manifest; every step of the sequence is exercised")
    func happyPath() throws {
        let box = try Sandbox()
        let counter = StepFault(step: .checkSpace, occurrence: 1_000_000, mode: .error)   // never fires: counts steps
        let result = try HandoffSession.run(environment: box.environment(faults: counter), files: try twoFiles(box))
        let receipt = try result.get()
        #expect(receipt.itemCount == 2)
        #expect(receipt.totalBytes == 500_004)
        for step in HandoffWriteStep.allCases {
            #expect((counter.reachedCounts[step] ?? 0) >= 1, "step \(step.rawValue) was never reached")
        }
        let manifests = box.manifests()
        try #require(manifests.count == 1)
        let manifest = try HandoffManifest.decode(Data(contentsOf: manifests[0]))
        try manifest.validate(directoryName: receipt.handoffID.uuidString)
        #expect(manifest.items.map(\.storedPath) == ["items/0.epub", "items/1.mp3"])
        #expect(manifest.items.map(\.originalFilename) == ["Walden.epub", "Meditations.mp3"])
        for item in manifest.items {
            let digest = try FileDigest.sha256(of: manifests[0].deletingLastPathComponent().appendingPathComponent(item.storedPath))
            #expect(digest.sha256 == item.sha256 && digest.byteCount == item.byteCount)
        }
        // No temporary manifest is left behind.
        let leftovers = try FileManager.default.contentsOfDirectory(atPath: manifests[0].deletingLastPathComponent().path)
        #expect(leftovers.sorted() == [HandoffManifest.fileName, "items"])
        // Staging class (plan 17.1): the extension marks the inbox as excluded from device backup itself, because it
        // can run before the app has ever launched and bootstrapped the container.
        #expect(VolumeSpace.isExcludedFromBackup(box.inbox))
    }

    @Test("injected I/O error at every step: failure, nothing left, nothing to import", arguments: faultCases)
    func errorAtEveryStep(step: HandoffWriteStep, occurrence: Int) throws {
        let box = try Sandbox()
        let fault = StepFault(step: step, occurrence: occurrence, mode: .error)
        let result = try HandoffSession.run(environment: box.environment(faults: fault), files: try twoFiles(box))
        #expect(fault.fired, "the fault at \(step.rawValue)#\(occurrence) never fired")
        guard case .failure = result else {
            Issue.record("reported received despite a fault at \(step.rawValue)#\(occurrence)")
            return
        }
        #expect(box.manifests().isEmpty)
        #expect(box.inboxEntries().isEmpty, "the failure path removes the handoff directory")
        let report = try box.scanner().scan()
        #expect(report.acceptedJobs.isEmpty)
        #expect(try box.journal().jobs.isEmpty)
    }

    @Test("simulated process death at every step: no receipt; no manifest unless the rename already happened",
          arguments: faultCases)
    func deathAtEveryStep(step: HandoffWriteStep, occurrence: Int) throws {
        let box = try Sandbox()
        let fault = StepFault(step: step, occurrence: occurrence, mode: .abandon)
        #expect(throws: SimulatedProcessDeath.self) {
            _ = try HandoffSession.run(environment: box.environment(faults: fault), files: try twoFiles(box))
        }
        #expect(fault.fired)
        let manifests = box.manifests()
        if step == .syncHandoffDirectory {
            // The process died after the commit point (rename) but before reporting receipt. The handoff is
            // complete and valid; the app imports it. The user was never told it was received.
            #expect(manifests.count == 1)
            let report = try box.scanner().scan()
            #expect(report.acceptedJobs.count == 1)
            return
        }
        #expect(manifests.isEmpty, "a manifest exists although the write sequence stopped at \(step.rawValue)")
        // The app leaves a fresh incomplete directory alone, then removes it once it is older than the policy.
        let fresh = try box.scanner().scan()
        #expect(fresh.acceptedJobs.isEmpty)
        #expect(fresh.inProgress.count == box.inboxEntries().count)
        let later = Date().addingTimeInterval(CleanupPolicy().abandonAfter + 60)
        let stale = try box.scanner(now: { later }).scan()
        #expect(stale.acceptedJobs.isEmpty)
        #expect(stale.abandonedRemoved.count == fresh.inProgress.count)
        #expect(box.inboxEntries().isEmpty)
        #expect(try box.journal().jobs.isEmpty)
        #expect(try box.journal().cleanups.allSatisfy { $0.reason == "abandoned_incomplete" })
    }

    @Test("not enough space: refused before anything is written, naming the shortfall")
    func insufficientSpace() throws {
        let box = try Sandbox()
        let env = box.environment(capacity: 64 << 20)    // 64 MiB free, 64 MiB margin
        let result = try HandoffSession.run(environment: env, files: [(try box.source("a.m4b", length: 1 << 20), "public.mpeg-4-audio")])
        #expect(result == .failure(.insufficientSpace(additionalBytesNeeded: 1 << 20)))
        #expect(box.inboxEntries().isEmpty)
        let route = FallbackRoute.for(try #require(result.failureValue))
        #expect(route.headline == FallbackRoute.notReceivedHeadline)
        #expect(route.reason.contains("MB"), "the shortfall is named: \(route.reason)")
    }

    @Test("an item over the size limit is refused before copying")
    func tooLarge() throws {
        let box = try Sandbox()
        let result = try HandoffSession.run(environment: box.environment(itemLimit: 1000), files: [(try box.source("a.pdf", length: 1001), "com.adobe.pdf")])
        #expect(result == .failure(.itemTooLarge(limit: 1000)))
        #expect(box.inboxEntries().isEmpty)
    }

    @Test("a source that changes during the copy is not received")
    func sourceChanged() throws {
        let box = try Sandbox()
        let src = try box.source("grow.txt", length: 1 << 20)
        var appended = false
        let result = try HandoffSession.run(environment: box.environment(buffer: 64 << 10), files: [(src, "public.plain-text")],
                                            progress: { bytes in
                                                if !appended && bytes > 200_000 {
                                                    appended = true
                                                    let h = try! FileHandle(forWritingTo: src)
                                                    try! h.seekToEnd()
                                                    try! h.write(contentsOf: Data([1, 2, 3]))
                                                    try! h.close()
                                                }
                                            })
        #expect(appended)
        #expect(result == .failure(.sourceChanged))
        #expect(box.inboxEntries().isEmpty)
    }

    @Test("cancellation mid-copy is not received and leaves nothing")
    func cancelled() throws {
        let box = try Sandbox()
        var chunks = 0
        let result = try HandoffSession.run(environment: box.environment(buffer: 64 << 10),
                                            files: [(try box.source("a.txt", length: 1 << 20), "public.plain-text")],
                                            isCancelled: { chunks += 1; return chunks > 4 })
        #expect(result == .failure(.cancelled))
        #expect(box.inboxEntries().isEmpty)
    }

    @Test("a directory or FIFO offered as a file is not received; a folder is named as such")
    func notRegular() throws {
        let box = try Sandbox()
        let dir = box.sources.appendingPathComponent("folder.epub", isDirectory: true)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        #expect(try HandoffSession.run(environment: box.environment(), files: [(dir, "org.idpf.epub-container")]) == .failure(.folderNotFile))
        let fifo = box.sources.appendingPathComponent("pipe.txt")
        #expect(mkfifo(fifo.path, 0o600) == 0)
        // A FIFO has no writer here; a blocking open would hang. The copier opens non-blocking and refuses it.
        #expect(try HandoffSession.run(environment: box.environment(), files: [(fifo, "public.plain-text")]) == .failure(.notADurableFile))
        #expect(box.inboxEntries().isEmpty)
    }

    @Test("stored names never come from the shared file name")
    func storedNames() throws {
        #expect(HandoffManifest.storedPath(ordinal: 0, preferredExtension: "../../x") == "items/0.x")
        #expect(HandoffManifest.storedPath(ordinal: 3, preferredExtension: "M4B") == "items/3.m4b")
        #expect(HandoffManifest.storedPath(ordinal: 1, preferredExtension: nil) == "items/1")
        for bad in ["../items/0", "items/../x", "items/0/x", "/items/0", "items/a", "items/0.e/x", "items/00000",
                    "items/0.ABC", "items/0.", "items/.epub"] {
            #expect(!HandoffManifest.isValidStoredPath(bad), "\(bad)")
        }
    }

    /// Found in the G0.3 review R4-01 audit: `cleanFilename` replaced "/" with Foundation's `replacingOccurrences`, which
    /// leaves a "/" that a combining mark follows (one grapheme cluster with it); the manifest's own validation then
    /// refused it, so the share failed. It now replaces code points.
    @Test("a shared file name holding a slash before a combining mark is recorded with an underscore, and the share is received")
    func slashBeforeCombiningMarkInName() throws {
        let box = try Sandbox()
        let src = try box.source("plain.epub", length: 10_000)
        let session = HandoffSession(environment: box.environment())
        let names = ["a/\u{301}b.epub", "\u{600}/x.epub", "a\u{0}/b.epub", String(repeating: "\u{E9}", count: 200) + "/x.epub"]
        for name in names {
            try session.addItem(copying: src, originalFilename: name, contentType: "org.idpf.epub-container",
                                preferredExtension: "epub", representation: .fileURL, providerTypeIdentifier: "public.file-url",
                                expectedLength: nil)
        }
        let receipt = try session.commit()
        let manifest = try HandoffManifest.read(contentsOf: box.manifests()[0])
        #expect(receipt.itemCount == names.count)
        #expect(manifest.items.map { Array($0.originalFilename.unicodeScalars) } == [
            Array("a_\u{301}b.epub".unicodeScalars), Array("\u{600}_x.epub".unicodeScalars), Array("a_b.epub".unicodeScalars),
            Array((String(repeating: "\u{E9}", count: 127)).unicodeScalars),
        ])
        for item in manifest.items {
            #expect(!PathBytes.containsSeparator(item.originalFilename) && item.originalFilename.utf8.count <= 255)
        }
    }

    /// G0.3 review R4-02: the app's scan reads at most 256 KiB of handoff.json. 100 items (the share limit) with file
    /// names and type identifiers at their limits fit; names that JSON must escape (control characters, six bytes each)
    /// together with long type identifiers do not, and such a manifest is never committed, so no receipt is shown for a
    /// handoff the app would refuse.
    @Test("handoff.json size: 100 items at the name and type limits fit within 256 KiB; a larger manifest is never committed")
    func manifestSize() throws {
        let box = try Sandbox()
        let src = try box.source("tiny.mp3", length: 16)
        func share(name: String, type: String) throws -> Result<HandoffReceipt, HandoffFailure> {
            let session = HandoffSession(environment: box.environment())
            do {
                for _ in 0..<HandoffManifest.maxItems {
                    try session.addItem(copying: src, originalFilename: name, contentType: type, preferredExtension: "mp3",
                                        representation: .fileRepresentation, providerTypeIdentifier: type, expectedLength: nil)
                }
                return .success(try session.commit())
            } catch {
                session.discard()
                return .failure(HandoffFailure.from(error))
            }
        }
        // 255-byte names (127 x U+00E9 + "a") and 128-character identifiers: the largest ordinary share.
        let ordinary = try share(name: String(repeating: "\u{E9}", count: 127) + "a",
                                 type: "public." + String(repeating: "a", count: 121))
        let receipt = try #require(try? ordinary.get())
        let manifest = try #require(box.manifests().first)
        let size = try #require(try FileManager.default.attributesOfItem(atPath: manifest.path)[.size] as? Int)
        #expect(size <= HandoffManifest.maxBytes)
        #expect(try HandoffManifest.read(contentsOf: manifest).items.count == receipt.itemCount)
        print("handoff.json size: \(receipt.itemCount) items with 255-byte names and 128-character type identifiers: \(size) bytes (limit \(HandoffManifest.maxBytes))")
        try FileManager.default.removeItem(at: manifest.deletingLastPathComponent())
        // 255 control characters per name (JSON writes each as six bytes) and 128-character astral identifiers.
        let escaped = try share(name: String(repeating: "\u{1}", count: 255), type: String(repeating: "\u{1F600}", count: 128))
        #expect(escaped == .failure(.manifestTooLarge))
        #expect(box.manifests().isEmpty && box.inboxEntries().isEmpty, "nothing committed, nothing left")
        #expect(FallbackRoute.for(.manifestTooLarge).headline == FallbackRoute.notReceivedHeadline)
    }

    @Test("the app reads handoff.json up to 256 KiB, whitespace included, and refuses one byte more")
    func readLimit() throws {
        let box = try Sandbox()
        let src = try box.source("small.pdf", length: 1_000)
        guard case .success = try HandoffSession.run(environment: box.environment(), files: [(src, "com.adobe.pdf")]) else {
            Issue.record("the share failed")
            return
        }
        let url = try #require(box.manifests().first)
        let text = try Data(contentsOf: url)
        try (text + Data(repeating: 0x20, count: HandoffManifest.maxBytes - text.count)).write(to: url)
        #expect(throws: Never.self) { _ = try HandoffManifest.read(contentsOf: url) }
        try (text + Data(repeating: 0x20, count: HandoffManifest.maxBytes - text.count + 1)).write(to: url)
        #expect(throws: HandoffManifestError.tooLarge(limit: HandoffManifest.maxBytes)) { _ = try HandoffManifest.read(contentsOf: url) }
        // The scan refuses it the same way: rejected, never imported.
        let report = try box.scanner().scan()
        #expect(report.acceptedJobs.isEmpty && report.rejected.count == 1)
        #expect(report.rejected.first?.reason == "handoff.json is larger than \(HandoffManifest.maxBytes) bytes")
    }
}

extension Result {
    var failureValue: Failure? { if case let .failure(f) = self { f } else { nil } }
}

extension HandoffReceipt: CustomStringConvertible {
    public var description: String { "receipt(\(itemCount) items, \(totalBytes) bytes)" }
}
