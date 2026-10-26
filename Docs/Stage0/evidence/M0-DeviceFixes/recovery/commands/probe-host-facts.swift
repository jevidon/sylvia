// Host facts behind the M0 device fixes (recovery), measured on the build Mac (macOS), never on a phone:
//   1. whether class A and B keys are available (the screen is unlocked);
//   2. Foundation's resolvingSymlinksInPath for a folder named under /var and through /private, an existing
//      path and a missing one, and a missing leaf below a link (diagnosis 2: the containment check of
//      BackupValidator.resolve before the fix), next to realpath(3), which the fix uses;
//   3. whether FileManager.copyItem keeps the source's class (diagnosis 1), next to a write with the class;
//   4. whether setAttributes changes an existing file's or directory's class, and what one URL value reports
//      before and after it, and after removeAllCachedResourceValues (finding: FileProtector.verify after
//      protect reads the class through the same URL value).
// Sections 3 and 4 need class A/B keys, so they are skipped while the screen is locked.
//   xcrun swift Docs/Stage0/evidence/M0-DeviceFixes/recovery/commands/probe-host-facts.swift
// Run by run-probe.sh, which records the context. Writes only in a folder of its own under the temporary folder,
// removed at the end.
import Foundation

let fm = FileManager.default
func viaURL(_ url: URL) -> String {
    (try? url.resourceValues(forKeys: [.fileProtectionKey]).fileProtection?.rawValue) ?? "none reported"
}
func fresh(_ path: String) -> String { viaURL(URL(fileURLWithPath: path)) }
func viaAttributes(_ path: String) -> String {
    ((try? fm.attributesOfItem(atPath: path)[.protectionKey]) as? FileProtectionType)?.rawValue ?? "none reported"
}
func realPath(_ path: String) -> String {
    guard let resolved = realpath(path, nil) else { return "realpath failed: errno \(errno)" }
    defer { free(resolved) }
    return String(cString: resolved)
}

print("host: macOS \(ProcessInfo.processInfo.operatingSystemVersionString)")
print("temporary folder (FileManager.temporaryDirectory): \(fm.temporaryDirectory.path)")
let base = fm.temporaryDirectory.appending(path: "g05-devicefix-probe-\(UUID().uuidString.prefix(8))", directoryHint: .isDirectory)
try fm.createDirectory(at: base, withIntermediateDirectories: true)
defer { try? fm.removeItem(at: base) }

print("\n== 1. class A/B keys")
var keys = false
do {
    let a = base.appending(path: "a.bin")
    try Data("x".utf8).write(to: a, options: .completeFileProtection)
    keys = try Data(contentsOf: a) == Data("x".utf8)
    print("a class-A file was created and read back: keys available (screen unlocked)")
} catch {
    print("class-A file not created or read: keys unavailable (screen locked): \(error.localizedDescription)")
}

print("\n== 2. resolvingSymlinksInPath and realpath(3), existing and missing paths")
let bundle = base.appending(path: "bundle", directoryHint: .isDirectory)
let outside = base.appending(path: "outside", directoryHint: .isDirectory)
try fm.createDirectory(at: bundle.appending(path: "export"), withIntermediateDirectories: true)
try fm.createDirectory(at: outside, withIntermediateDirectories: true)
try fm.createSymbolicLink(at: bundle.appending(path: "export/escape"), withDestinationURL: outside)
let varForm = bundle.path
let privateForm = varForm.hasPrefix("/private/") ? varForm : "/private" + varForm
for (label, path) in [("named under /var", varForm), ("named through /private", privateForm)] {
    let root = URL(fileURLWithPath: path, isDirectory: true)
    let missing = root.appending(path: "blobs/excerpts/missing.mp3")
    let rootResolved = root.resolvingSymlinksInPath().standardizedFileURL.path
    let missingResolved = missing.resolvingSymlinksInPath().standardizedFileURL.path
    print("\(label): root -> \(rootResolved)")
    print("\(label): missing file -> \(missingResolved)")
    print("\(label): the check before the fix (missing file's path starts with root + /): \(missingResolved.hasPrefix(rootResolved + "/"))")
    print("\(label): realpath(3) of the root -> \(realPath(root.path))")
}
let belowLink = URL(fileURLWithPath: varForm).appending(path: "export/escape/missing.md")
print("missing leaf below a link to a folder outside the root: resolvingSymlinksInPath -> \(belowLink.resolvingSymlinksInPath().path)")
print("the same link's folder by realpath(3) -> \(realPath(belowLink.deletingLastPathComponent().path))")

guard keys else {
    print("\n== 3, 4. skipped: class B keys unavailable (screen locked)")
    exit(0)
}

print("\n== 3. FileManager.copyItem and the source's class")
let classB = base.appending(path: "classB", directoryHint: .isDirectory)
try fm.createDirectory(at: classB, withIntermediateDirectories: true, attributes: [.protectionKey: FileProtectionType.completeUnlessOpen])
let classC = base.appending(path: "classC", directoryHint: .isDirectory)
try fm.createDirectory(at: classC, withIntermediateDirectories: true, attributes: [.protectionKey: FileProtectionType.completeUntilFirstUserAuthentication])
let source = classB.appending(path: "library-v1.sqlite")
try Data("fixture".utf8).write(to: source)
let copied = classC.appending(path: "library.sqlite")
try fm.copyItem(at: source, to: copied)
let written = classC.appending(path: "written.sqlite")
try Data("fixture".utf8).write(to: written, options: [.withoutOverwriting, .completeFileProtectionUntilFirstUserAuthentication])
print("source created in a class-B folder: \(fresh(source.path))")
print("copyItem of it into a class-C folder: \(fresh(copied.path))")
print("a new file written with the class-C option in the class-C folder: \(fresh(written.path))")

print("\n== 4. setAttributes on an existing item, read through one URL value")
for (kind, isDirectory) in [("file", false), ("directory", true)] {
    let item = classB.appending(path: "weak-\(kind)", directoryHint: isDirectory ? .isDirectory : .notDirectory)
    if isDirectory {
        try fm.createDirectory(at: item, withIntermediateDirectories: false, attributes: [.protectionKey: FileProtectionType.completeUnlessOpen])
    } else {
        try Data("x".utf8).write(to: item)
    }
    var url = URL(fileURLWithPath: item.path, isDirectory: isDirectory)
    let before = viaURL(url)
    var result = "no error"
    do { try fm.setAttributes([.protectionKey: FileProtectionType.completeUntilFirstUserAuthentication], ofItemAtPath: item.path) } catch { result = "error: \(error)" }
    let sameValue = viaURL(url)
    url.removeAllCachedResourceValues()
    let afterClearing = viaURL(url)
    print("\(kind) of class B, setAttributes(class C): \(result); the same URL value before: \(before), after: \(sameValue); "
          + "after removeAllCachedResourceValues: \(afterClearing); a new URL: \(fresh(item.path)); attributesOfItem: \(viaAttributes(item.path))")
}
