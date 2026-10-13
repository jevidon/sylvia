import Foundation

/// What removing a source file would do to captures that reference it (plan 10.2, 17.2; T23).
public struct SourceRemovalImpact: Equatable, Sendable {
    /// Captures whose excerpt is pending or failed: removing the source loses their audio, so removal needs an
    /// explicit warning and choice.
    public var unpreservedCaptures: [UUID]
    /// Captures whose excerpt is retained: they stay playable after the source is removed.
    public var preservedCaptures: [UUID]
    public var requiresExplicitChoice: Bool { !unpreservedCaptures.isEmpty }
}

public enum CaptureError: Error, Equatable, Sendable {
    case unknownCapture(UUID)
    case notAnAudioCapture
    case storeFailed(String)
    case range(CaptureRange.RangeError)
    case timeline(TimelineError)
}

/// The capture transaction for audio (plan 10.2, 11.1). The anchor and note are committed durably first and only
/// then is the excerpt exported; every state change is itself a durable commit, so the status key a caller shows
/// is always the stored state.
public actor CaptureService {
    public typealias SourceResolver = @Sendable (UUID) -> URL?
    /// The timing mode the import chose for an asset (ADR-0006 decision 2); the export opens the source with it.
    public typealias TimingResolver = @Sendable (UUID) -> AssetTiming

    private let store: any CaptureStore
    private let exporter: any ExcerptExporting
    private let resolveSource: SourceResolver
    private let resolveTiming: TimingResolver
    private let now: @Sendable () -> Int64
    /// The export running for each capture. One export per capture at a time: a second request (a retry, or a new
    /// range from `setRange`) waits for the running one and then exports what the record says.
    private var inFlight: [UUID: Task<CaptureRecord, any Error>] = [:]

    public init(store: any CaptureStore, exporter: any ExcerptExporting,
                resolveSource: @escaping SourceResolver, resolveTiming: @escaping TimingResolver = { _ in .precise },
                now: @escaping @Sendable () -> Date = Date.init) {
        self.store = store
        self.exporter = exporter
        self.resolveSource = resolveSource
        self.resolveTiming = resolveTiming
        self.now = { Int64((now().timeIntervalSince1970 * 1000).rounded(.down)) }
    }

    // MARK: Commands

    /// Saves a bookmark (a position only). Durable before it returns. Synchronous and nonisolated so that a caller
    /// that must answer synchronously (an MPRemoteCommand handler) can acknowledge only after the durable write.
    public nonisolated func bookmark(timeline: EditionTimeline, atGlobalMs globalMs: Int64, note: String?,
                         idempotencyKey: String, origin: String = "player") throws -> CaptureRecord {
        let point: AudioPoint
        do { point = try timeline.locate(globalMs: min(max(globalMs, 0), timeline.durationMs)).point } catch let e as TimelineError { throw CaptureError.timeline(e) }
        let t = now()
        let record = CaptureRecord(id: UUID(), idempotencyKey: idempotencyKey, kind: .bookmark, editionID: timeline.editionID,
                                   timelineRevision: timeline.revision, point: point, ranges: [], note: note,
                                   excerpt: .notRequested, createdAtMs: t, updatedAtMs: t, origin: origin)
        return try insert(record)
    }

    /// Captures the preceding 30 seconds (clamped). Writes the anchor and note durably and returns with the
    /// excerpt pending; call `preserveExcerpt` next. Synchronous and nonisolated for the same reason as `bookmark`.
    public nonisolated func captureAudio(timeline: EditionTimeline, atGlobalMs globalMs: Int64, note: String?,
                             idempotencyKey: String, origin: String = "player") throws -> CaptureRecord {
        let span = CaptureRange.preceding(globalMs: globalMs, durationMs: timeline.durationMs)
        let ranges: [AudioRange]
        do { ranges = try timeline.ranges(globalStartMs: span.start, globalEndMs: span.end) } catch let e as TimelineError { throw CaptureError.timeline(e) }
        let t = now()
        let record = CaptureRecord(id: UUID(), idempotencyKey: idempotencyKey, kind: .audio, editionID: timeline.editionID,
                                   timelineRevision: timeline.revision, point: nil, ranges: ranges, note: note,
                                   excerpt: .pending, createdAtMs: t, updatedAtMs: t, origin: origin)
        return try insert(record)
    }

    /// Sets the capture range from the range handles or the numeric start/end controls (plan 10.2, 18.3), in
    /// global milliseconds of the given timeline. The excerpt returns to pending; the old excerpt file stays until
    /// a new export replaces it.
    public func setRange(_ id: UUID, timeline: EditionTimeline, globalStartMs: Int64, globalEndMs: Int64) throws -> CaptureRecord {
        guard var record = try store.record(id) else { throw CaptureError.unknownCapture(id) }
        guard record.kind == .audio else { throw CaptureError.notAnAudioCapture }
        do { try CaptureRange.validate(startMs: globalStartMs, endMs: globalEndMs, durationMs: timeline.durationMs) } catch let e as CaptureRange.RangeError { throw CaptureError.range(e) }
        do { record.ranges = try timeline.ranges(globalStartMs: globalStartMs, globalEndMs: globalEndMs) } catch let e as TimelineError { throw CaptureError.timeline(e) }
        record.timelineRevision = timeline.revision
        record.excerpt = .pending
        record.updatedAtMs = now()
        try commit(record)
        return record
    }

    /// Exports the excerpt and durably records the outcome. A failure keeps the bookmark and note and records
    /// "Excerpt not preserved"; it never deletes anything.
    @discardableResult
    public func preserveExcerpt(_ id: UUID) async throws -> CaptureRecord {
        // Actor reentrancy: wait for any running export of this capture, then start ours with no suspension between
        // the check and the registration, so two exports of one capture never overlap.
        while let running = inFlight[id] {
            _ = await running.result
            if inFlight[id] == running { inFlight[id] = nil }
        }
        let task = Task { try await self.exportOnce(id) }
        inFlight[id] = task
        let result = await task.result
        if inFlight[id] == task { inFlight[id] = nil }
        return try result.get()
    }

    private func exportOnce(_ id: UUID) async throws -> CaptureRecord {
        guard var record = try store.record(id) else { throw CaptureError.unknownCapture(id) }
        guard record.kind == .audio else { throw CaptureError.notAnAudioCapture }
        if case .saved = record.excerpt { return record }
        let previousAttempts: Int
        if case let .failed(_, attempts) = record.excerpt { previousAttempts = attempts } else { previousAttempts = 0 }

        var segments: [SourceSegment] = []
        for r in record.ranges {
            guard let url = resolveSource(r.assetID) else {
                record.excerpt = .failed(reason: "source not on this device", attempts: previousAttempts + 1)
                record.updatedAtMs = now()
                try commit(record)
                return record
            }
            segments.append(SourceSegment(url: url, range: r, timing: resolveTiming(r.assetID)))
        }
        let outcome: ExcerptState
        do {
            outcome = .saved(try await exporter.export(segments, to: store.excerptURL(for: id)))
        } catch {
            outcome = .failed(reason: "\(error)", attempts: previousAttempts + 1)
        }
        // The export suspended this actor. If the range changed meanwhile (setRange), this result describes a range
        // the capture no longer has: keep the newer record as it is (pending) for the export that follows it.
        guard var current = try store.record(id) else { throw CaptureError.unknownCapture(id) }
        guard current.ranges == record.ranges else { return current }
        current.excerpt = outcome
        current.updatedAtMs = now()
        try commit(current)
        return current
    }

    /// "Retry" after "Excerpt not preserved", or for a capture whose export was interrupted (still pending, with no
    /// export running in this process: the app was terminated or crashed between the anchor write and the export
    /// result). A pending capture whose export is running is left to that export.
    @discardableResult
    public func retry(_ id: UUID) async throws -> CaptureRecord {
        guard let record = try store.record(id) else { throw CaptureError.unknownCapture(id) }
        guard canRetry(record) else { return record }
        return try await preserveExcerpt(id)
    }

    /// Whether "Retry" applies: the export failed, or it is pending with no export running in this process.
    public func canRetry(_ record: CaptureRecord) -> Bool {
        if record.canRetryExport { return true }
        return record.excerpt == .pending && record.kind == .audio && inFlight[record.id] == nil
    }

    public func isExportRunning(_ id: UUID) -> Bool { inFlight[id] != nil }

    /// Audio captures left pending by an earlier process: the anchor and note are durable, but no export is running
    /// for them here. Call at launch, before starting new exports, and resume them with `preserveExcerpt`.
    public func interruptedExports() throws -> [UUID] {
        try store.all().filter { $0.kind == .audio && $0.excerpt == .pending && inFlight[$0.id] == nil }.map(\.id)
    }

    public func sourceRemovalImpact(assetID: UUID) throws -> SourceRemovalImpact {
        var unpreserved: [UUID] = [], preserved: [UUID] = []
        for r in try store.all() where r.kind == .audio && r.ranges.contains(where: { $0.assetID == assetID }) {
            if case .saved = r.excerpt { preserved.append(r.id) } else { unpreserved.append(r.id) }
        }
        return SourceRemovalImpact(unpreservedCaptures: unpreserved, preservedCaptures: preserved)
    }

    public func record(_ id: UUID) throws -> CaptureRecord? { try store.record(id) }

    // MARK: Private

    /// Durably inserts a new capture, or returns the one already stored under its idempotency key (atomic in the
    /// store, so a repeated command never creates a duplicate).
    private nonisolated func insert(_ record: CaptureRecord) throws -> CaptureRecord {
        do { return try store.insert(record) } catch { throw CaptureError.storeFailed("\(error)") }
    }

    private func commit(_ record: CaptureRecord) throws {
        do { try store.commit(record) } catch { throw CaptureError.storeFailed("\(error)") }
    }
}
