import Foundation
import Testing
@testable import SylviaTransferCore

@Suite("Part plan, Range and response validation (15.4)")
struct RangeAndResponseTests {
    @Test func partPlanFor5GiBAt16MiB() {
        let length: Int64 = 5 * 1024 * 1024 * 1024
        let slices = PartPlan.slices(length: length, partSize: TransferProtocol.defaultPartSize)
        #expect(slices.count == 320)
        #expect(slices.first == .init(index: 0, offset: 0, length: TransferProtocol.defaultPartSize))
        #expect(slices.last?.offset == 319 * TransferProtocol.defaultPartSize)
        #expect(slices.reduce(0) { $0 + $1.length } == length)
    }

    @Test func partPlanWithShortFinalPart() {
        let slices = PartPlan.slices(length: 2 * TransferProtocol.mebibyte + 1, partSize: TransferProtocol.mebibyte)
        #expect(slices.map(\.length) == [TransferProtocol.mebibyte, TransferProtocol.mebibyte, 1])
        #expect(PartPlan.partCount(length: 2 * TransferProtocol.mebibyte + 1, partSize: TransferProtocol.mebibyte) == 3)
    }

    @Test func parsesSingleRanges() {
        #expect(RangeRequest.parse("bytes=0-99") == .fromTo(first: 0, last: 99))
        #expect(RangeRequest.parse("bytes=100-") == .fromTo(first: 100, last: nil))
        #expect(RangeRequest.parse("bytes=-500") == .suffix(500))
        #expect(RangeRequest.parse("bytes=0-0,5-9") == .multiple)
        for invalid in ["bytes=9-1", "bytes=-0", "bytes=a-b", "items=0-1", "bytes=", "bytes=1", "bytes= 0-1",
                        "bytes=99999999999999999999-", "bytes=+1-2"] {
            #expect(RangeRequest.parse(invalid) == .invalid, "\(invalid)")
        }
    }

    @Test func resolvesRangesAgainstLength() {
        #expect(RangeRequest.fromTo(first: 0, last: 99).resolve(length: 1000) == 0...99)
        #expect(RangeRequest.fromTo(first: 990, last: 2000).resolve(length: 1000) == 990...999)
        #expect(RangeRequest.fromTo(first: 1000, last: nil).resolve(length: 1000) == nil)
        #expect(RangeRequest.suffix(10).resolve(length: 1000) == 990...999)
        #expect(RangeRequest.suffix(5000).resolve(length: 1000) == 0...999)
    }

    @Test func contentRangeRoundTrip() {
        #expect(ContentRange.satisfied(0...99, length: 1000) == "bytes 0-99/1000")
        #expect(ContentRange.unsatisfied(length: 1000) == "bytes */1000")
        #expect(ContentRange.parse("bytes 0-99/1000")! == (0...99, 1000))
        #expect(ContentRange.parse("bytes 0-99/*") == nil)
        #expect(ContentRange.parse("bytes 99-0/1000") == nil)
        #expect(ContentRange.parse("bytes 0-1000/1000") == nil)
        #expect(ContentRange.parse("bytes */1000") == nil)
    }

    @Test func strongETags() {
        #expect(ETag.isStrong("\"sha256-abc\""))
        #expect(!ETag.isStrong("W/\"sha256-abc\""))
        #expect(!ETag.isStrong("\"a,b\""))
        #expect(!ETag.isStrong("\"\""))
        #expect(!ETag.isStrong("sha256-abc"))
        #expect(ETag.strongMatch("\"x\"", "\"x\""))
        #expect(!ETag.strongMatch("W/\"x\"", "W/\"x\""))
    }

    // MARK: Response head validation

    let asset = ManifestFactory.asset(data: ManifestFactory.bytes(seed: 3, count: 3 * 1_048_576 + 10))
    var part: TransferManifest.Part { asset.parts[1] }
    var expectation: PartResponseValidator.Expectation { .init(part: part, asset: asset) }

    func headers(_ overrides: [String: String?] = [:]) -> [String: String] {
        var base: [String: String] = [
            "ETag": asset.etag,
            "Content-Range": ContentRange.satisfied(part.offset...part.lastOffset, length: asset.length),
            "Content-Length": String(part.length),
            "Content-Type": "application/epub+zip",
        ]
        for (key, value) in overrides { base[key] = value }
        return base
    }

    func check(status: Int, _ headers: [String: String]) -> PartFailure? {
        PartResponseValidator.validateHead(
            status: status,
            header: { name in headers.first { $0.key.caseInsensitiveCompare(name) == .orderedSame }?.value },
            expectation: expectation)
    }

    @Test func acceptsExactPartialContent() {
        #expect(expectation.rangeHeader == "bytes=1048576-2097151")
        #expect(check(status: 206, headers()) == nil)
        #expect(check(status: 206, headers(["Content-Encoding": "identity"])) == nil)
    }

    @Test func classifiesEveryUnsafeResponse() {
        #expect(check(status: 200, headers()) == .rangeIgnored)
        #expect(check(status: 412, [:]) == .preconditionFailed)
        #expect(check(status: 416, ["Content-Range": "bytes */100"]) == .rangeNotSatisfiable)
        #expect(check(status: 401, [:]) == .unauthorized)
        #expect(check(status: 403, [:]) == .forbidden)
        #expect(check(status: 404, [:]) == .notFound)
        #expect(check(status: 429, [:]) == .rateLimited)
        #expect(check(status: 503, [:]) == .serverError(503))
        #expect(check(status: 302, [:]) == .unexpectedStatus(302))
        #expect(check(status: 206, headers(["ETag": "\"sha256-other\""])) == .etagChanged)
        #expect(check(status: 206, headers(["ETag": "W/" + asset.etag])) == .etagChanged)
        #expect(check(status: 206, headers(["ETag": nil])) == .etagChanged)
        #expect(check(status: 206, headers(["Content-Encoding": "gzip"])) == .unexpectedContentEncoding)
        #expect(check(status: 206, headers(["Transfer-Encoding": "chunked"])) == .missingContentLength)
        #expect(check(status: 206, headers(["Content-Length": nil])) == .missingContentLength)
        #expect(check(status: 206, headers(["Content-Length": String(part.length - 1)])) == .contentLengthMismatch)
        // Short 206: a consistent but smaller range is still not the part that was asked for.
        #expect(
            check(status: 206, headers(["Content-Range": ContentRange.satisfied(part.offset...(part.lastOffset - 10), length: asset.length)]))
                == .contentRangeMismatch)
        #expect(
            check(status: 206, headers(["Content-Range": ContentRange.satisfied(part.offset...part.lastOffset, length: asset.length + 1)]))
                == .contentRangeMismatch)
        #expect(check(status: 206, headers(["Content-Range": nil])) == .contentRangeMismatch)
    }

    @Test func recoveryPathForEachFailure() {
        #expect(PartFailure.rangeIgnored.recovery == .retryPart)
        #expect(PartFailure.digestMismatch.recovery == .retryPart)
        #expect(PartFailure.transport("lost").recovery == .retryPart)
        #expect(PartFailure.preconditionFailed.recovery == .refreshManifest)
        #expect(PartFailure.rangeNotSatisfiable.recovery == .refreshManifest)
        #expect(PartFailure.etagChanged.recovery == .refreshManifest)
        #expect(PartFailure.unauthorized.recovery == .pause(.reauthenticationRequired))
        #expect(PartFailure.forbidden.recovery == .pause(.accessRevoked))
        #expect(PartFailure.sourceIdentityChanged.recovery == .pause(.sourceIdentityChanged))
        for reason in [PauseReason.reauthenticationRequired, .sourceUnreachable, .finalDigestMismatch, .cancelled] {
            #expect(!reason.nextStep.isEmpty)
        }
    }

    @Test func bodyValidation() {
        let good = PartResponseValidator.validateBody(receivedBytes: part.length, sha256Hex: part.sha256, part: part)
        #expect(good == nil)
        #expect(
            PartResponseValidator.validateBody(receivedBytes: part.length - 1, sha256Hex: part.sha256, part: part)
                == .bodyLengthMismatch(expected: part.length, received: part.length - 1))
        #expect(
            PartResponseValidator.validateBody(receivedBytes: part.length, sha256Hex: String(repeating: "0", count: 64), part: part)
                == .digestMismatch)
    }
}

@Suite("Part state machine")
struct PartStateMachineTests {
    @Test func happyPathAndRetry() throws {
        var machine = PartStateMachine()
        try machine.apply(.request)
        #expect(machine.state == .requested(attempt: 1))
        try machine.apply(.failed(.transport("lost")))
        #expect(machine.state == .failed(attempt: 1, failure: .transport("lost")))
        try machine.apply(.request)
        try machine.apply(.bodyReceived)
        #expect(machine.state == .received(attempt: 2))
        try machine.apply(.verified)
        #expect(machine.state.isVerified)
    }

    @Test func digestFailureAfterReceiving() throws {
        var machine = PartStateMachine()
        try machine.apply(.request)
        try machine.apply(.bodyReceived)
        try machine.apply(.failed(.digestMismatch))
        #expect(machine.state == .failed(attempt: 1, failure: .digestMismatch))
    }

    @Test func illegalTransitionsAreRefused() {
        let cases: [(PartState, PartEvent)] = [
            (.pending, .verified),             // nothing received
            (.pending, .bodyReceived),
            (.requested(attempt: 1), .verified),  // must be received first
            (.requested(attempt: 1), .request),   // one request in flight per part
            (.verified, .request),             // a verified part is never fetched again
            (.verified, .bodyReceived),
            (.verified, .failed(.digestMismatch)),
        ]
        for (state, event) in cases {
            var machine = PartStateMachine(state: state)
            #expect(throws: IllegalPartTransition(from: state, event: event)) { try machine.apply(event) }
            #expect(machine.state == state)
        }
    }

    @Test func versionChangeInvalidates() throws {
        var machine = PartStateMachine(state: .verified)
        try machine.apply(.invalidate)
        #expect(machine.state == .pending)
    }
}
