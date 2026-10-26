import Foundation
import GRDB
import Testing
@testable import SylviaRecovery

/// Files put where the recovery code expects the library's class are created with it (plan 18.1,
/// T50). The first app-hosted device run (26 October 2026, runbook step 1.2; G0.5 recovery checklist
/// step 1) failed every migration and put-back test because their v1 fixture was copied out of the
/// app bundle with `FileManager.copyItem`, which keeps the source file's class: the copy had no
/// protection class (the class, it follows, of the fixture in the app bundle), and the open refused it.
/// The host and the simulator did not show it: on the Mac the copy reads back class C, the platform
/// default (the suite passes there), and the simulator reports class C for every file.
@Suite("Copies into a library carry the library's class (device run of 26 October 2026)")
struct ProtectedCopyTests {
    /// The phone's failure on the Mac. macOS does not support "no protection" (a request for it reads
    /// back class C, `DataProtectionTests.mismatchDetected`), so a class-B source stands in for the
    /// bundle's file: a copy that keeps its source's class comes out class B, not C.
    @Test("a v1 library installed from a source of another class is created with the library's class C and opens",
          .enabled(if: FileProtector.platformReportsProtection, "the iOS Simulator reports class C for every file whatever was requested, so a source of another class cannot be made there"),
          .enabled(if: DataProtectionTests.classKeysAvailable, "class A/B keys are unavailable (host screen locked): a class-B source cannot be read now"))
    func v1LibraryFromAnotherClass() throws {
        let scratch = try Scratch()
        let classB = FileProtector(protection: .completeUnlessOpen)
        let sourceDirectory = scratch.dir("ClassBSource")
        try classB.ensureDirectory(sourceDirectory)
        let source = sourceDirectory.appending(path: "library-v1.sqlite", directoryHint: .notDirectory)
        try classB.copyFile(from: MigrationTests.fixture, to: source)
        #expect(try FileProtector.library.protectionClass(of: source) == .completeUnlessOpen)

        let layout = try MigrationTests().installV1(scratch, from: source)
        let installed = try FileProtector.library.protectionClass(of: layout.databaseURL)
        #expect(installed == .completeUntilFirstUserAuthentication, "library.sqlite was created with \(installed?.rawValue ?? "none reported")")
        var outcome = "opened and migrated"
        do {
            let store = try LibraryStore.open(layout)
            defer { try? store.close() }
            #expect(store.openReport.appliedNow == LibrarySchema.migrations.map(\.identifier))
        } catch {
            // What the phone saw. The class read again after the failed open, through a new URL, shows
            // whether the open's `protect` had changed it although its check reported the old one.
            let after = (try? FileProtector.library.protectionClass(of: layout.databaseURL))?.rawValue ?? "none reported"
            outcome = "refused: \(error); library.sqlite read again after the refused open: \(after)"
            Issue.record("the open refused the library: \(outcome)")
        }
        evidence("v1 library installed from a class-B source: library.sqlite \(installed?.rawValue ?? "none reported") when created; \(outcome)")
    }

    /// The crash drills' template copy (`FileProtector.copyTree`): a tree of another class (B) comes out
    /// with the protector's class on every file and directory, and the same bytes.
    @Test("a tree copied with FileProtector.copyTree carries the protector's class C on every file and directory, whatever the source's",
          .enabled(if: FileProtector.platformReportsProtection, "the iOS Simulator reports class C for every file whatever was requested, so a source of another class cannot be made there"),
          .enabled(if: DataProtectionTests.classKeysAvailable, "class A/B keys are unavailable (host screen locked): a class-B source cannot be read now"))
    func copyTreeGivesTheClass() throws {
        let scratch = try Scratch()
        let classB = FileProtector(protection: .completeUnlessOpen)
        let source = scratch.dir("TemplateB")
        for directory in ["Library/Blobs/excerpts", "Recovery"] {
            try classB.ensureDirectory(source.appending(path: directory, directoryHint: .isDirectory))
        }
        // A file larger than copyFile's 1 MiB chunk, a hidden file, and an empty directory (Recovery/).
        let files = ["installation.json": Data("{}".utf8), "Library/library.sqlite": DeterministicBytes.make(seed: 7, count: (3 << 20) + 5),
                     "Library/Blobs/excerpts/a.mp3": DeterministicBytes.make(seed: 8, count: 4096), "Library/.hidden": Data("h".utf8)]
        for (path, data) in files { try classB.write(data, to: source.appending(path: path, directoryHint: .notDirectory)) }
        #expect(try FileProtector.library.protectionClass(of: source.appending(path: "Library/library.sqlite")) == .completeUnlessOpen)

        let copy = scratch.dir("Install")
        try FileProtector.library.copyTree(from: source, to: copy)
        var seen: [String: Int] = [:]
        for path in try [""] + FileManager.default.subpathsOfDirectory(atPath: copy.path) {
            let value = try FileProtector.library.protectionClass(of: path.isEmpty ? copy : copy.appending(path: path))?.rawValue ?? "none reported"
            seen[value, default: 0] += 1
            #expect(value == FileProtectionType.completeUntilFirstUserAuthentication.rawValue, "\(path.isEmpty ? "the copy itself" : path): \(value)")
        }
        #expect(try Set(FileManager.default.subpathsOfDirectory(atPath: copy.path)) == Set(FileManager.default.subpathsOfDirectory(atPath: source.path)))
        #expect(try treeFingerprint(copy) == treeFingerprint(source))
        evidence("class-B tree (\(files.count) files, 5 directories) copied with FileProtector.copyTree: \(seen)")
    }

    @Test("FileProtector.copyTree refuses a link, an existing destination, a destination inside the source and an unsupported class, and leaves no partial copy")
    func copyTreeRefusals() throws {
        let scratch = try Scratch()
        let fm = FileManager.default
        let source = scratch.dir("Template")
        try FileProtector.library.ensureDirectory(source.appending(path: "Library", directoryHint: .isDirectory))
        try FileProtector.library.write(Data("db".utf8), to: source.appending(path: "Library/library.sqlite"))

        let existing = scratch.dir("Existing")
        try fm.createDirectory(at: existing, withIntermediateDirectories: true)
        #expect(throws: FileSystemError.self) { try FileProtector.library.copyTree(from: source, to: existing) }
        #expect(try fm.contentsOfDirectory(atPath: existing.path).isEmpty, "the existing destination was changed")

        let inside = source.appending(path: "Library/Copy", directoryHint: .isDirectory)
        #expect(throws: FileSystemError.self) { try FileProtector.library.copyTree(from: source, to: inside) }
        #expect(!fm.fileExists(atPath: inside.path))

        let linkToSource = scratch.url.appending(path: "link-to-template", directoryHint: .notDirectory)
        try fm.createSymbolicLink(at: linkToSource, withDestinationURL: source)
        #expect(throws: FileSystemError.self) { try FileProtector.library.copyTree(from: linkToSource, to: scratch.dir("FromLink")) }
        #expect(!fm.fileExists(atPath: scratch.dir("FromLink").path))

        let unsupported = FileProtectionType(rawValue: "NSFileProtectionCompleteWhenUserInactive")
        #expect(throws: ProtectionError.unsupportedClass(unsupported.rawValue)) {
            try FileProtector(protection: unsupported).copyTree(from: source, to: scratch.dir("Unsupported"))
        }
        #expect(!fm.fileExists(atPath: scratch.dir("Unsupported").path))

        // A link anywhere in the tree fails the copy after part of it was made; nothing of it is left.
        let outside = scratch.url.appending(path: "outside.txt", directoryHint: .notDirectory)
        try Data("outside".utf8).write(to: outside)
        try fm.createSymbolicLink(at: source.appending(path: "Library/link.sqlite", directoryHint: .notDirectory), withDestinationURL: outside)
        let copy = scratch.dir("Install")
        #expect(throws: FileSystemError.self) { try FileProtector.library.copyTree(from: source, to: copy) }
        #expect(!fm.fileExists(atPath: copy.path), "a partial copy was left")
    }

    #if os(macOS)
    /// This package's directory, from this file's path at build time.
    static let packageRoot = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
        .deletingLastPathComponent()

    /// Calls that copy a file and keep the source's class: `FileManager.copyItem` (both forms), and
    /// the clone and copyfile(3) calls beneath it. Built from parts so that this file does not match.
    /// An ICU pattern (`NSRegularExpression`), whose `\b` falls between `\w` and `\W`, so it matches
    /// after a dot; Swift's `Regex` uses Unicode word boundaries, where `default.copyItem` is one word
    /// (a first version of this test found nothing that way).
    static let keepingCallPattern = "\\b(" + ["copy" + "Item", "clone" + "file", "clone" + "fileat", "fclone" + "fileat",
                                              "copy" + "file", "fcopy" + "file"].joined(separator: "|") + ")\\s*\\("

    /// The guard against the device run's failure coming back: no code in the recovery spike (the
    /// package, the device host, the lock harness) copies a file in a way that keeps the source's
    /// class; copies go through `FileProtector.copyFile` and `FileProtector.copyTree`. A test, not a
    /// check in the CI drop-in, so that it also runs in every `swift test`; it reads the sources from
    /// the checkout, so it is built for the Mac only. Whole-line comments, and the rest of a line after
    /// `//`, are not code.
    @Test("no code in the recovery spike copies a file with FileManager.copyItem, clonefile or copyfile, which keep the source's class")
    func noCopyKeepsTheSourceClass() throws {
        let fm = FileManager.default
        let keepingCalls = try NSRegularExpression(pattern: Self.keepingCallPattern)
        func matches(_ text: String) -> Bool { keepingCalls.firstMatch(in: text, range: NSRange(text.startIndex..., in: text)) != nil }
        // The pattern itself: it finds each call as code writes it, and not FileProtector's copies.
        for (sample, keeps) in [("try FileManager.default." + "copy" + "Item(at: a, to: b)", true),
                                ("try fm." + "copy" + "Item(atPath: a, toPath: b)", true),
                                ("guard " + "clone" + "file(a, b, 0) == 0", true),
                                ("_ = " + "copy" + "file(a, b, nil, flags)", true),
                                ("try protector.copyFile(from: a, to: b)", false),
                                ("try FileProtector.library.copyTree(from: a, to: b)", false)] {
            #expect(matches(sample) == keeps, "pattern \(keeps ? "missed" : "matched") \(sample)")
        }
        var scanned = 0
        var hits: [String] = []
        for directory in ["Sources", "Tests", "DeviceTests", "LockHarness"] {
            let base = Self.packageRoot.appending(path: directory, directoryHint: .isDirectory)
            #expect(fm.fileExists(atPath: base.path), "\(directory) not found under \(Self.packageRoot.path)")
            guard let walk = fm.enumerator(at: base, includingPropertiesForKeys: [.isRegularFileKey], options: [.skipsHiddenFiles]) else { continue }
            for case let url as URL in walk {
                if url.pathExtension == "xcodeproj" { walk.skipDescendants(); continue }
                guard ["swift", "c", "h", "m"].contains(url.pathExtension) else { continue }
                scanned += 1
                let relative = String(url.standardizedFileURL.path.dropFirst(Self.packageRoot.standardizedFileURL.path.count + 1))
                for (index, line) in try String(contentsOf: url, encoding: .utf8).split(separator: "\n", omittingEmptySubsequences: false).enumerated() {
                    let text = line.trimmingCharacters(in: .whitespaces)
                    if text.hasPrefix("//") { continue }
                    let code = text.components(separatedBy: "//")[0]
                    if matches(code) { hits.append("\(relative):\(index + 1): \(text)") }
                }
            }
        }
        #expect(scanned > 40, "only \(scanned) source files found under \(Self.packageRoot.path)")
        #expect(hits.isEmpty, "copies that keep the source's class:\n\(hits.joined(separator: "\n"))")
        evidence("copy guard: \(scanned) source files in Sources, Tests, DeviceTests and LockHarness; calls that keep the source's class: \(hits.count)")
    }
    #endif
}
