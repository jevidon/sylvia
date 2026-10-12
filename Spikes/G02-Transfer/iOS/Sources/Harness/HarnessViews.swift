import SwiftUI
import SylviaBackgroundTransfer
import SylviaTransferClient
import SylviaTransferCore
import VisionKit

/// Harness chrome only (plan 4.4.9 exemption for Spikes/): system list styling, no design tokens.
/// Accessibility identifiers are what the UI tests read.
struct HarnessRootView: View {
    @Bindable var model: HarnessModel

    var body: some View {
        NavigationStack {
            List {
                LaunchSection(model: model)
                JobsSection(model: model)
                PairingSection(model: model)
                SourcesSection(model: model)
                EventsSection(model: model)
            }
            .navigationTitle("G0.2 Transfer")
        }
    }
}

struct LaunchSection: View {
    let model: HarnessModel

    var body: some View {
        Section("Last launch reconciliation") {
            if let summary = model.reconciliation, let reason = summary.deferredReason {
                Text("Waiting: \(reason). Nothing was read, cancelled or written; this runs again when the stores can be read (after the first unlock).")
                    .accessibilityIdentifier("reconciliation.deferred")
            } else if let summary = model.reconciliation {
                Text("jobs \(summary.jobs), outstanding tasks \(summary.outstandingTasks), adopted \(summary.adopted), enqueued \(summary.enqueued)")
                    .accessibilityIdentifier("reconciliation.summary")
                Text("kept verified parts \(summary.keptVerifiedParts), discarded \(summary.discardedParts), cancelled \(summary.cancelled.values.reduce(0, +))")
                    .accessibilityIdentifier("reconciliation.kept")
            } else {
                Text("Reconciling...")
            }
        }
    }
}

struct PairingSection: View {
    @Bindable var model: HarnessModel
    @State private var scanning = false

    var body: some View {
        Section("Pair with a Mac") {
            TextField("Paste the pairing code or link", text: $model.codeText, axis: .vertical)
                .lineLimit(1...3)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
                .font(.caption.monospaced())
                .accessibilityIdentifier("pairing.code")
            HStack {
                Button("Check code") { model.checkCode() }
                    .disabled(model.codeText.isEmpty)
                    .accessibilityIdentifier("pairing.check")
                if DataScannerViewController.isSupported {
                    Button("Scan QR code") { scanning = true }
                } else {
                    Text("QR scanning needs a device camera").font(.caption).foregroundStyle(.secondary)
                }
            }
            if model.testCodeFile != nil {
                Button("Use code from test file") { model.useTestCode() }
                    .accessibilityIdentifier("pairing.useTestCode")
            }
            if let payload = model.pendingPayload {
                VStack(alignment: .leading, spacing: 4) {
                    Text(payload.sourceName).font(.headline)
                    Text("Fingerprint (SPKI SHA-256):").font(.caption)
                    Text((try? payload.pin.displayFingerprint) ?? "invalid")
                        .font(.footnote.monospaced())
                        .accessibilityIdentifier("pairing.fingerprint")
                    Text("Addresses: \(payload.endpoints.map { "\($0.urlHost):\($0.port)" }.joined(separator: ", "))")
                        .font(.caption)
                    Text("Expires \(payload.expiresAt.formatted(date: .omitted, time: .shortened))").font(.caption)
                        .accessibilityIdentifier("pairing.addresses")
                }
                HStack {
                    TextField("Other host or IP", text: $model.pairingOverrideHost)
                        .textInputAutocapitalization(.never).autocorrectionDisabled()
                        .accessibilityIdentifier("pairing.overrideHost")
                    TextField("Port", text: $model.pairingOverridePort).keyboardType(.numberPad).frame(width: 70)
                        .accessibilityIdentifier("pairing.overridePort")
                    Button("Use address") { model.overridePendingAddress() }
                        .accessibilityIdentifier("pairing.overrideUse")
                }
                Button("Pair") { Task { await model.pair() } }
                    .disabled(model.pairingInProgress)
                    .accessibilityIdentifier("pairing.pair")
            }
            if !model.pairingStatus.isEmpty {
                Text(model.pairingStatus).font(.caption).accessibilityIdentifier("pairing.status")
            }
        }
        .sheet(isPresented: $scanning) {
            QRScannerView { text in
                model.codeText = text
                model.checkCode()
                scanning = false
            }
        }
    }
}

struct SourcesSection: View {
    @Bindable var model: HarnessModel

    var body: some View {
        Section("Paired Macs") {
            if model.sources.isEmpty { Text("None").foregroundStyle(.secondary) }
            ForEach(model.sources, id: \.sourceID) { source in
                VStack(alignment: .leading, spacing: 4) {
                    Text(source.sourceName).font(.headline).accessibilityIdentifier("source.name")
                    Text((try? SPKIPin(hex: source.spkiSHA256).displayFingerprint) ?? "")
                        .font(.caption2.monospaced())
                        .accessibilityIdentifier("source.fingerprint")
                    Text("Addresses: \(source.endpoints.map { "\($0.urlHost):\($0.port)" }.joined(separator: ", "))")
                        .font(.caption)
                    Button("Browse catalog") { Task { await model.loadCatalog(source) } }
                        .accessibilityIdentifier("source.browse")
                    ForEach(model.catalog[source.sourceID] ?? [], id: \.itemID) { item in
                        Button("Download \(item.title)") { Task { await model.download(item, from: source) } }
                            .accessibilityIdentifier("catalog.download.\(item.title)")
                    }
                    // Pull-first device inbox (plan 15.1): what the Mac sent to this phone with "send".
                    Button("Check inbox") { Task { await model.checkInbox(source) } }
                        .accessibilityIdentifier("source.inbox")
                    ForEach(model.inbox[source.sourceID] ?? [], id: \.queueEntryID) { entry in
                        VStack(alignment: .leading) {
                            Text("\(entry.title): \(entry.state.rawValue)").font(.caption)
                                .accessibilityIdentifier("inbox.entry.\(entry.title)")
                            if entry.state == .queuedOnMac || entry.state == .observedByPhone || entry.state == .importFailed {
                                Button("Download from inbox: \(entry.title)") { Task { await model.download(entry, from: source) } }
                                    .accessibilityIdentifier("inbox.download.\(entry.title)")
                            }
                        }
                    }
                    HStack {
                        TextField("Host or IP", text: $model.manualHost)
                            .textInputAutocapitalization(.never).autocorrectionDisabled()
                            .accessibilityIdentifier("manual.host")
                        TextField("Port", text: $model.manualPort).keyboardType(.numberPad).frame(width: 70)
                            .accessibilityIdentifier("manual.port")
                        Button("Use") { Task { await model.addManualAddress(to: source) } }
                            .accessibilityIdentifier("manual.use")
                    }
                    Button(model.bonjour.found.isEmpty ? "Browse the local network" : "Refresh local network") { model.bonjour.start() }
                    Text(model.bonjour.status).font(.caption2)
                    ForEach(model.bonjour.found) { found in
                        Button("Use \(found.name)\(found.sourceID == source.sourceID ? " (this Mac)" : "")") {
                            Task { await model.useBonjourResult(found, for: source) }
                        }
                    }
                    if !model.manualStatus.isEmpty { Text(model.manualStatus).font(.caption).accessibilityIdentifier("manual.status") }
                }
            }
            if !model.catalogStatus.isEmpty { Text(model.catalogStatus).font(.caption) }
        }
    }
}

struct JobsSection: View {
    let model: HarnessModel

    var body: some View {
        Section("Transfers") {
            if model.jobs.isEmpty { Text("None").foregroundStyle(.secondary) }
            ForEach(model.jobs) { view in
                JobRow(view: view, coordinator: model.runtime.coordinator)
            }
        }
    }
}

struct JobRow: View {
    let view: BackgroundTransferCoordinator.JobView
    let coordinator: BackgroundTransferCoordinator

    var stage: String {
        switch view.job.state {
        case .downloading:
            view.progress.receivedBytes >= view.progress.totalBytes && !view.progress.isFullyVerified ? "Verifying parts" : "Downloading"
        case .refreshing: "The Mac's file changed: getting the new version"
        case .paused: "Paused"
        case .assembling: "Checking the whole file"
        case .readyForImport: "Verified, waiting for import"
        case .imported: "Imported"
        case .cancelled: "Cancelled"
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(view.job.title).font(.headline)
            Text(stage).accessibilityIdentifier("job.stage")
            Text(ProgressText.received(view.progress)).font(.caption).accessibilityIdentifier("job.received")
            Text(ProgressText.verified(view.progress)).font(.caption).accessibilityIdentifier("job.verified")
            Text("\(view.verifiedParts) of \(view.totalParts) parts verified, \(view.outstandingTasks) requests outstanding")
                .font(.caption2).accessibilityIdentifier("job.parts")
            Text("verifiedParts=\(view.verifiedParts)").font(.caption2).foregroundStyle(.secondary)
                .accessibilityIdentifier("job.verifiedCount")
            if let reason = view.job.pauseReason, view.job.state == .paused {
                Text(reason.nextStep).font(.caption).accessibilityIdentifier("job.nextStep")
            }
            HStack {
                if view.job.state == .downloading { Button("Pause") { coordinator.pause(jobID: view.job.jobID) } }
                if view.job.state == .paused { Button("Resume") { coordinator.resume(jobID: view.job.jobID) } }
                if !view.job.isTerminal { Button("Cancel", role: .destructive) { coordinator.cancel(jobID: view.job.jobID) } }
            }
            .buttonStyle(.borderless)
        }
    }
}

struct EventsSection: View {
    let model: HarnessModel

    var body: some View {
        Section("Recent events (no secrets, no titles)") {
            ForEach(Array(model.recentEvents.enumerated()), id: \.offset) { _, entry in
                Text("\(entry.event) " + entry.fields.sorted { $0.key < $1.key }.map { "\($0.key)=\($0.value)" }.joined(separator: " "))
                    .font(.caption2.monospaced())
                    .lineLimit(3)
            }
        }
    }
}

/// QR scanning of the pairing link (device only: DataScannerViewController needs a camera).
struct QRScannerView: UIViewControllerRepresentable {
    let onCode: (String) -> Void

    func makeUIViewController(context: Context) -> DataScannerViewController {
        let scanner = DataScannerViewController(recognizedDataTypes: [.barcode(symbologies: [.qr])], qualityLevel: .balanced)
        scanner.delegate = context.coordinator
        try? scanner.startScanning()
        return scanner
    }

    func updateUIViewController(_ controller: DataScannerViewController, context: Context) {}

    func makeCoordinator() -> Coordinator { Coordinator(onCode: onCode) }

    final class Coordinator: NSObject, DataScannerViewControllerDelegate {
        let onCode: (String) -> Void
        init(onCode: @escaping (String) -> Void) { self.onCode = onCode }

        func dataScanner(_ scanner: DataScannerViewController, didAdd items: [RecognizedItem], allItems: [RecognizedItem]) {
            for item in items {
                if case .barcode(let barcode) = item, let text = barcode.payloadStringValue,
                    text.hasPrefix(PairingPayload.linkPrefix) || text.hasPrefix(PairingPayload.codePrefix)
                {
                    scanner.stopScanning()
                    onCode(text)
                    return
                }
            }
        }
    }
}
