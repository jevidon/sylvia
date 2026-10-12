import Foundation

/// Locates committed fixtures in the repository checkout (Fixtures/, see Fixtures/LICENSES.md).
public enum RepoFixtures {
    /// The repository root, found by walking up from this source file.
    public static let repositoryRoot: URL = {
        var url = URL(fileURLWithPath: #filePath)
        while url.path != "/" {
            url.deleteLastPathComponent()
            if FileManager.default.fileExists(atPath: url.appendingPathComponent("Fixtures/LICENSES.md").path) { return url }
        }
        fatalError("Fixtures/LICENSES.md not found above \(#filePath)")
    }()

    public static func url(_ relativePath: String) -> URL {
        repositoryRoot.appendingPathComponent("Fixtures").appendingPathComponent(relativePath)
    }

    public static func data(_ relativePath: String) throws -> Data {
        try Data(contentsOf: url(relativePath))
    }
}

/// A canary credential used to prove keys never leak into errors, logs, bodies or persisted models.
public enum Canary {
    public static let apiKey = "sk-test-CANARY-7f3a9c1e5b2d4f6a8c0e1b3d5f7a9c2e"
    public static let anthropicKey = "sk-ant-test-CANARY-0b1c2d3e4f5a6b7c8d9e0f1a2b3c4d5e"
}
