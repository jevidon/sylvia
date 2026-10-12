// Runs inside the harness app on the simulator against the generated >4 GiB pack on the host file system.
// The CI drop-in passes the path as TEST_RUNNER_G03_LARGE_PACK (xcodebuild forwards it without the prefix).
// The test fails, never skips, when the path is missing.
import Darwin
import Foundation
import SylviaImportHandoff
import SylviaIntakeCore
import SylviaPack
import Testing

private func largePack() throws -> URL {
    let path = try #require(ProcessInfo.processInfo.environment["G03_LARGE_PACK"],
                            "set TEST_RUNNER_G03_LARGE_PACK to Scripts/fixtures/generate-g03-intake-pack.sh output")
    let url = URL(fileURLWithPath: path)
    try #require(FileManager.default.fileExists(atPath: url.path), "large pack not found at \(path)")
    return url
}

/// Signed difference in MiB ("+1.2 MiB" / "-0.3 MiB"); the sampled peak can sit below an earlier baseline.
private func deltaMiB(_ value: UInt64, _ baseline: UInt64) -> String {
    String(format: "%+.1f MiB", (Double(value) - Double(baseline)) / 1_048_576)
}

private func secondsSince(_ start: ContinuousClock.Instant) -> Double {
    let d = ContinuousClock.now - start
    return Double(d.components.seconds) + Double(d.components.attoseconds) / 1e18
}

@Suite("large pack in the simulator (T42 simulator half)", .serialized)
struct SimulatorLargePackTests {
    @Test("validate and extract the >4 GiB pack with bounded memory")
    func validateAndExtract() async throws {
        let pack = try largePack()
        let size = try #require(try FileManager.default.attributesOfItem(atPath: pack.path)[.size] as? NSNumber).uint64Value
        #expect(size > 4 << 30)

        let baseline = MemorySample.now().physFootprint
        let sampler = FootprintSampler()
        sampler.start()
        var start = ContinuousClock.now
        let validated = try await PackReader().validate(pack)
        let validateSeconds = secondsSince(start)
        let validatePeak = sampler.stop()
        #expect(validated.usesZIP64)
        print("G03-EVIDENCE simulator validate: \(size) bytes, \(validated.entryCount) entries, \(String(format: "%.1f", validateSeconds))s, phys_footprint before \(mib(baseline)), sampled peak \(mib(validatePeak)) (\(deltaMiB(validatePeak, baseline)))")

        let destination = FileManager.default.temporaryDirectory.appendingPathComponent("g03-extract-\(UUID().uuidString)")
        defer { Durability.removeTree(destination) }
        let extractSampler = FootprintSampler()
        extractSampler.start()
        start = ContinuousClock.now
        _ = try await PackReader().extract(pack, to: destination)
        let extractSeconds = secondsSince(start)
        let extractPeak = extractSampler.stop()
        let big = destination.appendingPathComponent("Generated Audiobook/part-01.caf")
        let bigSize = try #require(try FileManager.default.attributesOfItem(atPath: big.path)[.size] as? NSNumber).uint64Value
        #expect(bigSize > 4 << 30)
        print("G03-EVIDENCE simulator extract: \(String(format: "%.1f", extractSeconds))s, part-01.caf \(bigSize) bytes, sampled peak phys_footprint \(mib(extractPeak)) (\(deltaMiB(extractPeak, baseline)) over the pre-validation baseline); lifetime \(MemorySample.now())")
        #expect(Int64(validatePeak) - Int64(baseline) < 16 << 20 && Int64(extractPeak) - Int64(baseline) < 16 << 20, "memory must not grow with the bundle size")
    }

    @Test("truncated and zero-padded copies of the >4 GiB pack are rejected")
    func truncatedCopies() async throws {
        let pack = try largePack()
        let size = try #require(try FileManager.default.attributesOfItem(atPath: pack.path)[.size] as? NSNumber).uint64Value
        let work = FileManager.default.temporaryDirectory.appendingPathComponent("g03-cuts-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: work, withIntermediateDirectories: true)
        defer { Durability.removeTree(work) }
        var cuts: [UInt64] = [0, 22, 4 << 30, (4 << 30) + 1, size - 23, size - 22, size - 21, size - 42, size - 98, size / 2]
        for i in 1...30 { cuts.append(size * UInt64(i) / 31) }
        var rejected = 0
        var codes: [String: Int] = [:]
        let candidate = work.appendingPathComponent("cut.sylviapack")
        for cut in cuts {
            for padded in [false, true] {
                try? FileManager.default.removeItem(at: candidate)
                try #require(clonefile(pack.path, candidate.path, 0) == 0, "clonefile (APFS) failed: errno \(errno)")
                try #require(truncate(candidate.path, off_t(cut)) == 0)
                if padded { try #require(truncate(candidate.path, off_t(size)) == 0) }
                do {
                    _ = try await PackReader().validate(candidate)
                    Issue.record("accepted a copy cut at \(cut) (padded=\(padded))")
                } catch {
                    rejected += 1
                    codes[error.code.rawValue, default: 0] += 1
                }
            }
        }
        print("G03-EVIDENCE simulator truncation: \(rejected) of \(cuts.count * 2) partial copies rejected; codes \(codes)")
        #expect(rejected == cuts.count * 2)
    }

    @Test("a 4.5 GiB file through the share extension's write routine into the real App Group inbox, bounded memory")
    func multiGiBHandoff() throws {
        let pack = try largePack()
        let source = pack.deletingLastPathComponent().appendingPathComponent("work/part-01.caf")
        try #require(FileManager.default.fileExists(atPath: source.path))
        let group = try #require(FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: "group.com.jevidon.sylvia.spike"))
        // Same App Group volume and routine as the extension, but a test-only inbox the harness app never scans.
        let inbox = group.appendingPathComponent("Intake/TestHandoffs", isDirectory: true)
        let baseline = MemorySample.now().physFootprint
        let sampler = FootprintSampler()
        sampler.start()
        let start = ContinuousClock.now
        let result = try HandoffSession.run(
            environment: HandoffEnvironment(inbox: inbox, producerBundleIdentifier: "com.jevidon.sylvia.spike.intake.tests", producerBuildVersion: "1"),
            files: [(source, "com.apple.coreaudio-format")])
        let seconds = secondsSince(start)
        let peak = sampler.stop()
        let receipt = try result.get()
        defer { Durability.removeTree(inbox.appendingPathComponent(receipt.handoffID.uuidString)) }
        print("G03-EVIDENCE simulator handoff copy: \(receipt.totalBytes) bytes in \(String(format: "%.1f", seconds))s, phys_footprint before \(mib(baseline)), sampled peak \(mib(peak)) (\(deltaMiB(peak, baseline)))")
        #expect(receipt.totalBytes > 4 << 30)
        #expect(Int64(peak) - Int64(baseline) < 16 << 20, "the copy must not grow memory with the file size")
    }
}
