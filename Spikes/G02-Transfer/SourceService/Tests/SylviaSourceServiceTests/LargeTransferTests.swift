import CryptoKit
import Darwin
import Foundation
import Synchronization
import Testing
@_spi(Testing) import SylviaSourceService
@_spi(Testing) import SylviaTransferClient
import SylviaTransferCore
@_spi(Testing) import SylviaBackgroundTransfer

/// T38 at full size: a 5 GiB deterministic file over real TLS on loopback, 16 MiB parts, with repeated
/// connection drops, corrupted parts and two client restarts, while the process's memory is sampled.
/// Environment: host (macOS); source and client run in the same test process.
///
/// Needs the file from Scripts/fixtures/generate-g02-transfer-large.sh. Scripts/ci.d/40-g02-transfer.sh
/// generates it, sets SYLVIA_G02_LARGE_FILE and SYLVIA_G02_LARGE_SHA256, runs this suite in a process of
/// its own (so the kernel's lifetime peak footprint belongs to this test), and fails if it did not run.
@Suite("5 GiB transfer with interruptions and bounded memory (T38)", .serialized)
struct LargeTransferTests {
    static let filePath = ProcessInfo.processInfo.environment["SYLVIA_G02_LARGE_FILE"]
    static let expectedSHA256 = ProcessInfo.processInfo.environment["SYLVIA_G02_LARGE_SHA256"]

    /// The 1, 5 and 15 minute load averages, written next to the timings: other jobs may share this Mac, and
    /// timings taken under that load are indicative only.
    static func loadAverages() -> String {
        var loads = [Double](repeating: 0, count: 3)
        guard getloadavg(&loads, 3) == 3 else { return "unknown" }
        return String(format: "%.2f %.2f %.2f", loads[0], loads[1], loads[2])
    }

    @Test(.enabled(if: filePath != nil, "set SYLVIA_G02_LARGE_FILE; Scripts/ci.d/40-g02-transfer.sh does"))
    func fiveGiBTransferSurvivesInterruptionsWithBoundedMemory() async throws {
        let source = URL(fileURLWithPath: try #require(Self.filePath))
        let expected = try #require(Self.expectedSHA256)
        let length = try #require(try FileManager.default.attributesOfItem(atPath: source.path)[.size] as? NSNumber).int64Value
        #expect(length == 5 * 1_073_741_824)

        let base = FileManager.default.temporaryDirectory.appendingPathComponent("g02-large-\(UUID().uuidString)")
        let root = base.appendingPathComponent("library")
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: base) }  // synchronous: 5 GiB of staging must not linger
        // The shared folder holds an APFS clone of the cached file (no extra space used).
        guard clonefile(source.path, root.appendingPathComponent("large.m4b").path, 0) == 0 else {
            Issue.record("clonefile from the fixture cache failed: errno \(errno)")
            return
        }

        let baseline = MemoryProbe.read()
        let harness = try await Harness.make(partSize: TransferProtocol.defaultPartSize, root: root, state: base.appendingPathComponent("state"))
        let (client, _, _) = try await harness.pairDevice()
        let itemID = try await harness.itemID(titled: "large")
        let staging = base.appendingPathComponent("phone-staging")
        let partSize = TransferProtocol.defaultPartSize
        let partCount = Int((length + partSize - 1) / partSize)

        // Deterministic faults on first attempts only: a dropped connection in every 40th part and a
        // flipped byte in every 97th, offset so they hit different parts.
        let dropped = Set((0..<partCount).filter { $0 % 40 == 7 })
        let corrupted = Set((0..<partCount).filter { $0 % 97 == 50 })
        harness.faults.add { info in
            guard info.attempt == 1, let start = info.range?.lowerBound else { return nil }
            let index = Int(start / partSize)
            if dropped.contains(index) { return .dropAfter(bytes: 5 * 1_048_576) }
            if corrupted.contains(index) { return .corruptByte(at: 12_345) }
            return nil
        }

        let sampler = MemoryProbe.Sampler()
        sampler.start()
        let clock = ContinuousClock()
        let started = clock.now
        let loadAtStart = Self.loadAverages()
        var interruptions: [(afterVerified: Int, verifiedIndexes: Set<Int>, requestsSoFar: [Int64: Int])] = []
        var outcome: TransferEngine.Outcome?
        // Two client restarts: the engine is cancelled after 100 and after 220 verified parts (counted
        // across runs), then a brand-new engine resumes from the on-disk journal, as after a relaunch.
        for stopAfter in [100, 220, Int.max] {
            let verified = Mutex(Set<Int>())
            let alreadyVerified = interruptions.last?.verifiedIndexes ?? []
            verified.withLock { $0 = alreadyVerified }
            let engine = TransferEngine(client: client, itemID: itemID, stagingRoot: staging) { event in
                if case .partVerified(_, let index) = event {
                    let count = verified.withLock { $0.insert(index); return $0.count }
                    if count >= stopAfter { withUnsafeCurrentTask { $0?.cancel() } }
                }
            }
            let run = await Task { await engine.run() }.value
            if case .paused(.cancelled, _) = run {
                interruptions.append((stopAfter, verified.withLock { $0 }, Self.requestsPerOffset(harness)))
                continue
            }
            outcome = run
            break
        }
        let elapsed = clock.now - started
        sampler.stop()
        let peak = sampler.peak
        let final = MemoryProbe.read()

        guard case .ready(let manifest, let assets)? = outcome else {
            Issue.record("expected ready, got \(String(describing: outcome))")
            await harness.cleanUp()
            return
        }
        #expect(manifest.assets.count == 1 && manifest.assets[0].parts.count == partCount)
        #expect(manifest.assets[0].sha256 == expected)
        let ready = try #require(assets.first)
        // Independent re-hash of the handed-off file (the engine already checked it before handoff).
        let rehash = try Self.sha256(of: ready.url)
        #expect(rehash == expected)
        #expect(try FileManager.default.attributesOfItem(atPath: ready.url.path)[.size] as? NSNumber == NSNumber(value: length))

        // Only failed or interrupted parts were fetched again; parts verified before an interruption never.
        let requests = Self.requestsPerOffset(harness)
        #expect(requests.count == partCount)
        for interruption in interruptions {
            for index in interruption.verifiedIndexes {
                let offset = Int64(index) * partSize
                #expect(requests[offset] == interruption.requestsSoFar[offset], "part \(index) was verified before an interruption and fetched again")
            }
        }
        for index in dropped.union(corrupted) { #expect((requests[Int64(index) * partSize] ?? 0) >= 2, "faulted part \(index) was retried") }
        let refetched = requests.filter { $0.value > 1 }.count
        let extraRequests = requests.values.reduce(0, +) - partCount
        // Extra requests come from the faulted parts and from parts that were in flight when an engine was
        // cancelled for a restart; the second number depends on timing and varies from run to run.
        let faultedOffsets = Set(dropped.union(corrupted).map { Int64($0) * partSize })
        let faultedExtra = requests.filter { faultedOffsets.contains($0.key) }.values.reduce(0) { $0 + $1 - 1 }
        let inFlightExtra = extraRequests - faultedExtra

        // Memory: the transfer must not hold the file, or even one part per MiB of file, in memory.
        let growth = peak.physFootprint - baseline.physFootprint
        let bound: UInt64 = 256 * 1_048_576
        #expect(growth < bound, "peak footprint grew by \(growth / 1_048_576) MiB")
        let seconds = Double(elapsed.components.seconds) + Double(elapsed.components.attoseconds) / 1e18
        let lines = [
            "environment: host (macOS \(ProcessInfo.processInfo.operatingSystemVersionString)), in-process source and client, TLS on 127.0.0.1",
            "file: generate-g02-transfer-large.sh output, \(length) bytes, sha256 \(expected)",
            "part size \(partSize) bytes, \(partCount) parts, engine concurrency 2",
            "faults: connection dropped after 5 MiB on first attempt of \(dropped.count) parts \(dropped.sorted()); "
                + "one byte flipped on first attempt of \(corrupted.count) parts \(corrupted.sorted())",
            "client restarts: \(interruptions.count) (engine cancelled after \(interruptions.map(\.afterVerified)) verified parts, new engine resumed from the journal)",
            "content requests: \(requests.values.reduce(0, +)) for \(partCount) parts; \(refetched) parts fetched more than once; \(extraRequests) extra requests",
            "  of which \(faultedExtra) for the \(faultedOffsets.count) faulted parts and \(inFlightExtra) for parts in flight when an engine was cancelled "
                + "for a restart (that number depends on timing and varies between runs)",
            "parts verified before each interruption and fetched again afterwards: 0 (asserted)",
            "result: ready; handed-off file re-hashed independently: \(rehash == expected ? "matches" : "MISMATCH")",
            String(format: "elapsed: %.1f s (%.0f MiB/s including server preparation and three full-file hashes)", seconds, Double(length) / 1_048_576 / seconds),
            "load averages (1, 5, 15 min): \(loadAtStart) at the start, \(Self.loadAverages()) at the end (timings under parallel load are indicative only)",
            "memory (proc_pid_rusage, whole test process: source + client):",
            "  phys_footprint before: \(baseline.physFootprint / 1_048_576) MiB; peak sampled every 50 ms during transfer: \(peak.physFootprint / 1_048_576) MiB; after: \(final.physFootprint / 1_048_576) MiB",
            "  growth at peak: \(growth / 1_048_576) MiB (bound asserted: < \(bound / 1_048_576) MiB)",
            "  resident size peak sampled: \(peak.residentSize / 1_048_576) MiB",
            "  kernel lifetime maximum phys_footprint of the process: \(final.lifetimeMaxFootprint / 1_048_576) MiB",
        ]
        Evidence.write("faults/large-5GiB-transfer.log", lines.joined(separator: "\n") + "\n")
        await harness.cleanUp()
    }

    /// Gate gap from the round 1 review: the background client (download tasks, synchronous move, verified-only
    /// journal, assembly, importer) at 5 GiB, with a relaunch half way. Measures the launch re-hash of the staged
    /// verified parts and checks that it does not hold the coordinator's lock (the transfer screen polls
    /// `jobViews()` throughout; before this round the re-hash ran inside the lock).
    @Test(.enabled(if: filePath != nil, "set SYLVIA_G02_LARGE_FILE; Scripts/ci.d/40-g02-transfer.sh does"))
    func fiveGiBThroughTheBackgroundClientWithARelaunch() async throws {
        let source = URL(fileURLWithPath: try #require(Self.filePath))
        let expected = try #require(Self.expectedSHA256)
        let length = try #require(try FileManager.default.attributesOfItem(atPath: source.path)[.size] as? NSNumber).int64Value
        let base = FileManager.default.temporaryDirectory.appendingPathComponent("g02-large-bg-\(UUID().uuidString)")
        let root = base.appendingPathComponent("library")
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: base) }
        guard clonefile(source.path, root.appendingPathComponent("large.m4b").path, 0) == 0 else {
            Issue.record("clonefile from the fixture cache failed: errno \(errno)")
            return
        }
        let baseline = MemoryProbe.read()
        let harness = try await Harness.make(partSize: TransferProtocol.defaultPartSize, root: root, state: base.appendingPathComponent("state"))
        let (_, paired, token) = try await harness.pairDevice(name: "Large background client")
        let itemID = try await harness.itemID(titled: "large")
        let credentials = InMemoryCredentialStore()
        try credentials.saveToken(token, sourceID: paired.sourceID)
        let phone = base.appendingPathComponent("phone")
        let partSize = TransferProtocol.defaultPartSize
        let partCount = Int((length + partSize - 1) / partSize)
        let sampler = MemoryProbe.Sampler()
        sampler.start()
        let clock = ContinuousClock()
        let started = clock.now
        let loadAtStart = Self.loadAverages()

        func waitFor(_ coordinator: BackgroundTransferCoordinator, _ jobID: String, seconds: Int, _ done: (BackgroundTransferCoordinator.JobView) -> Bool) async throws -> BackgroundTransferCoordinator.JobView {
            let deadline = clock.now + .seconds(seconds)
            while clock.now < deadline {
                if let view = coordinator.job(jobID), done(view) { return view }
                try await Task.sleep(for: .milliseconds(100))
            }
            let view = try #require(coordinator.job(jobID))
            Issue.record("timed out: \(view.job.state) \(String(describing: view.job.pauseReason)), \(view.verifiedParts) verified parts")
            return view
        }

        // First "process": half the parts, then it dies with tasks in flight.
        let first = try BackgroundTransferCoordinator(kind: .inProcess, root: phone, credentials: credentials, appState: { "host_test" })
        try first.sources.upsert(paired)
        await first.start()
        let jobID = try await first.startJob(sourceID: paired.sourceID, itemID: itemID, title: "large")
        _ = try await waitFor(first, jobID, seconds: 600) { $0.verifiedParts >= partCount / 2 }
        first.invalidate()
        try await waitUntilQuiet(first)
        let verifiedAtStop = Set(first.log.allEntries().filter { $0.event == "part_verified" }.compactMap { $0.fields["part"] })
        let requestsAtStop = Self.requestsPerOffset(harness)
        let entriesAtStop = first.log.allEntries().count

        // Relaunch: start() re-hashes the verified parts while a "transfer screen" polls jobViews().
        let second = try BackgroundTransferCoordinator(kind: .inProcess, root: phone, credentials: credentials, appState: { "host_test" })
        let polling = Mutex((running: true, slowest: Duration.zero, polls: 0))
        let poller = Thread {
            while polling.withLock({ $0.running }) {
                let before = ContinuousClock.now
                _ = second.jobViews()
                let took = ContinuousClock.now - before
                polling.withLock { $0.slowest = max($0.slowest, took); $0.polls += 1 }
                usleep(5_000)
            }
        }
        poller.start()
        let startBegan = clock.now
        let summary = await second.start()
        let startTook = clock.now - startBegan
        polling.withLock { $0.running = false }
        let (slowestPoll, polls) = polling.withLock { ($0.slowest, $0.polls) }
        let check = try #require(second.log.allEntries().dropFirst(entriesAtStop).first { $0.event == "staging_checked" })
        #expect(summary.keptVerifiedParts == verifiedAtStop.count)
        #expect(check.fields["rehashed"] == "true")
        #expect(slowestPoll < .milliseconds(250), "jobViews() waited \(slowestPoll) during launch: the re-hash held the lock")

        // Review finding R2-04: the final full-file SHA-256 (5 GiB) must not hold the lock either. The "screen" keeps
        // polling until the import. Polls that start while the job shows "assembling" must not wait for the check
        // (with the check under the lock, "assembling" was never even visible: it was set and hashed in one hold).
        // While the job shows "assembling", the background-events completion is handed in as for a background
        // relaunch, and must be called only after the check has published its result. The slowest poll over the
        // whole rest of the transfer is reported too: part commits and the import's file work still hold the lock
        // (report findings 20, 22); the log says what the slowest call returned, which tells which of them it waited for.
        let finishing = Mutex((
            running: true, slowest: Duration.zero, slowestDuringAssembly: Duration.zero, inAssembly: false, polls: 0,
            assemblingPolls: 0, handedCompletion: false, slowestReturned: "no call"))
        let completedAfterAssembly = Mutex(false)
        let finishingPoller = Thread {
            while finishing.withLock({ $0.running }) {
                let before = ContinuousClock.now
                let views = second.jobViews()
                let took = ContinuousClock.now - before
                let assembling = views.first?.job.state == .assembling
                let handIn = finishing.withLock { state -> Bool in
                    if took > state.slowest {
                        state.slowest = took
                        state.slowestReturned = views.first.map { view in
                            "the job \(view.job.state.rawValue)"
                                + (view.totalParts > 0 ? " with \(view.verifiedParts) of \(view.totalParts) parts verified" : "")
                        } ?? "no job"
                    }
                    state.polls += 1
                    // A poll that started after "assembling" was seen and before the next state was seen.
                    if state.inAssembly { state.slowestDuringAssembly = max(state.slowestDuringAssembly, took) }
                    state.inAssembly = assembling
                    guard assembling else { return false }
                    state.assemblingPolls += 1
                    defer { state.handedCompletion = true }
                    return !state.handedCompletion
                }
                if handIn {
                    second.setBackgroundEventsCompletion { completedAfterAssembly.withLock { $0 = true } }
                    second.urlSessionDidFinishEvents(forBackgroundURLSession: URLSession.shared)
                }
                usleep(5_000)
            }
        }
        finishingPoller.start()

        let view = try await waitFor(second, jobID, seconds: 900) { $0.job.state == .imported }
        finishing.withLock { $0.running = false }
        let completionDeadline = ContinuousClock.now + .seconds(5)
        while !completedAfterAssembly.withLock({ $0 }), ContinuousClock.now < completionDeadline { try await Task.sleep(for: .milliseconds(20)) }
        let finish = finishing.withLock { $0 }
        let finalEvents = second.log.allEntries().dropFirst(entriesAtStop)
        let assemblyVerified = try #require(finalEvents.firstIndex { $0.event == "assembly_verified" })
        let assemblyMilliseconds = Int(finalEvents[assemblyVerified].fields["milliseconds"] ?? "") ?? -1
        let heldCompletion = finalEvents.firstIndex { $0.event == "background_events_completed_after_assembly" }
        #expect(finish.assemblingPolls > 0, "no poll ran while the full-file check ran (was it done under the lock?)")
        #expect(
            finish.slowestDuringAssembly < .milliseconds(250),
            "jobViews() waited \(finish.slowestDuringAssembly) while the job was assembling: the full-file check held the lock")
        #expect(finish.slowest < .seconds(1), "jobViews() waited \(finish.slowest) after the relaunch")
        let commitTimes = finalEvents.filter { $0.event == "part_verified" }.compactMap { Int($0.fields["commit_ms"] ?? "") }.sorted()
        let importMilliseconds = finalEvents.first { $0.event == "imported" }?.fields["import_ms"] ?? "not logged"
        #expect(finish.handedCompletion && completedAfterAssembly.withLock { $0 }, "the background-events completion was not called")
        #expect(heldCompletion.map { $0 > assemblyVerified } == true, "the completion was called before the full-file check published its result")
        let elapsed = clock.now - started
        sampler.stop()
        let peak = sampler.peak
        #expect(view.job.state == .imported)
        let record = try #require(second.importer.record(itemVersionID: view.job.itemVersionID))
        #expect(record.completions == 1 && record.assets.first?.sha256 == expected)
        let imported = second.importer.destination(importID: record.importID, assetID: try #require(record.assets.first).assetID)
        #expect(try FileManager.default.attributesOfItem(atPath: imported.path)[.size] as? NSNumber == NSNumber(value: length))
        let requests = Self.requestsPerOffset(harness)
        var verifiedRefetched = 0
        for part in verifiedAtStop {
            guard let index = Int(part.split(separator: ":").last ?? "") else { continue }
            let offset = Int64(index) * partSize
            if requests[offset] != requestsAtStop[offset] { verifiedRefetched += 1 }
        }
        #expect(verifiedRefetched == 0, "parts verified before the relaunch were requested again")
        let growth = peak.physFootprint - baseline.physFootprint
        let bound: UInt64 = 256 * 1_048_576
        #expect(growth < bound, "peak footprint grew by \(growth / 1_048_576) MiB")
        let seconds = { (duration: Duration) in Double(duration.components.seconds) + Double(duration.components.attoseconds) / 1e18 }
        let checkedBytes = Int64(check.fields["verified_bytes"] ?? "") ?? 0
        let checkMilliseconds = Int(check.fields["milliseconds"] ?? "") ?? 0
        let lines = [
            "environment: host (macOS \(ProcessInfo.processInfo.operatingSystemVersionString)), in-process source on 127.0.0.1, real TLS; "
                + "background client with its in-process session kind (download tasks, same delegate code as the background session)",
            "file: generate-g02-transfer-large.sh output, \(length) bytes, sha256 \(expected); \(partCount) parts of \(partSize) bytes; window 4 tasks, 2 connections",
            "first coordinator invalidated after \(verifiedAtStop.count) verified parts (tasks in flight cancelled)",
            String(format: "relaunch: start() took %.2f s; staging check re-hashed %lld bytes in %d ms (%.0f MiB/s)", seconds(startTook), checkedBytes,
                   checkMilliseconds, checkMilliseconds > 0 ? Double(checkedBytes) / 1_048_576 / (Double(checkMilliseconds) / 1000) : 0),
            String(format: "jobViews() polled %d times during start(); slowest call %.3f ms (asserted < 250 ms: the re-hash runs outside the lock)",
                   polls, seconds(slowestPoll) * 1000),
            "reconciliation: kept \(summary.keptVerifiedParts) verified parts, enqueued \(summary.enqueued), discarded \(summary.discardedParts)",
            String(format: "final full-file SHA-256 (assembly) took %d ms on the assembly queue; jobViews() polled %d times while the job showed "
                   + "\"assembling\", slowest of those %.3f ms (asserted < 250 ms: the check runs outside the lock)",
                   assemblyMilliseconds, finish.assemblingPolls, seconds(finish.slowestDuringAssembly) * 1000),
            String(format: "jobViews() polled %d times from the relaunch to the import; slowest call %.3f ms (asserted < 1 s), which returned ",
                   finish.polls, seconds(finish.slowest) * 1000)
                + "\(finish.slowestReturned). "
                + String(format: "Part commits (16 MiB copy, hash and write barrier) still hold the lock: commit_ms of the %d parts verified after "
                   + "the relaunch: median %d, max %d (report finding 20); ",
                   commitTimes.count, commitTimes.isEmpty ? -1 : commitTimes[commitTimes.count / 2], commitTimes.last ?? -1)
                + "the import's file work held it for \(importMilliseconds) ms (import_ms; report finding 22)",
            "background-events completion handed in while the job showed \"assembling\": "
                + (heldCompletion.map { $0 > assemblyVerified } == true && completedAfterAssembly.withLock({ $0 })
                    ? "held, then called after assembly_verified" : "NOT held until assembly_verified"),
            "content requests: \(requests.values.reduce(0, +)) for \(partCount) parts, no fault injected; parts requested more than once: "
                + "\(requests.filter { $0.value > 1 }.count) (a request in flight when the first coordinator stopped is made again); "
                + "parts verified before the relaunch requested again: \(verifiedRefetched) (asserted 0)",
            "result: imported once (completions \(record.completions)); imported asset digest from the verified assembly: \(record.assets.first?.sha256 == expected ? "matches" : "MISMATCH")",
            String(format: "elapsed: %.1f s", seconds(elapsed)),
            "load averages (1, 5, 15 min): \(loadAtStart) at the start, \(Self.loadAverages()) at the end (timings under parallel load are indicative only)",
            "memory (proc_pid_rusage, whole test process): phys_footprint before \(baseline.physFootprint / 1_048_576) MiB, "
                + "peak \(peak.physFootprint / 1_048_576) MiB, growth \(growth / 1_048_576) MiB (asserted < \(bound / 1_048_576) MiB)",
        ]
        Evidence.write("faults/large-5GiB-background-client.log", lines.joined(separator: "\n") + "\n")
        second.invalidate()
        await harness.cleanUp()
    }

    static func requestsPerOffset(_ harness: Harness) -> [Int64: Int] {
        var counts: [Int64: Int] = [:]
        for entry in harness.service.requestLog where entry.path.hasSuffix("/content") {
            if let range = entry.range, let first = Int64(range.dropFirst(6).split(separator: "-").first ?? "") {
                counts[first, default: 0] += 1
            }
        }
        return counts
    }

    static func sha256(of url: URL) throws -> String {
        let handle = try FileHandle(forReadingFrom: url)
        defer { try? handle.close() }
        var hasher = SHA256()
        while true {
            let chunk: Data = try autoreleasepool { try handle.read(upToCount: 8 * 1_048_576) ?? Data() }
            if chunk.isEmpty { break }
            hasher.update(data: chunk)
        }
        return Hex.encode(hasher.finalize())
    }
}

/// Reads this process's memory counters from the kernel (proc_pid_rusage, RUSAGE_INFO_V4).
enum MemoryProbe {
    struct Reading: Sendable {
        var physFootprint: UInt64
        var residentSize: UInt64
        var lifetimeMaxFootprint: UInt64
    }

    static func read() -> Reading {
        var info = rusage_info_v4()
        let status = withUnsafeMutablePointer(to: &info) { pointer in
            pointer.withMemoryRebound(to: rusage_info_t?.self, capacity: 1) { proc_pid_rusage(getpid(), RUSAGE_INFO_V4, $0) }
        }
        precondition(status == 0, "proc_pid_rusage failed")
        return Reading(physFootprint: info.ri_phys_footprint, residentSize: info.ri_resident_size,
                       lifetimeMaxFootprint: info.ri_lifetime_max_phys_footprint)
    }

    /// Samples every 50 ms on a background thread and keeps the maxima.
    final class Sampler: Sendable {
        private let state = Mutex((running: false, footprint: UInt64(0), resident: UInt64(0)))
        private let done = DispatchSemaphore(value: 0)

        func start() {
            state.withLock { $0.running = true }
            Thread.detachNewThread { [self] in
                while state.withLock({ $0.running }) {
                    let reading = MemoryProbe.read()
                    state.withLock {
                        $0.footprint = max($0.footprint, reading.physFootprint)
                        $0.resident = max($0.resident, reading.residentSize)
                    }
                    usleep(50_000)
                }
                done.signal()
            }
        }

        func stop() {
            state.withLock { $0.running = false }
            done.wait()
        }

        var peak: Reading {
            state.withLock { Reading(physFootprint: $0.footprint, residentSize: $0.resident, lifetimeMaxFootprint: 0) }
        }
    }
}
