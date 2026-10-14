// G0.3 intake harness app. Stage 0 harness chrome (plain SwiftUI, literal strings); never shipped.
//
// - Scans the App Group handoff inbox on launch and on every foreground (InboxScanner).
// - Lists the Finder drop area (Documents) and imports a .sylviapack only when the user taps Import.
// - Accepts open-in / AirDrop files through the same journal (DropAreaImporter.importOpenedFile: a .sylviapack goes
//   through the bundle importer, anything else through the single-file importer; the Documents/Inbox copy is removed
//   whatever the outcome).
// - Imports a raw supported file from the drop area too (plan 8.5), and a file chosen in the system document picker
//   ("Import from Files", fallback route step 1).
// - For UI tests: "Share test file" writes a file of the size in the -G03ShareBytes launch argument and presents
//   the system share sheet so a test can pick the Sylvia Intake extension. "Share from a slow provider" shares an
//   item provider that reports progress for -G03SlowProviderSeconds before delivering (an iCloud-like download), so a
//   test can cancel the extension before delivery. "Place test file in drop area" stands in for a Finder copy.
import os
import SwiftUI
import SylviaContainerLayout
import SylviaImportHandoff
import SylviaIntakeCore
import SylviaPack
import UIKit
import UniformTypeIdentifiers

let appGroupIdentifier = "group.com.jevidon.sylvia.spike"

@main
struct IntakeHarnessApp: App {
    @StateObject private var model = HarnessModel()
    @Environment(\.scenePhase) private var scenePhase

    var body: some Scene {
        WindowGroup {
            HarnessView(model: model)
                .onOpenURL { url in model.openIn(url) }
        }
        .onChange(of: scenePhase) { _, phase in
            if phase == .active { model.scan(reason: "foreground") }
        }
    }
}

@MainActor
final class HarnessModel: ObservableObject {
    @Published var summary = "not scanned"
    @Published var lastScan = ""
    @Published var dropArea: [DropAreaImporter.DropItem] = []
    @Published var message = ""
    @Published var shareURL: URL?

    let layout: StorageLayout?
    let importer: DropAreaImporter?
    let scanner: InboxScanner?
    let setupError: String?

    init() {
        do {
            let layout = try StorageLayout.current(appGroupIdentifier: appGroupIdentifier)
            try layout.bootstrap()
            guard let inbox = layout.handoffInbox else { throw HandoffFailure.writeFailed("App Group container unavailable") }
            let journal = try IntakeJournal(url: layout.journal)
            self.layout = layout
            self.importer = DropAreaImporter(layout: layout, journal: journal)
            self.scanner = InboxScanner(inbox: inbox, stagingRoot: layout.staging, journal: journal)
            self.setupError = nil
            importer?.recoverInterruptedImports()
        } catch {
            self.layout = nil
            self.importer = nil
            self.scanner = nil
            self.setupError = String(describing: error)
        }
        scan(reason: "launch")
    }

    /// Every scan's trigger, request time, start and duration (UI tests print it as evidence).
    @Published var scanLog: [String] = []

    func scan(reason: String) {
        guard let scanner else { summary = "setup failed: \(setupError ?? "?")"; return }
        let requested = Date()
        Task.detached(priority: .userInitiated) {
            let started = Date()
            let result = Result { try scanner.scan() }
            let finished = Date()
            await MainActor.run { self.apply(result, reason: reason, requested: requested, started: started, finished: finished) }
        }
    }

    private func apply(_ result: Result<InboxScanReport, any Error>, reason: String, requested: Date, started: Date, finished: Date) {
        switch result {
        case let .success(r):
            lastScan = "\(reason): accepted=\(r.acceptedJobs.count) recovered=\(r.recoveredJobs.count) inProgress=\(r.inProgress.count) removed=\(r.abandonedRemoved.count) rejected=\(r.rejected.count)"
        case let .failure(error):
            lastScan = "\(reason): scan failed: \(error)"
        }
        let time = ISO8601DateFormatter.string(from: requested, timeZone: .gmt, formatOptions: [.withFullTime, .withFractionalSeconds])
        scanLog.append(String(format: "%@ requested %@, waited %.1fs, ran %.1fs -> %@", reason, time,
                              started.timeIntervalSince(requested), finished.timeIntervalSince(started), lastScan))
        refresh()
    }

    func refresh() {
        guard let importer else { return }
        let jobs = importer.journal.jobs
        summary = "jobs=\(jobs.count) staged=\(jobs.filter { $0.state == .staged }.count) review=\(jobs.filter { $0.state == .needsReview }.count) share=\(jobs.filter { $0.route == .shareExtension }.count)"
        dropArea = importer.listDropArea()
    }

    /// The drop area's Import button: a bundle through the bundle importer, a raw supported file through the
    /// single-file importer (plan 8.5), an `Inbox/<name>` leftover as an opened file.
    func importDropAreaItem(_ name: String) {
        guard let importer else { return }
        message = "Verifying \(name)…"
        Task.detached(priority: .userInitiated) {
            let outcome: String
            do {
                let job = try await importer.importDropAreaItem(named: name)
                outcome = "Imported \(name): \(job.items.count) files, state \(job.state.rawValue), route \(job.route.rawValue)"
            } catch {
                outcome = "Not imported: \(error)"
            }
            await MainActor.run { self.message = outcome; self.refresh() }
        }
    }

    @Published var showingPicker = false

    /// Import, then Files (fallback route step 1): a file chosen in the system document picker, opened in place
    /// (security-scoped, not a copy the picker made), goes through the single-file importer, which takes scoped access
    /// and a coordinated read (plan 8.1 "Files/document picker"). The picked file is never modified or removed (I-08).
    func importPicked(_ url: URL) {
        guard let importer else { return }
        message = "Importing picked file…"
        pickCount += 1
        let pick = pickCount
        let folder = HarnessModel.containerRelativeFolder(of: url)
        Task.detached(priority: .userInitiated) {
            // A picked file outside this app's container is readable only with security-scoped access. Record whether
            // the system granted it: evidence that the picker handed over the provider's own file, not a copy. (The
            // importer takes the same access again for its coordinated read; the calls nest.)
            let scopedGranted = url.startAccessingSecurityScopedResource()
            defer { if scopedGranted { url.stopAccessingSecurityScopedResource() } }
            // Review R3-05: that the picked file is left untouched is measured, not assumed. Its identity (device, inode,
            // size, modification time to the nanosecond) is taken before and after the import, and afterwards its bytes
            // are hashed again inside a coordinated read and compared with what the importer staged.
            let before = DropAreaImporter.FileIdentity.of(url)
            let outcome: String
            var imported: CopyResult?
            do {
                let job = try importer.importSingleFile(at: url, route: .documentPicker)
                outcome = "Picked file staged: \(job.items.count) file(s), state \(job.state.rawValue), \(job.items.first.map { "\($0.byteCount) bytes" } ?? "")"
                if job.items.count == 1, let item = job.items.first {
                    imported = CopyResult(byteCount: item.byteCount, sha256: item.sha256)
                }
            } catch {
                outcome = "Picked file not imported: \(error)"
            }
            let after = DropAreaImporter.FileIdentity.of(url)
            let identityUnchanged = before != nil && before == after
            let bytesMatch: String
            if let imported {
                bytesMatch = HarnessModel.coordinatedDigest(of: url).map { $0 == imported ? "true" : "false" } ?? "unreadable"
            } else {
                bytesMatch = "not compared (nothing imported)"
            }
            let detail = "pick \(pick): picked from \(folder); security-scoped access granted: \(scopedGranted); "
                + "source identity before and after the import equal (device, inode, size, modification time): \(identityUnchanged) "
                + "[\(before.map(\.description) ?? "none")]; source SHA-256 afterwards equals the imported bytes: \(bytesMatch)"
            // Evidence for ImportRoutesUITests: where the picked file lives (relative to this app's container, never its
            // name), whether scoped access was granted, whether the source is untouched, and the outcome.
            HarnessModel.log.notice("G03-PICKER \(detail, privacy: .public) outcome=\(outcome, privacy: .public)")
            await MainActor.run {
                self.message = outcome
                self.pickerDetail = detail
                self.refresh()
            }
        }
    }

    /// The size and SHA-256 of a file read inside a coordinated read without changes, or nil when it cannot be read.
    nonisolated static func coordinatedDigest(of url: URL) -> CopyResult? {
        var result: CopyResult?
        var coordinationError: NSError?
        NSFileCoordinator().coordinate(readingItemAt: url, options: .withoutChanges, error: &coordinationError) { readURL in
            result = try? FileDigest.sha256(of: readURL)
        }
        return coordinationError == nil ? result : nil
    }

    @Published var pickerDetail = ""
    /// Numbers the picks since launch, so a UI test can tell two picks of the same file apart.
    private var pickCount = 0

    /// The item provider shared by "Share from a slow provider", and what its loads did (UI-test evidence).
    @Published var slowShareProvider: SlowProviderItem?
    @Published var slowProviderLog: [String] = []

    /// UI-test helper for G0.3 review R2-01: a provider that is still delivering when the user taps Cancel in the
    /// extension. It reports progress every 100 ms for the requested number of seconds, then delivers a small EPUB;
    /// it stops at once if its Progress is cancelled, and records which happened.
    func prepareSlowShare() {
        let seconds = max(1, UserDefaults.standard.string(forKey: "G03SlowProviderSeconds").flatMap { Int($0) } ?? 90)
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("G03 Slow Share.epub")
        try? FileManager.default.removeItem(at: url)
        do {
            try DeterministicBytes(seed: 0x51_0E).writeFile(url, length: 256 << 10)
        } catch {
            message = "could not create share file: \(error)"
            return
        }
        slowProviderLog = []
        let recorder = SlowProviderRecorder(model: self)
        let provider = NSItemProvider()
        provider.suggestedName = "G03 Slow Share"
        provider.registerFileRepresentation(forTypeIdentifier: UTType.epub.identifier, fileOptions: [], visibility: .all) { completion in
            let progress = Progress(totalUnitCount: Int64(seconds * 10))
            let load = recorder.beginLoad()
            let work = SlowProviderWork(progress: progress, completion: completion)
            DispatchQueue.global().async {
                let started = Date()
                for step in 1...(seconds * 10) {
                    if work.progress.isCancelled {
                        recorder.note(String(format: "load %d: asked to stop after %.1f s", load, Date().timeIntervalSince(started)))
                        work.completion(nil, false, NSError(domain: NSCocoaErrorDomain, code: NSUserCancelledError))
                        return
                    }
                    usleep(100_000)
                    work.progress.completedUnitCount = Int64(step)
                }
                recorder.note(String(format: "load %d: delivered after %.1f s", load, Date().timeIntervalSince(started)))
                work.completion(url, false, nil)
            }
            return progress
        }
        slowShareProvider = SlowProviderItem(provider: provider)
    }

    /// UI-test helper standing in for Finder's file-sharing copy: puts a deterministic file in Documents, the drop area.
    func placeDropAreaFile() {
        let name = UserDefaults.standard.string(forKey: "G03DropFileName") ?? "G03 Finder Copy.epub"
        guard let layout, !PathBytes.containsSeparator(name) else { return }
        do {
            try? FileManager.default.removeItem(at: layout.documents.appendingPathComponent(name))
            try DeterministicBytes(seed: 0xD20F).writeFile(layout.documents.appendingPathComponent(name), length: 750_000)
            message = "Placed \(name) in the drop area"
        } catch {
            message = "could not place a drop-area file: \(error)"
        }
        refresh()
    }

    func remove(_ name: String) {
        do { try importer?.removeFromDropArea(named: name) } catch { message = "\(error)" }
        refresh()
    }

    func openIn(_ url: URL) {
        guard let importer else { return }
        message = "Importing opened file…"
        // Evidence for the open-in probe (Spikes/G03-Intake/scripts/sim-open-in.sh): where the system put the file,
        // as a folder relative to the app container, and the outcome. Never the file name.
        let folder = HarnessModel.containerRelativeFolder(of: url)
        let inboxBefore = layout.map { HarnessModel.entryCount($0.documents.appendingPathComponent("Inbox")) } ?? -1
        Task.detached(priority: .userInitiated) {
            let outcome: String
            do {
                let job = try await importer.importOpenedFile(at: url, route: .openIn)
                outcome = "Opened file staged: \(job.items.count) file(s), state \(job.state.rawValue)"
            } catch {
                outcome = "Open-in not imported: \(error)"
            }
            let inboxAfter = await MainActor.run { self.layout.map { HarnessModel.entryCount($0.documents.appendingPathComponent("Inbox")) } ?? -1 }
            HarnessModel.log.notice("G03-OPENIN folder=\(folder, privacy: .public) inboxEntriesBefore=\(inboxBefore, privacy: .public) inboxEntriesAfter=\(inboxAfter, privacy: .public) outcome=\(outcome, privacy: .public)")
            await MainActor.run { self.message = outcome; self.refresh() }
        }
    }

    nonisolated static let log = Logger(subsystem: "com.jevidon.sylvia.spike.intake", category: "openin")

    /// "Documents/Inbox" for a system open-in copy; the folder path relative to the app's home directory otherwise,
    /// or "outside the app container".
    nonisolated static func containerRelativeFolder(of url: URL) -> String {
        let home = URL(fileURLWithPath: NSHomeDirectory()).standardizedFileURL.resolvingSymlinksInPath().path
        let folder = url.deletingLastPathComponent().standardizedFileURL.resolvingSymlinksInPath().path
        guard PathBytes.equal(folder, home) || PathBytes.hasPrefix(folder, home + "/") else { return "outside the app container" }
        return String(decoding: folder.utf8.dropFirst(home.utf8.count + 1), as: UTF8.self)
    }

    nonisolated static func entryCount(_ directory: URL) -> Int {
        (try? FileManager.default.contentsOfDirectory(atPath: directory.path).count) ?? 0
    }

    /// UI-test helper: a deterministic file of the requested size in the app's temporary directory.
    func prepareShareFile() {
        // Parse the launch argument as a 64-bit string: UserDefaults.integer(forKey:) clamps a string argument to
        // Int32.max, which silently turned a requested 4 GiB share into a 2 GiB one (found in G0.3).
        let bytes = UserDefaults.standard.string(forKey: "G03ShareBytes").flatMap { UInt64($0) } ?? 0
        let size = bytes > 0 ? bytes : 1 << 20
        let ext = UserDefaults.standard.string(forKey: "G03ShareExtension") ?? "epub"
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("G03 Share Test.\(ext)")
        try? FileManager.default.removeItem(at: url)
        do {
            try DeterministicBytes(seed: 0x5AA5).writeFile(url, length: size)
            shareURL = url
        } catch {
            message = "could not create share file: \(error)"
        }
    }
}

struct HarnessView: View {
    @ObservedObject var model: HarnessModel

    var body: some View {
        NavigationStack {
            List {
                Section("Handoff inbox") {
                    Text(model.summary).accessibilityIdentifier("harness.summary")
                    Text(model.lastScan).font(.footnote).accessibilityIdentifier("harness.lastScan")
                    Text(verbatim: model.scanLog.suffix(6).joined(separator: " | "))
                        .font(.caption2).lineLimit(nil).fixedSize(horizontal: false, vertical: true)
                        .accessibilityIdentifier("harness.scanLog")
                    Button("Scan now") { model.scan(reason: "manual") }.accessibilityIdentifier("harness.scan")
                }
                Section("Finder drop area (Documents)") {
                    if model.dropArea.isEmpty { Text("Empty") }
                    ForEach(model.dropArea, id: \.name) { item in
                        VStack(alignment: .leading) {
                            Text(item.name)
                            Text("\(item.byteCount) bytes · \(item.kind.rawValue)").font(.footnote)
                            HStack {
                                if item.kind == .bundle || item.kind == .file {
                                    Button("Import") { model.importDropAreaItem(item.name) }.buttonStyle(.bordered)
                                        .accessibilityIdentifier("harness.import.\(item.name)")
                                }
                                Button("Remove") { model.remove(item.name) }.buttonStyle(.bordered)
                                    .accessibilityIdentifier("harness.remove.\(item.name)")
                            }
                        }
                    }
                    Text(model.message).font(.footnote).accessibilityIdentifier("harness.message")
                }
                Section("Import") {
                    Button("Import from Files") {
                        model.message = ""   // a new outcome is then always a change, even for the same file again
                        model.showingPicker = true
                    }.accessibilityIdentifier("harness.pick")
                    Text(model.pickerDetail).font(.footnote).accessibilityIdentifier("harness.pickerDetail")
                }
                Section("Test") {
                    Button("Share test file") { model.prepareShareFile() }.accessibilityIdentifier("harness.share")
                    Button("Place test file in drop area") { model.placeDropAreaFile() }.accessibilityIdentifier("harness.placeDropFile")
                    Button("Share from a slow provider") { model.prepareSlowShare() }.accessibilityIdentifier("harness.shareSlow")
                    Text(verbatim: model.slowProviderLog.joined(separator: " | "))
                        .font(.caption2).accessibilityIdentifier("harness.slowProvider")
                }
            }
            .navigationTitle("Intake spike")
            .sheet(item: $model.slowShareProvider) { item in
                ProviderActivitySheet(provider: item.provider) { model.slowShareProvider = nil; model.scan(reason: "after share") }
            }
            .sheet(isPresented: $model.showingPicker) {
                DocumentPicker { url in
                    model.showingPicker = false
                    if let url { model.importPicked(url) }
                }
                .ignoresSafeArea()
            }
            .sheet(item: Binding(get: { model.shareURL.map(ShareItem.init) }, set: { if $0 == nil { model.shareURL = nil } })) { item in
                ActivitySheet(url: item.url) { model.shareURL = nil; model.scan(reason: "after share") }
            }
            .refreshable { model.scan(reason: "pull") }
        }
    }
}

struct ShareItem: Identifiable {
    let url: URL
    var id: String { url.path }
}

/// The system document picker, opening supported files in place (`asCopy: false`): the app receives a security-scoped
/// URL to the provider's file, as the product's Files import will (plan 8.1), not a copy the picker made.
struct DocumentPicker: UIViewControllerRepresentable {
    let completion: (URL?) -> Void

    func makeCoordinator() -> Coordinator { Coordinator(completion: completion) }

    func makeUIViewController(context: Context) -> UIDocumentPickerViewController {
        let types: [UTType] = [.epub, .pdf, SupportedContent.markdown, .plainText, .audio]
        let picker = UIDocumentPickerViewController(forOpeningContentTypes: types, asCopy: false)
        picker.allowsMultipleSelection = false
        picker.delegate = context.coordinator
        return picker
    }

    func updateUIViewController(_ controller: UIDocumentPickerViewController, context: Context) {}

    final class Coordinator: NSObject, UIDocumentPickerDelegate {
        let completion: (URL?) -> Void
        init(completion: @escaping (URL?) -> Void) { self.completion = completion }
        func documentPicker(_ controller: UIDocumentPickerViewController, didPickDocumentsAt urls: [URL]) { completion(urls.first) }
        func documentPickerWasCancelled(_ controller: UIDocumentPickerViewController) { completion(nil) }
    }
}

/// One shared item provider for the share sheet.
struct SlowProviderItem: Identifiable {
    let id = UUID()
    let provider: NSItemProvider
}

/// Progress and the provider's completion handler are thread-safe but not marked Sendable.
struct SlowProviderWork: @unchecked Sendable {
    let progress: Progress
    let completion: (URL?, Bool, (any Error)?) -> Void
}

/// Numbers the slow provider's loads (the share sheet may load an item itself) and records what each did.
final class SlowProviderRecorder: @unchecked Sendable {
    private let lock = NSLock()
    private var loads = 0
    private weak var model: HarnessModel?
    init(model: HarnessModel) { self.model = model }
    func beginLoad() -> Int {
        let n = lock.withLock { loads += 1; return loads }
        note("load \(n): started")
        return n
    }
    func note(_ line: String) {
        HarnessModel.log.notice("G03-SLOWPROVIDER \(line, privacy: .public)")
        Task { @MainActor [weak model] in model?.slowProviderLog.append(line) }
    }
}

/// The system share sheet for an item provider (rather than a file URL). The provider is passed as an activity item:
/// on the iOS 26.5 simulator, a sheet built from `UIActivityItemsConfiguration(itemProviders:)` listed the extension
/// but did nothing when it was tapped (the provider was never asked for its file).
struct ProviderActivitySheet: UIViewControllerRepresentable {
    let provider: NSItemProvider
    let completion: () -> Void

    func makeUIViewController(context: Context) -> UIActivityViewController {
        let controller = UIActivityViewController(activityItems: [provider], applicationActivities: nil)
        controller.completionWithItemsHandler = { _, _, _, _ in completion() }
        return controller
    }

    func updateUIViewController(_ controller: UIActivityViewController, context: Context) {}
}

struct ActivitySheet: UIViewControllerRepresentable {
    let url: URL
    let completion: () -> Void

    func makeUIViewController(context: Context) -> UIActivityViewController {
        let controller = UIActivityViewController(activityItems: [url], applicationActivities: nil)
        controller.completionWithItemsHandler = { _, _, _, _ in completion() }
        return controller
    }

    func updateUIViewController(_ controller: UIActivityViewController, context: Context) {}
}
