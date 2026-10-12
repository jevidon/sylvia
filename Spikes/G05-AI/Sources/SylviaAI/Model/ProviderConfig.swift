import Foundation

/// The wire dialect an adapter speaks. Each has its own request builder and stream decoder (plan 14.1).
public enum ProviderKind: String, Codable, Sendable, CaseIterable {
    /// OpenAI Responses API, `POST {base}/responses` (ADR-0011 explains the choice).
    case openAIResponses = "openai_responses"
    /// Anthropic Messages API, `POST {base}/messages`.
    case anthropicMessages = "anthropic_messages"
    /// Generic OpenAI-compatible chat, `POST {base}/chat/completions` relative to an explicit base URL.
    case openAICompatibleChat = "openai_compatible_chat"
    /// OpenAI-compatible speech-to-text, `POST {base}/audio/transcriptions`.
    case openAICompatibleTranscription = "openai_compatible_transcription"

    public var isTextGeneration: Bool { self != .openAICompatibleTranscription }

    /// The documented default base for first-party providers. Generic kinds have none: the user supplies it.
    public var defaultBaseURL: URL? {
        switch self {
        case .openAIResponses: URL(string: "https://api.openai.com/v1")
        case .anthropicMessages: URL(string: "https://api.anthropic.com/v1")
        case .openAICompatibleChat, .openAICompatibleTranscription: nil
        }
    }

    /// Path appended to the normalized base. None of these contain a version segment, so joining never
    /// produces `/v1/v1` (the version, if any, belongs to the base).
    public var endpointPath: String {
        switch self {
        case .openAIResponses: "responses"
        case .anthropicMessages: "messages"
        case .openAICompatibleChat: "chat/completions"
        case .openAICompatibleTranscription: "audio/transcriptions"
        }
    }
}

/// Who operates the endpoint, as disclosed to the user (plan 4.4.6 "Endpoint disclosure", 14.2).
/// Ordered from narrowest to broadest; a user may declare a broader class than the automatic one, never a narrower one.
public enum EndpointClassification: String, Codable, Sendable, Comparable, CaseIterable {
    case local
    case userManaged = "user_managed"
    case hosted

    var rank: Int {
        switch self {
        case .local: 0
        case .userManaged: 1
        case .hosted: 2
        }
    }

    public static func < (lhs: Self, rhs: Self) -> Bool { lhs.rank < rhs.rank }

    /// Disclosure word used in "{host} · {classification} · {model}".
    public var disclosureWord: String {
        switch self {
        case .local: "local"
        case .userManaged: "user-managed"
        case .hosted: "hosted"
        }
    }
}

/// Optional capabilities. None is required to configure a custom endpoint (plan 14.1).
public struct ProviderCapabilities: Codable, Sendable, Equatable {
    public var streaming: Bool
    /// Send `stream_options.include_usage` (chat dialect only); many compatible servers reject unknown options.
    public var streamUsage: Bool
    public var modelListing: Bool
    public var tokenCounting: Bool
    /// Transcription: request segment timing (`verbose_json`).
    public var timestamps: Bool

    public init(streaming: Bool = true, streamUsage: Bool = false, modelListing: Bool = false,
                tokenCounting: Bool = false, timestamps: Bool = false) {
        self.streaming = streaming
        self.streamUsage = streamUsage
        self.modelListing = modelListing
        self.tokenCounting = tokenCounting
        self.timestamps = timestamps
    }

    enum CodingKeys: String, CodingKey {
        case streaming
        case streamUsage = "stream_usage"
        case modelListing = "model_listing"
        case tokenCounting = "token_counting"
        case timestamps
    }
}

/// A reference to a credential held in the Keychain. The secret itself never appears in this model,
/// in SQLite, in exports or in logs (plan 14.2; Contracts README "Secrets").
///
/// The key is bound to the origin it was entered for (plan 18.1: endpoint credentials are origin-scoped). `origin` is
/// part of the reference and of the Keychain item's identity, and the providers send the key only to a request whose
/// origin equals it. A configuration whose base URL was edited to another origin, or an imported configuration that
/// names a key with another origin's base URL, therefore never sends the key there: the request stops before it leaves
/// with "enter the key for this address" (`ProviderError.credentialForAnotherOrigin`).
public struct CredentialRef: Codable, Sendable, Hashable {
    public var store: String
    public var account: UUID
    /// scheme://host[:port] as `Origin` writes it (lowercase, default port omitted), for example https://api.openai.com.
    public var origin: String

    public init(account: UUID = UUID(), origin: String) {
        self.store = "keychain"
        self.account = account
        self.origin = origin
    }

    /// A reference for a key entered for `baseURL`'s origin; nil when the URL has no origin.
    public init?(account: UUID = UUID(), for baseURL: URL) {
        guard let origin = Origin(baseURL) else { return nil }
        self.init(account: account, origin: origin.description)
    }
}

/// Provider configuration (Contracts/schemas/provider-config.v1.schema.json). Holds no secret.
public struct ProviderConfig: Codable, Sendable, Equatable {
    public var schemaVersion: Int = 1
    public var providerID: UUID
    public var kind: ProviderKind
    public var displayName: String
    /// Normalized once at configuration time with `BaseURL.normalize`.
    public var baseURL: URL
    /// Entered manually or picked from a listing; never hard-coded in domain logic.
    public var model: String
    public var credential: CredentialRef?
    public var capabilities: ProviderCapabilities
    /// Configured or discovered model context limit; nil means unknown (a conservative default applies).
    public var contextLimitTokens: Int?
    public var maxOutputTokens: Int?
    public var requestTimeoutMs: Int?
    /// The class the user declared. The effective class is never narrower than the automatic one.
    public var declaredClassification: EndpointClassification?
    /// Explicit opt-in for cleartext HTTP; honoured only for eligible local endpoints (EndpointPolicy).
    public var allowInsecureLocalHTTP: Bool

    public init(providerID: UUID = UUID(), kind: ProviderKind, displayName: String, baseURL: URL, model: String,
                credential: CredentialRef?, capabilities: ProviderCapabilities = ProviderCapabilities(),
                contextLimitTokens: Int? = nil, maxOutputTokens: Int? = nil, requestTimeoutMs: Int? = nil,
                declaredClassification: EndpointClassification? = nil, allowInsecureLocalHTTP: Bool = false) {
        self.providerID = providerID
        self.kind = kind
        self.displayName = displayName
        self.baseURL = baseURL
        self.model = model
        self.credential = credential
        self.capabilities = capabilities
        self.contextLimitTokens = contextLimitTokens
        self.maxOutputTokens = maxOutputTokens
        self.requestTimeoutMs = requestTimeoutMs
        self.declaredClassification = declaredClassification
        self.allowInsecureLocalHTTP = allowInsecureLocalHTTP
    }

    enum CodingKeys: String, CodingKey {
        case schemaVersion = "schema_version"
        case providerID = "provider_id"
        case kind = "provider_kind"
        case displayName = "display_name"
        case baseURL = "base_url"
        case model
        case credential = "credential_ref"
        case capabilities
        case contextLimitTokens = "context_limit_tokens"
        case maxOutputTokens = "max_output_tokens"
        case requestTimeoutMs = "request_timeout_ms"
        case declaredClassification = "privacy_classification"
        case allowInsecureLocalHTTP = "allow_insecure_local_http"
    }

    /// The full endpoint URL for this provider's dialect.
    public var endpointURL: URL { BaseURL.join(baseURL, kind.endpointPath) }

    /// True when the configuration names no key, or a key entered for the origin of its base URL (plan 18.1). The
    /// providers send a key only when this holds; settings should ask for the key again when an edit breaks it.
    public var credentialMatchesOrigin: Bool {
        guard let credential else { return true }
        return Origin(baseURL)?.description == credential.origin
    }
}

/// Model and endpoint identity without credentials, recorded with every request (plan 11.2).
public struct EndpointIdentity: Codable, Sendable, Equatable {
    public var providerKind: ProviderKind
    public var host: String
    public var origin: String
    public var basePath: String
    public var classification: EndpointClassification
    public var model: String

    public init(providerKind: ProviderKind, host: String, origin: String, basePath: String,
                classification: EndpointClassification, model: String) {
        self.providerKind = providerKind
        self.host = host
        self.origin = origin
        self.basePath = basePath
        self.classification = classification
        self.model = model
    }

    enum CodingKeys: String, CodingKey {
        case providerKind = "provider_kind"
        case host
        case origin
        case basePath = "base_path"
        case classification
        case model
    }

    /// The persistent disclosure row: "{host} · hosted · {model}" (plan 4.4.6, 14.2).
    public var disclosureRow: String { "\(host) · \(classification.disclosureWord) · \(model)" }

    /// True when both name the same destination as consent defines it (`ConsentLedger`): the same origin, effective
    /// classification and model.
    public func isSameDestination(as other: EndpointIdentity) -> Bool {
        origin == other.origin && classification == other.classification && model == other.model
    }
}
