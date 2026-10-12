import Foundation
import SylviaAI

/// Test transport that sends a first-party request (for example https://api.openai.com/v1/responses) to the
/// loopback fake server instead, keeping the path, method, headers and body. It lets host tests exercise the
/// OpenAI and Anthropic adapters end to end without TLS or network access; TLS itself is covered by a separate
/// test against a non-TLS listener.
public struct LoopbackRewriteTransport: HTTPTransport {
    let target: URL
    let inner: URLSessionTransport

    public init(target: URL) {
        self.target = target
        self.inner = URLSessionTransport()
    }

    public func send(_ request: HTTPRequestSpec) async throws -> HTTPStreamResponse {
        var components = URLComponents(url: request.url, resolvingAgainstBaseURL: false)!
        components.scheme = target.scheme
        components.host = target.host()
        components.port = target.port
        var rewritten = request
        rewritten.url = components.url!
        return try await inner.send(rewritten)
    }
}
