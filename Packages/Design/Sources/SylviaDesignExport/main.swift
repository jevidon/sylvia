// sylvia-design-export: writes or checks every file generated from the design tokens.
//
//   swift run --package-path Packages/Design sylvia-design-export write <repo-root>
//   swift run --package-path Packages/Design sylvia-design-export check <repo-root>
//   swift run --package-path Packages/Design sylvia-design-export contrast-table <repo-root> <out.md>
//
// Generated: Contracts/design/marginalia.v1.json, the color and symbol asset catalogs and the
// vocabulary String Catalog in Packages/Design/Sources/SylviaDesign/Resources. `check` exits 1 if
// any committed file differs from what the token definitions produce, or a stale generated file
// remains.
import Foundation
import SylviaDesignTokens

func fail(_ message: String) -> Never {
    FileHandle.standardError.write(Data((message + "\n").utf8))
    exit(1)
}

let arguments = CommandLine.arguments.dropFirst()
guard let command = arguments.first, let rootArgument = arguments.dropFirst().first else {
    fail("usage: sylvia-design-export write|check|contrast-table <repo-root> [out.md]")
}
let root = URL(fileURLWithPath: rootArgument, isDirectory: true).standardizedFileURL
guard FileManager.default.fileExists(atPath: root.appendingPathComponent("Packages/Design/Package.swift").path) else {
    fail("\(root.path) is not the Sylvia repository root")
}

let expected = GeneratedFiles.all()

/// Files currently inside the fully generated directories (relative paths, ignoring .DS_Store).
func existingGeneratedFiles() -> Set<String> {
    var found = Set<String>()
    for directory in GeneratedFiles.generatedDirectories {
        let url = root.appendingPathComponent(directory)
        guard let enumerator = FileManager.default.enumerator(at: url, includingPropertiesForKeys: [.isRegularFileKey]) else {
            continue
        }
        for case let file as URL in enumerator {
            guard (try? file.resourceValues(forKeys: [.isRegularFileKey]).isRegularFile) == true,
                  file.lastPathComponent != ".DS_Store" else { continue }
            let relative = String(file.standardizedFileURL.path.dropFirst(root.path.count + 1))
            found.insert(relative)
        }
    }
    return found
}

switch command {
case "write":
    for path in existingGeneratedFiles() where expected[path] == nil {
        try FileManager.default.removeItem(at: root.appendingPathComponent(path))
        print("removed stale \(path)")
    }
    for directory in GeneratedFiles.generatedDirectories {
        // Remove now-empty directories left by stale files.
        let url = root.appendingPathComponent(directory)
        if let items = try? FileManager.default.contentsOfDirectory(atPath: url.path) {
            for item in items {
                let sub = url.appendingPathComponent(item)
                var isDir: ObjCBool = false
                if FileManager.default.fileExists(atPath: sub.path, isDirectory: &isDir), isDir.boolValue,
                   (try? FileManager.default.contentsOfDirectory(atPath: sub.path).filter { $0 != ".DS_Store" }.isEmpty) == true {
                    try FileManager.default.removeItem(at: sub)
                }
            }
        }
    }
    var written = 0
    for (path, content) in expected.sorted(by: { $0.key < $1.key }) {
        let url = root.appendingPathComponent(path)
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        let data = Data(content.utf8)
        if (try? Data(contentsOf: url)) != data {
            try data.write(to: url, options: .atomic)
            print("wrote \(path)")
            written += 1
        }
    }
    print("\(expected.count) generated files, \(written) changed")

case "check":
    var problems: [String] = []
    for (path, content) in expected.sorted(by: { $0.key < $1.key }) {
        let url = root.appendingPathComponent(path)
        guard let data = try? Data(contentsOf: url) else {
            problems.append("missing: \(path)")
            continue
        }
        if data != Data(content.utf8) {
            problems.append("differs: \(path)")
        }
    }
    for path in existingGeneratedFiles().sorted() where expected[path] == nil {
        problems.append("stale: \(path)")
    }
    if problems.isEmpty {
        print("design export check: \(expected.count) generated files match the token definitions")
    } else {
        problems.forEach { print($0) }
        fail("design export check FAILED: \(problems.count) file(s) out of date; run sylvia-design-export write and commit")
    }

case "contrast-table":
    guard let out = arguments.dropFirst(2).first else { fail("contrast-table needs an output path") }
    let results = ContrastReport.evaluate { token, appearance in token.value(in: appearance) }
    let failures = results.filter { !$0.passes }
    var text = "# Contrast from token definitions (Swift)\n\n"
    text += "\(results.count) measurements (\(ContrastPairs.all.count) pairs x \(Appearance.allCases.count) appearances), "
    text += "\(failures.count) failing.\n\n"
    text += ContrastReport.markdownTable(results)
    let components = ContrastReport.evaluateComponents { token, appearance in token.value(in: appearance) }
    let componentFailures = components.filter(\.isFailure)
    let exemptBelow = components.filter { !$0.passes && !$0.isFailure }
    text += "\n## Component pairs\n\n"
    text += "Text and glyphs as components draw them where that differs from a token pair (`ComponentContrastPairs`): "
    text += "\(components.count) measurements (\(ComponentContrastPairs.all.count) pairs x \(Appearance.allCases.count) appearances), "
    text += "\(componentFailures.count) failing; \(exemptBelow.count) exempt disabled-state measurements below the minimum "
    text += "(reported, not enforced). Text needs 4.5:1, glyphs 3:1.\n\n"
    text += ContrastReport.componentMarkdownTable(components)
    try Data(text.utf8).write(to: URL(fileURLWithPath: out))
    print("wrote \(out): \(results.count) measurements, \(failures.count) failing; "
        + "\(components.count) component measurements, \(componentFailures.count) failing")
    if !failures.isEmpty || !componentFailures.isEmpty { exit(1) }

default:
    fail("unknown command \(command)")
}
