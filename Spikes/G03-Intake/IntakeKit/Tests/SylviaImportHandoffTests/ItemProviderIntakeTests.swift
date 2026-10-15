import Foundation
@testable import SylviaImportHandoff
import SylviaIntakeCore
import Testing
import UniformTypeIdentifiers

/// NSItemProvider behaviour the share extension depends on. Runs on host (macOS Foundation) and, through the
/// harness app's test bundle, on the simulator.
@Suite("NSItemProvider intake and fallback", .removesTemporaryFiles)
struct ItemProviderIntakeTests {
    struct Outcome: Equatable {
        var receipt: HandoffReceipt?
        var failure: HandoffFailure?
    }

    /// Runs one provider through the same sequence the extension uses (ShareViewController.handOff): receive, then
    /// commit unless cancelled, or discard.
    func share(_ provider: NSItemProvider, box: Sandbox, stall: Duration = .seconds(60),
               cancellation: CancellationSignal = CancellationSignal(),
               faults: any FaultInjecting = NoFaults()) async -> Outcome {
        let session = HandoffSession(environment: box.environment(faults: faults))
        do {
            _ = try await ItemProviderIntake(providerStallTimeout: stall).receive(provider, into: session, cancellation: cancellation)
            return Outcome(receipt: try session.commit(isCancelled: { cancellation.isCancelled }), failure: nil)
        } catch {
            session.discard()
            return Outcome(receipt: nil, failure: HandoffFailure.from(error))
        }
    }

    /// Invariant for every outcome: a receipt exists exactly when a verified manifest exists.
    func checkInvariant(_ outcome: Outcome, box: Sandbox) throws {
        let manifests = box.manifests()
        if let receipt = outcome.receipt {
            #expect(manifests.count == 1)
            let manifest = try HandoffManifest.decode(Data(contentsOf: manifests[0]))
            #expect(manifest.handoffID == receipt.handoffID)
            for item in manifest.items {
                let url = manifests[0].deletingLastPathComponent().appendingPathComponent(item.storedPath)
                #expect(try FileDigest.sha256(of: url).sha256 == item.sha256)
            }
        } else {
            #expect(manifests.isEmpty)
            #expect(box.inboxEntries().isEmpty)
            let route = FallbackRoute.for(try #require(outcome.failure))
            #expect(route.headline == FallbackRoute.notReceivedHeadline)
            #expect(!route.alternatives.isEmpty && route.alternatives.allSatisfy { !$0.steps.isEmpty })
        }
    }

    @Test("a file representation (as Files offers) is streamed into the handoff")
    func fileRepresentation() async throws {
        let box = try Sandbox()
        let src = try box.source("Walden.epub", length: 3 << 20)
        let provider = NSItemProvider()
        provider.registerFileRepresentation(forTypeIdentifier: UTType.epub.identifier, fileOptions: [], visibility: .all) { completion in
            completion(src, false, nil)
            return nil
        }
        provider.suggestedName = "Walden"
        let outcome = await share(provider, box: box)
        #expect(outcome.receipt?.totalBytes == 3 << 20)
        try checkInvariant(outcome, box: box)
        let manifest = try HandoffManifest.decode(Data(contentsOf: box.manifests()[0]))
        #expect(manifest.items[0].representation == .fileRepresentation)
        #expect(manifest.items[0].originalFilename == "Walden.epub")
        #expect(manifest.items[0].storedPath == "items/0.epub")
    }

    @Test("NSItemProvider(contentsOf:) for each supported kind", arguments: ["epub", "pdf", "txt", "md", "mp3", "m4a", "m4b"])
    func contentsOf(ext: String) async throws {
        let box = try Sandbox()
        let src = try box.source("sample.\(ext)", length: 100_000)
        let provider = try #require(NSItemProvider(contentsOf: src))
        let outcome = await share(provider, box: box)
        #expect(outcome.receipt != nil, "\(ext): \(String(describing: outcome.failure)); registered \(provider.registeredTypeIdentifiers)")
        try checkInvariant(outcome, box: box)
    }

    @Test("a direct file URL item is copied with coordination")
    func directFileURL() async throws {
        let box = try Sandbox()
        let src = try box.source("Meditations.pdf", length: 250_000)
        let provider = NSItemProvider(object: src as NSURL)
        let outcome = await share(provider, box: box)
        #expect(outcome.receipt != nil, "registered \(provider.registeredTypeIdentifiers): \(String(describing: outcome.failure))")
        try checkInvariant(outcome, box: box)
        if outcome.receipt != nil {
            let manifest = try HandoffManifest.decode(Data(contentsOf: box.manifests()[0]))
            print("direct file URL provider registered \(provider.registeredTypeIdentifiers); representation used: \(manifest.items[0].representation.rawValue)")
        }
    }

    @Test("provider error: fallback, nothing received")
    func providerError() async throws {
        let box = try Sandbox()
        let provider = NSItemProvider()
        provider.registerFileRepresentation(forTypeIdentifier: UTType.pdf.identifier, fileOptions: [], visibility: .all) { completion in
            completion(nil, false, NSError(domain: "com.example.provider", code: 7))
            return nil
        }
        let outcome = await share(provider, box: box)
        #expect(outcome.failure == .providerFailed)
        try checkInvariant(outcome, box: box)
    }

    @Test("provider returns no file and no error: fallback")
    func providerNoFile() async throws {
        let box = try Sandbox()
        let provider = NSItemProvider()
        provider.registerFileRepresentation(forTypeIdentifier: UTType.pdf.identifier, fileOptions: [], visibility: .all) { completion in
            completion(nil, false, nil)
            return nil
        }
        let outcome = await share(provider, box: box)
        #expect(outcome.failure != nil)
        try checkInvariant(outcome, box: box)
    }

    @Test("provider that never delivers: stall timeout, fallback")
    func providerStalls() async throws {
        let box = try Sandbox()
        let provider = NSItemProvider()
        provider.registerFileRepresentation(forTypeIdentifier: UTType.pdf.identifier, fileOptions: [], visibility: .all) { _ in
            Progress(totalUnitCount: 100)   // never calls completion, never progresses
        }
        let started = ContinuousClock.now
        let outcome = await share(provider, box: box, stall: .milliseconds(500))
        #expect(outcome.failure == .providerTimedOut)
        #expect(ContinuousClock.now - started < .seconds(10))
        try checkInvariant(outcome, box: box)
    }

    @Test("a provider whose progress keeps moving is never cut off by the stall timeout, however long it takes")
    func providerSlowButMoving() async throws {
        let box = try Sandbox()
        let src = try box.source("Slow.pdf", length: 200_000)
        let provider = NSItemProvider()
        let delivered = Flag()
        provider.registerFileRepresentation(forTypeIdentifier: UTType.pdf.identifier, fileOptions: [], visibility: .all) { completion in
            // As an iCloud download that keeps moving: progress every 100 ms for 3 s (six times the stall timeout used
            // below), then the file.
            let progress = SendableProgress(Progress(totalUnitCount: 30))
            let deliver = SendableCompletion(completion)
            DispatchQueue.global().async {
                for step in 1...30 {
                    usleep(100_000)
                    progress.progress.completedUnitCount = Int64(step)
                }
                delivered.set()
                deliver.completion(src, false, nil)
            }
            return progress.progress
        }
        let started = ContinuousClock.now
        let outcome = await share(provider, box: box, stall: .milliseconds(500))
        let elapsed = ContinuousClock.now - started
        print("slow but moving provider: \(outcome.receipt != nil ? "received" : "not received: \(outcome.failure!)") after \(elapsed)")
        #expect(outcome.receipt != nil, "a provider that keeps making progress must not time out: \(String(describing: outcome.failure))")
        #expect(delivered.isSet)
        #expect(elapsed >= .seconds(3))
        try checkInvariant(outcome, box: box)
    }

    @Test("a provider that makes progress and then stops is cut off after the stall timeout")
    func providerProgressThenStall() async throws {
        let box = try Sandbox()
        let provider = NSItemProvider()
        provider.registerFileRepresentation(forTypeIdentifier: UTType.pdf.identifier, fileOptions: [], visibility: .all) { _ in
            let progress = SendableProgress(Progress(totalUnitCount: 100))
            DispatchQueue.global().async {
                for step in 1...10 {
                    usleep(100_000)
                    progress.progress.completedUnitCount = Int64(step)
                }
                // ... then nothing more, and no completion.
            }
            return progress.progress
        }
        let started = ContinuousClock.now
        let outcome = await share(provider, box: box, stall: .milliseconds(500))
        let elapsed = ContinuousClock.now - started
        #expect(outcome.failure == .providerTimedOut)
        #expect(elapsed >= .milliseconds(1_400), "progress for 1 s kept it alive; then 0.5 s without progress: \(elapsed)")
        try checkInvariant(outcome, box: box)
    }

    /// G0.3 review R4-04: the stall timeout checked that work had not begun, then finished the gate unconditionally. A
    /// provider that delivered between the two started the copy, and the share still ended as timed out (the caller then
    /// discarded the session the copy was writing into). The seam runs the delivery in exactly that window.
    @Test("a delivery at the moment the stall timeout fires wins: the timeout neither fails the share nor cancels the load")
    func stallTimeoutLosesToADeliveryInItsWindow() async throws {
        final class GateBox: @unchecked Sendable { var gate: OnceGate<Int>? }
        let box = GateBox()
        let progress = Progress(totalUnitCount: 100)   // never moves: the timeout fires
        let delivered = Flag()
        let gate = OnceGate<Int>(beforeStallTimeoutFires: {
            // The provider's completion handler, arriving right now: it begins work, and its copy finishes a little later.
            guard let gate = box.gate, gate.beginWork() else { return }
            delivered.set()
            DispatchQueue.global().asyncAfter(deadline: .now() + 0.2) { gate.finish(.success(42)) }
        })
        box.gate = gate
        let started = ContinuousClock.now
        let outcome: Result<Int, any Error>
        do {
            outcome = .success(try await withCheckedThrowingContinuation { continuation in
                gate.install(continuation)
                gate.armStallTimeout(after: .milliseconds(300), progress: progress)
            })
        } catch {
            outcome = .failure(error)
        }
        let elapsed = ContinuousClock.now - started
        print("stall timeout vs a delivery in its window: \(String(describing: outcome)) after \(elapsed); load cancelled: \(progress.isCancelled)")
        #expect(delivered.isSet, "the seam ran: the timeout fired")
        #expect((try? outcome.get()) == 42, "the copy's result, not providerTimedOut")
        #expect(!progress.isCancelled, "the load was not cancelled under a copy that had begun")
    }

    /// G0.3 review R2-01: Cancel used to reach only the copier, so while a provider was still delivering (an iCloud
    /// download, a mail attachment) the sheet could not be cancelled until delivery or a 60 s stall.
    @Test("Cancel while the provider is still delivering (progress moving): fails as cancelled at once, the provider is told to stop, nothing received")
    func cancelBeforeDelivery() async throws {
        let box = try Sandbox()
        let src = try box.source("Slow.epub", length: 200_000)
        let provider = NSItemProvider()
        let providerSawCancel = Flag()
        let delivered = Flag()
        provider.registerFileRepresentation(forTypeIdentifier: UTType.epub.identifier, fileOptions: [], visibility: .all) { completion in
            // As a large iCloud download: progress every 100 ms for 60 s (the stall limit never fires), then the file.
            let progress = SendableProgress(Progress(totalUnitCount: 600))
            let deliver = SendableCompletion(completion)
            DispatchQueue.global().async {
                for step in 1...600 {
                    if progress.progress.isCancelled { providerSawCancel.set(); break }
                    usleep(100_000)
                    progress.progress.completedUnitCount = Int64(step)
                }
                // A provider that delivers anyway after being cancelled must not cause a copy or a receipt.
                delivered.set()
                deliver.completion(src, false, nil)
            }
            return progress.progress
        }
        let cancellation = CancellationSignal()
        let started = ContinuousClock.now
        let canceller = Task {
            try await Task.sleep(for: .seconds(1))
            cancellation.cancel()
        }
        let outcome = await share(provider, box: box, cancellation: cancellation)
        let elapsed = ContinuousClock.now - started
        _ = try await canceller.value
        print("cancel before delivery (file representation): \(outcome.receipt != nil ? "received" : "not received: \(outcome.failure!)") after \(elapsed), cancel sent at 1 s, delivery due at 60 s")
        #expect(outcome.failure == .cancelled)
        #expect(elapsed < .seconds(5), "cancel must act well before the provider delivers: \(elapsed)")
        let waitStart = ContinuousClock.now
        while !delivered.isSet && ContinuousClock.now - waitStart < .seconds(10) {
            try await Task.sleep(for: .milliseconds(50))
        }
        print("cancel before delivery (file representation): provider saw the cancel: \(providerSawCancel.isSet)")
        #expect(providerSawCancel.isSet, "cancelling the load's Progress must reach the provider's own Progress")
        try await Task.sleep(for: .milliseconds(300))   // the late delivery has been handled (and ignored)
        try checkInvariant(outcome, box: box)
    }

    @Test("Cancel while a direct file URL provider is still delivering: fails as cancelled at once, nothing received")
    func cancelBeforeFileURLDelivery() async throws {
        let box = try Sandbox()
        let src = try box.source("Slow.pdf", length: 100_000)
        let provider = NSItemProvider()
        let delivered = Flag()
        provider.registerItem(forTypeIdentifier: UTType.fileURL.identifier) { completion, _, _ in
            guard let completion else { return }
            DispatchQueue.global().asyncAfter(deadline: .now() + 30) {
                delivered.set()
                completion(src as NSURL, nil)
            }
        }
        let cancellation = CancellationSignal()
        let started = ContinuousClock.now
        let canceller = Task {
            try await Task.sleep(for: .seconds(1))
            cancellation.cancel()
        }
        let outcome = await share(provider, box: box, cancellation: cancellation)
        let elapsed = ContinuousClock.now - started
        _ = try await canceller.value
        print("cancel before delivery (file URL): \(outcome.receipt != nil ? "received" : "not received: \(outcome.failure!)") after \(elapsed), delivery due at 30 s")
        #expect(outcome.failure == .cancelled)
        #expect(elapsed < .seconds(5))
        #expect(!delivered.isSet)
        try checkInvariant(outcome, box: box)
    }

    @Test("Cancel while the coordinated read waits for another writer: the wait is cancelled, nothing copied or received")
    func cancelDuringCoordinatedWait() async throws {
        let box = try Sandbox()
        let src = try box.source("Held.epub", length: 300_000)
        let writerHolding = Flag()
        let releaseWriter = Flag()
        let writer = Thread {
            var error: NSError?
            NSFileCoordinator(filePresenter: nil).coordinate(writingItemAt: src, options: [], error: &error) { _ in
                writerHolding.set()
                let until = Date().addingTimeInterval(30)
                while !releaseWriter.isSet && Date() < until { Thread.sleep(forTimeInterval: 0.05) }
            }
        }
        writer.start()
        defer { releaseWriter.set() }
        while !writerHolding.isSet { try await Task.sleep(for: .milliseconds(10)) }

        let session = HandoffSession(environment: box.environment())
        let cancellation = CancellationSignal()
        let started = ContinuousClock.now
        let canceller = Task {
            try await Task.sleep(for: .seconds(1))
            cancellation.cancel()
        }
        let copy = Task.detached {
            Result {
                try ItemProviderIntake.copyCoordinated(
                    src, originalFilename: "Held.epub", type: .epub, representation: .fileRepresentation,
                    providerTypeIdentifier: UTType.epub.identifier, session: session,
                    cancellation: cancellation, progress: { _ in })
            }
        }
        let result = await copy.value
        let elapsed = ContinuousClock.now - started
        _ = try await canceller.value
        let writerStillHolding = !releaseWriter.isSet
        session.discard()
        let failure: HandoffFailure? = if case let .failure(error) = result { HandoffFailure.from(error) } else { nil }
        print("cancel during a coordinated-read wait: \(failure.map { "not received: \($0)" } ?? "copied") after \(elapsed), writer still holding: \(writerStillHolding)")
        #expect(failure == .cancelled)
        #expect(elapsed < .seconds(5), "the coordinated wait must end on cancel, not when the writer finishes (30 s): \(elapsed)")
        #expect(writerStillHolding)
        #expect(box.manifests().isEmpty && box.inboxEntries().isEmpty)
    }

    /// The copier polls the signal only before each read. A Cancel that lands after the last byte was read, while the
    /// item is synced and verified, used to end in "Received"; the commit now checks the signal first.
    @Test("Cancel after the last byte is copied but before the commit: discarded, nothing received")
    func cancelAfterLastByteBeforeCommit() async throws {
        let box = try Sandbox()
        let src = try box.source("Late.epub", length: 300_000)
        let provider = NSItemProvider()
        provider.registerFileRepresentation(forTypeIdentifier: UTType.epub.identifier, fileOptions: [], visibility: .all) { completion in
            completion(src, false, nil)
            return nil
        }
        let cancellation = CancellationSignal()
        // The user's Cancel arrives while the copied item is verified (after its full sync), the last write step before
        // the commit.
        let faults = CancelAtStep(step: .verifyItem, signal: cancellation)
        let outcome = await share(provider, box: box, cancellation: cancellation, faults: faults)
        print("cancel after the last byte, before the commit: \(outcome.receipt != nil ? "received" : "not received: \(outcome.failure!)")")
        #expect(faults.reached, "the copy must have run to its verify step")
        #expect(outcome.failure == .cancelled)
        try checkInvariant(outcome, box: box)
    }

    /// copyCoordinated registers its cancel handler, checks the signal and then starts the coordinated read. A cancel in
    /// that gap calls NSFileCoordinator.cancel() before coordinate(...) has begun. This pins the platform behaviour that
    /// keeps such a cancel effective: the later coordinate call does not wait for the other writer.
    @Test("platform: a file coordinator cancelled before its coordinate call returns at once with NSUserCancelledError (copyCoordinated relies on it)")
    func coordinatorCancelledBeforeCoordinate() async throws {
        let box = try Sandbox()
        let src = try box.source("Held.pdf", length: 4096)
        let writerHolding = Flag()
        let releaseWriter = Flag()
        let writer = Thread {
            var error: NSError?
            NSFileCoordinator(filePresenter: nil).coordinate(writingItemAt: src, options: [], error: &error) { _ in
                writerHolding.set()
                let until = Date().addingTimeInterval(30)
                while !releaseWriter.isSet && Date() < until { Thread.sleep(forTimeInterval: 0.05) }
            }
        }
        writer.start()
        defer { releaseWriter.set() }
        while !writerHolding.isSet { try await Task.sleep(for: .milliseconds(10)) }

        let read = Task.detached { () -> (Duration, Bool, Int?) in
            let coordinator = NSFileCoordinator(filePresenter: nil)
            coordinator.cancel()
            let started = ContinuousClock.now
            var error: NSError?
            var ran = false
            coordinator.coordinate(readingItemAt: src, options: [.withoutChanges], error: &error) { _ in ran = true }
            return (ContinuousClock.now - started, ran, error.map { $0.domain == NSCocoaErrorDomain ? $0.code : -1 })
        }
        let (elapsed, ran, code) = await read.value
        print("coordinator cancelled before coordinate: returned after \(elapsed), block ran: \(ran), error code: \(code.map(String.init) ?? "none")")
        #expect(!ran)
        #expect(code == NSUserCancelledError)
        #expect(elapsed < .seconds(5), "must not wait for the writer (it holds the file for 30 s): \(elapsed)")
    }

    @Test("a signal cancelled before the share starts: nothing is loaded or received")
    func cancelledBeforeStart() async throws {
        let box = try Sandbox()
        let src = try box.source("Early.epub", length: 10_000)
        let loaded = Flag()
        let provider = NSItemProvider()
        provider.registerFileRepresentation(forTypeIdentifier: UTType.epub.identifier, fileOptions: [], visibility: .all) { completion in
            loaded.set()
            completion(src, false, nil)
            return nil
        }
        let cancellation = CancellationSignal()
        cancellation.cancel()
        let outcome = await share(provider, box: box, cancellation: cancellation)
        #expect(outcome.failure == .cancelled)
        #expect(!loaded.isSet)
        try checkInvariant(outcome, box: box)
    }

    @Test("an EPUB package folder offered by a provider: the fallback names a folder, nothing received")
    func providerOffersFolder() async throws {
        let box = try Sandbox()
        let folder = box.sources.appendingPathComponent("Unpacked.epub", isDirectory: true)
        try FileManager.default.createDirectory(at: folder.appendingPathComponent("META-INF"), withIntermediateDirectories: true)
        try Data("application/epub+zip".utf8).write(to: folder.appendingPathComponent("mimetype"))
        try Data("<container/>".utf8).write(to: folder.appendingPathComponent("META-INF/container.xml"))

        let representation = NSItemProvider()
        representation.registerFileRepresentation(forTypeIdentifier: UTType.epub.identifier, fileOptions: [], visibility: .all) { completion in
            completion(folder, false, nil)
            return nil
        }
        let viaRepresentation = await share(representation, box: box)
        print("EPUB folder as a file representation: \(viaRepresentation.receipt != nil ? "received" : "not received: \(viaRepresentation.failure!)")")
        #expect(viaRepresentation.failure == .folderNotFile)
        try checkInvariant(viaRepresentation, box: box)

        let viaURL = await share(NSItemProvider(object: folder as NSURL), box: box)
        #expect(viaURL.failure == .folderNotFile)
        try checkInvariant(viaURL, box: box)
        #expect(FallbackRoute.for(.folderNotFile).reason.contains("folder"))
    }

    @Test("provider file deleted before the copy: fallback, nothing received")
    func providerFileVanishes() async throws {
        let box = try Sandbox()
        let gone = box.sources.appendingPathComponent("gone.pdf")
        let provider = NSItemProvider()
        provider.registerFileRepresentation(forTypeIdentifier: UTType.pdf.identifier, fileOptions: [], visibility: .all) { completion in
            completion(gone, false, nil)
            return nil
        }
        let outcome = await share(provider, box: box)
        #expect(outcome.failure != nil)
        try checkInvariant(outcome, box: box)
    }

    @Test("a web link is not a durable file: fallback names that")
    func webLink() async throws {
        let box = try Sandbox()
        let provider = NSItemProvider(object: URL(string: "https://example.com/book.epub")! as NSURL)
        let outcome = await share(provider, box: box)
        #expect(outcome.failure == .notADurableFile)
        try checkInvariant(outcome, box: box)
    }

    @Test("an unsupported type is not received")
    func unsupported() async throws {
        let box = try Sandbox()
        let src = try box.source("photo.jpg", length: 1000)
        let provider = try #require(NSItemProvider(contentsOf: src))
        let outcome = await share(provider, box: box)
        #expect(outcome.failure == .noSupportedItem)
        try checkInvariant(outcome, box: box)
    }

    @Test("in-memory text only (no file): records what NSItemProvider does; the invariant holds either way")
    func inMemoryData() async throws {
        let box = try Sandbox()
        let provider = NSItemProvider(item: Data("Plain shared text".utf8) as NSData, typeIdentifier: UTType.plainText.identifier)
        let outcome = await share(provider, box: box)
        print("in-memory plain-text provider: \(outcome.receipt != nil ? "materialized as a file and received" : "not received: \(outcome.failure!)")")
        try checkInvariant(outcome, box: box)
    }

    @Test("supported and refused file types")
    func typeTable() {
        for ext in ["epub", "pdf", "txt", "text", "md", "markdown", "mp3", "m4a", "m4b", "aac", "wav", "caf", "aiff"] {
            #expect(SupportedContent.supportedType(forFileExtension: ext) != nil, "\(ext) should be supported")
        }
        for ext in ["sh", "py", "swift", "js", "command", "html", "m3u", "m3u8", "pls", "jpg", "zip", "app", "exe", "", "sylviapack"] {
            #expect(SupportedContent.supportedType(forFileExtension: ext) == nil, "\(ext) should be refused")
        }
    }

    @Test("every failure maps to an actionable fallback that never claims receipt")
    func fallbackCopy() {
        let failures: [HandoffFailure] = [.noSupportedItem, .notADurableFile, .folderNotFile, .providerFailed, .providerTimedOut,
                                          .insufficientSpace(additionalBytesNeeded: 5_000_000_000), .insufficientSpace(additionalBytesNeeded: nil),
                                          .itemTooLarge(limit: 20 << 30), .sourceChanged, .cancelled, .writeFailed("x"), .tooManyItems,
                                          .manifestTooLarge]
        for failure in failures {
            let route = FallbackRoute.for(failure)
            #expect(route.headline.hasPrefix("Not received"))
            #expect(!route.reason.isEmpty)
            if case .itemTooLarge = failure {
                // Over the per-file limit nothing in Sylvia can import it; offering a route would be false.
                #expect(route.alternatives.isEmpty)
                #expect(route.reason.contains("any route"))
            } else {
                #expect(!route.alternatives.isEmpty)
            }
            for text in [route.headline, route.reason] + route.alternatives.flatMap({ [$0.title] + $0.steps }) {
                let lower = text.lowercased()
                #expect(!lower.contains("received by sylvia") && !lower.contains("ready") && !lower.contains("imported"),
                        "fallback copy must not claim receipt: \(text)")
            }
        }
        #expect(FallbackRoute.for(.insufficientSpace(additionalBytesNeeded: 5_000_000_000)).reason.contains("5 GB"))
    }
}
