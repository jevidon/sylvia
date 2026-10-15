import Foundation
import Testing
@testable import SylviaAI

/// Brief item 2 / plan 14.4: bounded streaming parsers against split UTF-8, partial events, CRLF, comments,
/// keepalives, oversized lines and early EOF.
@Suite("SSE parser")
struct SSEParserTests {
    /// Feeds `bytes` split at every possible single cut point and at every byte, and checks the result is identical.
    static func parseAllSplits(_ bytes: [UInt8], file: SourceLocation = #_sourceLocation) throws -> [SSEEvent] {
        var whole = SSEParser()
        let expected = try whole.feed(bytes)
        for cut in 0...bytes.count {
            var parser = SSEParser()
            let events = try parser.feed(bytes[..<cut]) + parser.feed(bytes[cut...])
            #expect(events == expected, "split at \(cut) changed the events", sourceLocation: file)
        }
        var byteWise = SSEParser()
        var events: [SSEEvent] = []
        for byte in bytes { events += try byteWise.feed([byte]) }
        #expect(events == expected, "byte-at-a-time feeding changed the events", sourceLocation: file)
        return expected
    }

    @Test func multiByteUTF8SplitAcrossChunksIsReassembled() throws {
        // "é" (2 bytes), "—" (3 bytes), "😀" (4 bytes), "﻿" word joiner (3 bytes) all straddle cut points.
        let text = "data: {\"t\":\"Café — 😀 \u{2060}done\"}\n\n"
        let events = try Self.parseAllSplits(Array(text.utf8))
        #expect(events.count == 1)
        #expect(events[0].data == "{\"t\":\"Café — 😀 \u{2060}done\"}")
        #expect(!events[0].data.contains("\u{FFFD}"))
    }

    @Test func crlfLfAndCrLineEndingsAreEquivalent() throws {
        let lf = try Self.parseAllSplits(Array("event: a\ndata: one\ndata: two\n\n".utf8))
        let crlf = try Self.parseAllSplits(Array("event: a\r\ndata: one\r\ndata: two\r\n\r\n".utf8))
        let cr = try Self.parseAllSplits(Array("event: a\rdata: one\rdata: two\r\r".utf8))
        #expect(lf == [SSEEvent(event: "a", data: "one\ntwo")])
        #expect(crlf == lf)
        #expect(cr == lf)
    }

    @Test func crAtChunkEndFollowedByLfIsOneLineBreak() throws {
        var parser = SSEParser()
        var events = try parser.feed(Array("data: x\r".utf8))
        events += try parser.feed(Array("\n\r".utf8))
        events += try parser.feed(Array("\ndata: y\r\n\r\n".utf8))
        #expect(events == [SSEEvent(data: "x"), SSEEvent(data: "y")])
    }

    @Test func commentsAndKeepalivesAreIgnoredAndCounted() throws {
        var parser = SSEParser()
        let events = try parser.feed(Array(": keepalive\n\n: ping\ndata: real\n\n:\n\n".utf8))
        #expect(events == [SSEEvent(data: "real")])
        #expect(parser.commentCount == 3)
    }

    @Test func partialEventIsHeldUntilBlankLine() throws {
        var parser = SSEParser()
        #expect(try parser.feed(Array("data: {\"a\":".utf8)).isEmpty)
        #expect(parser.hasPartialEvent)
        #expect(try parser.feed(Array("1}\n".utf8)).isEmpty)
        #expect(try parser.feed(Array("\n".utf8)) == [SSEEvent(data: "{\"a\":1}")])
        #expect(!parser.hasPartialEvent)
    }

    @Test func earlyEOFDiscardsTheUnfinishedEvent() throws {
        var parser = SSEParser()
        let events = try parser.feed(Array("data: complete\n\ndata: unfinished".utf8))
        #expect(events == [SSEEvent(data: "complete")])
        #expect(parser.hasPartialEvent)
        #expect(parser.finish().isEmpty)
    }

    @Test func fieldParsingFollowsTheStandard() throws {
        var parser = SSEParser()
        let events = try parser.feed(Array("data:no-space\ndata:  two-spaces\nid: 7\nretry: 100\nunknown: x\ndata\n\n".utf8))
        #expect(events == [SSEEvent(data: "no-space\n two-spaces\n", id: "7")])
    }

    @Test func eventWithoutDataIsNotDispatchedAndNameDoesNotLeak() throws {
        var parser = SSEParser()
        let events = try parser.feed(Array("event: orphan\n\ndata: next\n\n".utf8))
        #expect(events == [SSEEvent(event: nil, data: "next")])
    }

    @Test func leadingByteOrderMarkIsStripped() throws {
        var parser = SSEParser()
        let events = try parser.feed([0xEF, 0xBB, 0xBF] + Array("data: x\n\n".utf8))
        #expect(events == [SSEEvent(data: "x")])
    }

    @Test func invalidUTF8BecomesReplacementCharacterNotACrash() throws {
        var parser = SSEParser()
        let events = try parser.feed(Array("data: a".utf8) + [0xFF, 0xC3] + Array("b\n\n".utf8))
        #expect(events.count == 1)
        #expect(events[0].data.contains("\u{FFFD}"))
    }

    @Test func oversizedLineIsRejectedWithBoundedMemory() {
        var parser = SSEParser(maxLineBytes: 1024, maxEventBytes: 4096)
        let line = Array("data: ".utf8) + [UInt8](repeating: 0x61, count: 2000)
        #expect(throws: SSEError.lineTooLong(limit: 1024)) { _ = try parser.feed(line) }
    }

    @Test func oversizedEventIsRejected() {
        var parser = SSEParser(maxLineBytes: 1024, maxEventBytes: 2048)
        let line = "data: " + String(repeating: "b", count: 900) + "\n"
        #expect(throws: SSEError.eventTooLarge(limit: 2048)) { _ = try parser.feed(Array(String(repeating: line, count: 4).utf8)) }
    }
}
