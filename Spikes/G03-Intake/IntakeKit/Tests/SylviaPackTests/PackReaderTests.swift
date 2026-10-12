import CryptoKit
import Foundation
import SylviaIntakeCore
@testable import SylviaPack
import Testing

/// A new directory inside the current test's scope (removed when the test ends; TemporaryFiles.swift).
func temporaryDirectory() throws -> URL {
    try TestDirectory.make()
}

/// Writes `data` as a pack file and validates it; returns the rejection code or nil when accepted.
func verdict(_ data: Data, limits: PackLimits = PackLimits(), in dir: URL? = nil) async throws -> PackRejection.Code? {
    let dir = try dir ?? temporaryDirectory()
    let url = dir.appendingPathComponent("\(UUID().uuidString).sylviapack")
    try data.write(to: url)
    defer { try? FileManager.default.removeItem(at: url) }
    do {
        _ = try await PackReader(limits: limits).validate(url)
        return nil
    } catch {
        return error.code
    }
}

@Suite("sylviapack reader: accepted packs", .removesTemporaryFiles)
struct PackReaderAcceptTests {
    @Test("the raw baseline pack is accepted (control for every negative test)")
    func rawBaselineAccepted() async throws {
        let data = try PackFixture.standard().rawZip().build()
        #expect(try await verdict(data) == nil)
    }

    @Test("the raw baseline with ZIP64 end records is accepted")
    func rawZIP64BaselineAccepted() async throws {
        var zip = try PackFixture.standard().rawZip()
        zip.forceZIP64 = true
        #expect(try await verdict(zip.build()) == nil)
    }

    @Test("writer output validates, extracts to identical bytes and is deterministic")
    func writerRoundTrip() async throws {
        let dir = try temporaryDirectory()
        let fixture = PackFixture.standard()
        var sources: [PackSource] = []
        for file in fixture.files {
            let url = dir.appendingPathComponent("src-\(sources.count)")
            try file.data.write(to: url)
            sources.append(PackSource(url: url, path: file.path, kind: file.kind, mediaType: file.mediaType,
                                      groupID: fixture.groupOf[file.path]?.0, order: fixture.groupOf[file.path]?.1))
        }
        let packID = UUID(uuidString: "0B9E7A55-2C1D-4E0F-9A8B-7C6D5E4F3A2B")!
        let date = Date(timeIntervalSince1970: 1_790_000_000)
        let a = dir.appendingPathComponent("a.sylviapack")
        let b = dir.appendingPathComponent("b.sylviapack")
        let written = try await PackWriter().write(sources: sources, groups: fixture.groups, packID: packID, fixedDate: date, to: a)
        _ = try await PackWriter().write(sources: sources, groups: fixture.groups, packID: packID, fixedDate: date, to: b)
        #expect(try Data(contentsOf: a) == Data(contentsOf: b), "same inputs and date give byte-identical packs")
        #expect(written.manifest.files.count == 4)

        let out = dir.appendingPathComponent("out")
        let extracted = try await PackReader().extract(a, to: out)
        #expect(extracted.extractedRoot == out)
        for file in fixture.files {
            let bytes = try Data(contentsOf: out.appendingPathComponent(file.path))
            #expect(bytes == file.data)
            let mode = try FileManager.default.attributesOfItem(atPath: out.appendingPathComponent(file.path).path)[.posixPermissions] as? Int
            #expect(mode.map { $0 & 0o111 } == 0, "extracted files are never executable")
        }
        // Text and Markdown were deflated; audio stored.
        let structure = try withFD(a) { fd, size in try PackStructure.parse(fd: fd, fileSize: size, limits: PackLimits()) }
        #expect(structure.entries.map(\.method) == [0, 0, 8, 8, 0, 0])
        #expect(structure.entries.allSatisfy { $0.unixMode == 0o100644 })
    }

    @Test("the writer refuses an existing destination and leaves no partial file on bad input")
    func writerRefusals() async throws {
        let dir = try temporaryDirectory()
        let src = dir.appendingPathComponent("src")
        try Data("x".utf8).write(to: src)
        let dest = dir.appendingPathComponent("p.sylviapack")
        try Data().write(to: dest)
        await #expect(throws: PackWriterError.destinationExists) {
            try await PackWriter().write(sources: [PackSource(url: src, path: "a.txt", kind: .text, mediaType: "text/plain")], groups: [], to: dest)
        }
        let dest2 = dir.appendingPathComponent("q.sylviapack")
        await #expect(throws: PackWriterError.self) {
            try await PackWriter().write(sources: [PackSource(url: src, path: "../a.txt", kind: .text, mediaType: "text/plain")], groups: [], to: dest2)
        }
        let leftovers = try FileManager.default.contentsOfDirectory(atPath: dir.path).filter { $0.contains("partial") || $0 == "q.sylviapack" }
        #expect(leftovers.isEmpty)
    }

    @Test("a source that changes between hashing and packing is caught; no pack is published")
    func writerDetectsSourceChange() async throws {
        let dir = try temporaryDirectory()
        let src = dir.appendingPathComponent("a.caf")
        try DeterministicBytes(seed: 3).writeFile(src, length: 3 << 20)
        var writer = PackWriter(bufferSize: 64 << 10)
        writer.afterPassOne = {
            let handle = try! FileHandle(forWritingTo: src)
            try! handle.seek(toOffset: 1 << 20)
            try! handle.write(contentsOf: Data([0xFF, 0x00, 0xFF]))
            try! handle.close()
        }
        let dest = dir.appendingPathComponent("p.sylviapack")
        await #expect(throws: PackWriterError.sourceChanged(index: 0)) {
            try await writer.write(sources: [PackSource(url: src, path: "a.caf", kind: .audio, mediaType: "audio/x-caf")], groups: [], to: dest)
        }
        #expect(try Durability.lstatInfo(dest) == nil)
        #expect(try FileManager.default.contentsOfDirectory(atPath: dir.path).filter { $0.contains("partial") }.isEmpty)
    }
}

func withFD<T>(_ url: URL, _ body: (Int32, UInt64) throws -> T) throws -> T {
    let fd = open(url.path, O_RDONLY)
    guard fd >= 0 else { throw IntakeIOError("open") }
    defer { close(fd) }
    var info = stat()
    fstat(fd, &info)
    return try body(fd, UInt64(info.st_size))
}
