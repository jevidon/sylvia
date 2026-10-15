import Foundation

/// What the importer knows about one file of a multi-file audiobook before the user confirms the order (plan 8.3).
public struct MemberCandidate: Hashable, Sendable {
    public var fileName: String
    public var trackNumber: Int?
    public var trackTotal: Int?
    public var discNumber: Int?
    public init(fileName: String, trackNumber: Int? = nil, trackTotal: Int? = nil, discNumber: Int? = nil) {
        self.fileName = fileName
        self.trackNumber = trackNumber
        self.trackTotal = trackTotal
        self.discNumber = discNumber
    }
}

/// The importer's proposed order. The user confirms or edits it; the confirmed order becomes timeline revision 1.
public struct OrderProposal: Equatable, Sendable {
    public enum Basis: String, Equatable, Sendable {
        /// Every file has a unique (disc, track) pair: ordered by the embedded tags.
        case embeddedTags
        /// Tags are absent, incomplete or duplicated: ordered by natural file-name order.
        case naturalFileName
    }
    public enum Issue: Equatable, Sendable {
        /// Embedded track order and natural file-name order disagree.
        case tagAndFileNameOrderDisagree
        case missingTrackNumbers(fileNames: [String])
        case duplicateTrackNumber(disc: Int, track: Int, fileNames: [String])
        /// Track numbers that the tags imply but no selected file carries (gaps, or numbers up to a stated total), as
        /// ascending, disjoint ranges: `[3...4]` means tracks 3 and 4 are absent. Ranges, not a list of numbers, because
        /// the numbers come from tags (review R5-03): a tag can state any total, and the issue must stay as small as
        /// the number of files.
        case absentTracks(disc: Int, ranges: [ClosedRange<Int>])
    }
    /// Indices into the candidate array, in proposed playback order.
    public var order: [Int]
    public var basis: Basis
    public var issues: [Issue]
    /// True whenever the order is not unambiguous. The plan's order preview is always shown; this flag means the
    /// user must actively confirm before the edition becomes ready (T14).
    public var requiresConfirmation: Bool { !issues.isEmpty }
}

public enum MemberOrdering {
    /// Proposes an order: embedded disc/track numbers first, then natural file-name order (plan 8.3).
    public static func propose(_ candidates: [MemberCandidate]) -> OrderProposal {
        let indices = Array(candidates.indices)
        let byName = indices.sorted { naturalLess(candidates[$0].fileName, candidates[$1].fileName) }
        var issues: [OrderProposal.Issue] = []

        let untagged = indices.filter { candidates[$0].trackNumber == nil }
        if !untagged.isEmpty, untagged.count < candidates.count {
            issues.append(.missingTrackNumbers(fileNames: untagged.map { candidates[$0].fileName }))
        }

        // Duplicate (disc, track) pairs among tagged files.
        var groups: [Pair: [Int]] = [:]
        for i in indices {
            if let t = candidates[i].trackNumber { groups[Pair(disc: candidates[i].discNumber ?? 1, track: t), default: []].append(i) }
        }
        for (pair, members) in groups.sorted(by: { $0.key < $1.key }) where members.count > 1 {
            issues.append(.duplicateTrackNumber(disc: pair.disc, track: pair.track,
                                                fileNames: members.sorted().map { candidates[$0].fileName }))
        }

        // Absent tracks per disc: the numbers from 1 to max(highest track, stated total) that no file carries. Track
        // numbers and totals are read from tags (an ID3 TRCK frame is text and can hold any decimal), so the gaps are
        // derived from the sorted numbers present, as ranges: time and memory grow with the number of files, never
        // with the numbers a tag states (review R5-03).
        let discs = Set(groups.keys.map(\.disc))
        for disc in discs.sorted() {
            let present = Set(groups.keys.filter { $0.disc == disc }.map(\.track)).sorted()
            let total = indices.compactMap { (candidates[$0].discNumber ?? 1) == disc ? candidates[$0].trackTotal : nil }.max() ?? 0
            let gaps = absentRanges(present: present, upper: max(present.last ?? 0, total))
            if !gaps.isEmpty { issues.append(.absentTracks(disc: disc, ranges: gaps)) }
        }

        let fullyTagged = untagged.isEmpty && groups.values.allSatisfy { $0.count == 1 }
        if fullyTagged {
            let byTag = indices.sorted {
                let a = Pair(disc: candidates[$0].discNumber ?? 1, track: candidates[$0].trackNumber!)
                let b = Pair(disc: candidates[$1].discNumber ?? 1, track: candidates[$1].trackNumber!)
                return a < b
            }
            if byTag != byName { issues.insert(.tagAndFileNameOrderDisagree, at: 0) }
            return OrderProposal(order: byTag, basis: .embeddedTags, issues: issues)
        }
        return OrderProposal(order: byName, basis: .naturalFileName, issues: issues)
    }

    /// The numbers in `1...upper` missing from `present` (ascending, any values), as ascending disjoint ranges. Numbers
    /// below 1 are not track numbers and are ignored; nothing overflows at `Int.max`.
    static func absentRanges(present: [Int], upper: Int) -> [ClosedRange<Int>] {
        var gaps: [ClosedRange<Int>] = []
        var next = 1  // the lowest number not yet known to be present or absent
        for t in present where t >= next {
            if t > next { gaps.append(next...(t - 1)) }
            guard t < Int.max else { return gaps }  // every number up to Int.max is accounted for
            next = t + 1
        }
        if next <= upper { gaps.append(next...upper) }
        return gaps
    }

    private struct Pair: Hashable, Comparable {
        var disc: Int
        var track: Int
        static func < (a: Pair, b: Pair) -> Bool { (a.disc, a.track) < (b.disc, b.track) }
    }

    /// Deterministic natural order: runs of ASCII digits compare numerically, other text case-insensitively, and
    /// exact ties fall back to the raw scalars so the order is total and stable across locales.
    public static func naturalLess(_ a: String, _ b: String) -> Bool {
        let ca = chunks(a), cb = chunks(b)
        // Differences that only break ties (leading zeros, letter case) are decided after the whole name.
        var tieBreak: Bool?
        for (x, y) in zip(ca, cb) where x != y {
            switch (x, y) {
            case let (.number(n1, s1), .number(n2, s2)):
                if n1 != n2 { return n1 < n2 }
                if tieBreak == nil { tieBreak = s1.count < s2.count }  // "2" before "02"
            case let (.text(t1), .text(t2)):
                let l1 = t1.lowercased(), l2 = t2.lowercased()
                if l1 != l2 { return l1 < l2 }
                if tieBreak == nil { tieBreak = t1.unicodeScalars.lexicographicallyPrecedes(t2.unicodeScalars) }
            case (.number, .text): return true
            case (.text, .number): return false
            }
        }
        if ca.count != cb.count { return ca.count < cb.count }
        if let tieBreak { return tieBreak }
        return a.unicodeScalars.lexicographicallyPrecedes(b.unicodeScalars)
    }

    private enum Chunk: Equatable {
        case number(Decimal, String)
        case text(String)
    }

    private static func chunks(_ s: String) -> [Chunk] {
        var result: [Chunk] = []
        var current = ""
        var inDigits = false
        func flush() {
            guard !current.isEmpty else { return }
            result.append(inDigits ? .number(Decimal(string: current) ?? 0, current) : .text(current))
            current = ""
        }
        for ch in s {
            let isDigit = ch.isASCII && ch.isNumber
            if isDigit != inDigits { flush(); inDigits = isDigit }
            current.append(ch)
        }
        flush()
        return result
    }
}
