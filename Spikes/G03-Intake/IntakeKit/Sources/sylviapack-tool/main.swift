// sylviapack-tool: host (macOS) driver for the G0.3 scripted runs. Evidence tooling only.
//
//   make-caf <out.caf> <bytes>                     deterministic 16-bit mono LPCM CAF of exactly <bytes> bytes
//   gen-pack <out.sylviapack> <work-dir> <audio-bytes> [<extra-file> <pack-path> <kind> <media-type>]...
//   validate <pack> [--extract <dir>]              validate (and extract) with memory sampling
//   truncation-sweep <pack> <work-dir> <points>    clone + cut at structural boundaries and spread offsets
//   handoff <inbox> <file>...                      run the share-extension write sequence (no faults)
//   handoff-kill <inbox> <step> <occurrence> <file>...   same, but SIGKILL at the given step
//   copy-measure <inbox> <file>                    handoff of one large file with memory sampling, then cleanup
//   scan <inbox> <staging> [<now-offset-seconds>]  run the main app's inbox scan and print the report
import Darwin
import Foundation
import SylviaImportHandoff
import SylviaIntakeCore
import SylviaPack

let args = Array(CommandLine.arguments.dropFirst())
let fixedDate = Date(timeIntervalSince1970: 1_790_000_000)   // 2026-09-21T14:13:20Z, keeps generated packs byte-identical
let packID = UUID(uuidString: "5C1A0C2E-0003-4E5F-8A9B-000000000003")!

func fail(_ message: String) -> Never {
    FileHandle.standardError.write(Data("error: \(message)\n".utf8))
    exit(1)
}

func seconds(_ d: Duration) -> Double { Double(d.components.seconds) + Double(d.components.attoseconds) / 1e18 }

func environment(_ inbox: URL, faults: any FaultInjecting = NoFaults()) -> HandoffEnvironment {
    HandoffEnvironment(inbox: inbox, producerBundleIdentifier: "com.jevidon.sylvia.spike.intake.tool",
                       producerBuildVersion: "1", faults: faults)
}

func contentType(for url: URL) -> String {
    SupportedContent.supportedType(forFileExtension: url.pathExtension)?.identifier ?? "public.data"
}

/// Deterministic CAF: 44.1 kHz mono 16-bit little-endian LPCM, a quiet 441 Hz tone plus low-level noise.
func makeCAF(_ url: URL, totalBytes: UInt64) throws {
    let headerBytes: UInt64 = 8 + 12 + 32 + 12 + 4
    guard totalBytes > headerBytes else { fail("CAF must be larger than its header") }
    let audioBytes = (totalBytes - headerBytes) & ~1
    var header = Data()
    func be32(_ v: UInt32) { withUnsafeBytes(of: v.bigEndian) { header.append(contentsOf: $0) } }
    func be16(_ v: UInt16) { withUnsafeBytes(of: v.bigEndian) { header.append(contentsOf: $0) } }
    func be64(_ v: UInt64) { withUnsafeBytes(of: v.bigEndian) { header.append(contentsOf: $0) } }
    header.append(contentsOf: Array("caff".utf8)); be16(1); be16(0)
    header.append(contentsOf: Array("desc".utf8)); be64(32)
    be64(Double(44_100).bitPattern)
    header.append(contentsOf: Array("lpcm".utf8))
    be32(2)        // kCAFLinearPCMFormatFlagIsLittleEndian
    be32(2); be32(1); be32(1); be32(16)
    header.append(contentsOf: Array("data".utf8)); be64(4 + audioBytes); be32(0)
    precondition(UInt64(header.count) == headerBytes)

    let fd = open(url.path, O_WRONLY | O_CREAT | O_EXCL, 0o644)
    guard fd >= 0 else { throw IntakeIOError("create") }
    defer { close(fd) }
    try header.withUnsafeBytes { try Durability.writeAll(fd: fd, $0) }
    let tone: [Int16] = (0..<100).map { Int16(2000 * sin(2 * Double.pi * Double($0) / 100)) }
    let noise = DeterministicBytes(seed: 0x0CAF)
    let chunk = 1 << 20
    let buffer = UnsafeMutableRawBufferPointer.allocate(byteCount: chunk, alignment: 16)
    defer { buffer.deallocate() }
    var written: UInt64 = 0
    while written < audioBytes {
        let n = Int(min(UInt64(chunk), audioBytes - written))
        noise.fill(UnsafeMutableRawBufferPointer(rebasing: buffer[0..<n]), offset: written)
        let firstSample = written / 2
        let samples = buffer.bindMemory(to: Int16.self)
        for i in 0..<(n / 2) {
            let s = tone[Int((firstSample + UInt64(i)) % 100)] &+ (Int16(truncatingIfNeeded: samples[i]) >> 9)
            samples[i] = s.littleEndian
        }
        try Durability.writeAll(fd: fd, UnsafeRawBufferPointer(rebasing: buffer[0..<n]))
        written += UInt64(n)
    }
    try Durability.fullSync(fd: fd)   // an odd <bytes> yields a file one byte shorter (whole 16-bit samples)
}

func printMemory(_ label: String, sampled: UInt64) {
    let m = MemorySample.now()
    print("\(label) memory: sampled_peak_phys_footprint=\(mib(sampled)) lifetime_peak_phys_footprint=\(mib(m.peakPhysFootprint)) max_rss=\(mib(m.maxRSS))")
}

guard let command = args.first else { fail("no command; see the header of main.swift") }

switch command {
case "make-caf":
    guard args.count == 3, let bytes = UInt64(args[2]) else { fail("make-caf <out> <bytes>") }
    try makeCAF(URL(fileURLWithPath: args[1]), totalBytes: bytes)
    print("wrote \(args[1])")

case "gen-pack":
    guard args.count >= 4, let audioBytes = UInt64(args[3]), (args.count - 4) % 4 == 0 else {
        fail("gen-pack <out> <work-dir> <audio-bytes> [<file> <path> <kind> <media-type>]...")
    }
    let out = URL(fileURLWithPath: args[1])
    let work = URL(fileURLWithPath: args[2], isDirectory: true)
    try FileManager.default.createDirectory(at: work, withIntermediateDirectories: true)
    let big = work.appendingPathComponent("part-01.caf")
    let small = work.appendingPathComponent("part-02.caf")
    let notes = work.appendingPathComponent("notes.md")
    let text = work.appendingPathComponent("chapter.txt")
    for url in [big, small, notes, text] { try? FileManager.default.removeItem(at: url) }
    try makeCAF(big, totalBytes: audioBytes)
    try makeCAF(small, totalBytes: 3_000_068)
    try Data("# Generated G0.3 pack\n\nDeterministic test content; no third-party text.\n".utf8).write(to: notes)
    // Numbered lines with seeded hex so the text compresses like prose (a few to one), not like a repeated
    // string, which the pack's own 100:1 expansion limit would rightly refuse.
    let lineNoise = DeterministicBytes(seed: 0x7E47)
    let lines = (0..<20_000).map { i in
        "Line \(i): " + lineNoise.data(offset: UInt64(i) * 12, count: 12).map { String(format: "%02x", $0) }.joined()
    }
    try Data((lines.joined(separator: "\n") + "\n").utf8).write(to: text)
    var sources = [
        PackSource(url: big, path: "Generated Audiobook/part-01.caf", kind: .audio, mediaType: "audio/x-caf", groupID: "generated-audiobook", order: 1),
        PackSource(url: small, path: "Generated Audiobook/part-02.caf", kind: .audio, mediaType: "audio/x-caf", groupID: "generated-audiobook", order: 2),
        PackSource(url: notes, path: "Generated Audiobook/notes.md", kind: .markdown, mediaType: "text/markdown"),
        PackSource(url: text, path: "Generated Text/chapter.txt", kind: .text, mediaType: "text/plain"),
    ]
    var index = 4
    while index < args.count {
        guard let kind = PackManifest.Kind(rawValue: args[index + 2]) else { fail("unknown kind \(args[index + 2])") }
        sources.append(PackSource(url: URL(fileURLWithPath: args[index]), path: args[index + 1], kind: kind, mediaType: args[index + 3]))
        index += 4
    }
    let groups = [PackManifest.Group(groupID: "generated-audiobook", kind: .audiobook, title: "Generated Audiobook",
                                     creators: ["Sylvia test generator"], language: "en", memberOrderBasis: .filename)]
    try? FileManager.default.removeItem(at: out)
    let start = ContinuousClock.now
    let sampler = FootprintSampler()
    sampler.start()
    do {
        let pack = try await PackWriter(generator: .init(name: "sylviapack-tool gen-pack", version: "1"))
            .write(sources: sources, groups: groups, packID: packID, fixedDate: fixedDate, to: out)
        let peak = sampler.stop()
        print("gen-pack ok: \(pack.archiveSize) bytes, \(pack.entryCount) entries, zip64_end_record=\(pack.usesZIP64), manifest_sha256=\(pack.manifestSHA256), elapsed=\(String(format: "%.1f", seconds(ContinuousClock.now - start)))s")
        printMemory("gen-pack (write + self-validation)", sampled: peak)
    } catch {
        fail("gen-pack: \(error)")
    }

case "validate":
    guard args.count == 2 || (args.count == 4 && args[2] == "--extract") else { fail("validate <pack> [--extract <dir>]") }
    let pack = URL(fileURLWithPath: args[1])
    let sampler = FootprintSampler()
    sampler.start()
    let start = ContinuousClock.now
    do {
        let result = args.count == 4
            ? try await PackReader().extract(pack, to: URL(fileURLWithPath: args[3], isDirectory: true))
            : try await PackReader().validate(pack)
        let elapsed = seconds(ContinuousClock.now - start)
        let peak = sampler.stop()
        print("\(args.count == 4 ? "extract" : "validate") ACCEPTED: \(result.archiveSize) bytes, \(result.entryCount) entries, zip64_end_record=\(result.usesZIP64), elapsed=\(String(format: "%.1f", elapsed))s, \(String(format: "%.0f", Double(result.archiveSize) / 1_048_576 / max(elapsed, 0.001))) MiB/s")
        for file in result.manifest.files {
            print("  \(file.kind.rawValue) \(file.size) bytes sha256=\(file.sha256)")
        }
        printMemory(args.count == 4 ? "extract" : "validate", sampled: peak)
    } catch {
        _ = sampler.stop()
        print("REJECTED: \(error) elapsed=\(String(format: "%.3f", seconds(ContinuousClock.now - start)))s")
        exit(3)
    }

case "truncation-sweep":
    guard args.count == 4, let points = Int(args[3]) else { fail("truncation-sweep <pack> <work-dir> <points>") }
    let pack = URL(fileURLWithPath: args[1])
    let work = URL(fileURLWithPath: args[2], isDirectory: true)
    try FileManager.default.createDirectory(at: work, withIntermediateDirectories: true)
    guard let size = (try FileManager.default.attributesOfItem(atPath: pack.path)[.size] as? NSNumber)?.uint64Value else { fail("size") }
    let fd = open(pack.path, O_RDONLY)
    let structure = try PackStructure.parse(fd: fd, fileSize: size, limits: PackLimits())
    close(fd)
    // Structural boundaries (each +/- 1) and evenly spread offsets.
    var cuts = Set<UInt64>([0, 1, 21, 22, size - 1, size - 2, size - 21, size - 22, size - 23, size - 42, size - 98,
                            structure.centralDirectoryOffset, structure.centralDirectoryOffset + 1, structure.centralDirectoryOffset - 1])
    for e in structure.entries {
        for p in [e.localHeaderOffset, e.localHeaderOffset + 1, e.dataOffset - 1, e.dataOffset, e.dataOffset + 1,
                  e.dataOffset + e.compressedSize - 1, e.dataOffset + e.compressedSize / 2] where p < size {
            cuts.insert(p)
        }
    }
    for i in 1...points { cuts.insert(size * UInt64(i) / UInt64(points + 1)) }
    cuts.insert(4 << 30); cuts.insert((4 << 30) - 1); cuts.insert((4 << 30) + 1)
    let sorted = cuts.filter { $0 < size }.sorted()
    var wronglyAccepted = 0
    var identicalAccepted = 0
    var codes: [String: Int] = [:]
    var slowest = 0.0
    let candidate = work.appendingPathComponent("cut.sylviapack")
    let originalFD = open(pack.path, O_RDONLY)
    defer { close(originalFD) }
    for (i, length) in sorted.enumerated() {
        for padded in [false, true] {
            try? FileManager.default.removeItem(at: candidate)
            guard clonefile(pack.path, candidate.path, 0) == 0 else { fail("clonefile failed (APFS required)") }
            guard truncate(candidate.path, off_t(length)) == 0 else { fail("truncate") }
            // A partial copy that was preallocated to full length shows zeros after the copied prefix. If the
            // original's missing bytes are themselves all zero (possible only inside the last 22 bytes, which hold
            // the end-record signature), the padded copy IS the complete file and must be accepted.
            var identical = false
            if padded {
                guard truncate(candidate.path, off_t(size)) == 0 else { fail("extend") }
                if size - length <= 22 {
                    identical = try Durability.readExactly(fd: originalFD, count: Int(size - length), at: length).allSatisfy { $0 == 0 }
                }
            }
            let start = ContinuousClock.now
            do {
                _ = try await PackReader().validate(candidate)
                if identical {
                    identicalAccepted += 1
                } else {
                    wronglyAccepted += 1
                    print("!! ACCEPTED a partial copy cut at \(length) of \(size) (padded=\(padded))")
                }
            } catch {
                if identical { print("!! REJECTED a byte-identical copy (cut at \(length), padded)"); wronglyAccepted += 1 }
                codes[error.code.rawValue + (padded ? " (zero-padded)" : ""), default: 0] += 1
                let took = seconds(ContinuousClock.now - start)
                slowest = max(slowest, took)
                if took > 0.5 { print("  slow rejection: cut at \(length) padded=\(padded) took \(String(format: "%.2f", took))s: \(error)") }
            }
        }
        if i % 25 == 0 { print("  ... \(i + 1)/\(sorted.count) cut points") }
    }
    try? FileManager.default.removeItem(at: candidate)
    print("truncation-sweep: \(sorted.count) cut points x {truncated, zero-padded to full length} = \(sorted.count * 2) copies of a \(size)-byte pack")
    print("truncation-sweep: partial copies accepted=\(wronglyAccepted); zero-padded copies byte-identical to the original (accepted, correct)=\(identicalAccepted)")
    print("truncation-sweep: rejection codes: \(codes.sorted { $0.key < $1.key }.map { "\($0.key)=\($0.value)" }.joined(separator: ", "))")
    print("truncation-sweep: slowest single rejection \(String(format: "%.3f", slowest))s")
    exit(wronglyAccepted == 0 ? 0 : 4)

case "handoff", "handoff-kill":
    let killing = command == "handoff-kill"
    guard args.count >= (killing ? 5 : 3) else { fail("handoff <inbox> <file>... | handoff-kill <inbox> <step> <occurrence> <file>...") }
    let inbox = URL(fileURLWithPath: args[1], isDirectory: true)
    var faults: any FaultInjecting = NoFaults()
    var files = Array(args.dropFirst(2))
    if killing {
        guard let step = HandoffWriteStep(rawValue: args[2]), let occurrence = Int(args[3]) else { fail("bad step") }
        faults = StepFault(step: step, occurrence: occurrence, mode: .kill)
        files = Array(args.dropFirst(4))
    }
    let urls = files.map { URL(fileURLWithPath: $0) }
    let result = try HandoffSession.run(environment: environment(inbox, faults: faults), files: urls.map { ($0, contentType(for: $0)) })
    switch result {
    case let .success(receipt): print("RECEIVED handoff=\(receipt.handoffID.uuidString) items=\(receipt.itemCount) bytes=\(receipt.totalBytes)")
    case let .failure(failure): print("NOT RECEIVED: \(failure)"); exit(5)
    }

case "copy-measure":
    guard args.count == 3 else { fail("copy-measure <inbox> <file>") }
    let inbox = URL(fileURLWithPath: args[1], isDirectory: true)
    let src = URL(fileURLWithPath: args[2])
    let before = MemorySample.now()
    let sampler = FootprintSampler()
    sampler.start()
    let start = ContinuousClock.now
    let result = try HandoffSession.run(environment: environment(inbox), files: [(src, contentType(for: src))])
    let elapsed = seconds(ContinuousClock.now - start)
    let peak = sampler.stop()
    guard case let .success(receipt) = result else { fail("handoff failed: \(result)") }
    print("copy-measure: \(receipt.totalBytes) bytes in \(String(format: "%.1f", elapsed))s (\(String(format: "%.0f", Double(receipt.totalBytes) / 1_048_576 / elapsed)) MiB/s), buffer \(StreamingCopier.defaultBufferSize) bytes")
    print("copy-measure: phys_footprint before=\(mib(before.physFootprint))")
    printMemory("copy-measure", sampled: peak)
    Durability.removeTree(inbox.appendingPathComponent(receipt.handoffID.uuidString))

case "scan":
    guard args.count >= 3 else { fail("scan <inbox> <staging> [<now-offset-seconds>]") }
    let inbox = URL(fileURLWithPath: args[1], isDirectory: true)
    let staging = URL(fileURLWithPath: args[2], isDirectory: true)
    let offset = args.count > 3 ? TimeInterval(args[3]) ?? 0 : 0
    let journal = try IntakeJournal(url: staging.appendingPathComponent("journal.json"))
    let report = try InboxScanner(inbox: inbox, stagingRoot: staging, journal: journal, now: { Date().addingTimeInterval(offset) }).scan()
    print("scan: accepted=\(report.acceptedJobs.count) recovered=\(report.recoveredJobs.count) in_progress=\(report.inProgress.count) abandoned_removed=\(report.abandonedRemoved.count) rejected=\(report.rejected.count) already_accepted=\(report.alreadyAccepted.count)")
    for r in report.rejected { print("  rejected: \(r.reason)") }
    print("journal: jobs=\(journal.jobs.count) states=\(journal.jobs.map(\.state.rawValue).sorted())")

default:
    fail("unknown command \(command)")
}
