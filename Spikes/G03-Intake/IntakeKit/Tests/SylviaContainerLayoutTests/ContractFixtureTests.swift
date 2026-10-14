import Foundation
import SylviaImportHandoff
import SylviaIntakeCore
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

    /// G0.3 review R2-04: `created_at` is read as the schemas' `date-time` format accepts it. The same inputs are
    /// checked against the schemas themselves by Spikes/G03-Intake/scripts/check-contract-instances.sh, which compares
    /// the two verdicts.
    @Test("created_at: RFC 3339 exactly as the schemas' date-time format (fractions, offsets and lowercase t/z accepted; 30 February, hour 24, leap seconds, offsets without a colon refused)")
    func rfc3339() throws {
        let accepted: [(String, TimeInterval)] = [
            ("2026-10-06T12:00:00Z", 1_791_288_000),
            ("2026-10-06T12:00:00.5Z", 1_791_288_000.5),
            ("2026-10-06t12:00:00z", 1_791_288_000),
            ("2026-10-06T12:00:00+13:00", 1_791_241_200),
            ("2026-10-06T12:00:00-00:00", 1_791_288_000),
            ("2026-10-07T01:00:00.25+13:00", 1_791_288_000.25),
            ("2024-02-29T00:00:00Z", 1_709_164_800),
            ("1970-01-01T00:00:00Z", 0),
            // Proleptic Gregorian instants, as Python's datetime gives them ((datetime(...) - epoch) in seconds; G0.3 review
            // R4-03). Foundation's Gregorian Calendar, which the first version used, is Julian before 1582-10-15: it gave
            // 1582-10-10 as -12_218_860_800 (ten days late, after 1582-10-15) and 0001-01-01 as -62_135_769_600.
            ("0001-01-01T00:00:00Z", -62_135_596_800),
            ("0001-01-01T00:00:00+23:59", -62_135_683_140),
            ("0004-02-29T00:00:00Z", -62_035_891_200),
            ("1000-03-01T00:00:00Z", -30_605_126_400),
            ("1500-03-01T00:00:00Z", -14_826_672_000),
            ("1582-10-04T23:59:59Z", -12_220_156_801),
            ("1582-10-10T00:00:00Z", -12_219_724_800),
            ("1582-10-15T00:00:00Z", -12_219_292_800),
            ("1600-02-29T12:00:00Z", -11_670_955_200),
            ("1969-12-31T23:59:59Z", -1),
            ("9999-12-31T23:59:59Z", 253_402_300_799),
            ("9999-12-31T23:59:59-23:59", 253_402_387_139),
        ]
        for (text, expected) in accepted {
            let date = RFC3339.date(from: text)
            #expect(date != nil, "refused \(text)")
            if let date { #expect(abs(date.timeIntervalSince1970 - expected) < 0.000_1, "\(text) -> \(date.timeIntervalSince1970)") }
        }
        // Accepted, with a fraction finer than a Date keeps: only that it parses is checked.
        #expect(RFC3339.date(from: "2026-10-06T15:30:00.123456789+13:00") != nil)
        let refused = ["2026-02-30T12:00:00Z", "2025-02-29T00:00:00Z", "2026-04-31T00:00:00Z", "2026-10-06T24:00:00Z",
                       "1000-02-29T00:00:00Z", "1700-02-29T00:00:00Z",   // leap days in the Julian calendar only
                       "2026-10-06T12:60:00Z", "2026-10-06T12:00:60Z", "2026-10-06T12:00:00+1300", "2026-10-06T12:00:00+24:00",
                       "2026-10-06T12:00:00", "2026-10-06 12:00:00Z", "2026-10-06T12:00:00.Z", "0000-01-01T00:00:00Z",
                       "2026-13-01T00:00:00Z", "2026-00-10T00:00:00Z", "20261006T120000Z", "2026-10-06T12:00:00Z\n",
                       "\u{FF12}026-10-06T12:00:00Z", "6 October 2026", ""]
        for text in refused { #expect(RFC3339.date(from: text) == nil, "accepted \(text.debugDescription)") }
        // What the writers produce (JSONEncoder .iso8601) reads back to the same instant.
        let instant = Date(timeIntervalSince1970: 1_790_000_000)
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = RFC3339.decodingStrategy
        #expect(try decoder.decode([Date].self, from: encoder.encode([instant])) == [instant])
    }

    /// G0.3 review R4-03: no gap or overlap anywhere in years 1 to 9999, in particular none in October 1582, where a
    /// Julian-to-Gregorian calendar jumps ten days. Every first of the month is parsed, and each must lie exactly the
    /// previous month's length in days after the one before it.
    @Test("created_at: the first of every month from 0001 to 9999 lies exactly one proleptic Gregorian month after the previous one")
    func rfc3339Continuity() throws {
        func daysIn(_ month: Int, _ year: Int) -> Int {
            switch month {
            case 2: (year % 4 == 0 && year % 100 != 0) || year % 400 == 0 ? 29 : 28
            case 4, 6, 9, 11: 30
            default: 31
            }
        }
        var previous = try #require(RFC3339.date(from: "0001-01-01T00:00:00Z"))
        var previousMonth = (year: 1, month: 1)
        var checked = 0
        var mismatches: [String] = []
        for year in 1...9999 {
            for month in 1...12 where (year, month) != (1, 1) {
                let text = String(format: "%04d-%02d-01T00:00:00Z", year, month)
                let date = try #require(RFC3339.date(from: text), "refused \(text)")
                let expected = TimeInterval(daysIn(previousMonth.month, previousMonth.year) * 86_400)
                if date.timeIntervalSince(previous) != expected { mismatches.append(text) }
                previous = date
                previousMonth = (year, month)
                checked += 1
            }
        }
        print("created_at continuity: \(checked) consecutive months from 0001-01 to 9999-12, \(mismatches.count) not one month apart\(mismatches.isEmpty ? "" : ": \(mismatches.prefix(5))")")
        #expect(mismatches.isEmpty)
    }

    /// The divergences the contracts document, seen from the reader's side: a path or file name over its UTF-8 byte
    /// limit but within the schema's code-point bounds is valid against the schema (check-contract-instances.sh checks
    /// that side) and refused here.
    @Test("documented divergences: non-ASCII paths and file names over their byte limits are refused although the schema's code-point bounds admit them")
    func documentedByteDivergences() throws {
        let e = "\u{E9}"
        let hundred = String(repeating: e, count: 100)
        let packURL = Self.contracts.appendingPathComponent("sylviapack-manifest.v1/valid/single-file-no-groups.json")
        var pack = try PackManifest.decode(Data(contentsOf: packURL))
        pack.files[0].path = hundred + "/" + hundred + "/" + hundred + ".epub"   // 307 code points, 607 bytes
        #expect(throws: PackRejection(.unsafePath, "length")) { try pack.validate(limits: PackLimits()) }

        let handoffURL = Self.contracts.appendingPathComponent("import-handoff-manifest.v1/valid/one-file-representation.json")
        var handoff = try HandoffManifest.decode(Data(contentsOf: handoffURL))
        handoff.items[0].originalFilename = String(repeating: e, count: 128)     // 128 code points, 256 bytes
        #expect(throws: HandoffManifestError.invalidField("original_filename")) {
            try handoff.validate(directoryName: handoff.handoffID.uuidString)
        }
        handoff.items[0].originalFilename = String(repeating: e, count: 127) + "a"   // 255 bytes: at the limit
        #expect(throws: Never.self) { try handoff.validate(directoryName: handoff.handoffID.uuidString) }
    }
}
