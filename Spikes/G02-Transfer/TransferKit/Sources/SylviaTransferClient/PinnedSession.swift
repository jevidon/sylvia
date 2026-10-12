import Foundation
import Security
import Synchronization
import SylviaTransferCore

/// Checks the leaf certificate a peer presents against the pinned SPKI digest.
public enum PinnedTrustEvaluator {
    public enum Result: Equatable, Sendable {
        case matched
        case mismatched
        case noCertificate
    }

    public static func evaluate(_ trust: SecTrust, pin: SPKIPin) -> Result {
        guard let chain = SecTrustCopyCertificateChain(trust) as? [SecCertificate], let leaf = chain.first else {
            return .noCertificate
        }
        let der = [UInt8](SecCertificateCopyData(leaf) as Data)
        return pin.matches(certificateDER: der) ? .matched : .mismatched
    }

    /// The only answer to a server-trust challenge in the transfer client (foreground and background
    /// sessions): the presented leaf's SPKI digest must equal one of `acceptedPins`. Then, and only
    /// then, the challenge is answered with that trust; otherwise it is cancelled, so the handshake fails
    /// and no request line, header or body reaches the peer. There is no other trust override, no CA or
    /// host-name fallback and no "allow anyway" path (ADR-0008).
    ///
    /// Non-server-trust challenges get default handling (the sessions store no credentials).
    public static func answer(
        _ challenge: URLAuthenticationChallenge, acceptedPins: [SPKIPin]
    ) -> (disposition: URLSession.AuthChallengeDisposition, credential: URLCredential?, result: Result?) {
        guard challenge.protectionSpace.authenticationMethod == NSURLAuthenticationMethodServerTrust else {
            return (.performDefaultHandling, nil, nil)
        }
        guard let trust = challenge.protectionSpace.serverTrust else { return (.cancelAuthenticationChallenge, nil, .noCertificate) }
        var outcome = Result.mismatched
        for pin in acceptedPins {
            switch evaluate(trust, pin: pin) {
            case .matched: return (.useCredential, URLCredential(trust: trust), .matched)
            case .noCertificate: outcome = .noCertificate
            case .mismatched: continue
            }
        }
        return (.cancelAuthenticationChallenge, nil, outcome)
    }
}

/// Receives the events of one URLSession task.
protocol TaskSink: Sendable {
    /// Called once with the response head; returning false cancels the task before any body is kept.
    func head(_ response: HTTPURLResponse) -> Bool
    func body(_ data: Data)
    func complete(error: (any Error)?, pinMismatch: Bool)
}

/// The URLSession delegate for one paired source. Trust is decided only by the SPKI pin: the
/// certificate is self-signed, so there is no CA chain or host name to evaluate (ADR-0008). A
/// mismatch cancels the handshake, so no request line, header or body is ever sent to the peer.
final class PinnedSessionDelegate: NSObject, URLSessionDataDelegate, Sendable {
    let pin: SPKIPin
    private let sinks = Mutex<[Int: any TaskSink]>([:])
    private let mismatches = Mutex<Set<Int>>([])
    private let mismatchCount = Mutex<Int>(0)

    init(pin: SPKIPin) { self.pin = pin }

    func register(_ sink: any TaskSink, for task: URLSessionTask) {
        sinks.withLock { $0[task.taskIdentifier] = sink }
    }

    var pinMismatchesObserved: Int { mismatchCount.withLock { $0 } }

    func urlSession(
        _ session: URLSession, task: URLSessionTask, didReceive challenge: URLAuthenticationChallenge,
        completionHandler: @escaping @Sendable (URLSession.AuthChallengeDisposition, URLCredential?) -> Void
    ) {
        // HTTP or client-certificate challenges get default handling: the session stores no credentials,
        // so none is offered and the 401 (if any) reaches the caller.
        let answer = PinnedTrustEvaluator.answer(challenge, acceptedPins: [pin])
        if answer.result == .mismatched || answer.result == .noCertificate {
            mismatches.withLock { _ = $0.insert(task.taskIdentifier) }
            mismatchCount.withLock { $0 += 1 }
        }
        completionHandler(answer.disposition, answer.credential)
    }

    /// A source never redirects; a redirect must not inherit the pinned trust (plan 14.3).
    func urlSession(
        _ session: URLSession, task: URLSessionTask, willPerformHTTPRedirection response: HTTPURLResponse,
        newRequest request: URLRequest, completionHandler: @escaping @Sendable (URLRequest?) -> Void
    ) {
        completionHandler(nil)
    }

    func urlSession(
        _ session: URLSession, dataTask: URLSessionDataTask, didReceive response: URLResponse,
        completionHandler: @escaping @Sendable (URLSession.ResponseDisposition) -> Void
    ) {
        let sink = sinks.withLock { $0[dataTask.taskIdentifier] }
        guard let sink, let http = response as? HTTPURLResponse else {
            completionHandler(.cancel)
            return
        }
        completionHandler(sink.head(http) ? .allow : .cancel)
    }

    func urlSession(_ session: URLSession, dataTask: URLSessionDataTask, didReceive data: Data) {
        sinks.withLock { $0[dataTask.taskIdentifier] }?.body(data)
    }

    func urlSession(_ session: URLSession, task: URLSessionTask, didCompleteWithError error: (any Error)?) {
        let sink = sinks.withLock { $0.removeValue(forKey: task.taskIdentifier) }
        let mismatch = mismatches.withLock { $0.remove(task.taskIdentifier) != nil }
        sink?.complete(error: error, pinMismatch: mismatch)
    }

    func urlSession(
        _ session: URLSession, task: URLSessionTask, didFinishCollecting metrics: URLSessionTaskMetrics
    ) {
        if let observer = metricsObserver.withLock({ $0 }) {
            for transaction in metrics.transactionMetrics {
                observer(transaction.negotiatedTLSProtocolVersion, transaction.networkProtocolName)
            }
        }
    }

    /// Test and diagnostics hook: reports the negotiated TLS version and ALPN protocol of each request.
    let metricsObserver = Mutex<(@Sendable (tls_protocol_version_t?, String?) -> Void)?>(nil)
}

/// Builds the URLSession used for one source: ephemeral, no cache, cookies or credential storage,
/// TLS 1.2 minimum, no compression, no redirects.
enum PinnedSessionFactory {
    static func make(pin: SPKIPin, timeout: TimeInterval) -> (URLSession, PinnedSessionDelegate) {
        let delegate = PinnedSessionDelegate(pin: pin)
        let configuration = URLSessionConfiguration.ephemeral
        configuration.urlCache = nil
        configuration.httpCookieStorage = nil
        configuration.httpShouldSetCookies = false
        configuration.urlCredentialStorage = nil
        configuration.requestCachePolicy = .reloadIgnoringLocalAndRemoteCacheData
        configuration.tlsMinimumSupportedProtocolVersion = .TLSv12
        configuration.timeoutIntervalForRequest = timeout
        configuration.httpMaximumConnectionsPerHost = 2
        configuration.waitsForConnectivity = false
        let queue = OperationQueue()
        queue.maxConcurrentOperationCount = 1
        queue.name = "SylviaTransferClient.session"
        let session = URLSession(configuration: configuration, delegate: delegate, delegateQueue: queue)
        return (session, delegate)
    }
}
