// G0.3 intake harness app. Stage 0 harness chrome (plain SwiftUI, literal strings); never shipped.
//
// - Scans the App Group handoff inbox on launch and on every foreground (InboxScanner).
// - Lists the Finder drop area (Documents) and imports a .sylviapack only when the user taps Import.
// - Accepts open-in / AirDrop files through the same journal (DropAreaImporter.importOpenedFile: a .sylviapack goes
//   through the bundle importer, anything else through the single-file importer; the Documents/Inbox copy is removed
//   whatever the outcome).
// - For UI tests: "Share test file" writes a file of the size in the -G03ShareBytes launch argument and presents
//   the system share sheet so a test can pick the Sylvia Intake extension.
import os
import SwiftUI
import SylviaContainerLayout
import SylviaImportHandoff
import SylviaIntakeCore
import SylviaPack
import UIKit

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

    func importBundle(_ name: String) {
        guard let importer else { return }
        message = "Verifying \(name)…"
        Task.detached(priority: .userInitiated) {
            let outcome: String
            do {
                let job = try await importer.importBundle(named: name)
                outcome = "Imported \(name): \(job.items.count) files, state \(job.state.rawValue)"
            } catch {
                outcome = "Not imported: \(error)"
            }
            await MainActor.run { self.message = outcome; self.refresh() }
        }
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
        guard folder == home || folder.hasPrefix(home + "/") else { return "outside the app container" }
        return String(folder.dropFirst(home.count + 1))
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
                                if item.kind == .bundle || (item.kind == .file && item.name.hasPrefix("Inbox/")) {
                                    Button("Import") { model.importBundle(item.name) }.buttonStyle(.bordered)
                                }
                                Button("Remove") { model.remove(item.name) }.buttonStyle(.bordered)
                            }
                        }
                    }
                    Text(model.message).font(.footnote).accessibilityIdentifier("harness.message")
                }
                Section("Test") {
                    Button("Share test file") { model.prepareShareFile() }.accessibilityIdentifier("harness.share")
                }
            }
            .navigationTitle("Intake spike")
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
