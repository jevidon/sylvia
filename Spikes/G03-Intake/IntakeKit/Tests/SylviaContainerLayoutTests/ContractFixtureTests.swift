import Foundation
import SylviaImportHandoff
import SylviaPack
import Testing

/// The Swift types and the JSON Schemas in Contracts/ must agree: every valid contract fixture decodes and passes the
/// Swift validation, and every invalid one is refused by decoding or validation. Scripts/ci.sh contracts checks the
/// same fixtures against the schemas.
@Suite("contract fixtures agree with the Swift implementation", .removesTemporaryFiles)
struct ContractFixtureTests {
    static let contracts = URL(fileURLWithPath: #filePath)
        .deletingLastPathComponent()   // SylviaContainerLayoutTests
        .deletingLastPathComponent()   // Tests
        .deletingLastPathComponent()   // IntakeKit
        .deletingLastPathComponent()   // G03-Intake
        .deletingLastPathComponent()   // Spikes
        .deletingLastPathComponent()   // repository root
        .appendingPathComponent("Contracts/fixtures", isDirectory: true)

    static func fixtures(_ contract: String, _ kind: String) throws -> [URL] {
        let dir = contracts.appendingPathComponent("\(contract)/\(kind)", isDirectory: true)
        let names = try FileManager.default.contentsOfDirectory(atPath: dir.path).filter { $0.hasSuffix(".json") }.sorted()
        return names.map { dir.appendingPathComponent($0) }
    }

    static func handoffAccepted(_ url: URL) -> Bool {
        guard let data = try? Data(contentsOf: url), let manifest = try? HandoffManifest.decode(data) else { return false }
        return (try? manifest.validate(directoryName: manifest.handoffID.uuidString)) != nil
    }

    static func packAccepted(_ url: URL) -> Bool {
        guard let data = try? Data(contentsOf: url), let manifest = try? PackManifest.decode(data) else { return false }
        return (try? manifest.validate(limits: PackLimits())) != nil
    }

    @Test("import-handoff-manifest v1 fixtures")
    func handoffFixtures() throws {
        let valid = try Self.fixtures("import-handoff-manifest.v1", "valid")
        let invalid = try Self.fixtures("import-handoff-manifest.v1", "invalid")
        try #require(!valid.isEmpty && !invalid.isEmpty)
        for url in valid { #expect(Self.handoffAccepted(url), "valid fixture refused: \(url.lastPathComponent)") }
        for url in invalid { #expect(!Self.handoffAccepted(url), "invalid fixture accepted: \(url.lastPathComponent)") }
        print("contract fixtures: import-handoff-manifest.v1 valid=\(valid.count) invalid=\(invalid.count) agree with HandoffManifest")
    }

    @Test("sylviapack-manifest v1 fixtures")
    func packFixtures() throws {
        let valid = try Self.fixtures("sylviapack-manifest.v1", "valid")
        let invalid = try Self.fixtures("sylviapack-manifest.v1", "invalid")
        try #require(!valid.isEmpty && !invalid.isEmpty)
        for url in valid { #expect(Self.packAccepted(url), "valid fixture refused: \(url.lastPathComponent)") }
        for url in invalid { #expect(!Self.packAccepted(url), "invalid fixture accepted: \(url.lastPathComponent)") }
        print("contract fixtures: sylviapack-manifest.v1 valid=\(valid.count) invalid=\(invalid.count) agree with PackManifest")
    }
}
