// G0.3 share extension. Stage 0 harness chrome (plain SwiftUI, literal strings); never shipped.
//
// Sequence (plan 6.1, 8.1): stream every shared item into a unique App Group handoff directory, fsync, write
// handoff.json atomically last, and only then show "Received". On any failure show the fallback (FallbackRoute)
// and claim nothing. The extension never touches the catalog; the app imports from the inbox.
import SwiftUI
import SylviaImportHandoff
import SylviaIntakeCore
import UIKit
import UniformTypeIdentifiers
import os

let appGroupIdentifier = "group.com.jevidon.sylvia.spike"

@MainActor
final class ShareModel: ObservableObject {
    enum Phase: Equatable {
        case copying
        case received(items: Int, bytes: UInt64)
        case notReceived(FallbackRoute)
    }

    @Published var phase: Phase = .copying
    @Published var copiedBytes: UInt64 = 0
    @Published var startFootprint: UInt64 = 0
    @Published var peakFootprint: UInt64 = 0
    /// os_proc_available_memory() at start: bytes left before this process's memory limit (0 where no limit is
    /// enforced, as on the simulator). Footprint plus this approximates the extension's limit on a device.
    @Published var availableAtStart: UInt64 = 0
    /// task_vm_info.limit_bytes_remaining at start, read directly (os/proc.h says os_proc_available_memory() returns 0
    /// for a process that "is not an app"); nil when the kernel did not fill the field.
    @Published var limitRemainingAtStart: UInt64?
    @Published var series = ""
    /// Data-protection class of what this extension wrote (plan 18.1; device checklist step 24). "none reported" on
    /// the simulator, which has no data protection.
    @Published var protection = ""
    /// How each item reached the extension (file representation in place, file representation copy, or file URL).
    @Published var representations = ""
    /// Cancel acts while the provider is still delivering (an iCloud download, a mail attachment), while a coordinated
    /// read waits, and during the copy (G0.3 review R2-01).
    let cancellation = CancellationSignal()
}

/// Records phys_footprint every 1 GiB copied, so a run shows whether memory follows the bytes copied.
final class FootprintSeries: @unchecked Sendable {
    private let lock = NSLock()
    private var next: UInt64 = 0
    private var points: [(UInt64, UInt64)] = []
    func record(_ bytes: UInt64) {
        let due: Bool = lock.withLock {
            guard bytes >= next else { return false }
            next = bytes + (1 << 30)
            return true
        }
        guard due else { return }
        let footprint = MemorySample.now().physFootprint
        lock.withLock { points.append((bytes, footprint)) }
    }
    /// "<MiB copied>:<footprint MiB>" pairs.
    var summary: String {
        lock.withLock { points.map { "\($0.0 >> 20):\($0.1 >> 20)" }.joined(separator: " ") }
    }
}

/// Forwards copy progress to the UI at most every 32 MiB, so UI updates do not scale with the file size.
final class ProgressThrottle: @unchecked Sendable {
    private let lock = NSLock()
    private var last: UInt64 = 0
    private let step: UInt64 = 32 << 20
    func shouldReport(_ bytes: UInt64) -> Bool {
        lock.withLock {
            guard bytes >= last + step else { return false }
            last = bytes
            return true
        }
    }
}

final class ShareViewController: UIViewController {
    private let model = ShareModel()
    private var sampler: FootprintSampler?

    override func viewDidLoad() {
        super.viewDidLoad()
        let host = UIHostingController(rootView: ShareView(model: model,
                                                           done: { [weak self] in self?.finish() },
                                                           cancel: { [weak self] in self?.model.cancellation.cancel() }))
        addChild(host)
        host.view.frame = view.bounds
        host.view.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        view.addSubview(host.view)
        host.didMove(toParent: self)
        start()
    }

    private func start() {
        let providers = (extensionContext?.inputItems as? [NSExtensionItem] ?? []).flatMap { $0.attachments ?? [] }
        model.startFootprint = MemorySample.now().physFootprint
        model.availableAtStart = UInt64(os_proc_available_memory())
        model.limitRemainingAtStart = MemorySample.limitBytesRemaining()
        let sampler = FootprintSampler()
        sampler.start()
        self.sampler = sampler
        let model = self.model
        let cancellation = model.cancellation
        let box = ProvidersBox(providers)
        let throttle = ProgressThrottle()
        let series = FootprintSeries()
        Task.detached(priority: .userInitiated) {
            let (outcome, protection, representations) = await ShareViewController.handOff(box.providers, cancellation: cancellation) { bytes in
                series.record(bytes)
                guard throttle.shouldReport(bytes) else { return }
                Task { @MainActor in model.copiedBytes = bytes }
            }
            let peak = sampler.stop()
            await MainActor.run {
                model.peakFootprint = peak
                model.series = series.summary
                model.protection = protection
                model.representations = representations
                switch outcome {
                case let .success(receipt): model.phase = .received(items: receipt.itemCount, bytes: receipt.totalBytes)
                case let .failure(failure): model.phase = .notReceived(FallbackRoute.for(failure))
                }
            }
        }
    }

    /// Runs off the main actor: receive every provider into one session, then commit (manifest last). Also returns the
    /// protection classes of what was written and how each item arrived (evidence lines, no names).
    nonisolated static func handOff(_ providers: [NSItemProvider], cancellation: CancellationSignal,
                                    progress: @escaping @Sendable (UInt64) -> Void) async -> (Result<HandoffReceipt, HandoffFailure>, String, String) {
        guard !providers.isEmpty else { return (.failure(.noSupportedItem), "", "") }
        guard let group = FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: appGroupIdentifier) else {
            return (.failure(.writeFailed("App Group container unavailable")), "", "")
        }
        let environment = HandoffEnvironment(
            inbox: group.appendingPathComponent("Intake/Handoffs", isDirectory: true),
            producerBundleIdentifier: Bundle.main.bundleIdentifier ?? "unknown",
            producerBuildVersion: Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "0"
        )
        let session = HandoffSession(environment: environment)
        let intake = ItemProviderIntake()
        var completedBytes: UInt64 = 0
        var items: [HandoffManifest.Item] = []
        var inPlace: [String] = []
        do {
            for provider in providers {
                let base = completedBytes
                let delivered = InPlaceFlag()
                let item = try await intake.receive(provider, into: session,
                                                    cancellation: cancellation,
                                                    progress: { progress(base + $0) },
                                                    openedInPlace: { delivered.set($0) })
                completedBytes += item.byteCount
                items.append(item)
                inPlace.append(delivered.value.map { $0 ? "in place" : "temporary copy" } ?? "n/a")
            }
            let receipt = try session.commit(isCancelled: { cancellation.isCancelled })
            let representations = zip(items, inPlace).map { item, place in
                "\(item.storedPath): \(item.representation.rawValue), \(place) (\(item.providerTypeIdentifier))"
            }.joined(separator: "; ")
            return (.success(receipt), protectionSummary(session.directory, items: items), representations)
        } catch {
            session.discard()
            return (.failure(HandoffFailure.from(error)), "", "")
        }
    }

    nonisolated static func protectionSummary(_ directory: URL, items: [HandoffManifest.Item]) -> String {
        let probes = [("Handoffs/", directory.deletingLastPathComponent()), ("handoff directory", directory),
                      ("handoff.json", directory.appendingPathComponent(HandoffManifest.fileName))]
            + items.prefix(3).map { ($0.storedPath, directory.appendingPathComponent($0.storedPath)) }
        return probes.map { name, url in
            let value = (try? FileManager.default.attributesOfItem(atPath: url.path)[.protectionKey] as? FileProtectionType)?.rawValue
            return "\(name)=\(value ?? "none reported")"
        }.joined(separator: ", ")
    }

    private func finish() {
        switch model.phase {
        case .received: extensionContext?.completeRequest(returningItems: [], completionHandler: nil)
        case .notReceived, .copying:
            model.cancellation.cancel()
            extensionContext?.cancelRequest(withError: NSError(domain: "com.jevidon.sylvia.spike.intake.share",
                                                               code: NSUserCancelledError))
        }
    }
}

/// Whether the provider handed over its original file; nil when not a file representation.
final class InPlaceFlag: @unchecked Sendable {
    private let lock = NSLock()
    private var stored: Bool?
    func set(_ value: Bool) { lock.withLock { stored = value } }
    var value: Bool? { lock.withLock { stored } }
}

/// NSItemProvider is not Sendable; the providers are only used from the detached task.
struct ProvidersBox: @unchecked Sendable {
    let providers: [NSItemProvider]
    init(_ providers: [NSItemProvider]) { self.providers = providers }
}

struct ShareView: View {
    @ObservedObject var model: ShareModel
    let done: () -> Void
    let cancel: () -> Void

    var body: some View {
        NavigationStack {
            VStack(alignment: .leading, spacing: 16) {
                switch model.phase {
                case .copying:
                    ProgressView()
                    Text("Copying to Sylvia…").font(.headline).accessibilityIdentifier("share.copying")
                    Text("\(ByteCountFormatter.string(fromByteCount: Int64(model.copiedBytes), countStyle: .file)) copied")
                        .monospacedDigit()
                        .accessibilityIdentifier("share.copiedBytes")
                    Text("Keep this sheet open until the copy finishes.").font(.footnote)
                case let .received(items, bytes):
                    Text("Received by Sylvia").font(.headline).accessibilityIdentifier("share.received")
                    Text(verbatim: "\(items) item(s), \(bytes) bytes. Open Sylvia to finish importing.")
                        .accessibilityIdentifier("share.receivedDetail")
                case let .notReceived(route):
                    Text(route.headline).font(.headline).accessibilityIdentifier("share.notReceived")
                    Text(route.reason).accessibilityIdentifier("share.reason")
                    ForEach(route.alternatives, id: \.title) { alternative in
                        VStack(alignment: .leading, spacing: 4) {
                            Text(alternative.title).font(.subheadline.bold())
                            ForEach(Array(alternative.steps.enumerated()), id: \.offset) { index, step in
                                Text("\(index + 1). \(step)").font(.footnote)
                            }
                        }
                    }
                }
                if model.peakFootprint > 0 {
                    // Verbatim: a localized key would insert grouping separators, which the UI test parses.
                    Text(verbatim: "Extension footprint: start \(model.startFootprint) bytes, peak \(model.peakFootprint) bytes")
                        .font(.caption2).monospacedDigit()
                        .accessibilityIdentifier("share.peakFootprint")
                    Text(verbatim: "Available before the memory limit at start: os_proc_available_memory \(model.availableAtStart) bytes, task_vm_info.limit_bytes_remaining \(model.limitRemainingAtStart.map { "\($0) bytes" } ?? "not reported")")
                        .font(.caption2).monospacedDigit()
                        .accessibilityIdentifier("share.availableMemory")
                    Text(verbatim: "Footprint MiB by MiB copied: \(model.series)")
                        .font(.caption2).monospacedDigit()
                        .lineLimit(nil)
                        .fixedSize(horizontal: false, vertical: true)
                        .accessibilityIdentifier("share.footprintSeries")
                    if !model.protection.isEmpty {
                        Text(verbatim: "Protection: \(model.protection)")
                            .font(.caption2).lineLimit(nil).fixedSize(horizontal: false, vertical: true)
                            .accessibilityIdentifier("share.protection")
                        Text(verbatim: "Received as: \(model.representations)")
                            .font(.caption2).lineLimit(nil).fixedSize(horizontal: false, vertical: true)
                            .accessibilityIdentifier("share.representations")
                    }
                }
                Spacer()
            }
            .padding()
            .navigationTitle("Sylvia")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    if model.phase == .copying {
                        Button("Cancel", action: cancel).accessibilityIdentifier("share.cancel")
                    }
                }
                ToolbarItem(placement: .confirmationAction) {
                    if model.phase != .copying {
                        Button("Done", action: done).accessibilityIdentifier("share.done")
                    }
                }
            }
        }
    }
}
