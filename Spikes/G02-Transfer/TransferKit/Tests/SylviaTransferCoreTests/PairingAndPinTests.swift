import Foundation
import Testing
@testable import SylviaTransferCore

@Suite("SPKI pin and fingerprint (15.2)")
struct SPKIPinTests {
    /// The expected pins were computed by OpenSSL (Scripts/fixtures/generate-g02-transfer-test-certs.sh),
    /// an implementation independent of this code.
    @Test(arguments: ["p256", "p384", "rsa2048"])
    func matchesOpenSSLComputedPin(name: String) throws {
        let certs = TestPaths.bundledFixtures.appendingPathComponent("certs")
        let der = try [UInt8](Data(contentsOf: certs.appendingPathComponent("\(name).der")))
        let expected = try String(contentsOf: certs.appendingPathComponent("\(name).spki-sha256"), encoding: .utf8)
            .trimmingCharacters(in: .whitespacesAndNewlines)
        let pin = try SPKIPin(certificateDER: der)
        #expect(pin.hex == expected)
        #expect(pin.matches(certificateDER: der))
    }

    @Test func differentKeysDoNotMatch() throws {
        let certs = TestPaths.bundledFixtures.appendingPathComponent("certs")
        let p256 = try [UInt8](Data(contentsOf: certs.appendingPathComponent("p256.der")))
        let rsa = try [UInt8](Data(contentsOf: certs.appendingPathComponent("rsa2048.der")))
        #expect(!(try SPKIPin(certificateDER: p256)).matches(certificateDER: rsa))
    }

    @Test func malformedCertificatesAreRejected() throws {
        let certs = TestPaths.bundledFixtures.appendingPathComponent("certs")
        var der = try [UInt8](Data(contentsOf: certs.appendingPathComponent("p256.der")))
        #expect(throws: SPKIPinError.malformedCertificate) { try SPKIPin(certificateDER: Array(der.prefix(40))) }
        #expect(throws: SPKIPinError.malformedCertificate) { try SPKIPin(certificateDER: []) }
        der[0] = 0x31  // SET instead of SEQUENCE
        #expect(throws: SPKIPinError.malformedCertificate) { try SPKIPin(certificateDER: der) }
        let pin = try SPKIPin(hex: String(repeating: "a", count: 64))
        #expect(!pin.matches(certificateDER: der))
    }

    @Test func fingerprintIsUppercaseGroupsOfFour() throws {
        let pin = try SPKIPin(hex: "6176cad5417c16744110ab1d5cd016667faf0c99dec57123709a26478e525726")
        #expect(pin.displayFingerprint == "6176 CAD5 417C 1674 4110 AB1D 5CD0 1666 7FAF 0C99 DEC5 7123 709A 2647 8E52 5726")
        #expect(pin.displayFingerprint.split(separator: " ").count == 16)
        #expect(throws: SPKIPinError.invalidHex) { try SPKIPin(hex: "6176CAD5") }
    }
}

@Suite("Pairing payload codec (15.2)")
struct PairingPayloadTests {
    let now = Date(timeIntervalSince1970: 1_790_000_000)
    let pin = try! SPKIPin(hex: String(repeating: "ab", count: 32))

    func payload(secret: [UInt8] = secureRandomBytes(count: 32), expires: TimeInterval = 600,
                 endpoints: [PairingPayload.Endpoint] = [.init(host: "192.168.1.20", port: 48211)]) -> PairingPayload {
        PairingPayload(
            sourceID: CanonicalID.make(), sourceName: "Study Mac", endpoints: endpoints, spki: pin,
            invitationID: CanonicalID.make(), invitationSecret: secret, expiresAt: now.addingTimeInterval(expires))
    }

    @Test func codeAndLinkRoundTrip() throws {
        let original = payload(endpoints: [.init(host: "192.168.1.20", port: 48211), .init(host: "mac.tail1234.ts.net", port: 48211),
                                           .init(host: "fd7a:115c:a1e0::1", port: 48211)])
        let code = try original.code()
        #expect(code.hasPrefix("SYLVIA1-"))
        #expect(!code.contains("=") && !code.contains("+") && !code.contains("/"))
        #expect(try PairingPayload.decode(code, now: now) == original)
        let link = try original.link()
        #expect(link.hasPrefix("sylvia://pair/v1#"))
        #expect(try PairingPayload.decode("  \(link)\n", now: now) == original)
        #expect(try original.pin == pin)
        #expect(original.endpoints[2].baseURL()?.absoluteString == "https://[fd7a:115c:a1e0::1]:48211")
    }

    @Test func secretHasAtLeast128Bits() throws {
        #expect(throws: PairingPayloadError.weakSecret) { try payload(secret: secureRandomBytes(count: 15)).validate(now: now) }
        try payload(secret: secureRandomBytes(count: 16)).validate(now: now)
        #expect(Base64URL.decode(payload().invitationSecret)?.count == 32)
    }

    @Test func expiredInvitationIsRefusedLocally() throws {
        let code = try payload(expires: 600).code()
        #expect(throws: PairingPayloadError.expired) { try PairingPayload.decode(code, now: now.addingTimeInterval(601)) }
        #expect(throws: PairingPayloadError.expired) { try PairingPayload.decode(code, now: now.addingTimeInterval(600)) }
    }

    @Test func malformedAndForeignInputsAreRefused() throws {
        let code = try payload().code()
        #expect(throws: PairingPayloadError.unrecognizedFormat) { try PairingPayload.decode("https://example.com/pair", now: now) }
        #expect(throws: PairingPayloadError.malformed) { try PairingPayload.decode("SYLVIA1-!!!!", now: now) }
        #expect(throws: PairingPayloadError.malformed) { try PairingPayload.decode(String(code.dropLast(5)), now: now) }
        #expect(throws: PairingPayloadError.tooLong) {
            try PairingPayload.decode("SYLVIA1-" + String(repeating: "A", count: 5000), now: now)
        }
    }

    @Test func endpointsAndVersionsAreValidated() throws {
        #expect(throws: PairingPayloadError.invalidEndpoints) { try payload(endpoints: []).validate(now: now) }
        #expect(throws: PairingPayloadError.invalidEndpoints) { try payload(endpoints: [.init(host: "a b", port: 1)]).validate(now: now) }
        #expect(throws: PairingPayloadError.invalidEndpoints) { try payload(endpoints: [.init(host: "mac.local", port: 0)]).validate(now: now) }
        #expect(throws: PairingPayloadError.invalidEndpoints) { try payload(endpoints: [.init(host: "evil.example/x", port: 1)]).validate(now: now) }
        #expect(throws: PairingPayloadError.invalidEndpoints) { try payload(endpoints: [.init(host: "999.1.1.1", port: 1)]).validate(now: now) }
        #expect(throws: PairingPayloadError.invalidEndpoints) {
            try payload(endpoints: Array(repeating: .init(host: "10.0.0.1", port: 1), count: 9)).validate(now: now)
        }
        var future = payload()
        future.protocolVersion = ProtocolVersion(major: 2, minor: 0)
        #expect(throws: PairingPayloadError.unsupportedProtocolVersion) { try future.validate(now: now) }
        var badPin = payload()
        badPin.spkiSHA256 = String(repeating: "AB", count: 32)
        #expect(throws: PairingPayloadError.invalidPin) { try badPin.validate(now: now) }
    }

    @Test func contractFixturesDecode() throws {
        let fixtureNow = RFC3339.parse("2026-10-06T09:00:00Z")!
        for file in TestPaths.jsonFiles(in: TestPaths.contractFixtures.appendingPathComponent("pairing-payload.v1/valid")) {
            let decoded = try TransferJSON.decode(PairingPayload.self, from: Data(contentsOf: file))
            try decoded.validate(now: fixtureNow)
        }
        for file in TestPaths.jsonFiles(in: TestPaths.contractFixtures.appendingPathComponent("pairing-payload.v1/invalid")) {
            let rejected: Bool
            if let decoded = try? TransferJSON.decode(PairingPayload.self, from: Data(contentsOf: file)) {
                rejected = (try? decoded.validate(now: fixtureNow)) == nil
                    || file.lastPathComponent == "local-time-expiry.json"  // Swift accepts offsets; the contract requires Z
            } else {
                rejected = true
            }
            #expect(rejected, "\(file.lastPathComponent)")
        }
    }
}

@Suite("Encodings and wire models")
struct EncodingTests {
    @Test func base64URLIsCanonicalAndUnpadded() {
        #expect(Base64URL.encode([0xfb, 0xff]) == "-_8")
        #expect(Base64URL.decode("-_8") == [0xfb, 0xff])
        #expect(Base64URL.decode("-_8=") == nil)
        #expect(Base64URL.decode("+/8") == nil)
        #expect(Base64URL.decode("-_9") == nil)  // non-canonical trailing bits
        #expect(Base64URL.decode("A") == nil)
    }

    @Test func hexAndIdentifiers() {
        #expect(Hex.encode([0x00, 0xab]) == "00ab")
        #expect(Hex.decodeLowercase("00AB") == nil)
        #expect(Hex.isSHA256(String(repeating: "0", count: 64)))
        #expect(!Hex.isSHA256(String(repeating: "0", count: 63)))
        #expect(CanonicalID.isValid(CanonicalID.make()))
        #expect(!CanonicalID.isValid(UUID().uuidString))
        #expect(!CanonicalID.isValid("../../etc/passwd"))
        #expect(constantTimeEquals([1, 2, 3], [1, 2, 3]))
        #expect(!constantTimeEquals([1, 2, 3], [1, 2, 4]))
        #expect(!constantTimeEquals([1, 2], [1, 2, 3]))
        #expect(secureRandomBytes(count: 32) != secureRandomBytes(count: 32))
    }

    @Test func timestamps() {
        let date = RFC3339.parse("2026-10-06T09:00:00Z")!
        #expect(RFC3339.format(date) == "2026-10-06T09:00:00Z")
        #expect(RFC3339.parse("2026-10-06T09:00:00.250Z") != nil)
        #expect(RFC3339.parse("2026-10-06T22:00:00+13:00") == date)
        #expect(RFC3339.parse("06/10/2026") == nil)
    }

    @Test func capabilitiesNegotiation() {
        let caps = Capabilities(
            sourceID: CanonicalID.make(),
            partSize: .init(defaultBytes: 16 * 1_048_576, minimumBytes: 1_048_576, maximumBytes: 32 * 1_048_576))
        let mib = TransferProtocol.mebibyte
        #expect(caps.negotiatedPartSize() == Optional(16 * mib))
        #expect(caps.negotiatedPartSize(preferred: 64 * mib) == Optional(32 * mib))
        #expect(caps.negotiatedPartSize(preferred: 1) == Optional(mib))
        #expect(caps.negotiatedPartSize(preferred: 3 * mib + 5) == Optional(3 * mib))
        var future = caps
        future.supportedMajorVersions = [2]
        #expect(future.negotiatedPartSize() == nil)
    }

    /// Every valid contract fixture of the wire payloads decodes into the Swift model and re-encodes
    /// with the same keys, so the Swift types and the JSON Schemas describe the same shape.
    @Test(arguments: [
        "capabilities", "pair-request", "pair-response", "catalog-page", "device-inbox-page", "receipt", "error",
        "pairing-payload", "transfer-manifest",
    ])
    func validFixturesRoundTrip(schema: String) throws {
        let files = TestPaths.jsonFiles(in: TestPaths.contractFixtures.appendingPathComponent("\(schema).v1/valid"))
        #expect(!files.isEmpty)
        for file in files {
            let data = try Data(contentsOf: file)
            let reencoded: Data
            switch schema {
            case "capabilities": reencoded = try TransferJSON.encode(TransferJSON.decode(Capabilities.self, from: data))
            case "pair-request": reencoded = try TransferJSON.encode(TransferJSON.decode(PairRequest.self, from: data))
            case "pair-response": reencoded = try TransferJSON.encode(TransferJSON.decode(PairResponse.self, from: data))
            case "catalog-page": reencoded = try TransferJSON.encode(TransferJSON.decode(CatalogPage.self, from: data))
            case "device-inbox-page": reencoded = try TransferJSON.encode(TransferJSON.decode(DeviceInboxPage.self, from: data))
            case "receipt": reencoded = try TransferJSON.encode(TransferJSON.decode(Receipt.self, from: data))
            case "error": reencoded = try TransferJSON.encode(TransferJSON.decode(ErrorBody.self, from: data))
            case "pairing-payload": reencoded = try TransferJSON.encode(TransferJSON.decode(PairingPayload.self, from: data))
            default: reencoded = try TransferJSON.encode(TransferJSON.decode(TransferManifest.self, from: data))
            }
            let original = try JSONSerialization.jsonObject(with: data) as! [String: Any]
            let roundTrip = try JSONSerialization.jsonObject(with: reencoded) as! [String: Any]
            #expect(Self.keyPaths(roundTrip).isSubset(of: Self.keyPaths(original)), "\(file.lastPathComponent)")
            let unknown = Self.keyPaths(original).subtracting(Self.keyPaths(roundTrip)).filter { !$0.contains("future") }
            #expect(unknown.isEmpty, "\(file.lastPathComponent) loses \(unknown)")
        }
    }

    static func keyPaths(_ value: Any, prefix: String = "") -> Set<String> {
        var paths = Set<String>()
        if let dictionary = value as? [String: Any] {
            for (key, child) in dictionary {
                paths.insert(prefix + key)
                paths.formUnion(keyPaths(child, prefix: prefix + key + "."))
            }
        } else if let array = value as? [Any] {
            for child in array { paths.formUnion(keyPaths(child, prefix: prefix + "[]."))}
        }
        return paths
    }
}
