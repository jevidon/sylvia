import Foundation
import GRDB
import Testing
@testable import SylviaRecovery

/// The phone's second failure (device run of 26 October 2026, runbook step 1.2): the missing-blob-file
/// variant of `RestoreTests.rejections` was rejected, but as an unsafe path instead of a missing file.
/// An iPhone's temporary and container folders are under /private/var/mobile/. The bundle's
/// containment check resolved both paths with Foundation's `resolvingSymlinksInPath`, which drops a
/// leading /private only from a path that exists, so the existing root came out as /var/mobile/... and
/// the missing file as /private/var/mobile/..., and the prefix check failed before the missing-file
/// check ran. The Mac's temporary folder is /var/folders/... (a link to /private/var/folders/...), which
/// hides it; the same folder named through /private shows it on the Mac.
@Suite("Bundle paths under /private (device run of 26 October 2026)")
struct PrivatePathTests {
    /// The forms of a folder these tests use: as given, and through /private when it is under /var (the
    /// Mac's temporary folder). An iPhone's folders are already under /private/var, the phone's case
    /// itself; the simulator's are in the Mac's home folder, which has no /private form.
    static func forms(_ url: URL) -> [(label: String, url: URL)] {
        let path = url.path
        if path.hasPrefix("/var/") {
            return [("under /var, as the Mac names its temporary folder", url),
                    ("through /private, as an iPhone's folders are named", URL(fileURLWithPath: "/private" + path, isDirectory: true))]
        }
        return [(path.hasPrefix("/private/var/") ? "under /private/var, as on an iPhone" : "as given (no /private form)", url)]
    }

    @Test("a listed file missing from a bundle under /private/var is rejected as missing, not as an unsafe path")
    func missingFileUnderPrivateVar() throws {
        let scratch = try Scratch()
        let (source, _) = try corpusLibrary(scratch, "Source")
        let bundle = scratch.dir("Exports/b.sylviabackup")
        try FileManager.default.createDirectory(at: bundle.deletingLastPathComponent(), withIntermediateDirectories: true)
        _ = try BackupExporter(source).export(to: bundle)
        try source.close()
        let forms = Self.forms(bundle)

        // The good bundle validates through every form: its files exist, so their prefixes agreed.
        for form in forms {
            do { _ = try BackupValidator.validate(form.url) } catch { Issue.record("\(form.label): the good bundle was rejected: \(error)") }
        }
        // Paths that do not exist (a missing file, and one in a missing directory) resolve inside the root.
        let missing = ["blobs/excerpts/\(String(repeating: "0", count: 64)).mp3", "blobs/missing/x.mp3", "export/markdown/missing.md"]
        for form in forms {
            for path in missing {
                do { _ = try BackupValidator.resolve(path, in: form.url) } catch { Issue.record("\(form.label): \(path): \(error)") }
            }
        }

        // The phone's case: the excerpt blobs removed while the manifest still lists them.
        let blobs = bundle.appending(path: "blobs/excerpts", directoryHint: .isDirectory)
        let removed = try FileManager.default.contentsOfDirectory(atPath: blobs.path)
        #expect(!removed.isEmpty)
        for name in removed { try FileManager.default.removeItem(at: blobs.appending(path: name)) }
        var outcomes: [String] = []
        for form in forms {
            let restorer = BackupRestorer(layout: scratch.layout("Active"))
            var thrown: (any Error)?
            do { _ = try restorer.prepare(bundle: form.url) } catch { thrown = error }
            var missingFile = false
            if case .missingFile? = thrown as? BackupError { missingFile = true }
            #expect(missingFile, "\(form.label): expected missingFile, got \(thrown.map { String(describing: $0) } ?? "no error")")
            outcomes.append("\(form.label): \(thrown.map { String(describing: $0) } ?? "no error")")
        }
        evidence("missing listed file, bundle \(outcomes.joined(separator: "; "))")
    }

    /// The containment check is no weaker than before: links in the path are resolved whether or not
    /// the leaf exists (before the fix a missing leaf left the whole path unresolved, so a link above
    /// it was not followed), and `resolve` refuses every path the manifest stage refuses, itself.
    @Test("the containment check follows links whether or not the leaf exists, and resolve refuses unsafe paths itself")
    func containmentFollowsLinks() throws {
        let scratch = try Scratch()
        let fm = FileManager.default
        let root = scratch.dir("Bundle")
        try fm.createDirectory(at: root.appending(path: "export/markdown", directoryHint: .isDirectory), withIntermediateDirectories: true)
        try Data("x".utf8).write(to: root.appending(path: "export/markdown/a.md"))
        let outside = scratch.dir("Outside")
        try fm.createDirectory(at: outside, withIntermediateDirectories: true)
        try Data("y".utf8).write(to: outside.appending(path: "b.md"))
        try fm.createSymbolicLink(at: root.appending(path: "export/escape", directoryHint: .notDirectory), withDestinationURL: outside)

        for form in Self.forms(root) {
            let base = form.url
            for (path, inside) in [("export/markdown/a.md", true), ("export/markdown/missing.md", true), ("blobs/missing/x.mp3", true),
                                   ("export/escape/b.md", false), ("export/escape/missing.md", false)] {
                #expect(BackupValidator.isInside(base.appending(path: path), base) == inside, "\(form.label): \(path)")
            }
            #expect(!BackupValidator.isInside(outside.appending(path: "b.md"), base), "\(form.label): a file outside")
            #expect(BackupValidator.isInside(base, base) == false, "\(form.label): the root itself is not inside itself")
            // A link in the path is refused before the containment check, as before.
            #expect(throws: BackupError.symlinkInBundle("export/escape/missing.md")) { try BackupValidator.resolve("export/escape/missing.md", in: base) }
            // The manifest stage's path rules, now also refused by resolve itself.
            for path in ["../outside.txt", "/etc/passwd", "blobs/excerpts/../../../x", "blobs\\excerpts\\x", ".hidden/x",
                         "export/markdown/caf\u{e9}.md", "export//x.md", "export/./x.md", ""] {
                #expect(throws: BackupError.unsafePath(path), "\(form.label): \(path)") { try BackupValidator.resolve(path, in: base) }
            }
            // The same folder named both ways resolves to one form (realpath: /private/var/...).
            #expect(CanonicalPath.of(base) == CanonicalPath.of(root), "\(form.label)")
            // `.` or `..` below a folder that does not exist cannot be placed (review of 26 October 2026, fix-1).
            #expect(CanonicalPath.of(base.appending(path: "missing/../export/markdown/a.md")) == nil, "\(form.label)")
        }
        // Paths are compared byte by byte: a name that begins with a combining mark is still below its folder,
        // though Swift's `String.hasPrefix` joins it to the `/` before it.
        #expect(CanonicalPath.relative("/r/b/\u{301}x", to: "/r/b") == "\u{301}x")
        #expect(CanonicalPath.relative("/r/b", to: "/r/b") == nil && CanonicalPath.relative("/r/bc/x", to: "/r/b") == nil)
        evidence("containment check (realpath of the deepest existing part): \(Self.forms(root).map(\.label).joined(separator: " and ")): a missing leaf is inside; a missing leaf below a link to outside the root is outside; resolve refuses links and the manifest's unsafe paths")
    }
}
