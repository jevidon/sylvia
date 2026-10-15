import Foundation
import Testing
@testable import G04AudioKit

/// Records how the exporter applied the protection class (review R5-04).
final class ProtectionCalls: @unchecked Sendable {
    struct Call {
        var type: FileProtectionType
        var url: URL
        var fileExisted: Bool
        var targetExisted: Bool
    }
    private let lock = NSLock()
    private var calls: [Call] = []
    func append(_ call: Call) { lock.withLock { calls.append(call) } }
    var all: [Call] { lock.withLock { calls } }
}

extension RealAV {
    /// Review R5-04: a retained excerpt is user content on the capture path, so it gets class C
    /// (`completeUntilFirstUserAuthentication`) explicitly, like the capture records and checkpoints (ADR-0007
    /// decision 4, ADR-0012), instead of whatever class the platform gives a new file. The iOS Simulator ignores file
    /// protection (it logs "ignoring unsupported value" and reads back class C whatever was set), so these tests show
    /// that the exporter applies the class, and when; the class a device reads back is device checklist step 9.
    @Suite("Retained excerpts are written with file protection class C (R5-04)")
    struct ExcerptProtectionTests {
        static func source() throws -> [SourceSegment] {
            [SourceSegment(url: try Fixtures.url("fmt-mp3-cbr.mp3"), range: AudioRange(assetID: UUID(), startMs: 10_000, endMs: 12_000))]
        }

        static func scratch() throws -> URL {
            let dir = FileManager.default.temporaryDirectory.appendingPathComponent("g04-protection-\(UUID().uuidString)/excerpts")
            return dir
        }

        @Test func theExporterAppliesClassCToTheFinishedExcerptBeforeItIsRenamedIntoPlace() async throws {
            let dir = try Self.scratch()
            defer { try? FileManager.default.removeItem(at: dir.deletingLastPathComponent()) }
            let target = dir.appendingPathComponent("capture.m4a")
            let calls = ProtectionCalls()
            var exporter = AACExcerptExporter()
            #expect(exporter.protection == .completeUntilFirstUserAuthentication)
            exporter.applyProtection = { type, url in
                calls.append(.init(type: type, url: url, fileExisted: FileManager.default.fileExists(atPath: url.path),
                                   targetExisted: FileManager.default.fileExists(atPath: target.path)))
                try DurableFile.applyProtection(type, to: url)
            }
            let excerpt = try await exporter.export(try Self.source(), to: target)
            #expect(excerpt.frameCount > 0)
            let call = try #require(calls.all.first)
            #expect(calls.all.count == 1)
            #expect(call.type == .completeUntilFirstUserAuthentication)
            // The finished temporary file in the excerpt's own directory, before the rename made it the excerpt.
            #expect(call.url.deletingLastPathComponent().standardizedFileURL == dir.standardizedFileURL)
            #expect(call.url.lastPathComponent.hasPrefix(".tmp-") && call.url.pathExtension == "m4a")
            #expect(call.fileExisted && !call.targetExisted)
            #expect(FileManager.default.fileExists(atPath: target.path))
            #expect(try FileManager.default.contentsOfDirectory(atPath: dir.path) == ["capture.m4a"])
            // What the simulator reads back (not discriminating here; a device shows the class, checklist step 9).
            let readback = try target.resourceValues(forKeys: [.fileProtectionKey]).fileProtection
            #expect(readback == nil || readback == .completeUntilFirstUserAuthentication)
        }

        /// No excerpt without its class: when the class cannot be applied, the export fails (the capture then offers
        /// Retry with its bookmark and note kept, as for any export failure) and nothing is left behind.
        @Test func anExcerptWhoseClassCannotBeAppliedIsNotKept() async throws {
            let dir = try Self.scratch()
            defer { try? FileManager.default.removeItem(at: dir.deletingLastPathComponent()) }
            let target = dir.appendingPathComponent("capture.m4a")
            var failing = AACExcerptExporter()
            failing.applyProtection = { _, _ in throw DurableFileError.write(path: "protection", errno: 1) }
            let exporter = failing
            await #expect(throws: ExportError.self) { try await exporter.export(try Self.source(), to: target) }
            #expect(!FileManager.default.fileExists(atPath: target.path))
            #expect(try FileManager.default.contentsOfDirectory(atPath: dir.path).isEmpty)
        }
    }
}
