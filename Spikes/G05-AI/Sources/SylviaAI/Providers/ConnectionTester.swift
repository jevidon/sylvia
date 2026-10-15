import Foundation

/// Why an endpoint that answered the connection test still fails it (plan 14.1: a gateway or custom route is usable
/// only if it passes conformance tests as a text-only route with no side effects; plan 14.3: "invalid response"). The
/// test passes only when the reply ends normally with answer text.
public enum ConformanceFailure: Sendable, Equatable {
    /// The route answered with a tool call. Sylvia sends no tools and never runs one.
    case toolCall
    /// The model answered with a refusal instead of the test reply.
    case refused
    /// A content filter withheld the test reply.
    case contentFiltered
    /// The output limit was reached before any answer text (for example a model that reasons before answering).
    case outputLimitBeforeText(maxOutputTokens: Int)
    /// Answer text arrived but was cut off at the output limit.
    case outputLimitTruncated(maxOutputTokens: Int)
    /// The reply ended early for another reason (context window, a provider-reported incomplete state).
    case incomplete
}

public struct ConnectionTestReport: Sendable, Equatable {
    public enum Outcome: Sendable, Equatable {
        case passed
        case failed(ProviderError)
        /// The endpoint answered, but not with a usable text reply (plan 14.1 conformance).
        case failedConformance(ConformanceFailure)
    }

    public var outcome: Outcome
    public var endpoint: EndpointIdentity?
    /// What the provider reported as the serving model, when it did.
    public var reportedModel: String?
    /// True when the reply arrived as an event stream (from the adapter's delivery status, not from configuration).
    public var streamed: Bool
    public var usageReported: Bool
    public var finish: FinishReason?

    public var userMessage: String {
        let host = endpoint?.host ?? "The endpoint"
        switch outcome {
        case .passed:
            return "Connected to \(endpoint?.disclosureRow ?? "the endpoint"). Test reply received\(streamed ? " as a stream" : "")."
        case .failed(let error):
            return error.userMessage
        case .failedConformance(let failure):
            switch failure {
            case .toolCall:
                return "\(host) answered the test by asking to run a tool. Sylvia never runs tools, so it can't use this route. Configure a text-only route or model for this endpoint."
            case .refused:
                return "\(host) answered but refused the test question, so Sylvia can't confirm it will answer questions. Check the model and any content policy on this endpoint."
            case .contentFiltered:
                return "\(host) answered but a content filter withheld the test reply. Check the model and any content policy on this endpoint."
            case .outputLimitBeforeText(let tokens):
                return "\(host) reached the output limit (\(tokens) tokens) before any reply text. Models that reason before answering can do this. Raise the maximum output for this endpoint in provider settings."
            case .outputLimitTruncated(let tokens):
                return "\(host) started the test reply but was cut off at the output limit (\(tokens) tokens). Raise the maximum output for this endpoint in provider settings."
            case .incomplete:
                return "\(host) ended the test reply before finishing it. Check the model and provider type, then test again."
            }
        }
    }
}

/// Connection and capability test (plan 14.3). It sends only a fixed probe text, never book content or notes, and
/// classifies failures into the plan's categories with secret-free, actionable messages. It is also the route's
/// conformance check (plan 14.1): it passes only when the reply ends normally with answer text, so a route that
/// answers with a tool call, a refusal, a filtered reply or no text fails.
public struct ConnectionTester: Sendable {
    public static let probeSystem = "This is a connection test from a reading app."
    public static let probeQuestion = "Reply with the single word OK."
    /// Output limit for the probe when the configuration sets none. It equals the reserve real questions get
    /// (`BuilderSettings.defaultOutputReserveTokens`), so a model that reasons before answering has room to reply, and a
    /// route that passes has the room real questions get. A model that answers directly stops after a token or two.
    public static let defaultProbeOutputTokens = 1_024

    /// The fixed probe for `config`, with the output limit real questions to that configuration use.
    public static func probe(for config: ProviderConfig) -> GenerationRequest {
        GenerationRequest(system: probeSystem, messages: [.init(role: .user, text: probeQuestion)],
                          maxOutputTokens: config.maxOutputTokens ?? defaultProbeOutputTokens)
    }

    let credentials: any CredentialStore
    let transport: any HTTPTransport
    let inspector: any NetworkPathInspector
    let log: any AILogSink

    public init(credentials: any CredentialStore, transport: any HTTPTransport,
                inspector: any NetworkPathInspector = SystemNetworkPathInspector(), log: any AILogSink = NullLogSink()) {
        self.credentials = credentials
        self.transport = transport
        self.inspector = inspector
        self.log = log
    }

    public func test(_ config: ProviderConfig) async -> ConnectionTestReport {
        var report = ConnectionTestReport(outcome: .passed, endpoint: nil, reportedModel: nil, streamed: false, usageReported: false, finish: nil)
        do {
            report.endpoint = try EndpointIdentity.of(config)
        } catch {
            report.outcome = .failed(ProviderError(kind: .insecureEndpointRejected, acceptance: .notSent,
                                                   host: config.baseURL.host() ?? "", detail: error.userMessage))
            return report
        }
        let probe = Self.probe(for: config)
        let provider = HTTPTextGenerationProvider(config: config, credentials: credentials, transport: transport, log: log, inspector: inspector)
        var sawText = false
        var sawRefusal = false
        var sawToolCall = false
        do {
            for try await event in provider.streamGeneration(probe) {
                switch event {
                case .status(.accepted(_, let model)): report.reportedModel = model
                case .text(let text): sawText = sawText || !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                case .refusal(let text): sawRefusal = sawRefusal || !text.isEmpty
                case .status(.toolCallRejected): sawToolCall = true
                case .status(.delivery(let streamed)): report.streamed = streamed
                case .usage: report.usageReported = true
                case .finished(let reason): report.finish = reason
                case .status(.reasoningOmitted), .status(.finishReasonMissing): break
                }
            }
            report.outcome = Self.judge(finish: report.finish, sawText: sawText, sawRefusal: sawRefusal, sawToolCall: sawToolCall,
                                        maxOutputTokens: probe.maxOutputTokens, host: report.endpoint?.host ?? "")
        } catch {
            let classified = ErrorClassifier.classify(error, host: report.endpoint?.host ?? "", bodyMayHaveBeenSent: true, inspector: inspector)
            report.outcome = .failed(classified)
        }
        return report
    }

    /// Passes only a reply that ended normally with answer text and no refusal. A tool call fails whatever else
    /// arrived (I-04: a tool-emitting route is never usable); a refusal or a filter fails even with some text, because
    /// the endpoint did not give the reply that was asked for.
    static func judge(finish: FinishReason?, sawText: Bool, sawRefusal: Bool, sawToolCall: Bool, maxOutputTokens: Int,
                      host: String) -> ConnectionTestReport.Outcome {
        if sawToolCall || finish == .toolCallRejected { return .failedConformance(.toolCall) }
        guard let finish else {
            return .failed(ProviderError(kind: .invalidResponse, acceptance: .uncertain, host: host, detail: "no final event"))
        }
        switch finish {
        case .complete:
            if sawRefusal { return .failedConformance(.refused) }
            if sawText { return .passed }
            return .failed(ProviderError(kind: .invalidResponse, acceptance: .uncertain, host: host, detail: "empty reply"))
        case .refused: return .failedConformance(.refused)
        case .contentFiltered: return .failedConformance(.contentFiltered)
        case .outputLimit:
            return .failedConformance(sawText ? .outputLimitTruncated(maxOutputTokens: maxOutputTokens)
                                              : .outputLimitBeforeText(maxOutputTokens: maxOutputTokens))
        case .contextWindowExceeded, .incomplete: return .failedConformance(.incomplete)
        case .toolCallRejected: return .failedConformance(.toolCall)
        }
    }
}
