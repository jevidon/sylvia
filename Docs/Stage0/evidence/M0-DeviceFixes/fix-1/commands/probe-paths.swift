// fix-1: how Foundation names paths under /private/var, for the review findings F1 and F3 of 26 October 2026. Independent
// of the recovery package: it makes its own folders in the user's temporary folder (as the tests' Scratch does), names
// them under /var and through /private, prints what each check of the unfixed code compared, and removes them.
//   xcrun swift Docs/Stage0/evidence/M0-DeviceFixes/fix-1/commands/probe-paths.swift
import Foundation

let fm = FileManager.default
let base = fm.temporaryDirectory.appending(path: "g05-fix1-probe-\(UUID().uuidString.prefix(8))", directoryHint: .isDirectory)
try fm.createDirectory(at: base.appending(path: "Template/Library", directoryHint: .isDirectory), withIntermediateDirectories: true)
defer { try? fm.removeItem(at: base) }
print("temporaryDirectory: \(fm.temporaryDirectory.path)")

func realPath(_ path: String) -> String? {
    guard let resolved = realpath(path, nil) else { return nil }
    defer { free(resolved) }
    return String(cString: resolved)
}
func naming(_ url: URL) -> String { url.path.hasPrefix("/private/") ? "through /private" : "under /var" }

print("== F1: copyTree's inside check before fix-1 (standardizedFileURL of an existing source and a missing destination)")
for form in [base, URL(fileURLWithPath: "/private" + base.path, isDirectory: true)] {
    let source = form.appending(path: "Template", directoryHint: .isDirectory)
    let destination = source.appending(path: "Library/Copy", directoryHint: .isDirectory)
    let s = source.standardizedFileURL.path, d = destination.standardizedFileURL.path
    print("folder named \(naming(form)):")
    print("  source, standardized:      \(s)")
    print("  destination, standardized: \(d)")
    print("  the check sees the destination inside the source: \(d == s || d.hasPrefix(s + "/"))")
    print("  realpath(3) of the source: \(realPath(source.path) ?? "nil")")
}

print("== F3: the bundle walk before fix-1 (enumerator URLs and standardizedFileURL, with a dangling link)")
let bundle = base.appending(path: "Bundle", directoryHint: .isDirectory)
try fm.createDirectory(at: bundle.appending(path: "export/markdown", directoryHint: .isDirectory), withIntermediateDirectories: true)
try Data("x".utf8).write(to: bundle.appending(path: "export/markdown/a.md"))
try fm.createSymbolicLink(atPath: bundle.appending(path: "export/markdown/dangling.md").path,
                          withDestinationPath: base.appending(path: "nowhere.md").path)
for form in [bundle, URL(fileURLWithPath: "/private" + bundle.path, isDirectory: true)] {
    let rootPath = form.standardizedFileURL.path
    print("bundle named \(naming(form)); root, standardized: \(rootPath)")
    guard let walk = fm.enumerator(at: form, includingPropertiesForKeys: [.isSymbolicLinkKey], options: []) else { continue }
    for case let url as URL in walk {
        let full = url.standardizedFileURL.path
        print("  enumerated \(url.path)\n    standardized \(full)\n    under the root: \(full.hasPrefix(rootPath + "/"))")
    }
}

print("== Why fix-1's CanonicalPath.relative compares bytes: a name that begins with a combining mark")
let marked = "/a/b/\u{301}x"
print("characters in \"/\" followed by U+0301: \("/\u{301}".count)")
print("String.hasPrefix(\"/a/b/\") of \"/a/b/\" + U+0301 + \"x\": \(marked.hasPrefix("/a/b/"))")
print("UTF-8 bytes start with those of \"/a/b/\": \(marked.utf8.starts(with: "/a/b/".utf8))")
