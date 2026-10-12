import Foundation
import Synchronization
import SylviaAI

/// A deterministic `TextGenerationProvider` for lifecycle tests. Each call to `streamGeneration` consumes the
/// next script; the provider records every request it was given.
public final class ScriptedProvider: TextGenerationProvider {
    public enum Step: Sendable {
        case event(GenerationEvent)
        case fail(ProviderError)
        case pause(milliseconds: Int)
        /// Runs a hook (for example: advance a manual clock, or inspect the store mid-stream).
        case hook(@Sendable () async -> Void)
        /// Waits until the consumer cancels; after 10 s without a stop the stream fails instead.
        case waitForCancellation
    }

    public let config: ProviderConfig
    private let scripts: Mutex<[[Step]]>
    private let requestLog = Mutex<[GenerationRequest]>([])

    public init(config: ProviderConfig, scripts: [[Step]]) {
        self.config = config
        self.scripts = Mutex(scripts)
    }

    public var requests: [GenerationRequest] { requestLog.withLock { $0 } }

    public func streamGeneration(_ request: GenerationRequest) -> AsyncThrowingStream<GenerationEvent, any Error> {
        requestLog.withLock { $0.append(request) }
        let steps = scripts.withLock { scripts -> [Step] in
            scripts.isEmpty ? [.fail(ProviderError(kind: .invalidResponse, acceptance: .uncertain, host: "scripted", detail: "no script left"))]
                : scripts.removeFirst()
        }
        return AsyncThrowingStream { continuation in
            let task = Task {
                do {
                    for step in steps {
                        try Task.checkCancellation()
                        switch step {
                        case .event(let event): continuation.yield(event)
                        case .fail(let error): throw error
                        case .pause(let ms): try await Task.sleep(for: .milliseconds(ms))
                        case .hook(let hook): await hook()
                        case .waitForCancellation:
                            // Bounded, so a missing stop (for example a removed cap, in a mutation check) fails the
                            // test instead of hanging the suite.
                            let deadline = ContinuousClock.now + .seconds(10)
                            while !Task.isCancelled && ContinuousClock.now < deadline { try? await Task.sleep(for: .milliseconds(5)) }
                            if Task.isCancelled { throw CancellationError() }
                            throw ProviderError(kind: .invalidResponse, acceptance: .uncertain, host: "scripted",
                                                detail: "scripted stream waited 10 s for a stop that never came")
                        }
                    }
                    continuation.finish()
                } catch {
                    continuation.finish(throwing: error)
                }
            }
            continuation.onTermination = { _ in task.cancel() }
        }
    }
}

/// Wraps several providers by origin, recording which ones were ever asked to generate. Used to prove that a
/// failing provider never causes another to be called (no fallback, I-07).
public final class ProviderRegistry: Sendable {
    private let providers: [UUID: any TextGenerationProvider]
    private let calls = Mutex<[UUID]>([])

    public init(_ providers: [any TextGenerationProvider]) {
        var map: [UUID: any TextGenerationProvider] = [:]
        for provider in providers { map[provider.config.providerID] = provider }
        self.providers = map
    }

    public func provider(for config: ProviderConfig) -> any TextGenerationProvider {
        calls.withLock { $0.append(config.providerID) }
        return providers[config.providerID]!
    }

    public var calledProviderIDs: [UUID] { calls.withLock { $0 } }
}
