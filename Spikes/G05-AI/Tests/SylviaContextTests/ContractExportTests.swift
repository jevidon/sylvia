import Foundation
import G05TestSupport
import Testing
@testable import SylviaAI
@testable import SylviaContext

/// Brief item 10: produces real ContextPack and ProviderConfig JSON from the Swift code. The checks below run
/// every time; when G05_CONTRACT_EXPORT names a directory, the instances are also written there so
/// Scripts/ci.d/70-g05-ai.sh can validate them against Contracts/schemas with the repository's validator stack.
@Suite("Contract export")
struct ContractExportTests {
    static let exportDirectory = ProcessInfo.processInfo.environment["G05_CONTRACT_EXPORT"].map { URL(fileURLWithPath: $0) }

    /// Replaces every UUID in an encoded instance with one derived from the instance name and the UUID's order of first
    /// appearance in the sorted-key JSON, so that re-exporting gives byte-identical fixtures (equal UUIDs stay equal,
    /// for example a work ID repeated in each evidence item). Pack digests are recomputed afterwards.
    static func stabilizedJSON(_ json: Data, name: String) -> Data {
        let text = String(decoding: json, as: UTF8.self)
        let pattern = try! NSRegularExpression(pattern: "[0-9A-Fa-f]{8}-[0-9A-Fa-f]{4}-[0-9A-Fa-f]{4}-[0-9A-Fa-f]{4}-[0-9A-Fa-f]{12}")
        var mapping: [String: String] = [:]
        var out = ""
        var last = text.startIndex
        for match in pattern.matches(in: text, range: NSRange(text.startIndex..., in: text)) {
            let range = Range(match.range, in: text)!
            let original = String(text[range]).uppercased()
            if mapping[original] == nil {
                var hex = Array(SHA256Hex.of("sylvia-g05-fixture/\(name)/\(mapping.count)").prefix(32).uppercased())
                hex[12] = "4"  // version 4 layout, variant 10xx
                hex[16] = Array("89AB")[Int(String(hex[16]), radix: 16)! & 3]
                let h = String(hex)
                mapping[original] = [h.prefix(8), h.dropFirst(8).prefix(4), h.dropFirst(12).prefix(4), h.dropFirst(16).prefix(4), h.dropFirst(20)]
                    .map(String.init).joined(separator: "-")
            }
            out += text[last..<range.lowerBound] + mapping[original]!
            last = range.upperBound
        }
        out += text[last...]
        return Data(out.utf8)
    }

    static func stabilized(_ pack: ContextPack, name: String) throws -> ContextPack {
        let json = stabilizedJSON(try ContextPack.encoder().encode(pack), name: "context-pack.\(name)")
        var copy = try ContextPack.decoder().decode(ContextPack.self, from: json)
        copy.packSHA256 = copy.computeDigest()
        return copy
    }

    static func stabilized(_ config: ProviderConfig, name: String) -> ProviderConfig {
        let json = stabilizedJSON(try! ContextPack.encoder().encode(config), name: "provider-config.\(name)")
        return try! ContextPack.decoder().decode(ProviderConfig.self, from: json)
    }

    static func packs() throws -> [String: ContextPack] {
        try rawPacks().reduce(into: [:]) { result, entry in result[entry.key] = try stabilized(entry.value, name: entry.key) }
    }

    static func rawPacks() throws -> [String: ContextPack] {
        let walden = Library.walden, mm = Library.middlemarch
        let paragraph = Library.paragraph(in: walden, containing: "I went to the woods because I wished to live deliberately")
        let selection = TextSelection(paragraphOrdinal: paragraph.ordinal, exactText: "I went to the woods because I wished to live deliberately")
        let boundary = mm.work.paragraphs.last { $0.resourceHref == "text/chapter-10.xhtml" }!.ordinal
        var small = Library.config
        small.contextLimitTokens = 3_000
        small.maxOutputTokens = 500
        var otherModel = Library.endpoint
        otherModel.model = "another-local-model"
        let history = [
            ConversationTurnSnapshot(turnID: UUID(), question: "Who is Lydgate?", answer: "A new doctor in Middlemarch [c1].", maxEvidenceOrdinal: boundary - 40, editionID: mm.snapshot.editionID, sharedScopes: [.sourceText], destination: Library.endpoint),
            ConversationTurnSnapshot(turnID: UUID(), question: "What happens later?", answer: "Later events.", maxEvidenceOrdinal: boundary + 5_000, editionID: mm.snapshot.editionID, sharedScopes: [.sourceText], destination: Library.endpoint),
            ConversationTurnSnapshot(turnID: UUID(), question: "What do my notes say about Dorothea?", answer: "Your note calls her ardent [c1].",
                                     maxEvidenceOrdinal: nil, editionID: mm.snapshot.editionID, sharedScopes: [.savedThoughts], destination: otherModel),
        ]
        return [
            "selected-passage": try Library.build(ContextRequest(question: "What does he mean by deliberately?", scope: .selectedPassage, selection: selection), work: walden),
            "passage-and-nearby": try Library.build(ContextRequest(question: "What does he mean by deliberately?", scope: .passageAndNearby, selection: selection), work: walden),
            "work-search-restricted": try Library.build(ContextRequest(question: "What is Bulstrode like?", scope: .workSearch, excludeLaterPassages: true,
                                                                       confirmedPosition: ReadingPosition(editionID: mm.snapshot.editionID, paragraphOrdinal: boundary), history: history), work: mm),
            "work-search-truncated": try Library.build(ContextRequest(question: "Why did Thoreau go to the woods to live deliberately?", scope: .workSearch),
                                                       work: walden, config: small),
            "selected-thoughts": try Library.build(ContextRequest(question: "How do these relate?", scope: .selectedThoughts, thoughts: [
                SavedThought(captureID: UUID(), kind: .quote, text: "Simplify, simplify.", workID: walden.snapshot.workID, editionID: walden.snapshot.editionID, locationLabel: "Where I Lived, and What I Lived For", ordinal: paragraph.ordinal + 4),
                SavedThought(captureID: UUID(), kind: .note, text: "Compare with Seneca on the shortness of life.", workID: nil, editionID: nil, locationLabel: "Note", ordinal: nil),
                SavedThought(captureID: UUID(), kind: .transcript, text: "From my grandfather Verus I learned good morals.", workID: nil, editionID: nil, locationLabel: "Meditations, Book One, 0:02", ordinal: nil),
            ]), work: walden),
            // Saved thoughts under "Do not include later passages" (R4-06): the quote on this work keeps its place, so the
            // stored pack shows it lies within the boundary; the note on the ending is left out; the note on another book
            // has no place in this one and is not restricted by it.
            "selected-thoughts-restricted": try Library.build(ContextRequest(question: "How do these relate?", scope: .selectedThoughts, thoughts: [
                SavedThought(captureID: UUID(), kind: .quote, text: "Miss Brooke had that kind of beauty which seems to be thrown into relief by poor dress.",
                             workID: mm.snapshot.workID, editionID: mm.snapshot.editionID, locationLabel: "Chapter I", ordinal: Library.paragraph(in: mm, containing: "Miss Brooke had that kind of beauty").ordinal),
                SavedThought(captureID: UUID(), kind: .note, text: "How it ends for Lydgate.", workID: mm.snapshot.workID, editionID: mm.snapshot.editionID, locationLabel: "Finale", ordinal: boundary + 3_000),
                SavedThought(captureID: UUID(), kind: .note, text: "Compare with Walden on plain living.", workID: walden.snapshot.workID, editionID: walden.snapshot.editionID, locationLabel: "Note", ordinal: nil),
            ], excludeLaterPassages: true, confirmedPosition: ReadingPosition(editionID: mm.snapshot.editionID, paragraphOrdinal: boundary)), work: mm),
            // Nothing sent, and the pack says why (plan 13.3): "Do not include later passages" with no position set.
            "work-search-no-position": try Library.build(ContextRequest(question: "What happens to Dorothea?", scope: .workSearch, excludeLaterPassages: true), work: mm),
            // A question about a moment in a recording with no transcript (plan 10.4): the pack states the audio is unavailable.
            "selected-thoughts-audio-unavailable": try Library.build(ContextRequest(question: "What did the narrator say about his grandfather?", scope: .selectedThoughts, thoughts: [
                SavedThought(captureID: UUID(), kind: .note, text: "At 2:30 in Book One the reader said something about his grandfather.", workID: nil, editionID: nil, locationLabel: "Note", ordinal: nil),
            ], audioMoment: "Meditations, Book One, 2:30"), work: walden),
        ]
    }

    static func configs() -> [String: ProviderConfig] {
        rawConfigs().reduce(into: [:]) { result, entry in result[entry.key] = stabilized(entry.value, name: entry.key) }
    }

    static func rawConfigs() -> [String: ProviderConfig] {
        [
            "openai-hosted": ProviderConfig(kind: .openAIResponses, displayName: "OpenAI", baseURL: ProviderKind.openAIResponses.defaultBaseURL!,
                                            model: "model-entered-by-user", credential: CredentialRef(origin: "https://api.openai.com"), contextLimitTokens: 128_000, maxOutputTokens: 4_000),
            "anthropic-hosted": ProviderConfig(kind: .anthropicMessages, displayName: "Anthropic", baseURL: ProviderKind.anthropicMessages.defaultBaseURL!,
                                               model: "model-entered-by-user", credential: CredentialRef(origin: "https://api.anthropic.com"), maxOutputTokens: 4_000, requestTimeoutMs: 120_000),
            "local-generic-http": ProviderConfig(kind: .openAICompatibleChat, displayName: "Studio Mac", baseURL: try! BaseURL.normalize("http://192.168.1.20:1234/v1/chat/completions"),
                                                 model: "local-model", credential: nil, capabilities: ProviderCapabilities(streaming: true, streamUsage: true),
                                                 contextLimitTokens: 32_768, allowInsecureLocalHTTP: true),
            "gateway-declared-hosted": ProviderConfig(kind: .openAICompatibleChat, displayName: "Gateway", baseURL: try! BaseURL.normalize("https://gateway.example.com/api/v1/v1/"),
                                                      model: "gateway-model", credential: CredentialRef(origin: "https://gateway.example.com"), declaredClassification: .hosted),
            "transcription-timestamps": ProviderConfig(kind: .openAICompatibleTranscription, displayName: "Speech", baseURL: try! BaseURL.normalize("https://speech.example.com/v1/audio/transcriptions"),
                                                       model: "speech-model", credential: CredentialRef(origin: "https://speech.example.com"), capabilities: ProviderCapabilities(timestamps: true)),
        ]
    }

    @Test func packsAreSelfConsistent() throws {
        for (name, pack) in try Self.packs() {
            #expect(pack.digestIsValid, "\(name)")
            #expect(pack.citationAllowlist.count == pack.evidence.count, "\(name): citation IDs are unique")
            #expect(pack.evidence.map(\.citationID) == (0..<pack.evidence.count).map { "c\($0 + 1)" }, "\(name)")
            #expect(pack.evidence.allSatisfy { $0.textSHA256 == SHA256Hex.of($0.text) }, "\(name)")
            let json = String(decoding: try ContextPack.encoder().encode(pack), as: UTF8.self)
            #expect(!json.contains("Authorization") && !json.contains("api_key"), "\(name)")
            #expect(try ContextPack.decoder().decode(ContextPack.self, from: Data(json.utf8)) == pack, "\(name)")
        }
        let packs = try Self.packs()
        #expect(packs["work-search-truncated"]?.truncation.truncated == true)
        // One earlier turn went past the position and one went to another model; the included one is resent without its
        // citation marker (R2-02, R2-03).
        #expect(packs["work-search-restricted"]?.history.excludedTurnCount == 2)
        #expect(packs["work-search-restricted"]?.history.includedTurns.map(\.answer) == ["A new doctor in Middlemarch [earlier source]."])
        #expect(packs.values.allSatisfy { $0.historyViolations.isEmpty })
        #expect(packs["work-search-no-position"]?.limitations.map(\.code) == [.noEnforceablePosition])
        #expect(packs["work-search-no-position"]?.coverage == .noPassages)
        #expect(packs["selected-thoughts-audio-unavailable"]?.limitations.map(\.code) == [.audioPassageUnavailable])
        let thoughts = try #require(packs["selected-thoughts-restricted"])
        #expect(thoughts.evidence.map(\.origin) == [.savedQuote, .userNote])
        #expect(thoughts.evidence[0].position != nil && thoughts.evidence[0].workID == thoughts.work?.workID)
        #expect(thoughts.evidence[1].position == nil && thoughts.evidence[1].workID != thoughts.work?.workID)
        #expect(thoughts.spoilerBoundary.enabled && thoughts.spoilerBoundary.excludedEvidenceCount == 1)
        #expect(packs.values.allSatisfy { $0.spoilerBoundaryViolations.isEmpty })
    }

    /// R1-10: committed fixtures are regenerated byte for byte. Two independent builds give the same instances
    /// (fresh random UUIDs in each), and stabilizing keeps equal IDs equal and distinct IDs distinct.
    @Test func exportIsDeterministic() throws {
        let encoder = ContextPack.encoder()
        let first = try Self.packs().mapValues { try encoder.encode($0) }
        let second = try Self.packs().mapValues { try encoder.encode($0) }
        #expect(first == second)
        let configsA = try Self.configs().mapValues { try encoder.encode($0) }
        let configsB = try Self.configs().mapValues { try encoder.encode($0) }
        #expect(configsA == configsB)
        let raw = try Self.rawPacks()["work-search-restricted"]!
        let stable = try Self.packs()["work-search-restricted"]!
        #expect(Set(stable.evidence.map(\.evidenceID)).count == raw.evidence.count)
        #expect(stable.evidence.allSatisfy { $0.workID == stable.work?.workID }, "a repeated ID maps to the same stable ID")
        #expect(stable.packID != stable.requestID && stable.requestID != stable.conversationID)
        #expect(stable.digestIsValid)
    }

    @Test func configsNormalizeAndPassPolicy() throws {
        for (name, config) in Self.configs() {
            #expect(throws: Never.self, "\(name)") { try EndpointPolicy.assess(config) }
            #expect(!config.endpointURL.absoluteString.contains("/v1/v1"), "\(name)")
            #expect(config.credentialMatchesOrigin, "\(name): the key is bound to the configuration's own origin")
        }
        #expect(Self.configs()["gateway-declared-hosted"]?.baseURL.absoluteString == "https://gateway.example.com/api/v1")
    }

    @Test func exportInstancesForSchemaValidation() throws {
        guard let directory = Self.exportDirectory else {
            // Without the variable this test still built and encoded every instance above; it writes nothing.
            #expect(Self.configs().count == 5)
            #expect(try Self.packs().count == 8)
            return
        }
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let encoder = ContextPack.encoder()
        encoder.outputFormatting = [.sortedKeys, .prettyPrinted, .withoutEscapingSlashes]
        for (name, pack) in try Self.packs() {
            try encoder.encode(pack).write(to: directory.appendingPathComponent("context-pack.\(name).json"))
        }
        for (name, config) in Self.configs() {
            try encoder.encode(config).write(to: directory.appendingPathComponent("provider-config.\(name).json"))
        }
        #expect(try FileManager.default.contentsOfDirectory(atPath: directory.path).count >= 10)
    }
}
