import Foundation
import Testing
@testable import G04AudioKit

@Suite("Media inspection: ID3 chapters and multi-file metadata (plan 8.3; T14)")
struct MediaTests {
    @Test func id3ChapParserMatchesTheGeneratedTableAndAVFoundation() async throws {
        let url = try Fixtures.url("fmt-mp3-chap.mp3")
        let parsed = try ID3Chapters.read(url: url)
        #expect(parsed == Fixtures.chapters600)
        // No duration to close an indefinite end with: every ID3 CHAP frame carries its own end time.
        let av = try await AssetInspector.avChapters(AssetInspector.preciseAsset(url), durationMs: nil)
        #expect(av.map(\.title) == parsed.map(\.title))
        #expect(zip(av, parsed).allSatisfy { abs($0.startMs - $1.startMs) <= 1 && abs($0.endMs - $1.endMs) <= 1 })
    }

    @Test func id3ParserRejectsMalformedTagsWithoutCrashing() throws {
        func header(size: Int, version: UInt8 = 3, flags: UInt8 = 0) -> Data {
            Data([0x49, 0x44, 0x33, version, 0, flags,
                  UInt8((size >> 21) & 0x7f), UInt8((size >> 14) & 0x7f), UInt8((size >> 7) & 0x7f), UInt8(size & 0x7f)])
        }
        // A CHAP frame claiming more bytes than the tag holds.
        var frame = Data("CHAP".utf8) + Data([0, 0, 0x10, 0, 0, 0])
        frame += Data([0x63, 0x31, 0])
        let body = frame
        #expect(throws: ID3Chapters.ParseError.truncated) { try ID3Chapters.parse(header: header(size: body.count), body: body) }
        // Unsupported version.
        #expect(throws: ID3Chapters.ParseError.unsupportedVersion(2)) { try ID3Chapters.parse(header: header(size: 0, version: 2), body: Data()) }
        // A CHAP payload too short for its four time fields.
        var short = Data("CHAP".utf8) + Data([0, 0, 0, 5, 0, 0])
        short += Data([0x63, 0, 1, 2, 3])
        #expect(throws: ID3Chapters.ParseError.truncated) { try ID3Chapters.parse(header: header(size: short.count), body: short) }
        // Padding only: no chapters.
        #expect(try ID3Chapters.parse(header: header(size: 64), body: Data(count: 64)).isEmpty)
        // Random bytes never crash the parser.
        var rng = SeededRNG(seed: 99)
        for _ in 0..<500 {
            let n = Int(rng.next() % 300)
            let bytes = Data((0..<n).map { _ in UInt8(truncatingIfNeeded: rng.next()) })
            _ = try? ID3Chapters.parse(header: header(size: n, version: rng.next() % 2 == 0 ? 3 : 4), body: bytes)
        }
    }

    @Test func T14_multiFileBookReadsEmbeddedTrackNumbersAndProposesTagOrder() async throws {
        var candidates: [MemberCandidate] = []
        for m in Fixtures.multi {
            let report = try await AssetInspector.inspect(try Fixtures.url("multi/\(m.name)"))
            #expect(report.trackNumber == m.track, "\(m.name)")
            #expect(report.trackTotal == 4)
            #expect(abs((report.preciseDurationMs ?? 0) - Int64(m.duration * 1000)) <= 100, "\(m.name) duration \(report.preciseDurationMs ?? -1)")
            candidates.append(MemberCandidate(fileName: m.name, trackNumber: report.trackNumber, trackTotal: report.trackTotal, discNumber: report.discNumber))
        }
        // Present them in the order a directory listing would (lexicographic), not in content order.
        let listing = candidates.sorted { $0.fileName < $1.fileName }
        let p = MemberOrdering.propose(listing)
        #expect(p.order.map { listing[$0].fileName } == ["Part 2.mp3", "Part 1.mp3", "Part 3.mp3", "Part 10.mp3"])
        #expect(p.requiresConfirmation)
        #expect(p.issues.first == .tagAndFileNameOrderDisagree)

        // A missing member is identified from the stated total.
        let without3 = listing.filter { $0.fileName != "Part 3.mp3" }
        let q = MemberOrdering.propose(without3)
        #expect(q.issues.contains(.absentTracks(disc: 1, ranges: [3...3])))
    }
}
