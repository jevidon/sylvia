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

    /// Runs one provider through the same sequence the extension uses: receive, then commit or discard.
    func share(_ provider: NSItemProvider, box: Sandbox, stall: Duration = .seconds(60)) async -> Outcome {
        let session = HandoffSession(environment: box.environment())
        do {
            _ = try await ItemProviderIntake(providerStallTimeout: stall).receive(provider, into: session)
            return Outcome(receipt: try session.commit(), failure: nil)
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
                                          .itemTooLarge(limit: 20 << 30), .sourceChanged, .cancelled, .writeFailed("x"), .tooManyItems]
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
