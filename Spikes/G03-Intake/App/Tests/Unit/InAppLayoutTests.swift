// Runs inside the harness app on the simulator: the real container, the real Info.plist, the real App Group.
import Foundation
import SQLite3
import SylviaContainerLayout
import SylviaImportHandoff
import SylviaIntakeCore
import Testing
import UniformTypeIdentifiers

@Suite("in-app container layout (simulator)")
struct InAppLayoutTests {
    @Test("Documents holds only the drop area; database, notes, knowledge and staging are private; Info.plist keys set")
    func layout() throws {
        let layout = try StorageLayout.current(appGroupIdentifier: "group.com.jevidon.sylvia.spike")
        try #require(layout.appGroup != nil, "App Group container must be available (entitlement applied)")
        try layout.bootstrap()
        let db = try SQLiteFixture.makeWALDatabase(at: layout.database)
        defer { sqlite3_close(db) }
        try Data("note".utf8).write(to: layout.notes.appendingPathComponent("layout-probe.md"))
        try Data("clip".utf8).write(to: layout.retainedKnowledge.appendingPathComponent("layout-probe.m4a"))

        let info = Bundle.main.infoDictionary
        #expect(info?["UIFileSharingEnabled"] as? Bool == true)
        #expect(info?["LSSupportsOpeningDocumentsInPlace"] as? Bool == false)
        let violations = LayoutAudit.audit(layout, infoDictionary: info)
        #expect(violations.isEmpty, "\(violations)")

        let fm = FileManager.default
        for suffix in ["", "-wal", "-shm"] {
            #expect(fm.fileExists(atPath: layout.database.path + suffix), "library.sqlite\(suffix) exists in Application Support")
        }
        let home = URL(fileURLWithPath: NSHomeDirectory()).standardizedFileURL.path
        func relative(_ url: URL) -> String { url.standardizedFileURL.path.replacingOccurrences(of: home, with: "<app>") }
        print("G03-EVIDENCE layout: documents=\(relative(layout.documents)) database=\(relative(layout.database)) notes=\(relative(layout.notes)) staging=\(relative(layout.staging)) handoffInbox=<appgroup>/Intake/Handoffs")
        let documentsContents = (try? fm.subpathsOfDirectory(atPath: layout.documents.path)) ?? []
        print("G03-EVIDENCE layout: Documents contains \(documentsContents.count) item(s): \(documentsContents.sorted())")
        // Data protection (plan 18.1: database, WAL/SHM, staging, manifests; G8). A handoff is written here through the
        // extension's own write routine into the real App Group inbox so its directory, manifest and item are covered;
        // the extension also shows the class of what it wrote (device checklist step 24).
        let probeSource = fm.temporaryDirectory.appendingPathComponent("protection-probe.epub")
        try DeterministicBytes(seed: 22).writeFile(probeSource, length: 4096)
        let inbox = try #require(layout.handoffInbox)
        let environment = HandoffEnvironment(inbox: inbox, producerBundleIdentifier: "in-app protection probe", producerBuildVersion: "1")
        let receipt = try HandoffSession.run(environment: environment, files: [(probeSource, "org.idpf.epub-container")]).get()
        let handoff = inbox.appendingPathComponent(receipt.handoffID.uuidString, isDirectory: true)
        defer { try? fm.removeItem(at: handoff); try? fm.removeItem(at: probeSource) }
        let probes: [(String, URL)] = [
            ("library.sqlite", layout.database),
            ("library.sqlite-wal", URL(fileURLWithPath: layout.database.path + "-wal")),
            ("library.sqlite-shm", URL(fileURLWithPath: layout.database.path + "-shm")),
            ("Staging/", layout.staging), ("Staging/journal.json", layout.journal),
            ("Knowledge/Notes/", layout.notes), ("Media/", layout.media),
            ("<appgroup>/Intake/Handoffs/", inbox), ("handoff directory", handoff),
            ("handoff.json", handoff.appendingPathComponent(HandoffManifest.fileName)),
            ("handoff item", handoff.appendingPathComponent("items/0.epub")),
        ]
        let classes = probes.map { name, url in
            guard fm.fileExists(atPath: url.path) else { return "\(name)=absent" }
            let value = (try? fm.attributesOfItem(atPath: url.path)[.protectionKey] as? FileProtectionType)?.rawValue
            return "\(name)=\(value ?? "none reported")"
        }
        print("G03-EVIDENCE layout: protection attributes (\(ProcessInfo.processInfo.environment["SIMULATOR_UDID"] == nil ? "device" : "simulator")): \(classes.joined(separator: ", "))")
        for url in layout.backupExcludedLocations {
            #expect(VolumeSpace.isExcludedFromBackup(url), "\(url.lastPathComponent) must be excluded from backup")
        }
        #expect(!VolumeSpace.isExcludedFromBackup(layout.databaseDirectory) && !VolumeSpace.isExcludedFromBackup(layout.notes))
        print("G03-EVIDENCE layout: excluded from backup: Staging=\(VolumeSpace.isExcludedFromBackup(layout.staging)) handoffInbox=\(VolumeSpace.isExcludedFromBackup(inbox)); backup-eligible: Database, Knowledge, Media")
    }

    @Test("type resolution inside the app: what the system maps each Markdown extension to, and what intake accepts")
    func markdownTypes() {
        for ext in ["md", "markdown", "mdown"] {
            let system = UTType(filenameExtension: ext)
            print("G03-EVIDENCE types: UTType(filenameExtension: \"\(ext)\") in the harness app = \(system?.identifier ?? "nil"), dynamic=\(system?.isDynamic ?? false)")
            #expect(SupportedContent.supportedType(forFileExtension: ext) == SupportedContent.markdown)
        }
        #expect(SupportedContent.supportedType(forFileExtension: "sylviapack") == nil)
    }

    /// Open-in and drop-area imports keep an APFS clone of the source (DropAreaImporter). clonefile(2) copies the
    /// source's attributes, so a clone may keep the source's data-protection class instead of taking its staging
    /// directory's. This records which class a clone ends up with when the source's class differs (device checklist
    /// step 24; the simulator has no data protection and reports none).
    @Test("protection class of an APFS clone whose source has a different class (evidence only)")
    func cloneProtectionClass() throws {
        let layout = try StorageLayout.current(appGroupIdentifier: "group.com.jevidon.sylvia.spike")
        try layout.bootstrap()
        let fm = FileManager.default
        let root = layout.staging.appendingPathComponent("clone-protection-probe-\(UUID().uuidString)", isDirectory: true)
        defer { try? fm.removeItem(at: root) }
        let sourceDir = root.appendingPathComponent("source", isDirectory: true)
        let targetDir = root.appendingPathComponent("target", isDirectory: true)
        try fm.createDirectory(at: sourceDir, withIntermediateDirectories: true)
        try fm.createDirectory(at: targetDir, withIntermediateDirectories: true)
        #if os(iOS)
        try fm.setAttributes([.protectionKey: FileProtectionType.complete], ofItemAtPath: sourceDir.path)
        try fm.setAttributes([.protectionKey: FileProtectionType.completeUntilFirstUserAuthentication], ofItemAtPath: targetDir.path)
        #endif
        let source = sourceDir.appendingPathComponent("source.epub")
        try DeterministicBytes(seed: 24).writeFile(source, length: 65_536)
        let clone = targetDir.appendingPathComponent("clone.epub")
        let fd = open(source.path, O_RDONLY | O_CLOEXEC)
        try #require(fd >= 0)
        defer { close(fd) }
        let cloned = fclonefileat(fd, AT_FDCWD, clone.path, 0) == 0
        func protection(_ url: URL) -> String {
            ((try? fm.attributesOfItem(atPath: url.path)[.protectionKey] as? FileProtectionType)?.rawValue) ?? "none reported"
        }
        let environment = ProcessInfo.processInfo.environment["SIMULATOR_UDID"] == nil ? "device" : "simulator"
        print("G03-EVIDENCE layout: clone protection (\(environment)): cloned=\(cloned) sourceDir=\(protection(sourceDir)) source=\(protection(source)) targetDir=\(protection(targetDir)) clone=\(cloned ? protection(clone) : "n/a")")
        #expect(cloned, "fclonefileat failed: errno \(errno)")
    }

    @Test("removing everything in Documents (as Finder can) leaves the database untouched")
    func finderDeletion() throws {
        let layout = try StorageLayout.current(appGroupIdentifier: "group.com.jevidon.sylvia.spike")
        try layout.bootstrap()
        let db = try SQLiteFixture.makeWALDatabase(at: layout.database)
        sqlite3_close(db)
        let before = try FileDigest.sha256(of: layout.database)
        try Data("dropped".utf8).write(to: layout.documents.appendingPathComponent("dropped.txt"))
        for name in try FileManager.default.contentsOfDirectory(atPath: layout.documents.path) {
            try FileManager.default.removeItem(at: layout.documents.appendingPathComponent(name))
        }
        #expect(try FileDigest.sha256(of: layout.database) == before)
    }
}
