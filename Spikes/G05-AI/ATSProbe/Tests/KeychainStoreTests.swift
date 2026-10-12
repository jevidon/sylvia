import Foundation
import G05TestSupport
import Security
import Testing
import SylviaAI

/// Keychain credential store (plan 14.2), hosted in the probe app: the data-protection keychain needs a signed
/// app process (an unhosted SwiftPM test bundle gets errSecMissingEntitlement, -34018, on the simulator).
/// Behaviour while the device is locked or after reboot is a device check (Docs/Stage0/device-checklists/G05-AI.md).
@Suite("Keychain credential store (simulator)", .serialized)
struct KeychainStoreTests {
    let store = KeychainCredentialStore(service: "com.jevidon.sylvia.spike.ai-credentials.tests")

    @Test func roundTripUpdateAndDelete() throws {
        let ref = CredentialRef(origin: "https://api.openai.com")
        defer { try? store.delete(ref) }
        try store.save(Secret(Canary.apiKey), for: ref)
        #expect(try store.secret(for: ref).revealForAuthorizationHeader() == Canary.apiKey)
        try store.save(Secret(Canary.anthropicKey), for: ref)
        #expect(try store.secret(for: ref).revealForAuthorizationHeader() == Canary.anthropicKey)
        try store.delete(ref)
        #expect(throws: CredentialStoreError.notFound) { try store.secret(for: ref) }
    }

    @Test func storedWithWhenUnlockedThisDeviceOnlyAndNotSynchronized() throws {
        let ref = CredentialRef(origin: "https://api.openai.com")
        defer { try? store.delete(ref) }
        try store.save(Secret(Canary.apiKey), for: ref)
        #expect(store.storedAccessibility(for: ref) == (kSecAttrAccessibleWhenUnlockedThisDeviceOnly as String))
        var query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: store.service,
            kSecAttrAccount as String: KeychainCredentialStore.accountAttribute(ref),
            kSecAttrSynchronizable as String: kCFBooleanTrue as Any,
            kSecUseDataProtectionKeychain as String: kCFBooleanTrue as Any,
        ]
        query[kSecReturnAttributes as String] = kCFBooleanTrue
        var result: CFTypeRef?
        #expect(SecItemCopyMatching(query as CFDictionary, &result) == errSecItemNotFound, "no synchronizable copy exists")
    }

    /// R4-02 (plan 18.1): the origin is part of the Keychain item's identity, so a reference with the same account and
    /// another origin (for example in an imported configuration) finds no key, and saving for a second origin does not
    /// replace the first origin's key.
    @Test func aKeyIsStoredForOneOriginOnly() throws {
        let ref = CredentialRef(origin: "https://api.openai.com")
        let other = CredentialRef(account: ref.account, origin: "https://gateway.example.com")
        defer {
            try? store.delete(ref)
            try? store.delete(other)
        }
        try store.save(Secret(Canary.apiKey), for: ref)
        #expect(throws: CredentialStoreError.notFound) { try store.secret(for: other) }
        try store.save(Secret(Canary.anthropicKey), for: other)
        #expect(try store.secret(for: ref).revealForAuthorizationHeader() == Canary.apiKey)
        #expect(try store.secret(for: other).revealForAuthorizationHeader() == Canary.anthropicKey)
    }

    @Test func providerReadsTheKeyFromTheKeychainOnly() async throws {
        let server = try await FakeHTTPServer { _ in
            .sse(["data: {\"choices\":[{\"index\":0,\"delta\":{\"content\":\"ok\"},\"finish_reason\":\"stop\"}]}\n\ndata: [DONE]\n\n"])
        }
        let ref = try #require(CredentialRef(for: server.baseURL))
        defer { try? store.delete(ref) }
        try store.save(Secret(Canary.apiKey), for: ref)
        let config = ProviderConfig(kind: .openAICompatibleChat, displayName: "Local", baseURL: server.url("/v1"), model: "m",
                                    credential: ref, allowInsecureLocalHTTP: true)
        let request = GenerationRequest(system: "s", messages: [.init(role: .user, text: "q")], maxOutputTokens: 10)
        var text = ""
        for try await event in HTTPTextGenerationProvider(config: config, credentials: store, transport: URLSessionTransport()).streamGeneration(request) {
            if case .text(let delta) = event { text += delta }
        }
        #expect(text == "ok")
        #expect(server.requests.first?.headers["authorization"] == "Bearer \(Canary.apiKey)")
    }
}
