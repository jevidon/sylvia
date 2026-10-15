import Foundation
import SylviaAI

/// Small hand-built ContextPacks for SylviaAI tests that do not need retrieval.
public enum TestPacks {
    public static let waldenPassage = "I went to the woods because I wished to live deliberately, to front only the essential facts of life, and see if I could not learn what it had to teach, and not, when I came to die, discover that I had not lived."

    public static func endpoint(for config: ProviderConfig) -> EndpointIdentity {
        try! EndpointIdentity.of(config)
    }

    public static func make(question: String = "What does Thoreau mean by living deliberately?", config: ProviderConfig,
                            evidence: [(text: String, origin: EvidenceOrigin)] = [(waldenPassage, .sourceText)],
                            createdAt: Date = Date(timeIntervalSince1970: 1_791_590_400), outputReserve: Int = 512) -> ContextPack {
        let work = WorkSnapshot(workID: UUID(), editionID: UUID(), title: "Walden", authorDisplay: "Henry David Thoreau", sourceKind: "local_epub")
        // Source text names the work and the edition its position counts in, as the builder writes it.
        let items = evidence.enumerated().map { index, item in
            EvidenceItem(citationID: "c\(index + 1)", role: item.origin == .sourceText ? .selection : .thought, origin: item.origin,
                         sourceQuality: item.origin == .sourceText ? .extractedText : .userEntered, text: item.text,
                         locationLabel: "Where I Lived, and What I Lived For", captureID: item.origin == .sourceText ? nil : UUID(),
                         workID: item.origin == .sourceText ? work.workID : nil, editionID: item.origin == .sourceText ? work.editionID : nil,
                         position: item.origin == .sourceText ? EvidencePosition(resourceHref: "text/where-i-lived-and-what-i-lived-for.xhtml", firstOrdinal: 40 + index, lastOrdinal: 40 + index) : nil,
                         estimatedTokens: item.text.utf8.count / 3 + 1)
        }
        let budget = BudgetAccounting(contextLimitTokens: 8192, contextLimitSource: .defaultUnknownModel, systemTokens: 200, questionTokens: 20,
                                      historyTokens: 0, outputReserveTokens: outputReserve, safetyMarginTokens: 819, evidenceBudgetTokens: 6000,
                                      evidenceTokens: items.map(\.estimatedTokens).reduce(0, +),
                                      estimator: TokenEstimatorInfo(kind: .heuristic, name: "utf8-bytes-div-3"), estimated: true)
        return ContextPack(conversationID: UUID(), createdAt: createdAt, scope: .selectedPassage, coverage: .excerptOnly, question: question,
                           work: work,
                           evidence: items, spoilerBoundary: .disabled, history: HistoryInclusion(), budget: budget, truncation: TruncationInfo(),
                           retrieval: nil, textCoverage: TextCoverage(state: .bookTextIndexed, resourcesIndexed: 18, resourcesTotal: 18),
                           endpoint: endpoint(for: config), promptTemplateVersion: PromptTemplate.version)
    }

    /// Parent of `scratchRoot`: `G05_TEST_SCRATCH` when set (CI points it into the spike's `.build` directory and checks
    /// that it is empty after the run), otherwise the system temporary directory.
    public static var scratchParent: URL {
        if let configured = ProcessInfo.processInfo.environment["G05_TEST_SCRATCH"], !configured.isEmpty {
            return URL(fileURLWithPath: configured, isDirectory: true)
        }
        return FileManager.default.temporaryDirectory
    }

    /// One directory per test process, holding every directory `temporaryDirectory` hands out (stored questions, packs,
    /// answers and queued clips). It is removed when the process exits, so test runs leave nothing behind (review R3-05;
    /// CI checks it).
    public static let scratchRoot: URL = {
        let root = scratchParent
            .appendingPathComponent("g05-tests-\(ProcessInfo.processInfo.processIdentifier)-\(UUID().uuidString.prefix(8))")
        try? FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        atexit { TestPacks.removeScratchRoot() }
        return root
    }()

    /// Removes this process's scratch directories. Runs at process exit.
    public static func removeScratchRoot() {
        try? FileManager.default.removeItem(at: scratchRoot)
    }

    /// A new empty directory under `scratchRoot`, removed with it when the test process exits.
    public static func temporaryDirectory(_ name: String = "g05") -> URL {
        let url = scratchRoot.appendingPathComponent("\(name)-\(UUID().uuidString)")
        try? FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }
}
