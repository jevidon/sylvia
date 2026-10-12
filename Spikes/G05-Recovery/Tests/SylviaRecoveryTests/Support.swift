import Foundation
import GRDB
import Testing
@testable import SylviaRecovery

/// A temporary installation root, removed when the test ends.
final class Scratch: @unchecked Sendable {
    let url: URL

    init(_ name: String = #function) throws {
        let safe = name.filter { $0.isLetter || $0.isNumber }
        url = FileManager.default.temporaryDirectory
            .appending(path: "g05-tests/\(safe)-\(UUID().uuidString.prefix(8))", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
    }

    deinit { try? FileManager.default.removeItem(at: url) }

    func dir(_ path: String) -> URL { url.appending(path: path, directoryHint: .isDirectory) }
    func layout(_ path: String = "Install") -> LibraryLayout { LibraryLayout(root: dir(path)) }
}

/// Environment label printed with measured results (evidence logs must name the environment).
var testEnvironment: String {
    #if targetEnvironment(simulator)
    let model = ProcessInfo.processInfo.environment["SIMULATOR_MODEL_IDENTIFIER"] ?? "?"
    let device = ProcessInfo.processInfo.environment["SIMULATOR_DEVICE_NAME"] ?? "?"
    return "simulator (iOS \(ProcessInfo.processInfo.operatingSystemVersionString), \(device), \(model))"
    #elseif os(macOS)
    return "host (macOS \(ProcessInfo.processInfo.operatingSystemVersionString))"
    #else
    return "device (\(ProcessInfo.processInfo.operatingSystemVersionString))"
    #endif
}

func evidence(_ line: String) {
    print("[evidence] [\(testEnvironment)] \(line)")
}

/// Opens a library and builds the golden corpus in it.
func corpusLibrary(_ scratch: Scratch, _ path: String = "Install", options: StoreOptions = StoreOptions()) throws -> (LibraryStore, GoldenCorpus) {
    let store = try LibraryStore.open(scratch.layout(path), options: options)
    let corpus = try GoldenCorpus.build(in: store, sourceDirectory: scratch.dir("\(path)-source"))
    return (store, corpus)
}

/// A fingerprint of everything under a directory: relative path, size and SHA-256 of each file.
/// Used to prove an operation left a library byte-for-byte untouched.
func treeFingerprint(_ root: URL, excluding: Set<String> = []) throws -> [String: String] {
    var result: [String: String] = [:]
    let base = root.standardizedFileURL.path
    guard let enumerator = FileManager.default.enumerator(at: root, includingPropertiesForKeys: [.isRegularFileKey]) else { return [:] }
    for case let url as URL in enumerator {
        let values = try url.resourceValues(forKeys: [.isRegularFileKey])
        guard values.isRegularFile == true else { continue }
        let relative = String(url.standardizedFileURL.path.dropFirst(base.count + 1))
        if excluding.contains(url.lastPathComponent) { continue }
        let (sha, size) = try Digest.sha256Hex(fileAt: url)
        result[relative] = "\(size):\(sha)"
    }
    return result
}

/// Reads a manifest, lets the test change it, and writes it back.
func rewriteManifest(_ bundle: URL, _ change: (inout BackupManifest) throws -> Void) throws {
    let url = bundle.appending(path: "manifest.json", directoryHint: .notDirectory)
    var manifest = try JSONDecoder().decode(BackupManifest.self, from: Data(contentsOf: url))
    try change(&manifest)
    try JSONEncoder.sortedPretty.encode(manifest).write(to: url)
}

/// Recomputes size and digest of a listed file after a test modified it, so the bundle passes
/// file-level validation and the deeper check is what must reject it.
func refreshEntry(_ manifest: inout BackupManifest, bundle: URL, path: String) throws {
    guard let index = manifest.files.firstIndex(where: { $0.path == path }) else { throw StoreError.invalid("no \(path)") }
    let (sha, size) = try Digest.sha256Hex(fileAt: bundle.appending(path: path, directoryHint: .notDirectory))
    manifest.files[index].sha256 = sha
    manifest.files[index].byte_count = size
}

/// Copies a directory tree (to make variants of a good bundle).
func copyTree(_ from: URL, to: URL) throws {
    try? FileManager.default.removeItem(at: to)
    try FileManager.default.copyItem(at: from, to: to)
}

/// Locates the tool executable built next to the test bundle.
final class BundleLocator {}
func toolExecutable() -> URL {
    Bundle(for: BundleLocator.self).bundleURL.deletingLastPathComponent().appending(path: "g05-recovery-tool", directoryHint: .notDirectory)
}
