import Foundation

/// A point in one audio asset, in asset-local milliseconds (plan 7.5). This is the canonical audio anchor unit:
/// it never depends on the order of the members of a multi-file edition.
public struct AudioPoint: Codable, Hashable, Sendable {
    public var assetID: UUID
    public var ms: Int64
    public init(assetID: UUID, ms: Int64) {
        self.assetID = assetID
        self.ms = ms
    }
}

/// A half-open range `[startMs, endMs)` in one audio asset (plan 7.5). A selection that crosses a file boundary is
/// stored as several ordered `AudioRange`s.
public struct AudioRange: Codable, Hashable, Sendable {
    public var assetID: UUID
    public var startMs: Int64
    public var endMs: Int64
    public init(assetID: UUID, startMs: Int64, endMs: Int64) {
        self.assetID = assetID
        self.startMs = startMs
        self.endMs = endMs
    }
    public var durationMs: Int64 { endMs - startMs }
}

/// One file of an edition.
public struct EditionMember: Codable, Hashable, Sendable {
    public var assetID: UUID
    public var fileName: String
    public var durationMs: Int64
    /// How the player, preview and export open this file, decided at import (ADR-0006 decision 2): estimated timing
    /// only for an MP3 proved constant bit rate.
    public var timing: AssetTiming
    public init(assetID: UUID, fileName: String, durationMs: Int64, timing: AssetTiming = .precise) {
        self.assetID = assetID
        self.fileName = fileName
        self.durationMs = durationMs
        self.timing = timing
    }

    enum CodingKeys: String, CodingKey { case assetID, fileName, durationMs, timing }

    /// A member stored before the timing mode existed opens with precise timing.
    public init(from decoder: any Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        assetID = try c.decode(UUID.self, forKey: .assetID)
        fileName = try c.decode(String.self, forKey: .fileName)
        durationMs = try c.decode(Int64.self, forKey: .durationMs)
        timing = try c.decodeIfPresent(AssetTiming.self, forKey: .timing) ?? .precise
    }
}

public enum TimelineError: Error, Equatable, Sendable {
    case empty
    case nonPositiveDuration(fileName: String)
    case duplicateAsset(UUID)
    case positionOutOfRange(Int64)
    case unknownAsset(UUID)
    case localPositionOutOfRange(assetID: UUID, ms: Int64)
    case notAPermutation
    case emptyRange
}

/// The ordered manifest of an edition and the derived global timeline used for display (plan 10.1). Canonical
/// anchors stay file-local (`AudioPoint`, `AudioRange`); the global timeline is a view that changes revision when
/// the member order changes, and old captures keep pointing at the same files and ranges.
public struct EditionTimeline: Codable, Hashable, Sendable {
    public let editionID: UUID
    public let revision: Int
    public let members: [EditionMember]
    /// Global start of each member, in milliseconds. `starts[i]` is the sum of the durations before member `i`.
    public let starts: [Int64]

    public init(editionID: UUID, revision: Int = 1, members: [EditionMember]) throws {
        guard !members.isEmpty else { throw TimelineError.empty }
        var seen = Set<UUID>()
        var starts: [Int64] = []
        var total: Int64 = 0
        for member in members {
            guard member.durationMs > 0 else { throw TimelineError.nonPositiveDuration(fileName: member.fileName) }
            guard seen.insert(member.assetID).inserted else { throw TimelineError.duplicateAsset(member.assetID) }
            starts.append(total)
            total += member.durationMs
        }
        self.editionID = editionID
        self.revision = revision
        self.members = members
        self.starts = starts
    }

    public var durationMs: Int64 { starts[starts.count - 1] + members[members.count - 1].durationMs }

    public func index(of assetID: UUID) -> Int? { members.firstIndex { $0.assetID == assetID } }

    /// Maps a global position to the member that plays it. The end of the timeline maps to the end of the last member.
    public func locate(globalMs: Int64) throws -> (memberIndex: Int, point: AudioPoint) {
        guard globalMs >= 0, globalMs <= durationMs else { throw TimelineError.positionOutOfRange(globalMs) }
        // Last member whose start is <= globalMs (binary search: editions may have hundreds of members).
        var lo = 0, hi = members.count - 1
        while lo < hi {
            let mid = (lo + hi + 1) / 2
            if starts[mid] <= globalMs { lo = mid } else { hi = mid - 1 }
        }
        return (lo, AudioPoint(assetID: members[lo].assetID, ms: globalMs - starts[lo]))
    }

    public func globalMs(of point: AudioPoint) throws -> Int64 {
        guard let i = index(of: point.assetID) else { throw TimelineError.unknownAsset(point.assetID) }
        guard point.ms >= 0, point.ms <= members[i].durationMs else {
            throw TimelineError.localPositionOutOfRange(assetID: point.assetID, ms: point.ms)
        }
        return starts[i] + point.ms
    }

    /// Splits a global range into ordered file-local ranges (plan 7.5, 10.2). Empty pieces are dropped.
    public func ranges(globalStartMs: Int64, globalEndMs: Int64) throws -> [AudioRange] {
        guard globalStartMs < globalEndMs else { throw TimelineError.emptyRange }
        guard globalStartMs >= 0 else { throw TimelineError.positionOutOfRange(globalStartMs) }
        guard globalEndMs <= durationMs else { throw TimelineError.positionOutOfRange(globalEndMs) }
        var result: [AudioRange] = []
        for (i, member) in members.enumerated() {
            let memberStart = starts[i], memberEnd = starts[i] + member.durationMs
            let s = max(globalStartMs, memberStart), e = min(globalEndMs, memberEnd)
            if s < e { result.append(AudioRange(assetID: member.assetID, startMs: s - memberStart, endMs: e - memberStart)) }
        }
        return result
    }

    /// The global span of stored file-local ranges under this revision, or nil when the ranges are no longer
    /// contiguous in this order (for example after a reorder). The ranges themselves never change.
    public func globalSpan(of ranges: [AudioRange]) throws -> (startMs: Int64, endMs: Int64)? {
        guard let first = ranges.first else { return nil }
        let start = try globalMs(of: AudioPoint(assetID: first.assetID, ms: first.startMs))
        var cursor = start
        for r in ranges {
            let s = try globalMs(of: AudioPoint(assetID: r.assetID, ms: r.startMs))
            guard s == cursor else { return nil }
            cursor = s + r.durationMs
        }
        return (start, cursor)
    }

    /// A new revision with the members in a confirmed new order (plan 8.3, 10.1). `order` lists asset IDs.
    public func reordered(_ order: [UUID]) throws -> EditionTimeline {
        guard order.count == members.count, Set(order) == Set(members.map(\.assetID)) else {
            throw TimelineError.notAPermutation
        }
        let byID = Dictionary(uniqueKeysWithValues: members.map { ($0.assetID, $0) })
        return try EditionTimeline(editionID: editionID, revision: revision + 1, members: order.map { byID[$0]! })
    }
}
