import Foundation
import Testing
@testable import G04AudioKit

@Suite("Timeline and member order (plan 7.5, 8.3, 10.1; T14, T20)")
struct TimelineTests {
    let a = UUID(), b = UUID(), c = UUID()

    func timeline() throws -> EditionTimeline {
        try EditionTimeline(editionID: UUID(), members: [
            EditionMember(assetID: a, fileName: "a.mp3", durationMs: 10_000),
            EditionMember(assetID: b, fileName: "b.mp3", durationMs: 20_000),
            EditionMember(assetID: c, fileName: "c.mp3", durationMs: 5_000),
        ])
    }

    @Test func globalAndLocalPositionsRoundTrip() throws {
        let t = try timeline()
        #expect(t.durationMs == 35_000)
        #expect(try t.locate(globalMs: 0).point == AudioPoint(assetID: a, ms: 0))
        #expect(try t.locate(globalMs: 9_999).point == AudioPoint(assetID: a, ms: 9_999))
        #expect(try t.locate(globalMs: 10_000).point == AudioPoint(assetID: b, ms: 0))
        #expect(try t.locate(globalMs: 35_000).point == AudioPoint(assetID: c, ms: 5_000))
        for g in stride(from: Int64(0), through: 35_000, by: 250) {
            #expect(try t.globalMs(of: t.locate(globalMs: g).point) == g)
        }
        #expect(throws: TimelineError.positionOutOfRange(35_001)) { try t.locate(globalMs: 35_001) }
        #expect(throws: TimelineError.positionOutOfRange(-1)) { try t.locate(globalMs: -1) }
    }

    @Test func crossFileSelectionIsSeveralOrderedFileLocalRanges() throws {
        let t = try timeline()
        let r = try t.ranges(globalStartMs: 5_000, globalEndMs: 32_000)
        #expect(r == [
            AudioRange(assetID: a, startMs: 5_000, endMs: 10_000),
            AudioRange(assetID: b, startMs: 0, endMs: 20_000),
            AudioRange(assetID: c, startMs: 0, endMs: 2_000),
        ])
        #expect(try t.ranges(globalStartMs: 10_000, globalEndMs: 12_000) == [AudioRange(assetID: b, startMs: 0, endMs: 2_000)])
        let span = try #require(try t.globalSpan(of: r))
        #expect(span.startMs == 5_000)
        #expect(span.endMs == 32_000)
        #expect(throws: TimelineError.emptyRange) { try t.ranges(globalStartMs: 3, globalEndMs: 3) }
    }

    @Test func reorderCreatesNewRevisionAndKeepsFileLocalAnchors() throws {
        let t1 = try timeline()
        let captured = try t1.ranges(globalStartMs: 8_000, globalEndMs: 12_000)  // a 8-10 s, b 0-2 s
        let t2 = try t1.reordered([b, a, c])
        #expect(t2.revision == t1.revision + 1)
        #expect(t2.editionID == t1.editionID)
        // The stored ranges are unchanged; under the new order they are no longer contiguous.
        let reorderedSpan = try t2.globalSpan(of: captured)
        #expect(reorderedSpan == nil)
        // Each piece still resolves to the same file and offset.
        #expect(try t2.globalMs(of: AudioPoint(assetID: a, ms: 8_000)) == 28_000)
        #expect(try t2.globalMs(of: AudioPoint(assetID: b, ms: 0)) == 0)
        #expect(throws: TimelineError.notAPermutation) { try t1.reordered([a, b]) }
        #expect(throws: TimelineError.notAPermutation) { try t1.reordered([a, a, c]) }
    }

    @Test func rejectsInvalidManifests() {
        #expect(throws: TimelineError.empty) { try EditionTimeline(editionID: UUID(), members: []) }
        #expect(throws: TimelineError.nonPositiveDuration(fileName: "z")) {
            try EditionTimeline(editionID: UUID(), members: [EditionMember(assetID: UUID(), fileName: "z", durationMs: 0)])
        }
        let id = UUID()
        #expect(throws: TimelineError.duplicateAsset(id)) {
            try EditionTimeline(editionID: UUID(), members: [EditionMember(assetID: id, fileName: "x", durationMs: 1),
                                                             EditionMember(assetID: id, fileName: "y", durationMs: 1)])
        }
    }

    @Test func locateIsCorrectForHundredsOfMembers() throws {
        let members = (0..<500).map { EditionMember(assetID: UUID(), fileName: "\($0).mp3", durationMs: Int64(1_000 + $0)) }
        let t = try EditionTimeline(editionID: UUID(), members: members)
        var g: Int64 = 0
        for (i, m) in members.enumerated() {
            #expect(try t.locate(globalMs: g).memberIndex == i)
            #expect(try t.locate(globalMs: g + m.durationMs - 1).memberIndex == i)
            g += m.durationMs
        }
    }

    // MARK: T14 ordering

    @Test func T14_tagOrderWinsAndDisagreementWithFileNamesRequiresConfirmation() {
        let candidates = Fixtures.multi.map { MemberCandidate(fileName: $0.name, trackNumber: $0.track, trackTotal: 4) }
        let p = MemberOrdering.propose(candidates)
        #expect(p.basis == .embeddedTags)
        #expect(p.order.map { candidates[$0].fileName } == ["Part 2.mp3", "Part 1.mp3", "Part 3.mp3", "Part 10.mp3"])
        #expect(p.issues == [.tagAndFileNameOrderDisagree])
        #expect(p.requiresConfirmation)
    }

    @Test func T14_naturalFileNameOrderWithoutTags() {
        let names = ["Part 10.mp3", "Part 2.mp3", "part 1.mp3", "Part 3.mp3", "Part 02b.mp3"]
        let p = MemberOrdering.propose(names.map { MemberCandidate(fileName: $0) })
        #expect(p.basis == .naturalFileName)
        #expect(p.order.map { names[$0] } == ["part 1.mp3", "Part 2.mp3", "Part 02b.mp3", "Part 3.mp3", "Part 10.mp3"])
        #expect(p.issues.isEmpty)  // the preview is still shown; nothing contradicts it
    }

    @Test func T14_missingDuplicateAndAbsentTracksAreIdentified() {
        let c = [
            MemberCandidate(fileName: "01.mp3", trackNumber: 1, trackTotal: 5),
            MemberCandidate(fileName: "02.mp3", trackNumber: 2, trackTotal: 5),
            MemberCandidate(fileName: "02 copy.mp3", trackNumber: 2, trackTotal: 5),
            MemberCandidate(fileName: "bonus.mp3"),
            MemberCandidate(fileName: "05.mp3", trackNumber: 5, trackTotal: 5),
        ]
        let p = MemberOrdering.propose(c)
        #expect(p.basis == .naturalFileName)
        #expect(p.issues.contains(.missingTrackNumbers(fileNames: ["bonus.mp3"])))
        #expect(p.issues.contains(.duplicateTrackNumber(disc: 1, track: 2, fileNames: ["02.mp3", "02 copy.mp3"])))
        #expect(p.issues.contains(.absentTracks(disc: 1, ranges: [3...4])))
        #expect(p.requiresConfirmation)
    }

    /// Review R5-03: track numbers and totals come from tags (an ID3 TRCK frame is text and can hold any decimal), so
    /// the absent tracks are ranges, computed in time and memory proportional to the number of files, whatever the
    /// tags state. Before the fix a stated total of Int.max listed every number up to it.
    @Test(.timeLimit(.minutes(1)))
    func T14_absentTracksFromUntrustedTagsAreBoundedRanges() {
        let huge = [
            MemberCandidate(fileName: "a.mp3", trackNumber: 1, trackTotal: Int.max),
            MemberCandidate(fileName: "b.mp3", trackNumber: 2, trackTotal: Int.max),
            MemberCandidate(fileName: "c.mp3", trackNumber: 1_000_000_000_000, trackTotal: 3),
        ]
        let p = MemberOrdering.propose(huge)
        #expect(p.issues.contains(.absentTracks(disc: 1, ranges: [3...999_999_999_999, 1_000_000_000_001...Int.max])))
        #expect(p.requiresConfirmation)
        #expect(p.order.map { huge[$0].fileName } == ["a.mp3", "b.mp3", "c.mp3"])
        // A track numbered Int.max (no overflow past it), numbers below 1 (not track numbers) and a gap at the start.
        let edges = [
            MemberCandidate(fileName: "x.mp3", trackNumber: Int.max),
            MemberCandidate(fileName: "y.mp3", trackNumber: 0),
            MemberCandidate(fileName: "z.mp3", trackNumber: -7),
        ]
        #expect(MemberOrdering.propose(edges).issues.contains(.absentTracks(disc: 1, ranges: [1...(Int.max - 1)])))
        #expect(MemberOrdering.absentRanges(present: [-7, 0, Int.max], upper: Int.max) == [1...(Int.max - 1)])
        #expect(MemberOrdering.absentRanges(present: [1, 2, 3], upper: 3).isEmpty)
        #expect(MemberOrdering.absentRanges(present: [2, 4], upper: 6) == [1...1, 3...3, 5...6])
        #expect(MemberOrdering.absentRanges(present: [], upper: 0).isEmpty)
        // Random tags: the issue never holds more ranges than files plus one per disc.
        var rng = SeededRNG(seed: 503)
        for _ in 0..<300 {
            let n = Int(rng.next() % 12) + 1
            let c = (0..<n).map { i in
                MemberCandidate(fileName: "\(i).mp3", trackNumber: Int(truncatingIfNeeded: rng.next()) % 1_000_000_000_000,
                                trackTotal: rng.next() % 2 == 0 ? Int(truncatingIfNeeded: rng.next()) : nil,
                                discNumber: rng.next() % 3 == 0 ? Int(rng.next() % 3) : nil)
            }
            for case let .absentTracks(_, ranges) in MemberOrdering.propose(c).issues {
                #expect(ranges.count <= n + 1)
                // Ascending and separated by at least one number that is present.
                #expect(zip(ranges, ranges.dropFirst()).allSatisfy { $0.upperBound < $1.lowerBound - 1 })
            }
        }
    }

    @Test func T14_discNumbersOrderBeforeTracks() {
        let c = [
            MemberCandidate(fileName: "a", trackNumber: 1, discNumber: 2),
            MemberCandidate(fileName: "b", trackNumber: 2, discNumber: 1),
            MemberCandidate(fileName: "c", trackNumber: 1, discNumber: 1),
        ]
        let p = MemberOrdering.propose(c)
        #expect(p.order.map { c[$0].fileName } == ["c", "b", "a"])
        #expect(p.basis == .embeddedTags)
    }

    @Test func T14_orderIsStableUnderRandomInputPermutations() {
        let base = Fixtures.multi.map { MemberCandidate(fileName: $0.name, trackNumber: $0.track, trackTotal: 4) }
        var rng = SeededRNG(seed: 14)
        for _ in 0..<200 {
            let shuffled = base.shuffled(using: &rng)
            let p = MemberOrdering.propose(shuffled)
            #expect(p.order.map { shuffled[$0].fileName } == ["Part 2.mp3", "Part 1.mp3", "Part 3.mp3", "Part 10.mp3"])
        }
        let names = (1...120).map { "Chapter \($0).mp3" }
        for _ in 0..<50 {
            let shuffled = names.shuffled(using: &rng)
            let p = MemberOrdering.propose(shuffled.map { MemberCandidate(fileName: $0) })
            #expect(p.order.map { shuffled[$0] } == names)
        }
    }
}

/// Deterministic generator for property tests.
struct SeededRNG: RandomNumberGenerator {
    var state: UInt64
    init(seed: UInt64) { state = seed &* 0x9E37_79B9_7F4A_7C15 | 1 }
    mutating func next() -> UInt64 {
        state ^= state << 13
        state ^= state >> 7
        state ^= state << 17
        return state
    }
}
