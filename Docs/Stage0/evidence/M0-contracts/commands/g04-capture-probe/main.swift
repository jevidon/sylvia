// M0 contract consolidation (ADR-0016): run G0.4's own capture code on the host and keep the records it persists,
// so the capture-envelope and anchor schemas are checked against what the audio spike really writes.
//
// Compiled by run-g04-capture-probe.sh together with these files from `m0-g04-audio` (commit named in its log):
// Capture/{CaptureModel,CaptureService,CaptureStore,VocabularyKey}, Timeline/EditionTimeline,
// Excerpt/ExcerptExporter, Media/{PCMDecoder,AssetInspector,ID3Chapters}, Persistence/DurableFile, and, from the commit
// that introduced G0.4's per-file timing mode (ADR-0006 decision 2), Media/{AssetTiming,MP3FrameScanner}. For such a
// commit the runner defines G04_ASSET_TIMING, and the probe passes each member's import decision
// (`AssetReport.timing`) to the timeline and to `CaptureService(resolveTiming:)`, as the G0.4 harness does.
// Nothing here is a copy of spike logic: the probe only calls the spike's public API. `CountingStore` forwards every
// call to G0.4's `FileCaptureStore` unchanged and only counts the durable writes, so the envelope's `revision`
// (1 at creation plus each later durable change) can be taken from what the spike did rather than assumed.
//
// Audio: the probe decodes and encodes only (AVAssetReader, AVAudioFile). It creates no player, no audio session
// and no output node, so nothing is played and the Mac's output is never touched.
//
// Usage: g04-capture-probe <directory with the four-file MP3 book> <output directory>
import CryptoKit
import Foundation

/// Forwards to G0.4's store and counts, per record, the writes that store made durable.
final class CountingStore: CaptureStore, @unchecked Sendable {
    let inner: FileCaptureStore
    private let lock = NSLock()
    private var counts: [UUID: Int] = [:]

    init(_ inner: FileCaptureStore) { self.inner = inner }

    func commit(_ record: CaptureRecord) throws {
        try inner.commit(record)
        count(record.id)
    }

    func insert(_ record: CaptureRecord) throws -> CaptureRecord {
        let stored = try inner.insert(record)
        // A repeated idempotency key returns the record already stored, without writing.
        if stored.id == record.id { count(record.id) }
        return stored
    }

    func record(_ id: UUID) throws -> CaptureRecord? { try inner.record(id) }
    func all() throws -> [CaptureRecord] { try inner.all() }
    func excerptURL(for id: UUID) -> URL { inner.excerptURL(for: id) }

    var writes: [UUID: Int] {
        lock.lock()
        defer { lock.unlock() }
        return counts
    }

    private func count(_ id: UUID) {
        lock.lock()
        counts[id, default: 0] += 1
        lock.unlock()
    }
}

enum Probe {
    static let memberNames = ["Part 1.mp3", "Part 2.mp3", "Part 3.mp3", "Part 10.mp3"]
    /// The origin G0.4 records for its App Shortcut: `CaptureMomentIntent.origin(surface: nil, process:)` with the
    /// harness's bundle identifier, as the G0.4 report's row 18 observed it on the simulator. This command-line probe
    /// has no bundle and does not run the intent, so it passes that string to `captureAudio(origin:)`.
    static let appShortcutOrigin = "intent@com.jevidon.sylvia.spike.g04audio"

    /// Fixed asset and edition IDs, so two runs describe the same assets (capture IDs come from the spike: random).
    static func fixedUUID(_ n: Int) -> UUID { UUID(uuidString: String(format: "00000000-0000-4000-8000-%012x", n))! }

    static func sha256(_ url: URL) throws -> (hex: String, bytes: Int64) {
        let handle = try FileHandle(forReadingFrom: url)
        defer { try? handle.close() }
        var hasher = SHA256()
        var total: Int64 = 0
        while let chunk = try handle.read(upToCount: 1 << 20), !chunk.isEmpty {
            hasher.update(data: chunk)
            total += Int64(chunk.count)
        }
        return (hasher.finalize().map { String(format: "%02x", $0) }.joined(), total)
    }

    static func run(bookDirectory: URL, output: URL) async throws {
        var members: [EditionMember] = []
        var sources: [UUID: URL] = [:]
        var memberRows: [[String: Any]] = []
        #if G04_ASSET_TIMING
        var timings: [UUID: AssetTiming] = [:]
        #endif
        for (i, name) in memberNames.enumerated() {
            let url = bookDirectory.appendingPathComponent(name)
            let report = try await AssetInspector.inspect(url)
            guard let duration = report.preciseDurationMs else { throw ProbeError.noDuration(name) }
            let id = fixedUUID(0x401 + i)
            sources[id] = url
            let digest = try sha256(url)
            let row: [String: Any] = ["asset_id": id.uuidString, "file_name": name, "duration_ms": duration,
                                      "sha256": digest.hex, "byte_count": digest.bytes]
            #if G04_ASSET_TIMING
            members.append(EditionMember(assetID: id, fileName: name, durationMs: duration, timing: report.timing))
            timings[id] = report.timing
            memberRows.append(row.merging(["timing": report.timing.rawValue,
                                           "timing_reason": report.timingDecision.reason]) { $1 })
            #else
            members.append(EditionMember(assetID: id, fileName: name, durationMs: duration))
            memberRows.append(row)
            #endif
        }
        let timeline = try EditionTimeline(editionID: fixedUUID(0x301), members: members)

        let storeDirectory = output.appendingPathComponent("store", isDirectory: true)
        try? FileManager.default.removeItem(at: storeDirectory)
        let fileStore = try FileCaptureStore(directory: storeDirectory)
        let store = CountingStore(fileStore)
        let available = sources
        #if G04_ASSET_TIMING
        let chosen = timings
        let service = CaptureService(store: store, exporter: AACExcerptExporter(), resolveSource: { available[$0] },
                                     resolveTiming: { chosen[$0] ?? .precise })
        #else
        let service = CaptureService(store: store, exporter: AACExcerptExporter(), resolveSource: { available[$0] })
        #endif

        // 1. The default capture (preceding 30 s) inside one file, with a note, from the player.
        let single = try service.captureAudio(timeline: timeline, atGlobalMs: 90_000,
                                              note: "The part about the gods.", idempotencyKey: "m0-contracts-single")
        _ = try await service.preserveExcerpt(single.id)

        // 2. The preceding 30 s at 10 s into Part 2, through the App Shortcut's origin: crosses the Part 1 / Part 2
        //    boundary, so two file-local ranges.
        let cross = try service.captureAudio(timeline: timeline, atGlobalMs: timeline.starts[1] + 10_000, note: nil,
                                             idempotencyKey: "m0-contracts-cross-file", origin: appShortcutOrigin)
        _ = try await service.preserveExcerpt(cross.id)

        // 3. An export that fails because Part 3 is not on this device: the capture and its note stay.
        let missing = members[2].assetID
        let withoutPart3 = sources.filter { $0.key != missing }
        #if G04_ASSET_TIMING
        let failingService = CaptureService(store: store, exporter: AACExcerptExporter(),
                                            resolveSource: { withoutPart3[$0] }, resolveTiming: { chosen[$0] ?? .precise })
        #else
        let failingService = CaptureService(store: store, exporter: AACExcerptExporter(),
                                            resolveSource: { withoutPart3[$0] })
        #endif
        let failed = try failingService.captureAudio(timeline: timeline, atGlobalMs: timeline.starts[2] + 45_000,
                                                     note: "Part 3 was not on this device.",
                                                     idempotencyKey: "m0-contracts-failed")
        _ = try await failingService.preserveExcerpt(failed.id)

        // 4. A capture whose export has not run yet (pending).
        _ = try service.captureAudio(timeline: timeline, atGlobalMs: timeline.starts[3] + 60_000, note: nil,
                                     idempotencyKey: "m0-contracts-pending")

        // 5. A bookmark: a position only, which is not a capture in the envelope (ADR-0016).
        _ = try service.bookmark(timeline: timeline, atGlobalMs: 5_000, note: nil, idempotencyKey: "m0-contracts-bookmark")

        // Keep the records exactly as the store wrote them, the digests of the excerpt files and the write counts.
        let records = output.appendingPathComponent("records", isDirectory: true)
        try? FileManager.default.removeItem(at: records)
        try FileManager.default.createDirectory(at: records, withIntermediateDirectories: true)
        var excerptRows: [[String: Any]] = []
        for record in try store.all() {
            let source = fileStore.recordURL(for: record.id)
            try FileManager.default.copyItem(at: source, to: records.appendingPathComponent(source.lastPathComponent))
            let excerpt = store.excerptURL(for: record.id)
            if FileManager.default.fileExists(atPath: excerpt.path) {
                let digest = try sha256(excerpt)
                excerptRows.append(["capture_id": record.id.uuidString, "file_name": excerpt.lastPathComponent,
                                    "sha256": digest.hex, "byte_count": digest.bytes])
            }
        }
        var writes: [String: Int] = [:]
        for (id, n) in store.writes { writes[id.uuidString] = n }
        let info = ProcessInfo.processInfo
        let context: [String: Any] = [
            "what": "Records written by G0.4's FileCaptureStore through CaptureService and AACExcerptExporter, and facts the spike does not record (member digests, excerpt digests, the number of durable writes the store made per record).",
            "edition_id": timeline.editionID.uuidString,
            "timeline_revision": timeline.revision,
            "members": memberRows,
            "excerpt_files": excerptRows,
            "durable_writes": writes,
            "environment": "host: macOS \(info.operatingSystemVersionString), \(info.processorCount) cores",
            "audio_output": "none: decode and encode only (no player, no audio session)",
        ]
        let data = try JSONSerialization.data(withJSONObject: context, options: [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes])
        try data.write(to: output.appendingPathComponent("context.json"))
        print("records: \(try store.all().count), excerpt files: \(excerptRows.count), durable writes: \(writes.values.reduce(0, +))")
    }
}

enum ProbeError: Error { case usage, noDuration(String) }

let arguments = CommandLine.arguments
guard arguments.count == 3 else {
    FileHandle.standardError.write(Data("usage: g04-capture-probe <book directory> <output directory>\n".utf8))
    exit(2)
}
try await Probe.run(bookDirectory: URL(fileURLWithPath: arguments[1], isDirectory: true),
                    output: URL(fileURLWithPath: arguments[2], isDirectory: true))
