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

    /// Each refusal is checked by its reason, not only by its type, and in every form of the test's folder
    /// (`PrivatePathTests.forms`): on the Mac also through /private, as an iPhone names its folders. There the
    /// inside check used to compare Foundation's `standardizedFileURL` of the existing source (/var/…) with that of
    /// the destination, which did not exist yet and kept /private, so it missed it: the copy went on into itself
    /// until a name was too long and failed with a Cocoa error (review of 26 October 2026, finding F1; fix-1).
    @Test("FileProtector.copyTree refuses a link, an existing destination, a destination inside the source and an unsupported class, and leaves no partial copy")
    func copyTreeRefusals() throws {
        let scratch = try Scratch()
        let fm = FileManager.default
        var insideRefusals: [String] = []
        for (index, form) in PrivatePathTests.forms(scratch.url).enumerated() {
            let base = form.url.appending(path: "form-\(index + 1)", directoryHint: .isDirectory)
            let source = base.appending(path: "Template", directoryHint: .isDirectory)
            try FileProtector.library.ensureDirectory(source.appending(path: "Library", directoryHint: .isDirectory))
            try FileProtector.library.write(Data("db".utf8), to: source.appending(path: "Library/library.sqlite"))
            let sourceTree = try Set(fm.subpathsOfDirectory(atPath: source.path))

            let existing = base.appending(path: "Existing", directoryHint: .isDirectory)
            try fm.createDirectory(at: existing, withIntermediateDirectories: true)
            Self.expectRefusal("\(form.label): an existing destination", saying: "already exists") {
                try FileProtector.library.copyTree(from: source, to: existing)
            }
            #expect(try fm.contentsOfDirectory(atPath: existing.path).isEmpty, "\(form.label): the existing destination was changed")

            let inside = source.appending(path: "Library/Copy", directoryHint: .isDirectory)
            let insideRefusal = Self.expectRefusal("\(form.label): a destination inside the source", saying: "is inside") {
                try FileProtector.library.copyTree(from: source, to: inside)
            }
            insideRefusals.append("\(form.label): \(insideRefusal)")
            #expect(!fm.fileExists(atPath: inside.path), "\(form.label): a copy was left inside the source")
            #expect(try Set(fm.subpathsOfDirectory(atPath: source.path)) == sourceTree, "\(form.label): the source tree changed")

            // Through a link to the source's folder, and named with `..` below a folder that does not exist (its
            // meaning depends on what a copy would create, so the check cannot place it and refuses it).
            let linkToBase = base.appending(path: "link-to-base", directoryHint: .notDirectory)
            try fm.createSymbolicLink(at: linkToBase, withDestinationURL: base)
            Self.expectRefusal("\(form.label): a destination inside the source, named through a link", saying: "is inside") {
                try FileProtector.library.copyTree(from: source, to: linkToBase.appending(path: "Template/Library/Copy", directoryHint: .isDirectory))
            }
            Self.expectRefusal("\(form.label): a destination named with .. below a missing folder", saying: "cannot be resolved") {
                try FileProtector.library.copyTree(from: source, to: base.appending(path: "Missing/../Template/Library/Copy", directoryHint: .isDirectory))
            }
            #expect(!fm.fileExists(atPath: inside.path) && !fm.fileExists(atPath: base.appending(path: "Missing").path),
                    "\(form.label): a refused copy left something behind")
            #expect(try Set(fm.subpathsOfDirectory(atPath: source.path)) == sourceTree, "\(form.label): the source tree changed")

            let linkToSource = base.appending(path: "link-to-template", directoryHint: .notDirectory)
            try fm.createSymbolicLink(at: linkToSource, withDestinationURL: source)
            let fromLink = base.appending(path: "FromLink", directoryHint: .isDirectory)
            Self.expectRefusal("\(form.label): a link as the source", saying: "is not a directory") {
                try FileProtector.library.copyTree(from: linkToSource, to: fromLink)
            }
            #expect(!fm.fileExists(atPath: fromLink.path), "\(form.label): a copy from the link was left")

            let unsupported = FileProtectionType(rawValue: "NSFileProtectionCompleteWhenUserInactive")
            let unsupportedCopy = base.appending(path: "Unsupported", directoryHint: .isDirectory)
            #expect(throws: ProtectionError.unsupportedClass(unsupported.rawValue), "\(form.label)") {
                try FileProtector(protection: unsupported).copyTree(from: source, to: unsupportedCopy)
            }
            #expect(!fm.fileExists(atPath: unsupportedCopy.path), "\(form.label): a copy with an unsupported class was left")

            // A link anywhere in the tree fails the copy after part of it was made; nothing of it is left.
            let outside = base.appending(path: "outside.txt", directoryHint: .notDirectory)
            try Data("outside".utf8).write(to: outside)
            try fm.createSymbolicLink(at: source.appending(path: "Library/link.sqlite", directoryHint: .notDirectory), withDestinationURL: outside)
            let copy = base.appending(path: "Install", directoryHint: .isDirectory)
            Self.expectRefusal("\(form.label): a link in the tree", saying: "is not a regular file or a directory") {
                try FileProtector.library.copyTree(from: source, to: copy)
            }
            #expect(!fm.fileExists(atPath: copy.path), "\(form.label): a partial copy was left")
        }
        evidence("copyTree, a destination inside the source: \(insideRefusals.joined(separator: "; "))")
    }

    /// Expects `copy` to throw the `FileSystemError` of a refusal whose text contains `reason`, and returns what it
    /// threw (or "not refused"), so that a refusal for another reason, or another kind of error, fails the test.
    @discardableResult
    static func expectRefusal(_ what: String, saying reason: String, sourceLocation: SourceLocation = #_sourceLocation,
                              _ copy: () throws -> Void) -> String {
        do {
            try copy()
            Issue.record("\(what): not refused", sourceLocation: sourceLocation)
            return "not refused"
        } catch let error as FileSystemError {
            let text = String(describing: error)
            #expect(text.contains(reason), "\(what): expected a refusal saying \"\(reason)\", got \(text)", sourceLocation: sourceLocation)
            return text
        } catch {
            Issue.record("\(what): expected a FileSystemError saying \"\(reason)\", got \(error)", sourceLocation: sourceLocation)
            return "\(error)"
        }
    }

    #if os(macOS)
    /// This package's directory, from this file's path at build time.
    static let packageRoot = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
        .deletingLastPathComponent()

    /// Calls that copy or link a file and keep the source's class, as code spells them: FileManager's
    /// `copyItem` and `linkItem` (Swift, and the Objective-C `copyItemAtURL:`, `copyItemAtPath:`,
    /// `linkItemAtURL:` and `linkItemAtPath:`), and the C calls beneath or beside them: clonefile(2)
    /// and its variants, copyfile(3) and fcopyfile(3), and link(2) and linkat(2), whose hard link is the
    /// source file itself. The links and the Objective-C forms were added after the security review of
    /// 26 October 2026 (finding S4). Built from parts so that this file does not match. An ICU pattern
    /// (`NSRegularExpression`), whose `\b` falls between `\w` and `\W`, so it matches after a dot;
    /// Swift's `Regex` uses Unicode word boundaries, where `default.copyItem` is one word (a first
    /// version of this test found nothing that way). `\s` matches a line break too, so a call split
    /// across lines is found.
    static let keepingCallNames: [String] = ["copy" + "Item", "link" + "Item", "clone" + "file", "clone" + "fileat",
                                             "fclone" + "fileat", "copy" + "file", "fcopy" + "file", "lin" + "k", "lin" + "kat"]
    static let keepingSelectorNames: [String] = ["copy" + "Item", "link" + "Item"]
    static let keepingCallPattern: String = "\\b(?:(?:" + keepingCallNames.joined(separator: "|") + ")\\s*\\(|(?:"
        + keepingSelectorNames.joined(separator: "|") + ")At(?:URL|Path)\\s*:)"

    /// A source file's code: each line without its `//` comment, joined again by line breaks, so that a
    /// hit's line number is the line's. A `//` inside a string literal ("file://…") starts no comment:
    /// cutting every line at its first `//` hid a call written after such a literal (security review of
    /// 26 October 2026, finding S4). Block comments stay in as text: they can add a hit, never hide one.
    static func code(of source: String) -> String {
        source.split(omittingEmptySubsequences: false, whereSeparator: \.isNewline).map { line -> String in
            var kept = ""
            var inString = false
            var escaped = false
            var previous: Character?
            for character in line {
                if inString {
                    if escaped { escaped = false } else if character == "\\" { escaped = true } else if character == "\"" { inString = false }
                } else if character == "\"" {
                    inString = true
                } else if character == "/" && previous == "/" {
                    kept.removeLast()
                    return kept
                }
                kept.append(character)
                previous = inString ? nil : character
            }
            return kept
        }.joined(separator: "\n")
    }

    /// The guard against the device run's failure coming back: no code in the recovery spike (the
    /// package, the device host, the lock harness) copies or links a file in a way that keeps the
    /// source's class; copies go through `FileProtector.copyFile` and `FileProtector.copyTree`. A test,
    /// not a check in the CI drop-in, so that it also runs in every `swift test`; it reads the sources
    /// from the checkout, so it is built for the Mac only. What it reads: the Swift, C and Objective-C
    /// files (.swift, .c, .h, .m, .mm) of Sources, Tests, DeviceTests and LockHarness, without their `//`
    /// comments (`code(of:)`). It is a text check: a call made another way, such as through a selector
    /// built at run time or a function value, is not found.
    @Test("no code in the recovery spike copies or links a file in a way that keeps the source's class (FileManager.copyItem or linkItem, clonefile, copyfile, link)")
    func noCopyKeepsTheSourceClass() throws {
        let fm = FileManager.default
        let keepingCalls = try NSRegularExpression(pattern: Self.keepingCallPattern)
        func hits(in code: String) -> [NSTextCheckingResult] { keepingCalls.matches(in: code, range: NSRange(code.startIndex..., in: code)) }
        func matches(_ source: String) -> Bool { !hits(in: Self.code(of: source)).isEmpty }
        // The pattern and the comment handling: each call is found as code writes it, and neither FileProtector's
        // copies nor a call in a comment is. The samples from the URL string on came with finding S4.
        let samples: [(String, Bool)] = [
            ("try FileManager.default." + "copy" + "Item(at: a, to: b)", true),
            ("try fm." + "copy" + "Item(atPath: a, toPath: b)", true),
            ("guard " + "clone" + "file(a, b, 0) == 0", true),
            ("_ = " + "copy" + "file(a, b, nil, flags)", true),
            ("let u = URL(string: \"file:/" + "/x\")!; try fm." + "copy" + "Item(at: a, to: b)", true),
            ("try fm." + "link" + "Item(at: a, to: b)", true),
            ("guard " + "lin" + "k(a, b) == 0", true),
            ("[fm " + "copy" + "ItemAtURL:a toURL:b error:&error];", true),
            ("[fm " + "link" + "ItemAtPath:a toPath:b error:nil];", true),
            ("return " + "copy" + "file\n    (a, b, NULL, COPYFILE_ALL);", true),
            ("try protector.copyFile(from: a, to: b)", false),
            ("try FileProtector.library.copyTree(from: a, to: b)", false),
            ("try fm.createSymbolicLink(at: a, withDestinationURL: b); un" + "lin" + "k(c); sym" + "lin" + "k(d, e)", false),
            ("let s = \"a\" /" + "/ try fm." + "copy" + "Item(at: a, to: b)", false),
            ("    /" + "// try fm." + "copy" + "Item(at: a, to: b)", false),
        ]
        for (sample, keeps) in samples {
            #expect(matches(sample) == keeps, "pattern \(keeps ? "missed" : "matched") \(sample)")
        }
        var scanned = 0
        var found: [String] = []
        for directory in ["Sources", "Tests", "DeviceTests", "LockHarness"] {
            let base = Self.packageRoot.appending(path: directory, directoryHint: .isDirectory)
            #expect(fm.fileExists(atPath: base.path), "\(directory) not found under \(Self.packageRoot.path)")
            guard let walk = fm.enumerator(at: base, includingPropertiesForKeys: [.isRegularFileKey], options: [.skipsHiddenFiles]) else { continue }
            for case let url as URL in walk {
                if url.pathExtension == "xcodeproj" { walk.skipDescendants(); continue }
                guard ["swift", "c", "h", "m", "mm"].contains(url.pathExtension) else { continue }
                scanned += 1
                let relative = String(url.standardizedFileURL.path.dropFirst(Self.packageRoot.standardizedFileURL.path.count + 1))
                let source = try String(contentsOf: url, encoding: .utf8)
                let lines = source.split(omittingEmptySubsequences: false, whereSeparator: \.isNewline)
                let code = Self.code(of: source)
                for hit in hits(in: code) {
                    let line = (code as NSString).substring(to: hit.range.location).components(separatedBy: "\n").count
                    found.append("\(relative):\(line): \(lines[line - 1].trimmingCharacters(in: .whitespaces))")
                }
            }
        }
        #expect(scanned > 40, "only \(scanned) source files found under \(Self.packageRoot.path)")
        #expect(found.isEmpty, "copies that keep the source's class:\n\(found.joined(separator: "\n"))")
        evidence("copy guard: \(scanned) source files in Sources, Tests, DeviceTests and LockHarness; calls that keep the source's class: \(found.count)")
    }
    #endif
}
