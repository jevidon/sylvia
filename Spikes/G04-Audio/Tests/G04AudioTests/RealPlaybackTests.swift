import AVFoundation
import Foundation
import MediaPlayer
import Testing
@testable import G04AudioKit

/// The multi-file fixture book as an edition, in confirmed (embedded-tag) order. Its global timeline equals
/// master-long time, because the members are consecutive slices of master-long.
@MainActor
struct RealEdition {
    /// How the members are opened (ADR-0006 decision 2). `.precise` for every member (the default of the suites that
    /// measure the precise path), or `.asImported`: each member's own import decision, which for these constant-bit-rate
    /// MP3 files is estimated timing (the per-file timing mode, review R4-01).
    enum Timing: String, Sendable, CaseIterable { case precise, asImported }

    let timeline: EditionTimeline
    let urls: [UUID: URL]
    let ids: [UUID]

    init(timing: Timing = .precise) async throws {
        var members: [EditionMember] = []
        var urls: [UUID: URL] = [:]
        var ids: [UUID] = []
        for m in Fixtures.multi {
            let url = try Fixtures.url("multi/\(m.name)")
            let report = try await AssetInspector.inspect(url)
            let id = UUID()
            members.append(EditionMember(assetID: id, fileName: m.name, durationMs: try #require(report.preciseDurationMs),
                                         timing: timing == .asImported ? report.timing : .precise))
            urls[id] = url
            ids.append(id)
        }
        timeline = try EditionTimeline(editionID: UUID(), members: members)
        self.urls = urls
        self.ids = ids
    }

    /// The members' timing modes, for the label of a table line ("precise" or "estimatedCBR" for each member).
    var timingLabel: String { timeline.members.map(\.timing.rawValue).joined(separator: ",") }

    func resolver(missing: Set<Int> = [], replace: [Int: URL] = [:]) -> @Sendable (UUID) -> URL? {
        let ids = ids, urls = urls
        return { id in
            guard let i = ids.firstIndex(of: id), !missing.contains(i) else { return nil }
            return replace[i] ?? urls[id]
        }
    }
}

/// A playback service over the real AVQueuePlayer engine, with an analysis tap on every item it creates.
@MainActor
final class RealPlayer {
    let engine = TestAudio.engine()
    let preview = TestAudio.previewPlayer()
    /// The real audio session (.playback, spoken audio, long-form route sharing).
    let session = SystemAudioSession()
    let store: any PositionStore
    let service: PlaybackService
    /// One collector per member index (the latest item created for that member).
    private(set) var collectors: [Int: AudioTapCollector] = [:]
    /// One collector per preview segment index (the latest preview).
    private(set) var previewCollectors: [Int: AudioTapCollector] = [:]
    private(set) var tapErrors: [String] = []

    init(store: (any PositionStore)? = nil) {
        self.store = store ?? InMemoryPositionStore()
        service = PlaybackService(engine: engine, previewPlayer: preview, session: session, positions: self.store)
        engine.itemPreparer = { [unowned self] item, index in
            let c = AudioTapCollector()
            self.collectors[index] = c
            do { try AudioTap.attach(to: item, trackID: 1, collector: c) } catch { self.tapErrors.append("\(error)") }
        }
        preview.itemPreparer = { [unowned self] item, index in
            if index == 0 { self.previewCollectors.removeAll() }
            let c = AudioTapCollector()
            self.previewCollectors[index] = c
            do { try AudioTap.attach(to: item, trackID: 1, collector: c) } catch { self.tapErrors.append("\(error)") }
        }
    }

    var memory: InMemoryPositionStore { store as! InMemoryPositionStore }

    /// Polls `condition` every 20 ms for up to `seconds`.
    func wait(_ seconds: Double, until condition: () -> Bool) async throws -> Bool {
        let deadline = ProcessInfo.processInfo.systemUptime + seconds
        while ProcessInfo.processInfo.systemUptime < deadline {
            if condition() { return true }
            try await Task.sleep(for: .milliseconds(20))
        }
        return condition()
    }

    func stop() {
        service.pause()
        engine.player.removeAllItems()
        preview.stop()
    }
}

/// Zero crossings per second / 2 over a steady tone.
func toneFrequency(_ x: [Float], rate: Double) -> Double {
    var crossings = 0
    var positive = (x.first ?? 0) >= 0
    for s in x {
        if positive, s < -0.05 { positive = false; crossings += 1 } else if !positive, s > 0.05 { positive = true; crossings += 1 }
    }
    return Double(crossings) / 2 / (Double(x.count) / rate)
}

extension RealAV {
    @Suite("Playback service with the real AVQueuePlayer engine (T18-T20, T22)", .serialized)
    @MainActor
    struct RealPlaybackTests {
        /// Rate and pitch: media time advances at the selected rate, and a post-effects tap on a 1 kHz tone shows
        /// whether the time-pitch stage keeps the pitch. `.varispeed` (which does not preserve pitch) is the control:
        /// it shows that the tap sits after the stage that changes pitch.
        @Test("Rate 0.5x-3x advances media time at the rate; time-domain algorithm keeps the pitch", .timeLimit(.minutes(5)))
        func rateAndPitch() async throws {
            let url = try Fixtures.url("tone-1khz-60s.m4a")
            var lines = ["# Rate and pitch on tone-1khz-60s.m4a (post-effects tap). Environment: \(Results.environmentLabel())",
                         "algorithm\trate\tmedia_advance_per_wall_s\ttap_rate_hz\tmeasured_tone_hz"]
            defer { Results.write("rate-pitch.txt", lines) }
            var observed: [String: Double] = [:]
            for algorithm in [AVAudioTimePitchAlgorithm.timeDomain, .varispeed] {
                for rate in [Float(0.5), 1, 2, 3] {
                    let item = AVPlayerItem(asset: AssetInspector.preciseAsset(url))
                    item.audioTimePitchAlgorithm = algorithm
                    let collector = AudioTapCollector()
                    try await AudioTap.attach(to: item, collector: collector, postEffects: true)
                    let player = TestAudio.player(item)
                    player.automaticallyWaitsToMinimizeStalling = false
                    for _ in 0..<200 where item.status == .unknown { try await Task.sleep(for: .milliseconds(25)) }
                    #expect(item.status == .readyToPlay)
                    _ = await player.seek(to: CMTime(seconds: 5, preferredTimescale: 600), toleranceBefore: .zero, toleranceAfter: .zero)
                    player.playImmediately(atRate: rate)
                    try await Task.sleep(for: .seconds(1))  // settle
                    collector.reset()
                    let m0 = player.currentTime().seconds, w0 = ProcessInfo.processInfo.systemUptime
                    try await Task.sleep(for: .seconds(3))
                    let m1 = player.currentTime().seconds, w1 = ProcessInfo.processInfo.systemUptime
                    player.pause()
                    let advance = (m1 - m0) / (w1 - w0)
                    let samples = collector.snapshot().flatMap(\.samples)
                    let freq = toneFrequency(samples, rate: collector.sampleRate)
                    observed["\(algorithm.rawValue)@\(rate)"] = freq
                    lines.append("\(algorithm.rawValue)\t\(rate)\t\(String(format: "%.3f", advance))\t\(Int(collector.sampleRate))\t\(String(format: "%.1f", freq))")
                    #expect(abs(advance - Double(rate)) <= 0.1 * Double(rate), "media advance \(advance) at rate \(rate)")
                    // Pitch: kept at 1 kHz by the time-domain algorithm; scaled by the rate with varispeed (the control
                    // that shows the tap sits after the time-pitch stage).
                    let expectedHz = algorithm == .timeDomain ? 1_000 : 1_000 * Double(rate)
                    #expect(abs(freq - expectedHz) <= 0.02 * expectedHz, "\(algorithm.rawValue) at \(rate)x: \(freq) Hz")
                    player.replaceCurrentItem(with: nil)
                }
            }
            #expect(observed.count == 8)
        }
    }
}
