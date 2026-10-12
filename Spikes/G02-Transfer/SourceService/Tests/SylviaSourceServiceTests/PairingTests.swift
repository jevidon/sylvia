import Foundation
import Synchronization
import Testing
@_spi(Testing) import SylviaSourceService
@_spi(Testing) import SylviaTransferClient
import SylviaTransferCore

/// T36 (rogue host, wrong pin, reused invitation) and T37 (revocation, changed source identity).
/// Environment: host (macOS), in-process source on 127.0.0.1 with an ephemeral port, real TLS.
@Suite("Pairing and trust (T36, T37)", .serialized)
struct PairingTests {
    @Test func pairsOverPinnedTLSAfterApproval() async throws {
        let harness = try await Harness.make(files: ["walden.epub": Harness.bytes(seed: 1, count: 1000)])
        defer { await harness.cleanUp() }
        let payload = await harness.service.issueInvitation()
        let code = try payload.code()
        let decoded = try PairingPayload.decode(code, now: harness.clock.now())
        let roundTrips = decoded == payload  // compared outside #expect so a failure never prints the secret
        #expect(roundTrips)
        #expect(Base64URL.decode(payload.invitationSecret)?.count == 32)

        let deviceID = CanonicalID.make()
        let (paired, token) = try await SourceClient.pair(payload: decoded, deviceID: deviceID, deviceName: "Justin's iPhone", now: harness.clock.now())
        #expect(paired.sourceID == harness.service.sourceID)
        #expect(paired.spkiSHA256 == harness.service.pin.hex)
        #expect(Set(paired.scopes) == Set(TransferProtocol.allScopes))

        // The Mac user saw the device and the fingerprint in groups of four.
        let asked = try #require(harness.approver.asked.withLock { $0.first })
        #expect(asked.deviceName == "Justin's iPhone" && asked.deviceID == deviceID)
        #expect(asked.sourceFingerprint == harness.service.pin.displayFingerprint)
        #expect(asked.sourceFingerprint.split(separator: " ").allSatisfy { $0.count == 4 })

        // The token works, and the Mac stored only its hash.
        let tls = Mutex<[String]>([])
        let client = harness.client(token: token)
        client.observeConnectionMetrics { version, alpn in
            tls.withLock { $0.append("\(version.map { String(describing: $0) } ?? "nil") \(alpn ?? "nil")") }
        }
        let page = try await client.catalog()
        #expect(page.items.count == 1)
        let devicesFile = try String(contentsOf: harness.state.appendingPathComponent("devices.json"), encoding: .utf8)
        #expect(!devicesFile.contains(token))
        #expect(devicesFile.contains(SHA256Hex.digest(Data(token.utf8))))
        #expect(!devicesFile.contains(payload.invitationSecret))
        try await Task.sleep(for: .milliseconds(100))
        let negotiated = tls.withLock { $0 }
        Evidence.write("tls-negotiation.txt", "host (macOS) URLSession -> NIOSSL source on 127.0.0.1\n" + negotiated.joined(separator: "\n") + "\n")
        #expect(negotiated.contains { $0.contains("TLSv13") || $0.contains("772") })
    }

    @Test func rogueHostWithAnotherKeyNeverReceivesTheSecret() async throws {
        let real = try await Harness.make()
        let rogue = try await Harness.make()
        defer { await real.cleanUp(); await rogue.cleanUp() }
        var payload = await real.service.issueInvitation()
        payload.endpoints = [.init(host: "127.0.0.1", port: rogue.service.port)]  // a rogue host answers at the address
        await #expect(throws: ClientError.pinMismatch) {
            _ = try await SourceClient.pair(payload: payload, deviceID: CanonicalID.make(), deviceName: "Phone", now: real.clock.now())
        }
        #expect(rogue.service.connectionCount >= 1)  // the TLS handshake was attempted
        #expect(rogue.service.decryptedBytesReceived == 0)  // not one application byte, so no secret, reached it
        #expect(rogue.service.requestCount == 0)
        #expect(rogue.approver.askedCount == 0)
        // The invitation was never consumed, so the real source still accepts it.
        payload.endpoints = [.init(host: "127.0.0.1", port: real.service.port)]
        _ = try await SourceClient.pair(payload: payload, deviceID: CanonicalID.make(), deviceName: "Phone", now: real.clock.now())
    }

    @Test func wrongPinAgainstTheRealSourceSendsNothing() async throws {
        let harness = try await Harness.make()
        defer { await harness.cleanUp() }
        var payload = await harness.service.issueInvitation()
        let genuinePin = payload.spkiSHA256
        payload.spkiSHA256 = SHA256Hex.digest(Data("not the source".utf8))
        await #expect(throws: ClientError.pinMismatch) {
            _ = try await SourceClient.pair(payload: payload, deviceID: CanonicalID.make(), deviceName: "Phone", now: harness.clock.now())
        }
        #expect(harness.service.connectionCount >= 1)
        #expect(harness.service.decryptedBytesReceived == 0)
        #expect(harness.service.requestCount == 0)
        payload.spkiSHA256 = genuinePin
        _ = try await SourceClient.pair(payload: payload, deviceID: CanonicalID.make(), deviceName: "Phone", now: harness.clock.now())
    }

    @Test func fallsBackPastARogueEndpointToTheGenuineOne() async throws {
        let real = try await Harness.make()
        let rogue = try await Harness.make()
        defer { await real.cleanUp(); await rogue.cleanUp() }
        var payload = await real.service.issueInvitation()
        payload.endpoints = [.init(host: "127.0.0.1", port: rogue.service.port), .init(host: "127.0.0.1", port: real.service.port)]
        _ = try await SourceClient.pair(payload: payload, deviceID: CanonicalID.make(), deviceName: "Phone", now: real.clock.now())
        #expect(rogue.service.connectionCount >= 1)
        #expect(rogue.service.decryptedBytesReceived == 0)
        #expect(rogue.service.requestCount == 0)
    }

    @Test func slowApprovalOutlivesTheConnectionIdleLimit() async throws {
        // The Mac user takes longer to answer than the idle limit: the waiting request is not cut off.
        let harness = try await Harness.make(approver: ScriptedApprover(.wait(.seconds(3), true)), idleTimeout: .seconds(1))
        defer { await harness.cleanUp() }
        let payload = await harness.service.issueInvitation()
        let (paired, _) = try await SourceClient.pair(
            payload: payload, deviceID: CanonicalID.make(), deviceName: "Phone", now: harness.clock.now())
        #expect(await harness.service.pairing.pairedDevices().map(\.deviceID) == [paired.deviceID])
    }

    @Test func invitationIsSingleUse() async throws {
        let harness = try await Harness.make()
        defer { await harness.cleanUp() }
        let payload = await harness.service.issueInvitation()
        _ = try await SourceClient.pair(payload: payload, deviceID: CanonicalID.make(), deviceName: "First", now: harness.clock.now())
        await #expect(throws: ClientError.http(status: 403, code: "invitation_used")) {
            _ = try await SourceClient.pair(payload: payload, deviceID: CanonicalID.make(), deviceName: "Second", now: harness.clock.now())
        }
        #expect(harness.approver.askedCount == 1)
    }

    @Test func concurrentUseOfOneInvitationPairsAtMostOneDevice() async throws {
        let approver = ScriptedApprover(.wait(.milliseconds(300), true))
        let harness = try await Harness.make(approver: approver)
        defer { await harness.cleanUp() }
        let payload = await harness.service.issueInvitation()
        let now = harness.clock.now()
        async let first = Result { () async throws(ClientError) in
            try await SourceClient.pair(payload: payload, deviceID: CanonicalID.make(), deviceName: "A", now: now)
        }
        async let second = Result { () async throws(ClientError) in
            try await SourceClient.pair(payload: payload, deviceID: CanonicalID.make(), deviceName: "B", now: now)
        }
        let results = await [first, second]
        #expect(results.filter { if case .success = $0 { true } else { false } }.count == 1)
        #expect(results.contains { if case .failure(.http(403, "invitation_used")) = $0 { true } else { false } })
        #expect(approver.askedCount == 1)
    }

    @Test func expiredInvitationFailsOnBothEnds() async throws {
        let harness = try await Harness.make()
        defer { await harness.cleanUp() }
        let payload = await harness.service.issueInvitation()
        // Phone side: refused locally, nothing is sent.
        await #expect(throws: ClientError.invalidPayload(.expired)) {
            _ = try await SourceClient.pair(payload: payload, deviceID: CanonicalID.make(), deviceName: "Phone",
                                            now: harness.clock.now().addingTimeInterval(601))
        }
        #expect(harness.service.requestCount == 0)
        // Mac side: a phone with a wrong clock still cannot use it.
        harness.clock.advance(601)
        await #expect(throws: ClientError.http(status: 403, code: "invitation_expired")) {
            _ = try await SourceClient.pair(payload: payload, deviceID: CanonicalID.make(), deviceName: "Phone",
                                            now: harness.clock.now().addingTimeInterval(-601))
        }
        #expect(harness.approver.askedCount == 0)
    }

    @Test func wrongSecretsBurnTheInvitationAfterTheAttemptLimit() async throws {
        let harness = try await Harness.make()
        defer { await harness.cleanUp() }
        let payload = await harness.service.issueInvitation()
        var guess = payload
        for _ in 0..<5 {
            guess.invitationSecret = Base64URL.encode(secureRandomBytes(count: 32))
            await #expect(throws: ClientError.http(status: 403, code: "invitation_invalid")) {
                _ = try await SourceClient.pair(payload: guess, deviceID: CanonicalID.make(), deviceName: "Attacker", now: harness.clock.now())
            }
        }
        // Even the genuine secret no longer works.
        await #expect(throws: ClientError.http(status: 403, code: "invitation_invalid")) {
            _ = try await SourceClient.pair(payload: payload, deviceID: CanonicalID.make(), deviceName: "Phone", now: harness.clock.now())
        }
        #expect(harness.approver.askedCount == 0)
    }

    @Test func pairingRequestsAreRateLimited() async throws {
        let harness = try await Harness.make()
        defer { await harness.cleanUp() }
        var limited: SourceClient.RawResponse?
        let client = harness.unauthenticatedClient()
        for attempt in 1...11 {
            let body = try TransferJSON.encode(PairRequest(
                invitationID: CanonicalID.make(), invitationSecret: Base64URL.encode(secureRandomBytes(count: 32)),
                sourceID: harness.service.sourceID, deviceID: CanonicalID.make(), deviceName: "Attacker"))
            let response = try await client.raw(method: "POST", pathAndQuery: "/v1/pair", headers: ["Content-Type": "application/json"], body: body)
            if attempt <= 10 { #expect(response.status == 403) } else { limited = response }
        }
        let response = try #require(limited)
        #expect(response.status == 429)
        #expect(Int(response.header("Retry-After") ?? "") ?? 0 >= 1)
        let error = try TransferJSON.decode(ErrorBody.self, from: response.body)
        #expect(error.error.code == "rate_limited" && error.error.retryable)
        Evidence.write("captured/error-rate-limited.json", String(decoding: response.body, as: UTF8.self))
    }

    @Test func deniedOrUnansweredApprovalIssuesNoToken() async throws {
        let denying = try await Harness.make(approver: ScriptedApprover(.deny))
        var limits = PairingAuthority.Limits()
        limits.approvalTimeout = .milliseconds(300)
        let silent = try await Harness.make(approver: ScriptedApprover(.never), limits: limits)
        defer { await denying.cleanUp(); await silent.cleanUp() }
        let denied = await denying.service.issueInvitation()
        await #expect(throws: ClientError.http(status: 403, code: "pairing_denied")) {
            _ = try await SourceClient.pair(payload: denied, deviceID: CanonicalID.make(), deviceName: "Phone", now: denying.clock.now())
        }
        await #expect(throws: ClientError.http(status: 403, code: "invitation_used")) {
            _ = try await SourceClient.pair(payload: denied, deviceID: CanonicalID.make(), deviceName: "Phone", now: denying.clock.now())
        }
        let unanswered = await silent.service.issueInvitation()
        await #expect(throws: ClientError.http(status: 403, code: "approval_timeout")) {
            _ = try await SourceClient.pair(payload: unanswered, deviceID: CanonicalID.make(), deviceName: "Phone", now: silent.clock.now())
        }
        #expect(await denying.service.pairing.pairedDevices().isEmpty)
        #expect(await silent.service.pairing.pairedDevices().isEmpty)
    }

    @Test func approvalTimeoutHoldsEvenIfThePromptNeverReturns() async throws {
        var limits = PairingAuthority.Limits()
        limits.approvalTimeout = .milliseconds(300)
        let approver = ScriptedApprover(.uncancellable(seconds: 2, true))
        let harness = try await Harness.make(approver: approver, limits: limits)
        defer { await harness.cleanUp() }
        let payload = await harness.service.issueInvitation()
        let started = ContinuousClock.now
        await #expect(throws: ClientError.http(status: 403, code: "approval_timeout")) {
            _ = try await SourceClient.pair(payload: payload, deviceID: CanonicalID.make(), deviceName: "Phone", now: harness.clock.now())
        }
        #expect(ContinuousClock.now - started < .milliseconds(1500))
        // The late "yes" arrives after the timeout and is ignored: no device is paired.
        try await Task.sleep(for: .seconds(2.2))
        #expect(approver.askedCount == 1)
        #expect(await harness.service.pairing.pairedDevices().isEmpty)
    }

    @Test func sourceBindingIsChecked() async throws {
        let harness = try await Harness.make()
        defer { await harness.cleanUp() }
        let payload = await harness.service.issueInvitation()
        let body = try TransferJSON.encode(PairRequest(
            invitationID: payload.invitationID, invitationSecret: payload.invitationSecret, sourceID: CanonicalID.make(),
            deviceID: CanonicalID.make(), deviceName: "Phone"))
        let response = try await harness.unauthenticatedClient().raw(
            method: "POST", pathAndQuery: "/v1/pair", headers: ["Content-Type": "application/json"], body: body)
        #expect(response.status == 403)
        #expect(try TransferJSON.decode(ErrorBody.self, from: response.body).error.code == "source_mismatch")
    }

    @Test func revokedTokensAreDeniedAndStayDeniedAfterRestart() async throws {
        let harness = try await Harness.make(files: ["a.epub": Harness.bytes(seed: 2, count: 100)])
        let (ownerRevoked, ownerPaired, ownerToken) = try await harness.pairDevice(name: "Old phone")
        let (selfRevoked, selfPaired, selfToken) = try await harness.pairDevice(name: "Other phone")
        _ = try await ownerRevoked.catalog()

        // Owner revocation on the Mac.
        #expect(try await harness.service.revoke(deviceID: ownerPaired.deviceID))
        await #expect(throws: ClientError.http(status: 401, code: "unauthenticated")) { _ = try await ownerRevoked.catalog() }

        // A device may not revoke another device, only itself.
        let response = try await selfRevoked.raw(method: "DELETE", pathAndQuery: "/v1/pairings/\(ownerPaired.deviceID)",
                                                 headers: ["Authorization": "Bearer \(ownerToken)"])
        #expect(response.status == 401)  // the revoked token cannot act at all
        let other = try await selfRevoked.raw(method: "DELETE", pathAndQuery: "/v1/pairings/\(CanonicalID.make())",
                                              headers: ["Authorization": "Bearer \(selfToken)"])
        #expect(other.status == 403)
        try await selfRevoked.revoke(deviceID: selfPaired.deviceID)
        await #expect(throws: ClientError.http(status: 401, code: "unauthenticated")) { _ = try await selfRevoked.catalog() }

        // Revocation is durable: a relaunched source still refuses both tokens.
        let relaunched = try await harness.restarted()
        defer { await relaunched.cleanUp() }
        await #expect(throws: ClientError.http(status: 401, code: "unauthenticated")) {
            _ = try await relaunched.client(token: ownerToken).catalog()
        }
    }

    @Test func changedSourceKeyRequiresExplicitRepairing() async throws {
        let harness = try await Harness.make(files: ["a.epub": Harness.bytes(seed: 3, count: 100)])
        let (oldClient, _, token) = try await harness.pairDevice()
        _ = try await oldClient.catalog()
        let oldPin = harness.service.pin

        // The Mac's key changes (reinstall, reset); the source ID stays the same.
        try harness.identityStore.rotateKeyKeepingSourceID()
        let relaunched = try await harness.restarted()
        defer { await relaunched.cleanUp() }
        #expect(relaunched.service.sourceID == harness.service.sourceID)
        #expect(relaunched.service.pin != oldPin)

        // The paired phone refuses the new key before sending its token; nothing silently re-trusts.
        let stale = SourceClient(baseURL: relaunched.baseURL, pin: oldPin, sourceID: relaunched.service.sourceID, token: token)
        await #expect(throws: ClientError.pinMismatch) { _ = try await stale.catalog() }
        #expect(ClientError.pinMismatch.requiresRepairing)
        #expect(relaunched.service.decryptedBytesReceived == 0)  // the token never left the phone
        #expect(relaunched.service.requestCount == 0)

        // Tokens issued under the old key are void: even a client that accepts the new key cannot use one.
        let acceptingNewKey = SourceClient(baseURL: relaunched.baseURL, pin: relaunched.service.pin, sourceID: relaunched.service.sourceID, token: token)
        await #expect(throws: ClientError.http(status: 401, code: "unauthenticated")) { _ = try await acceptingNewKey.catalog() }

        // Explicit re-pairing with a new invitation (new fingerprint) works.
        let (fresh, _, _) = try await relaunched.pairDevice()
        #expect(try await fresh.catalog().items.count == 1)
    }

    @Test func tokensAreAcceptedOnlyInTheAuthorizationHeader() async throws {
        let harness = try await Harness.make()
        defer { await harness.cleanUp() }
        let (_, _, token) = try await harness.pairDevice()
        let client = harness.unauthenticatedClient()
        for name in ["access_token", "token", "Authorization"] {
            let response = try await client.raw(method: "GET", pathAndQuery: "/v1/catalog?\(name)=\(token)")
            #expect(response.status == 400)
            #expect(try TransferJSON.decode(ErrorBody.self, from: response.body).error.code == "token_in_query_forbidden")
        }
        let missing = try await client.raw(method: "GET", pathAndQuery: "/v1/catalog")
        #expect(missing.status == 401)
        #expect(missing.header("WWW-Authenticate")?.hasPrefix("Bearer") == true)
        let basic = try await client.raw(method: "GET", pathAndQuery: "/v1/catalog", headers: ["Authorization": "Basic dXNlcjpwYXNz"])
        #expect(basic.status == 401)
        let ok = try await client.raw(method: "GET", pathAndQuery: "/v1/catalog", headers: ["Authorization": "Bearer \(token)"])
        #expect(ok.status == 200)
    }
}
