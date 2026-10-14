import Foundation
import Testing
@testable import G04AudioKit

/// ADR-0015 TM-F2: DurableFile sets the protection class through URLFileProtection (a FileProtectionType given to the
/// resource key is accepted and ignored) and reads it back. The iOS Simulator ignores file protection and reads back
/// class C (or nothing) whatever was set, so these tests show the mapping, the refusal of an unmapped class and the
/// readback path; the class a device reads back is device checklist step 9.
@Suite("DurableFile applies and reads back the protection class (ADR-0015 TM-F2)")
struct DurableFileProtectionTests {
    static func scratch() -> URL {
        let name = "g04-durable-" + UUID().uuidString
        return FileManager.default.temporaryDirectory.appendingPathComponent(name)
    }

    @Test func classesAToCMapToTheirResourceValues() throws {
        let url = Self.scratch()
        let a = try DurableFile.urlFileProtection(.complete, for: url)
        let b = try DurableFile.urlFileProtection(.completeUnlessOpen, for: url)
        let c = try DurableFile.urlFileProtection(.completeUntilFirstUserAuthentication, for: url)
        #expect(a == .complete)
        #expect(b == .completeUnlessOpen)
        #expect(c == .completeUntilFirstUserAuthentication)
    }

    @Test func anUnmappedClassIsRefusedAndNothingIsWritten() throws {
        let dir = Self.scratch()
        defer { try? FileManager.default.removeItem(at: dir) }
        let target = dir.appendingPathComponent("record.json")
        let unmapped = FileProtectionType(rawValue: "SylviaTestUnknownProtectionClass")
        let body = Data("{}".utf8)
        #expect(throws: DurableFileError.self) { try DurableFile.write(body, to: target, protection: unmapped) }
        #expect(FileManager.default.fileExists(atPath: target.path) == false)
        let leftovers = (try? FileManager.default.contentsOfDirectory(atPath: dir.path)) ?? []
        #expect(leftovers.isEmpty, "temporary files left: \(leftovers)")
    }

    @Test func aDurableWriteReadsBackClassC() throws {
        let dir = Self.scratch()
        defer { try? FileManager.default.removeItem(at: dir) }
        let target = dir.appendingPathComponent("record.json")
        try DurableFile.write(Data("{}".utf8), to: target)
        let readback = try URL(fileURLWithPath: target.path).resourceValues(forKeys: [.fileProtectionKey]).fileProtection
        // Simulator: class C or nothing whatever was set (not discriminating); a device shows the class.
        #expect(readback == nil || readback == .completeUntilFirstUserAuthentication)
    }
}
