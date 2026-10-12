// The same file is in each IntakeKit test target (test targets cannot share a source file).
import Foundation
import Testing

/// Every file a test creates lives under a directory that belongs to that one test (or test case) and is removed when
/// it ends, so test runs leave nothing behind in $TMPDIR and two runs at once (two worktrees, a reviewer) never share a
/// path. Apply `.removesTemporaryFiles` to every suite; `TestDirectory.make()` refuses to work outside one.
struct RemovesTemporaryFiles: TestTrait, SuiteTrait, TestScoping {
    var isRecursive: Bool { true }

    func provideScope(for test: Test, testCase: Test.Case?,
                      performing function: @Sendable () async throws -> Void) async throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("g03-tests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        try await TestDirectory.$root.withValue(root) {
            try await function()
        }
    }
}

extension Trait where Self == RemovesTemporaryFiles {
    static var removesTemporaryFiles: Self { Self() }
}

enum TestDirectory {
    @TaskLocal static var root: URL?

    struct OutsideScope: Error, CustomStringConvertible {
        var description: String { "this test's suite lacks the .removesTemporaryFiles trait" }
    }

    /// A new, empty directory inside the current test's scope.
    static func make() throws -> URL {
        guard let root else { throw OutsideScope() }
        let url = root.appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }
}
