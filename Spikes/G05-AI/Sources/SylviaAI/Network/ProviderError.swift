import Foundation
import Network

/// Failure classes required by plan 14.3, plus the few the lifecycle needs.
public enum FailureKind: String, Codable, Sendable, CaseIterable {
    case dns
    case localNetworkPermissionDenied = "local_network_permission_denied"
    case hostUnreachable = "host_unreachable"
    case offline
    case tls
    case insecureEndpointRejected = "insecure_endpoint_rejected"
    case authentication
    case unsupportedModel = "unsupported_model"
    case unsupportedDialect = "unsupported_dialect"
    case rateLimited = "rate_limited"
    case quotaExhausted = "quota_exhausted"
    case invalidResponse = "invalid_response"
    case serverError = "server_error"
    case timeout
    case connectionLost = "connection_lost"
    case redirectBlocked = "redirect_blocked"
    case contextTooLong = "context_too_long"
    case badRequest = "bad_request"
    case providerStreamError = "provider_stream_error"
    case credentialMissing = "credential_missing"
    case cancelled
    /// The endpoint sent more than Sylvia accepts for one answer (plan 14.5 output caps).
    case responseSizeLimit = "response_size_limit"
    /// The endpoint was still sending after Sylvia's time limit for one answer (plan 14.5).
    case responseTimeLimit = "response_time_limit"
}

/// Whether the provider may have accepted (and billed) the generation (plan 14.4).
public enum Acceptance: String, Codable, Sendable {
    /// The request never reached the server (DNS, connect, TLS, ATS, offline, policy).
    case notSent = "not_sent"
    /// The server answered with an error status before generating.
    case rejected
    /// The request may have been accepted: timeout or connection loss after sending, or failure mid-stream.
    case uncertain
}

public struct ProviderError: Error, Sendable, Equatable, CustomStringConvertible {
    public var kind: FailureKind
    public var acceptance: Acceptance
    public var host: String
    public var httpStatus: Int?
    public var retryAfter: Duration?
    /// Provider error code or type (for example "rate_limit_error"), already scrubbed.
    public var providerCode: String?
    /// Short technical detail, already scrubbed; never shown without `userMessage`.
    public var detail: String?

    /// `detail` of a `credentialMissing` failure whose stored key was entered for another origin (plan 18.1).
    public static let credentialForAnotherOrigin = "credential bound to another origin"

    public init(kind: FailureKind, acceptance: Acceptance, host: String, httpStatus: Int? = nil,
                retryAfter: Duration? = nil, providerCode: String? = nil, detail: String? = nil) {
        self.kind = kind
        self.acceptance = acceptance
        self.host = host
        self.httpStatus = httpStatus
        self.retryAfter = retryAfter
        self.providerCode = providerCode
        self.detail = detail
    }

    /// Automatic retry is allowed only for transient failures where the generation was certainly not
    /// accepted (plan 14.4). An uncertain generation is never replayed without asking the user.
    public var isTransient: Bool {
        guard acceptance != .uncertain else { return false }
        switch kind {
        case .dns, .hostUnreachable, .rateLimited, .serverError: return true
        default: return false
        }
    }

    public var description: String {
        var parts = ["ProviderError(\(kind.rawValue)", "acceptance=\(acceptance.rawValue)", "host=\(host)"]
        if let httpStatus { parts.append("http=\(httpStatus)") }
        if let providerCode { parts.append("code=\(providerCode)") }
        return parts.joined(separator: " ") + ")"
    }

    /// Actionable, secret-free text for the user (plan 14.3: no generic "AI failed").
    public var userMessage: String {
        switch kind {
        case .dns:
            "Couldn't find \(host). Check the address for typos, or check that this network can resolve it."
        case .localNetworkPermissionDenied:
            "Sylvia isn't allowed to reach devices on your local network, so \(host) can't be contacted. Turn on Local Network for Sylvia in Settings › Privacy & Security › Local Network."
        case .hostUnreachable:
            "\(host) didn't accept the connection. Check that the server is running and listening on that port, and that this device can reach it."
        case .offline:
            "This device is offline. Your question is saved on this device and has not been sent."
        case .tls:
            "The secure connection to \(host) failed, so nothing was sent. The server's certificate isn't trusted or the server doesn't speak HTTPS on this port."
        case .insecureEndpointRejected:
            "\(host) uses an unencrypted connection that isn't allowed. Use an https:// address."
        case .authentication:
            httpStatus == 403
                ? "\(host) refused this key for the request (HTTP 403). Check that the key has access to this model and project."
                : "\(host) rejected the key (HTTP \(httpStatus.map(String.init) ?? "401")). Enter the key again in provider settings."
        case .unsupportedModel:
            "\(host) doesn't offer the model you entered. Check the model name in provider settings."
        case .unsupportedDialect:
            "\(host) doesn't answer this kind of request at this address (HTTP \(httpStatus.map(String.init) ?? "?")). Check the API base address; many servers expect it to end in /v1."
        case .rateLimited:
            retryAfter.map {
                Self.seconds($0) > 3_600
                    ? "\(host) is limiting requests and asked Sylvia to wait more than an hour. Try again later."
                    : "\(host) is limiting requests. You can try again in about \(Self.seconds($0)) seconds."
            } ?? "\(host) is limiting requests. Wait a moment and try again."
        case .quotaExhausted:
            "\(host) reports that the account has no remaining quota or credit. Check billing with the provider."
        case .invalidResponse:
            "\(host) sent a response Sylvia couldn't read as this provider type. Check the provider type and address."
        case .serverError:
            acceptance == .uncertain
                ? "\(host) reported a server or gateway error (HTTP \(httpStatus.map(String.init) ?? "5xx")). The request may or may not have been processed, so Sylvia won't send it again without asking."
                : "\(host) had a temporary problem (HTTP \(httpStatus.map(String.init) ?? "5xx")). Try again shortly."
        case .timeout:
            "\(host) stopped responding. The request may or may not have been processed."
        case .connectionLost:
            "The connection to \(host) dropped. The request may or may not have been processed."
        case .redirectBlocked:
            "\(host) tried to redirect the request to a different address\(detail.map { " (\($0))" } ?? ""). Sylvia doesn't follow redirects to other hosts, so nothing was sent there. Update the base address if the service has moved."
        case .contextTooLong:
            "The question and its passages are too long for this model. Choose a narrower context and try again."
        case .badRequest:
            "\(host) rejected the request (HTTP \(httpStatus.map(String.init) ?? "400")). Check the model and provider type."
        case .providerStreamError:
            "\(host) reported an error while answering\(providerCode.map { " (\($0))" } ?? "")."
        case .credentialMissing:
            detail == Self.credentialForAnotherOrigin
                ? "The key stored for this provider was entered for a different address, so Sylvia won't send it to \(host). Enter the key for this address in provider settings."
                : "No key is stored for this provider. Enter it in provider settings."
        case .cancelled:
            "Cancelled."
        case .responseSizeLimit:
            "\(host) sent more than Sylvia accepts for one answer, so Sylvia stopped reading. What arrived up to that point is kept and labelled as partial."
        case .responseTimeLimit:
            "\(host) was still sending after Sylvia's time limit for one answer, so Sylvia stopped reading. What arrived up to that point is kept and labelled as partial."
        }
    }

    static func seconds(_ duration: Duration) -> Int {
        Int((Double(duration.components.seconds) + Double(duration.components.attoseconds) / 1e18).rounded(.up))
    }
}

/// Hook for reading why the system considered the network unsatisfied. Real implementation inspects the
/// NWPath URLSession attaches to the error; tests inject a fake (permission denial cannot be produced on host).
public protocol NetworkPathInspector: Sendable {
    func isLocalNetworkDenied(_ error: URLError) -> Bool
}

public struct SystemNetworkPathInspector: NetworkPathInspector {
    public init() {}
    public func isLocalNetworkDenied(_ error: URLError) -> Bool {
        // URLSession attaches the NWPath under this key when a path is unsatisfied (iOS 14+).
        guard let path = error.userInfo["_NSURLErrorNWPathKey"] as? NWPath else { return false }
        if case .unsatisfied = path.status, path.unsatisfiedReason == .localNetworkDenied { return true }
        return false
    }
}

public enum ErrorClassifier {
    /// Classifies a transport-level error. `bodySent` reflects whether request bytes may have reached the server.
    public static func classify(_ error: any Error, host: String, bodyMayHaveBeenSent: Bool,
                                inspector: any NetworkPathInspector = SystemNetworkPathInspector()) -> ProviderError {
        if let providerError = error as? ProviderError { return providerError }
        if error is CancellationError { return ProviderError(kind: .cancelled, acceptance: bodyMayHaveBeenSent ? .uncertain : .notSent, host: host) }
        guard let urlError = error as? URLError else {
            return ProviderError(kind: .connectionLost, acceptance: bodyMayHaveBeenSent ? .uncertain : .notSent, host: host,
                                 detail: String(describing: type(of: error)))
        }
        let uncertain: Acceptance = bodyMayHaveBeenSent ? .uncertain : .notSent
        switch urlError.code {
        case .cannotFindHost, .dnsLookupFailed:
            return ProviderError(kind: .dns, acceptance: .notSent, host: host, detail: "URLError \(urlError.code.rawValue)")
        case .cannotConnectToHost:
            return ProviderError(kind: .hostUnreachable, acceptance: .notSent, host: host, detail: "URLError \(urlError.code.rawValue)")
        case .notConnectedToInternet, .internationalRoamingOff, .dataNotAllowed, .callIsActive:
            if inspector.isLocalNetworkDenied(urlError) {
                return ProviderError(kind: .localNetworkPermissionDenied, acceptance: .notSent, host: host, detail: "URLError \(urlError.code.rawValue)")
            }
            return ProviderError(kind: .offline, acceptance: .notSent, host: host, detail: "URLError \(urlError.code.rawValue)")
        case .secureConnectionFailed, .serverCertificateHasBadDate, .serverCertificateUntrusted,
             .serverCertificateHasUnknownRoot, .serverCertificateNotYetValid, .clientCertificateRejected,
             .clientCertificateRequired:
            return ProviderError(kind: .tls, acceptance: .notSent, host: host, detail: "URLError \(urlError.code.rawValue)")
        case .appTransportSecurityRequiresSecureConnection:
            return ProviderError(kind: .insecureEndpointRejected, acceptance: .notSent, host: host, detail: "URLError \(urlError.code.rawValue)")
        case .timedOut:
            return ProviderError(kind: .timeout, acceptance: uncertain, host: host, detail: "URLError \(urlError.code.rawValue)")
        case .networkConnectionLost:
            return ProviderError(kind: .connectionLost, acceptance: uncertain, host: host, detail: "URLError \(urlError.code.rawValue)")
        case .cancelled:
            return ProviderError(kind: .cancelled, acceptance: uncertain, host: host)
        case .badServerResponse, .cannotParseResponse, .cannotDecodeRawData, .cannotDecodeContentData:
            return ProviderError(kind: .invalidResponse, acceptance: uncertain, host: host, detail: "URLError \(urlError.code.rawValue)")
        default:
            return ProviderError(kind: .connectionLost, acceptance: uncertain, host: host, detail: "URLError \(urlError.code.rawValue)")
        }
    }

    /// Whether a 5xx reply means the generation certainly was not accepted (plan 14.4: retry 5xx automatically, but
    /// never replay a generation whose acceptance is uncertain).
    ///
    /// - 503 (service unavailable) and 529 (Anthropic: overloaded) say the service did not take the request. From a
    ///   hosted service or a local server (for example llama.cpp answering 503 while it loads a model) they are
    ///   `rejected`, so the request is retried automatically.
    /// - 502 and 504 are a gateway or proxy reporting an upstream failure or timeout: the upstream provider may already
    ///   have accepted and billed the generation, so they are `uncertain` from any endpoint.
    /// - 500 and every other 5xx say the server failed while handling the request, which may be after generation
    ///   started: `uncertain`.
    /// - A user-managed endpoint may itself be a gateway (Hermes, a commercial gateway, a tailnet proxy) relaying any
    ///   status from an upstream that accepted the request, so every 5xx from it is `uncertain`. An unknown
    ///   classification is treated as user-managed.
    /// `uncertain` failures end `failed_retryable` and are resent only after the user confirms.
    public static func serverErrorAcceptance(status: Int, classification: EndpointClassification?) -> Acceptance {
        switch (status, classification) {
        case (503, .hosted), (503, .local), (529, .hosted), (529, .local): .rejected
        default: .uncertain
        }
    }

    /// Classifies an HTTP error response from the status, headers and (bounded, scrubbed) body. `classification` is the
    /// endpoint's effective classification; it decides whether a 5xx is certainly not accepted
    /// (`serverErrorAcceptance`).
    public static func classifyHTTP(status: Int, headers: [String: String], body: Data, host: String,
                                    redactor: Redactor, classification: EndpointClassification? = nil, now: Date = Date()) -> ProviderError {
        let parsed = ProviderErrorBody.parse(body)
        let code = parsed.code.map(redactor.scrub)
        let message = parsed.message.map(redactor.scrub)
        let lowerMessage = (message ?? "").lowercased()
        let retryAfter = RetryAfter.parse(headers["retry-after"], now: now)
        let mentionsModel = lowerMessage.contains("model") || (code?.contains("model") ?? false)

        func make(_ kind: FailureKind) -> ProviderError {
            ProviderError(kind: kind, acceptance: .rejected, host: host, httpStatus: status,
                          retryAfter: retryAfter, providerCode: code, detail: message)
        }

        if code == "context_length_exceeded" || lowerMessage.contains("context length") || lowerMessage.contains("context window")
            || lowerMessage.contains("prompt is too long") || lowerMessage.contains("maximum context") {
            return make(.contextTooLong)
        }
        switch status {
        case 401: return make(.authentication)
        case 402: return make(.quotaExhausted)
        case 403: return make(.authentication)
        case 404: return make(mentionsModel ? .unsupportedModel : .unsupportedDialect)
        case 405, 415, 501: return make(.unsupportedDialect)
        case 400, 422:
            if code == "model_not_found" || (mentionsModel && (lowerMessage.contains("not found") || lowerMessage.contains("does not exist")
                || lowerMessage.contains("not supported") || lowerMessage.contains("invalid model") || lowerMessage.contains("unknown model"))) {
                return make(.unsupportedModel)
            }
            if code == "insufficient_quota" || lowerMessage.contains("credit balance") || lowerMessage.contains("spend limit") {
                return make(.quotaExhausted)
            }
            return make(.badRequest)
        case 408: return make(.timeout)
        case 413: return make(.contextTooLong)
        case 429:
            return make(code == "insufficient_quota" ? .quotaExhausted : .rateLimited)
        default:
            guard status >= 500 else { return make(.badRequest) }
            var error = make(.serverError)
            error.acceptance = serverErrorAcceptance(status: status, classification: classification)
            return error
        }
    }
}

/// OpenAI: {"error": {"message", "type", "param", "code"}}; Anthropic: {"type":"error","error":{"type","message"}}.
struct ProviderErrorBody {
    var code: String?
    var message: String?

    static func parse(_ body: Data) -> ProviderErrorBody {
        guard !body.isEmpty, let object = try? JSONSerialization.jsonObject(with: body.prefix(65_536)) as? [String: Any] else {
            return ProviderErrorBody()
        }
        if let error = object["error"] as? [String: Any] {
            let code = (error["code"] as? String) ?? (error["type"] as? String)
            return ProviderErrorBody(code: code, message: error["message"] as? String)
        }
        if let message = object["error"] as? String { return ProviderErrorBody(code: nil, message: message) }
        return ProviderErrorBody(code: object["code"] as? String, message: object["message"] as? String)
    }
}

public enum RetryAfter {
    /// Longest wait Sylvia records from a Retry-After header. Larger or absurd values (a hostile or broken server can
    /// send any number) are clamped to this, which is far above `RetryPolicy.maxRetryAfter`, so they read as
    /// "too long to wait" and never overflow a conversion.
    public static let ceiling: Duration = .seconds(86_400)

    /// Parses Retry-After as delta-seconds (`1*DIGIT`) or an HTTP-date (RFC 9110 10.2.3). Anything else is ignored.
    /// The value comes from an untrusted server: it is clamped to `ceiling` and never converted unchecked.
    public static func parse(_ value: String?, now: Date) -> Duration? {
        guard let raw = value?.trimmingCharacters(in: .whitespaces), !raw.isEmpty else { return nil }
        if raw.allSatisfy(\.isASCIIDigit) {
            // Ten or more digits is beyond the ceiling whatever the value; Int parsing of the rest cannot overflow.
            guard raw.count < 10, let seconds = Int(raw) else { return ceiling }
            return min(.seconds(seconds), ceiling)
        }
        guard raw.utf8.count <= 64 else { return nil }
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone(identifier: "GMT")
        formatter.dateFormat = "EEE, dd MMM yyyy HH:mm:ss zzz"
        guard let date = formatter.date(from: raw) else { return nil }
        let interval = date.timeIntervalSince(now)
        guard interval.isFinite else { return nil }
        let ceilingSeconds = Double(ceiling.components.seconds)
        guard interval < ceilingSeconds else { return ceiling }
        return .milliseconds(Int64(max(0, interval) * 1000))
    }
}
