import Foundation
import SylviaTransferCore

/// Downloads one item version part by part, verifying each part before it counts, retrying only
/// failed parts, refreshing the manifest when the version changes, and handing off only after every
/// asset's full SHA-256 matches (plan 15.4, 15.5; tests T38-T40).
///
/// This engine uses foreground requests through `SourceClient`; the iOS background client reuses its
/// staging store, validation and state machine with background URLSession download tasks.
public actor TransferEngine {
    public struct Options: Sendable {
        public var concurrency = 2
        public var maxAttemptsPerPart = 4
        public var maxManifestRefreshes = 4
        public var preferredPartSize: Int64?
        public var verifyStagedPartsOnOpen = true
        public var retryDelay: Duration = .milliseconds(20)
        /// While the Mac answers 503 `preparing` (clone and hash still running), ask again this often...
        public var preparationPollInterval: Duration = .seconds(2)
        /// ...for at most this long, then pause with `sourcePreparing`.
        public var maxPreparationWait: Duration = .seconds(1800)
        public init() {}
    }

    public enum Event: Sendable, Equatable {
        /// The Mac is still preparing the item ("Preparing transfer", plan 16.2); nothing is downloading yet.
        case sourcePreparing
        case manifestFetched(itemVersionID: String)
        case versionChanged(from: String, to: String, keptParts: Int, discardedParts: Int)
        case resumed(assetID: String, verifiedParts: Int)
        case partRequested(assetID: String, index: Int, attempt: Int)
        case partVerified(assetID: String, index: Int)
        case partFailed(assetID: String, index: Int, failure: PartFailure)
        case assetFinalized(assetID: String)
        case paused(PauseReason)
    }

    public struct ReadyAsset: Sendable, Equatable {
        public var assetID: String
        public var url: URL
        public var length: Int64
        public var sha256: String
    }

    public enum Outcome: Sendable, Equatable {
        case ready(manifest: TransferManifest, assets: [ReadyAsset])
        case paused(PauseReason, TransferProgress)
    }

    private struct PartRef: Hashable, Sendable {
        var asset: Int
        var part: Int
    }

    private enum RoundResult {
        case complete
        case refreshManifest
        case pause(PauseReason)
    }

    private let client: SourceClient
    private let itemID: String
    private let stagingRoot: URL
    private let options: Options
    private let onEvent: (@Sendable (Event) async -> Void)?
    private var stores: [PartStagingStore] = []
    private var machines: [PartRef: PartStateMachine] = [:]
    public private(set) var progress = TransferProgress(totalBytes: 0)

    public init(
        client: SourceClient, itemID: String, stagingRoot: URL, options: Options = Options(),
        onEvent: (@Sendable (Event) async -> Void)? = nil
    ) {
        self.client = client
        self.itemID = itemID
        self.stagingRoot = stagingRoot
        self.options = options
        self.onEvent = onEvent
    }

    public func run() async -> Outcome {
        var refreshes = 0
        var previousVersion: String?
        let clock = ContinuousClock()
        var preparingSince: ContinuousClock.Instant?
        while true {
            if Task.isCancelled { return await pause(.cancelled) }
            let manifest: TransferManifest
            do {
                manifest = try await client.manifest(itemID: itemID, partSize: options.preferredPartSize)
            } catch {
                if case .http(503, "preparing") = error {
                    let since = preparingSince ?? clock.now
                    preparingSince = since
                    guard clock.now - since < options.maxPreparationWait else { return await pause(.sourcePreparing) }
                    await onEvent?(.sourcePreparing)
                    do { try await Task.sleep(for: options.preparationPollInterval) } catch { return await pause(.cancelled) }
                    continue
                }
                return await pause(Self.pauseReason(for: error))
            }
            preparingSince = nil
            await onEvent?(.manifestFetched(itemVersionID: manifest.itemVersionID))
            let versionRoot = stagingRoot.appendingPathComponent(itemID, isDirectory: true)
            var kept = 0
            var discarded = 0
            do {
                stores = []
                machines = [:]
                for (assetIndex, asset) in manifest.assets.enumerated() {
                    let (store, reconciliation) = try PartStagingStore.open(
                        root: versionRoot, asset: asset, itemVersionID: manifest.itemVersionID,
                        verifyExistingParts: options.verifyStagedPartsOnOpen)
                    kept += reconciliation.keptParts
                    discarded += reconciliation.discardedParts
                    stores.append(store)
                    for part in asset.parts {
                        machines[PartRef(asset: assetIndex, part: part.index)] = PartStateMachine(
                            state: store.isVerified(part.index) || store.isFinalVerified ? .verified : .pending)
                    }
                    if previousVersion == nil, reconciliation.keptParts > 0 {
                        await onEvent?(.resumed(assetID: asset.assetID, verifiedParts: reconciliation.keptParts))
                    }
                }
            } catch {
                return await pause(.insufficientSpace)
            }
            if let previousVersion, previousVersion != manifest.itemVersionID {
                await onEvent?(.versionChanged(
                    from: previousVersion, to: manifest.itemVersionID, keptParts: kept, discardedParts: discarded))
            }
            previousVersion = manifest.itemVersionID
            updateProgress(manifest)
            guard hasSpace(for: manifest) else { return await pause(.insufficientSpace) }

            switch await downloadRound(manifest) {
            case .complete:
                return await finalize(manifest)
            case .refreshManifest:
                refreshes += 1
                if refreshes > options.maxManifestRefreshes { return await pause(.manifestInvalid) }
            case .pause(let reason):
                return await pause(reason)
            }
        }
    }

    private func downloadRound(_ manifest: TransferManifest) async -> RoundResult {
        let initial: [PartRef] = machines.keys.filter { machines[$0]?.state.isVerified == false }
            .sorted { ($0.asset, $0.part) < ($1.asset, $1.part) }
        if initial.isEmpty { return .complete }
        let client = self.client
        let concurrency = max(1, options.concurrency)
        return await withTaskGroup(of: (PartRef, Result<URL, PartFailure>).self) { group in
            var queue = initial
            var decision: RoundResult?
            var inFlight = 0
            while true {
                while decision == nil, inFlight < concurrency, !queue.isEmpty {
                    // Never start a request after cancellation; parts in flight are cancelled with the task.
                    if Task.isCancelled {
                        decision = .pause(.cancelled)
                        break
                    }
                    let ref = queue.removeFirst()
                    let asset = manifest.assets[ref.asset]
                    let part = asset.parts[ref.part]
                    try? machines[ref]?.apply(.request)
                    let attempt = machines[ref]?.state.attempts ?? 1
                    await onEvent?(.partRequested(assetID: asset.assetID, index: part.index, attempt: attempt))
                    let incoming = stores[ref.asset].incomingDirectory
                    let delay = attempt > 1 ? options.retryDelay * (attempt - 1) : .zero
                    group.addTask {
                        if delay > .zero { try? await Task.sleep(for: delay) }
                        return (ref, await client.fetchPart(part, of: asset, into: incoming))
                    }
                    inFlight += 1
                }
                guard let (ref, result) = await group.next() else { break }
                inFlight -= 1
                let asset = manifest.assets[ref.asset]
                let part = asset.parts[ref.part]
                switch result {
                case .success(let url):
                    // Also while draining after a decision: a part that arrived valid for this manifest
                    // is kept. Reconciliation with any newer manifest keeps it only if its digest matches.
                    try? machines[ref]?.apply(.bodyReceived)
                    do throws(StagingError) {
                        try stores[ref.asset].commit(part: part, from: url)
                        try? machines[ref]?.apply(.verified)
                        updateProgress(manifest)
                        await onEvent?(.partVerified(assetID: asset.assetID, index: part.index))
                    } catch {
                        // A full disk pauses at once (fetching again cannot help); another local write error
                        // is retried and, if it persists, reported as a storage problem, not a network one.
                        let failure: PartFailure = switch error {
                        case .digestMismatchOnCommit: .digestMismatch
                        case .noSpace: .localStorageFull
                        default: .localWriteFailed("\(error)")
                        }
                        try? machines[ref]?.apply(.failed(failure))
                        await onEvent?(.partFailed(assetID: asset.assetID, index: part.index, failure: failure))
                        if decision == nil {
                            switch failure.recovery {
                            case .pause(let reason): decision = .pause(reason)
                            default: decision = retryOrPause(ref, failure: failure, queue: &queue)
                            }
                        }
                    }
                case .failure(let failure):
                    try? machines[ref]?.apply(.failed(failure))
                    await onEvent?(.partFailed(assetID: asset.assetID, index: part.index, failure: failure))
                    if decision != nil { continue }
                    if Task.isCancelled {
                        decision = .pause(.cancelled)
                    } else {
                        switch failure.recovery {
                        case .retryPart: decision = retryOrPause(ref, failure: failure, queue: &queue)
                        case .refreshManifest: decision = .refreshManifest
                        case .pause(let reason): decision = .pause(reason)
                        }
                    }
                }
                // Only cancellation aborts requests in flight; other decisions let them finish (bounded by
                // the concurrency limit) so valid parts are not thrown away.
                if case .pause(.cancelled)? = decision { group.cancelAll() }
            }
            if let decision { return decision }
            return machines.values.allSatisfy(\.state.isVerified) ? .complete : .refreshManifest
        }
    }

    private func retryOrPause(_ ref: PartRef, failure: PartFailure, queue: inout [PartRef]) -> RoundResult? {
        let attempts = machines[ref]?.state.attempts ?? 0
        if attempts >= options.maxAttemptsPerPart { return .pause(failure.exhaustedRetriesReason) }
        queue.append(ref)
        return nil
    }

    private func finalize(_ manifest: TransferManifest) async -> Outcome {
        var ready: [ReadyAsset] = []
        for index in stores.indices {
            do {
                let url = try stores[index].finalize()
                let asset = manifest.assets[index]
                ready.append(ReadyAsset(assetID: asset.assetID, url: url, length: asset.length, sha256: asset.sha256))
                await onEvent?(.assetFinalized(assetID: asset.assetID))
            } catch {
                for part in manifest.assets[index].parts {
                    try? machines[PartRef(asset: index, part: part.index)]?.apply(.invalidate)
                }
                updateProgress(manifest)
                return await pause(.finalDigestMismatch)
            }
        }
        return .ready(manifest: manifest, assets: ready)
    }

    private func pause(_ reason: PauseReason) async -> Outcome {
        await onEvent?(.paused(reason))
        return .paused(reason, progress)
    }

    private func updateProgress(_ manifest: TransferManifest) {
        var verified: Int64 = 0
        for (assetIndex, asset) in manifest.assets.enumerated() {
            for part in asset.parts where machines[PartRef(asset: assetIndex, part: part.index)]?.state.isVerified == true {
                verified += part.length
            }
        }
        progress = TransferProgress(totalBytes: manifest.totalBytes, receivedBytes: verified, verifiedBytes: verified)
    }

    private func hasSpace(for manifest: TransferManifest) -> Bool {
        guard let available = VolumeSpace.available(at: stagingRoot) else { return true }
        // Staging files are preallocated sparse files, so count what is still to arrive plus parts in flight.
        let inFlight = (manifest.assets.map(\.partSize).max() ?? 0) * Int64(max(1, options.concurrency))
        return available >= manifest.totalBytes - progress.verifiedBytes + inFlight
    }

    public static func pauseReason(for error: ClientError) -> PauseReason {
        switch error {
        case .pinMismatch: .sourceIdentityChanged
        case .http(401, _): .reauthenticationRequired
        case .http(403, _): .accessRevoked
        case .http(404, _): .itemRemoved
        case .invalidManifest, .unsupportedProtocol, .invalidResponse: .manifestInvalid
        case .cancelled: .cancelled
        case .localNetworkDenied: .localNetworkDenied
        default: .sourceUnreachable
        }
    }
}
