import Foundation
import Security
import Synchronization
import SylviaTransferClient
import SylviaTransferCore

/// Downloads transfer jobs with URLSession download tasks, normally in a background session, so the
/// system keeps fetching parts while Sylvia is suspended or not running (plan 6.4, 15.4, 15.5).
///
/// - Each part is one download task: a single `Range`, `If-Match` with the manifest's strong ETag,
///   `Accept-Encoding: identity` and the per-device token in `Authorization: Bearer`. The task
///   description names the job, asset, part and attempt only (`TaskDescriptor`).
/// - Server trust is answered only by `PinnedTrustEvaluator.answer` with the SPKI pin of the source the
///   task's job belongs to (task-level challenge). Each challenge is logged with the app state, as
///   evidence of when a background session asks the app.
/// - `didFinishDownloadingTo` checks the response head, moves the file synchronously out of the system's
///   temporary location, then copies it into the asset's staging file while re-hashing it; the part is
///   journalled as verified only after its digest matched and the write was ordered to disk.
/// - When every part is verified the job is assembled through the staging journal (full SHA-256, then
///   rename) and handed to `StubImporter` exactly once.
/// - `start()` reconciles persisted jobs, verified parts and the session's outstanding tasks on every
///   launch (`ReconciliationPlanner`).
///
/// All mutable state is behind one lock; delegate callbacks arrive on a serial queue.
public final class BackgroundTransferCoordinator: NSObject, URLSessionDownloadDelegate, Sendable {
    public enum SessionKind: Sendable, Equatable {
        /// `URLSessionConfiguration.background(withIdentifier:)`: tasks outlive the process.
        case background(identifier: String)
        /// A default session with the same download tasks and delegate code, for host tests. Tasks die
        /// with the process, so a "relaunch" there exercises reconciliation without outstanding tasks.
        case inProcess
    }

    public struct Options: Sendable {
        /// Outstanding download tasks per job (requested and queued). Two run at a time per host.
        public var window = 4
        public var connectionsPerHost = 2
        public var maxAttemptsPerPart = 4
        public var maxManifestRefreshes = 4
        public var retryBaseDelay: TimeInterval = 1
        public var requestTimeout: TimeInterval = 60
        public var preparationPollInterval: Duration = .seconds(2)
        public var maxPreparationWait: Duration = .seconds(1800)
        /// Re-hash verified parts when a job is opened at launch (detects damaged or missing staged bytes).
        public var verifyStagedPartsOnLaunch = true
        /// Free bytes for the job store's volume (plan 15.4 reservation). Nil reads the volume's
        /// "available for important usage" capacity; tests substitute a value.
        public var availableCapacity: (@Sendable (URL) -> Int64?)?
        /// Whether the local network is denied to this app for an endpoint (iOS local network privacy).
        /// Nil uses `LocalNetworkProbe`; tests substitute an answer.
        public var localNetworkDenied: (@Sendable (PairingPayload.Endpoint) async -> Bool)?
        /// Test only: an error to report for a task in place of what the session reported, as if the system
        /// had failed the task itself (for example when it cannot write the body to a full phone, in which
        /// case `didFinishDownloadingTo` is never called). The task's file, if any, is not used.
        @_spi(Testing) public var injectedTaskError: (@Sendable (TaskDescriptor) -> (any Error)?)?
        public init() {}
    }

    /// What the transfer screen shows for one job.
    public struct JobView: Identifiable, Hashable, Sendable {
        public var id: String { job.jobID }
        public var job: JobRecord
        public var progress: TransferProgress
        public var outstandingTasks: Int
        public var verifiedParts: Int
        public var totalParts: Int
    }

    public struct ReconciliationSummary: Hashable, Sendable {
        public var time: Date
        public var jobs: Int
        public var outstandingTasks: Int
        /// Listed by `allTasks` but already completed (delegate event delivered first); not adopted.
        public var completedBeforeReconciliation: Int
        public var adopted: Int
        public var cancelled: [String: Int]
        public var enqueued: Int
        public var keptVerifiedParts: Int
        public var discardedParts: Int
        public var blocked: [String: String]
        public var finalized: Int
        public var importsRetried: Int
        public var refreshes: Int
        /// Set when launch was deferred: nothing was read, cancelled, scheduled or written, and no
        /// session was created. Call `start()` again once protected data is available.
        public var deferredReason: String? = nil

        static func deferred(_ reason: String) -> ReconciliationSummary {
            ReconciliationSummary(
                time: Date(), jobs: 0, outstandingTasks: 0, completedBeforeReconciliation: 0, adopted: 0, cancelled: [:], enqueued: 0,
                keptVerifiedParts: 0, discardedParts: 0, blocked: [:], finalized: 0, importsRetried: 0, refreshes: 0,
                deferredReason: reason)
        }
    }

    enum TaskOutcome: Sendable {
        case verified(PartKey, commitMilliseconds: Int)
        case failed(PartKey, PartFailure)
        case discarded(String)
    }

    struct Runtime {
        var manifest: TransferManifest
        var stores: [String: PartStagingStore]
        var outstanding: [PartKey: Int] = [:]
        var tasks: [Int: URLSessionDownloadTask] = [:]
        var receivedInFlight: [Int: Int64] = [:]

        func part(_ key: PartKey) -> (TransferManifest.Asset, TransferManifest.Part)? {
            guard let asset = manifest.assets.first(where: { $0.assetID == key.assetID }),
                asset.parts.indices.contains(key.index)
            else { return nil }
            return (asset, asset.parts[key.index])
        }

        var allParts: [PartKey] {
            manifest.assets.flatMap { asset in asset.parts.map { PartKey(assetID: asset.assetID, index: $0.index) } }
        }

        func isVerified(_ key: PartKey) -> Bool {
            guard let store = stores[key.assetID] else { return false }
            return store.isFinalVerified || store.isVerified(key.index)
        }

        var verifiedParts: Set<PartKey> { Set(allParts.filter { isVerified($0) }) }

        var verifiedBytes: Int64 {
            manifest.assets.reduce(0) { total, asset in
                total + asset.parts.reduce(0) { $0 + (isVerified(PartKey(assetID: asset.assetID, index: $1.index)) ? $1.length : 0) }
            }
        }
    }

    enum StartPhase {
        /// Not started, or the last start was deferred.
        case idle
        case starting
        case started
    }

    struct State {
        var phase = StartPhase.idle
        var session: URLSession?
        var records: [String: JobRecord] = [:]
        var runtimes: [String: Runtime] = [:]
        var outcomes: [Int: TaskOutcome] = [:]
        var pinMismatchTasks: Set<Int> = []
        var backgroundCompletion: (@Sendable () -> Void)?
        var lastReconciliation: ReconciliationSummary?
        var refreshing: Set<String> = []
        /// False until launch reconciliation ran: events the recreated session delivers before then are
        /// journalled, but no new task is created until the outstanding ones are known (no duplicates).
        var reconciled = false
        /// Tasks whose completion was delivered before launch reconciliation ran. `allTasks` may still list
        /// them (its answer and the delegate's events are not ordered), so reconciliation must not adopt them:
        /// an adopted task that already completed would hold its part's slot forever.
        var completedBeforeReconciliation: Set<Int> = []
        /// Jobs whose full-file check runs on the assembly queue (outside this lock; review finding R2-04).
        var assembling: Set<String> = []
        /// The background-events completion handler, held back while an assembly runs, so the system does not
        /// suspend the app in the middle of the full-file check.
        var completionAfterAssembly: (@Sendable () -> Void)?
        /// Jobs paused as `source_unreachable` whose cause is being checked against local network privacy.
        var probingLocalNetwork: Set<String> = []
    }

    public let kind: SessionKind
    public let root: URL
    public let jobStore: JobStore
    public let sources: PairedSourceStore
    public let importer: StubImporter
    public let log: TransferEventLog
    public let options: Options
    let credentials: any CredentialStore
    let appState: @Sendable () -> String
    let protectedDataAvailable: (@Sendable () async -> Bool)?
    private let state = Mutex(State())
    private let delegateQueue: OperationQueue
    /// Full-file checks run here, never under the state lock (review finding R2-04).
    private let assemblyQueue = DispatchQueue(label: "SylviaBackgroundTransfer.assembly", qos: .utility)

    /// - Parameter protectedDataAvailable: on iOS, `UIApplication.isProtectedDataAvailable`, **recorded in the
    ///   event log only** (`protected_data_available` on `coordinator_start` and `start_deferred`). It must
    ///   never gate the launch (review finding R2-01): it reports class A (`NSFileProtectionComplete`)
    ///   availability, which is false every time a phone with a passcode is locked, also long after its first
    ///   unlock, when the job store (class C) and the token (after first unlock) are readable and background
    ///   transfers must run. "Before the first unlock" is detected from the class C data itself: a store file
    ///   that exists but cannot be read defers the launch (`deferralReason`, `JobStore.loadAll`).
    public init(
        kind: SessionKind, root: URL, credentials: any CredentialStore, options: Options = Options(),
        appState: @escaping @Sendable () -> String = { "unknown" },
        protectedDataAvailable: (@Sendable () async -> Bool)? = nil
    ) throws {
        self.kind = kind
        self.root = root
        self.credentials = credentials
        self.options = options
        self.appState = appState
        self.protectedDataAvailable = protectedDataAvailable
        try DurableFile.createDirectory(root)
        jobStore = try JobStore(root: root)
        sources = try PairedSourceStore(url: root.appendingPathComponent("sources.json"))
        importer = try StubImporter(root: root)
        log = try TransferEventLog(url: root.appendingPathComponent("events.jsonl"))
        let queue = OperationQueue()
        queue.maxConcurrentOperationCount = 1
        queue.name = "SylviaBackgroundTransfer.delegate"
        delegateQueue = queue
        super.init()
    }

    public var sessionIdentifier: String? {
        if case .background(let identifier) = kind { identifier } else { nil }
    }

    // MARK: Launch

    /// Loads persisted jobs, recreates the session (which reattaches the system's outstanding tasks and
    /// delivers events that completed while the app was not running) and reconciles. Call on every launch,
    /// including a background relaunch for session events, and again whenever the returned summary has a
    /// `deferredReason` (for example on `UIApplication.protectedDataDidBecomeAvailableNotification`); a call
    /// while a start runs or after one succeeded does nothing. Returns after reconciliation has been applied.
    ///
    /// Deferred launch (review findings R1-04, R2-01): while any store (sources.json, imports.json, a job.json
    /// or the jobs folder) exists but cannot be read, which is the case before the first unlock after a
    /// restart (their class C files refuse reads with EPERM), nothing is acted on: no session is created (so
    /// no outstanding task is listed, adopted or cancelled), no job is paused or rewritten and no store is
    /// written. An unreadable store is never taken for an empty one. A phone that is merely locked after its
    /// first unlock does not defer: its stores and token are readable, and background transfers must run.
    /// When a launch defers, a stored background-events completion handler is called at once, so the system
    /// is not left waiting for events this process will not take.
    @discardableResult
    public func start() async -> ReconciliationSummary { await start(beforeReconciliation: nil) }

    /// Test seam: `hook` runs after the session exists and before reconciliation; download tasks it returns
    /// are added to what `allTasks` listed, to reproduce the system listing a task whose completion the
    /// delegate already received (the two answers are not ordered).
    @_spi(Testing) @discardableResult
    public func start(
        beforeReconciliation hook: (@Sendable (URLSession) async -> [URLSessionDownloadTask])?
    ) async -> ReconciliationSummary {
        let previous: StartPhase = state.withLock { state in
            let phase = state.phase
            if phase == .idle { state.phase = .starting }
            return phase
        }
        guard previous == .idle else {
            return lastReconciliation ?? .deferred(previous == .starting ? "start_in_progress" : "already_started")
        }
        // Recorded for the device checklist only; never a reason to defer (R2-01, see init).
        let protectedData = await protectedDataAvailable?().description ?? "not_reported"
        if let reason = deferralReason() {
            log.record("start_deferred", ["reason": reason, "app_state": appState(), "protected_data_available": protectedData])
            return deferLaunch(reason)
        }
        let loaded = jobStore.loadAll()
        if !loaded.inaccessible.isEmpty {
            log.record("start_deferred", [
                "reason": "job_store_not_accessible", "jobs_not_accessible": String(loaded.inaccessible.count), "app_state": appState(),
                "protected_data_available": protectedData,
            ])
            return deferLaunch("job_store_not_accessible")
        }
        // Open each job's staging, re-hashing its verified parts, outside the state lock: for a large item this
        // reads gigabytes and takes seconds, and the UI (jobViews) must not wait on the lock meanwhile. Nothing
        // else touches these jobs yet: no session exists and public operations find no records until they are
        // published below.
        var kept = 0
        var discarded = 0
        var opened: [String: Runtime] = [:]
        let clock = ContinuousClock()
        let checkStarted = clock.now
        for job in loaded.jobs where !job.isTerminal {
            if let (runtime, reconciliation) = openRuntime(for: job, verify: options.verifyStagedPartsOnLaunch) {
                opened[job.jobID] = runtime
                kept += reconciliation.keptParts
                discarded += reconciliation.discardedParts
            }
        }
        let stagingCheck = clock.now - checkStarted
        let checkedBytes = opened.values.reduce(Int64(0)) { $0 + $1.verifiedBytes }
        state.withLock { state in
            for job in loaded.jobs {
                state.records[job.jobID] = job
                if let runtime = opened[job.jobID] { state.runtimes[job.jobID] = runtime }
            }
        }
        log.record("staging_checked", [
            "jobs": String(opened.count), "verified_bytes": String(checkedBytes), "rehashed": String(options.verifyStagedPartsOnLaunch),
            "milliseconds": String(stagingCheck.components.seconds * 1000 + stagingCheck.components.attoseconds / 1_000_000_000_000_000),
        ])
        for name in loaded.unreadable { log.record("job_unreadable", ["job": name]) }
        log.record("coordinator_start", [
            "session": sessionIdentifier ?? "in_process", "app_state": appState(), "jobs": String(loaded.jobs.count),
            "protected_data_available": protectedData,
        ])
        let session = makeSession()
        state.withLock { state in
            state.session = session
            state.phase = .started
        }
        let extra = await hook?(session) ?? []
        let tasks = await session.allTasks
        let downloads = tasks.compactMap { $0 as? URLSessionDownloadTask }
        let listed = downloads + extra.filter { task in !downloads.contains { $0.taskIdentifier == task.taskIdentifier } }
        return reconcile(tasks: listed, foreign: tasks.filter { !($0 is URLSessionDownloadTask) }, kept: kept, discarded: discarded)
    }

    private func deferLaunch(_ reason: String) -> ReconciliationSummary {
        let summary = ReconciliationSummary.deferred(reason)
        let completion = state.withLock { state -> (@Sendable () -> Void)? in
            state.phase = .idle
            state.lastReconciliation = summary
            defer { state.backgroundCompletion = nil }
            return state.backgroundCompletion
        }
        // A background relaunch whose launch deferred: no session exists in this process, so the system's
        // events will not be delivered to it; tell the system at once instead of leaving it waiting (R2-01).
        if let completion {
            log.record("background_events_released", ["reason": reason, "app_state": appState()])
            DispatchQueue.main.async { completion() }
        }
        return summary
    }

    /// Why launch must wait, or nil. The stores are read again here: at init the files may not have been
    /// readable yet. A store that exists but cannot be read (not accessible: before the first unlock; or
    /// damaged) defers launch; a damaged one needs a repair path in the product (not part of this spike).
    /// `UIApplication.isProtectedDataAvailable` is deliberately not consulted (R2-01).
    private func deferralReason() -> String? {
        sources.reload()
        importer.reload()
        if let unreadable = sources.unreadable { return "sources_\(unreadable.reason)" }
        if importer.isUnreadable { return "imports_unreadable" }
        return nil
    }

    private func makeSession() -> URLSession {
        let configuration: URLSessionConfiguration
        switch kind {
        case .background(let identifier):
            configuration = .background(withIdentifier: identifier)
            configuration.sessionSendsLaunchEvents = true
            configuration.isDiscretionary = false
        case .inProcess:
            configuration = .ephemeral
        }
        configuration.urlCache = nil
        configuration.httpCookieStorage = nil
        configuration.httpShouldSetCookies = false
        configuration.urlCredentialStorage = nil
        configuration.requestCachePolicy = .reloadIgnoringLocalAndRemoteCacheData
        configuration.tlsMinimumSupportedProtocolVersion = .TLSv12
        configuration.httpMaximumConnectionsPerHost = options.connectionsPerHost
        configuration.timeoutIntervalForRequest = options.requestTimeout
        return URLSession(configuration: configuration, delegate: self, delegateQueue: delegateQueue)
    }

    private func reconcile(tasks listed: [URLSessionDownloadTask], foreign: [URLSessionTask], kept: Int, discarded: Int) -> ReconciliationSummary {
        for task in foreign { task.cancel() }
        let summary: ReconciliationSummary = state.withLock { state in
            // Completed while `allTasks` was answering: already handled by didCompleteWithError, not outstanding.
            let tasks = listed.filter { !state.completedBeforeReconciliation.contains($0.taskIdentifier) }
            let alreadyCompleted = listed.count - tasks.count
            state.completedBeforeReconciliation = []
            var snapshots: [ReconciliationPlanner.JobSnapshot] = []
            for job in state.records.values where !job.isTerminal {
                let runtime = state.runtimes[job.jobID]
                snapshots.append(.init(
                    jobID: job.jobID, state: job.state, parts: runtime?.allParts, verified: runtime?.verifiedParts ?? [],
                    credential: credentialStatus(job.sourceID)))
            }
            let outstanding = tasks.map { ReconciliationPlanner.OutstandingTask(taskIdentifier: $0.taskIdentifier, taskDescription: $0.taskDescription) }
            let plan = ReconciliationPlanner.plan(jobs: snapshots, tasks: outstanding, window: options.window)
            state.reconciled = true
            let byID = Dictionary(tasks.map { ($0.taskIdentifier, $0) }, uniquingKeysWith: { first, _ in first })
            var cancelled: [String: Int] = [:]
            for (identifier, reason) in plan.cancel {
                byID[identifier]?.cancel()
                cancelled[reason.rawValue, default: 0] += 1
            }
            for (identifier, descriptor) in plan.adopt {
                guard let task = byID[identifier] else { continue }
                state.runtimes[descriptor.jobID]?.outstanding[descriptor.partKey] = identifier
                state.runtimes[descriptor.jobID]?.tasks[identifier] = task
            }
            for (jobID, reason) in plan.block { pauseLocked(&state, jobID: jobID, reason: reason, event: "blocked_at_launch") }
            for (jobID, parts) in plan.enqueue {
                for part in parts { enqueueLocked(&state, jobID: jobID, key: part) }
            }
            for jobID in plan.finalize { finalizeLocked(&state, jobID: jobID) }
            for jobID in plan.importReady { importLocked(&state, jobID: jobID) }
            let summary = ReconciliationSummary(
                time: Date(), jobs: snapshots.count, outstandingTasks: tasks.count + foreign.count,
                completedBeforeReconciliation: alreadyCompleted, adopted: plan.adoptedCount,
                cancelled: cancelled.merging(foreign.isEmpty ? [:] : ["non_download_task": foreign.count], uniquingKeysWith: +),
                enqueued: plan.enqueuedCount, keptVerifiedParts: kept, discardedParts: discarded,
                blocked: plan.block.mapValues(\.rawValue), finalized: plan.finalize.count, importsRetried: plan.importReady.count,
                refreshes: plan.refresh.count)
            state.lastReconciliation = summary
            return summary
        }
        var fields: [String: String] = [
            "jobs": String(summary.jobs), "outstanding_tasks": String(summary.outstandingTasks), "adopted": String(summary.adopted),
            "completed_before_reconciliation": String(summary.completedBeforeReconciliation),
            "enqueued": String(summary.enqueued), "kept_verified_parts": String(summary.keptVerifiedParts),
            "discarded_parts": String(summary.discardedParts), "finalized": String(summary.finalized),
            "imports_retried": String(summary.importsRetried), "refreshes": String(summary.refreshes), "app_state": appState(),
        ]
        for (reason, count) in summary.cancelled { fields["cancelled_\(reason)"] = String(count) }
        for (job, reason) in summary.blocked { fields["blocked_\(job)"] = reason }
        log.record("launch_reconciliation", fields)
        let refresh = state.withLock { state in state.records.values.filter { $0.state == .refreshing }.map(\.jobID) }
        for jobID in refresh { startRefresh(jobID: jobID) }
        retryPendingReceipts()
        return summary
    }

    // MARK: Public operations

    public var lastReconciliation: ReconciliationSummary? { state.withLock { $0.lastReconciliation } }

    public func jobViews() -> [JobView] {
        state.withLock { state in
            state.records.values.sorted { $0.createdAt < $1.createdAt }.map { job in
                guard let runtime = state.runtimes[job.jobID] else {
                    // Imported jobs keep no staging; their size comes from the importer's record.
                    let total = job.state == .imported
                        ? (importer.record(itemVersionID: job.itemVersionID)?.assets.reduce(0) { $0 + $1.length } ?? 0) : 0
                    return JobView(
                        job: job, progress: TransferProgress(totalBytes: total, receivedBytes: total, verifiedBytes: total),
                        outstandingTasks: 0, verifiedParts: 0, totalParts: 0)
                }
                let verified = runtime.verifiedBytes
                let inFlight = runtime.receivedInFlight.values.reduce(0, +)
                let total = runtime.manifest.totalBytes
                return JobView(
                    job: job,
                    progress: TransferProgress(totalBytes: total, receivedBytes: min(total, verified + inFlight), verifiedBytes: verified),
                    outstandingTasks: runtime.outstanding.count, verifiedParts: runtime.verifiedParts.count,
                    totalParts: runtime.allParts.count)
            }
        }
    }

    public func job(_ jobID: String) -> JobView? { jobViews().first { $0.job.jobID == jobID } }

    /// The pull-first device inbox (plan 15.1): what the Mac queued for this phone ("Send to device").
    /// Listing marks the Mac's entries "observed by phone"; that never implies download or import. Follows
    /// the pages to the end (at most 20 pages).
    public func inbox(sourceID: String) async throws(ClientError) -> [InboxEntry] {
        guard let client = client(sourceID: sourceID) else { throw .notPaired }
        var entries: [InboxEntry] = []
        var cursor: String?
        for _ in 0..<20 {
            let page: DeviceInboxPage
            do throws(ClientError) {
                page = try await client.deviceInbox(cursor: cursor)
            } catch {
                throw await explain(error, sourceID: sourceID)
            }
            entries += page.entries
            guard let next = page.nextCursor else { break }
            cursor = next
        }
        let states = Dictionary(grouping: entries, by: \.state.rawValue).map { "\($0.key)=\($0.value.count)" }.sorted()
        log.record("inbox_checked", ["source": sourceID, "entries": String(entries.count), "states": states.joined(separator: ",")])
        return entries
    }

    /// Fetches and validates the manifest (waiting while the Mac prepares the item), persists the job,
    /// then schedules its first parts. Returns the job ID. `queueEntryID` names the Mac's outbound queue entry
    /// when the item came from the device inbox; the job's receipts then acknowledge that entry.
    public func startJob(
        sourceID: String, itemID: String, title: String, queueEntryID: String? = nil
    ) async throws(ClientError) -> String {
        guard state.withLock({ $0.phase == .started }) else { throw .invalidResponse("the transfer store is not available yet") }
        let manifest: TransferManifest
        do throws(ClientError) {
            manifest = try await fetchManifest(sourceID: sourceID, itemID: itemID, endpointIndex: 0)
        } catch {
            throw await explain(error, sourceID: sourceID)
        }
        let job = JobRecord(
            jobID: CanonicalID.make(), sourceID: sourceID, itemID: itemID, title: title, itemVersionID: manifest.itemVersionID,
            now: Date(), queueEntryID: queueEntryID)
        do {
            try jobStore.saveManifest(manifest, jobID: job.jobID)
            try jobStore.save(job)
        } catch {
            throw .invalidResponse("cannot persist the job")
        }
        let available = availableSpace()
        state.withLock { state in
            state.records[job.jobID] = job
            if let (runtime, _) = openRuntime(for: job, verify: false) { state.runtimes[job.jobID] = runtime }
            log.record("job_created", [
                "job": job.jobID, "item": itemID, "version": manifest.itemVersionID, "bytes": String(manifest.totalBytes),
                "parts": String(manifest.assets.reduce(0) { $0 + $1.parts.count }), "queue_entry": queueEntryID ?? "none",
            ])
            if spaceShortfallLocked(&state, jobID: job.jobID, available: available) == nil {
                topUpLocked(&state, jobID: job.jobID, available: available)
            }
        }
        return job.jobID
    }

    /// Plan 15.4 disk reservation: the bytes still to arrive (staging files are sparse and parts are
    /// written in place; assembly and import are renames, so there is no assembly copy) plus one part per
    /// outstanding task (the system's download file before it is copied into staging). When the volume has
    /// less, the job pauses with `insufficient_space` before any request; returns the missing bytes then.
    /// `available` comes from `availableSpace()`, read before the lock was taken.
    private func spaceShortfallLocked(_ state: inout State, jobID: String, available: Int64?) -> Int64? {
        guard let runtime = state.runtimes[jobID] else { return nil }
        guard let available else { return nil }  // unknown: the write path still pauses on ENOSPC
        let largestPart = runtime.manifest.assets.map(\.partSize).max() ?? 0
        let required = runtime.manifest.totalBytes - runtime.verifiedBytes + largestPart * Int64(options.window)
        guard available < required else { return nil }
        log.record("space_check_failed", ["job": jobID, "required_bytes": String(required), "available_bytes": String(available)])
        pauseLocked(&state, jobID: jobID, reason: .insufficientSpace, event: "paused")
        return required - available
    }

    /// Free bytes on the job store's volume, or nil when unknown. Never called with the state lock held: the
    /// "available for important usage" figure is a request to the system that took about 20 ms on the host when
    /// idle and several hundred milliseconds while the disk was busy (found by the 5 GiB test in round 2, when
    /// the per-request reservation first ran it under the lock and `jobViews()` waited 425 ms).
    private func availableSpace() -> Int64? {
        options.availableCapacity?(root) ?? VolumeSpace.available(at: root)
    }

    /// The person pauses: outstanding tasks are cancelled, verified parts kept.
    public func pause(jobID: String) {
        state.withLock { state in pauseLocked(&state, jobID: jobID, reason: .cancelled, event: "paused_by_person") }
    }

    /// Resumes a paused job (after re-pairing, unlocking, or when the Mac is reachable again).
    public func resume(jobID: String) {
        // A job without open staging is opened (verified parts re-hashed) outside the lock, as at launch.
        let unopened: JobRecord? = state.withLock { state in
            guard let job = state.records[jobID], job.state == .paused, state.runtimes[jobID] == nil else { return nil }
            return job
        }
        let opened = unopened.flatMap { openRuntime(for: $0, verify: true)?.0 }
        let available = availableSpace()
        state.withLock { state in
            guard var job = state.records[jobID], job.state == .paused else { return }
            if state.runtimes[jobID] == nil {
                guard let opened else { return }
                state.runtimes[jobID] = opened
            }
            job.state = .downloading
            job.pauseReason = nil
            job.failedAttempts = [:]
            job.manifestRefreshes = 0
            saveLocked(&state, job)
            log.record("resumed", ["job": jobID])
            if state.runtimes[jobID]?.verifiedParts.count == state.runtimes[jobID]?.allParts.count {
                finalizeLocked(&state, jobID: jobID)
            } else if spaceShortfallLocked(&state, jobID: jobID, available: available) == nil {
                topUpLocked(&state, jobID: jobID, available: available)
            }
        }
    }

    /// The person cancels: tasks cancelled, staging deleted. Imported files are not touched.
    public func cancel(jobID: String) {
        state.withLock { state in
            guard var job = state.records[jobID], !job.isTerminal else { return }
            cancelTasksLocked(&state, jobID: jobID)
            job.state = .cancelled
            saveLocked(&state, job)
            state.runtimes[jobID] = nil
            jobStore.deleteStaging(jobID)
            log.record("cancelled_by_person", ["job": jobID])
        }
    }

    /// Called by the app delegate for `handleEventsForBackgroundURLSession`, followed by `start()`. The
    /// completion is invoked on the main queue after the session has delivered every pending event and any
    /// full-file check it started has finished, or at once if that `start()` defers (no session in this
    /// process can take the events).
    public func setBackgroundEventsCompletion(_ completion: @escaping @Sendable () -> Void) {
        state.withLock { $0.backgroundCompletion = completion }
        log.record("background_events_launch", ["app_state": appState()])
    }

    /// Re-pins and tests an address (manual entry, Bonjour result), then makes it the source's first
    /// endpoint. The capabilities response must name the paired source.
    public func verifyAndPreferEndpoint(sourceID: String, endpoint: PairingPayload.Endpoint) async throws(ClientError) -> Capabilities {
        guard var source = sources.source(sourceID), let pin = try? SPKIPin(hex: source.spkiSHA256) else { throw .notPaired }
        guard HostValidation.isValid(endpoint.host), (1...65_535).contains(endpoint.port), let base = endpoint.baseURL() else {
            throw .invalidResponse("not a valid address")
        }
        let client = SourceClient(baseURL: base, pin: pin, sourceID: sourceID, token: nil, timeout: 15)
        let capabilities: Capabilities
        do throws(ClientError) {
            capabilities = try await client.capabilities()
        } catch {
            let coordinator = self
            throw await error.classifyingLocalNetwork(endpoints: [endpoint], isDenied: { await coordinator.localNetworkDenied($0) })
        }
        source.endpoints.removeAll { $0 == endpoint }
        source.endpoints.insert(endpoint, at: 0)
        source.endpoints = Array(source.endpoints.prefix(PairingPayload.maximumEndpoints))
        do { try sources.upsert(source) } catch { throw .invalidResponse("cannot save the address") }
        state.withLock { state in
            for var job in state.records.values where job.sourceID == sourceID && job.endpointIndex != 0 {
                job.endpointIndex = 0
                saveLocked(&state, job)
            }
        }
        log.record("endpoint_preferred", ["source": sourceID, "host": endpoint.host, "port": String(endpoint.port)])
        return capabilities
    }

    /// For messages to the person: a network failure towards a paired source becomes `.localNetworkDenied`
    /// when iOS refuses the source's addresses because the local network is denied to the app (R2-03).
    public func explain(_ error: ClientError, sourceID: String) async -> ClientError {
        let endpoints = sources.source(sourceID)?.endpoints ?? []
        let coordinator = self
        return await error.classifyingLocalNetwork(endpoints: endpoints, isDenied: { await coordinator.localNetworkDenied($0) })
    }

    func localNetworkDenied(_ endpoints: [PairingPayload.Endpoint]) async -> Bool {
        guard let probe = options.localNetworkDenied else { return await LocalNetworkProbe.anyDenied(endpoints) }
        for endpoint in endpoints where await probe(endpoint) { return true }
        return false
    }

    /// After a job paused as `source_unreachable`, checks whether the cause is a denied local network
    /// permission and, if so, changes the reason to `local_network_denied` with its Settings next step
    /// (plan 14.3, 15.5; review finding R2-03). The probe runs outside the lock.
    private func checkLocalNetworkLocked(_ state: inout State, jobID: String) {
        guard let job = state.records[jobID], !state.probingLocalNetwork.contains(jobID),
            let endpoints = sources.source(job.sourceID)?.endpoints, !endpoints.isEmpty
        else { return }
        state.probingLocalNetwork.insert(jobID)
        let coordinator = self
        Task {
            let denied = await coordinator.localNetworkDenied(endpoints)
            coordinator.state.withLock { state in
                state.probingLocalNetwork.remove(jobID)
                coordinator.log.record("local_network_checked", ["job": jobID, "denied": String(denied)])
                guard denied, var job = state.records[jobID], job.state == .paused, job.pauseReason == .sourceUnreachable else { return }
                job.pauseReason = .localNetworkDenied
                coordinator.saveLocked(&state, job)
                coordinator.log.record("pause_reason_refined", [
                    "job": jobID, "from": PauseReason.sourceUnreachable.rawValue, "reason": PauseReason.localNetworkDenied.rawValue,
                ])
            }
        }
    }

    /// A client for foreground calls (catalog, receipts) to the source's preferred endpoint.
    public func client(sourceID: String, endpointIndex: Int = 0, timeout: TimeInterval = 30) -> SourceClient? {
        guard let source = sources.source(sourceID), !source.endpoints.isEmpty, let pin = try? SPKIPin(hex: source.spkiSHA256),
            let base = source.endpoints[endpointIndex % source.endpoints.count].baseURL()
        else { return nil }
        let token = try? credentials.token(sourceID: sourceID)
        return SourceClient(baseURL: base, pin: pin, sourceID: sourceID, token: token, timeout: timeout)
    }

    /// Invalidates the session (tests). Background tasks are cancelled. No task is created afterwards.
    public func invalidate() {
        let session = state.withLock { state -> URLSession? in
            defer { state.session = nil }
            return state.session
        }
        session?.invalidateAndCancel()
    }

    // MARK: Delegate: trust

    // Only the task-level challenge is implemented. With a session-level handler, URLSession sends server
    // trust there instead, without the task, so the pin could not be tied to the task's own source.

    public func urlSession(
        _ session: URLSession, task: URLSessionTask, didReceive challenge: URLAuthenticationChallenge,
        completionHandler: @escaping @Sendable (URLSession.AuthChallengeDisposition, URLCredential?) -> Void
    ) {
        // Task level: only the pin of the source this task's job belongs to.
        let descriptor = TaskDescriptor.parse(task.taskDescription)
        let pin: SPKIPin? = descriptor.flatMap { descriptor in
            state.withLock { $0.records[descriptor.jobID]?.sourceID }
        }.flatMap { sources.source($0) }.flatMap { try? SPKIPin(hex: $0.spkiSHA256) }
        let answer = PinnedTrustEvaluator.answer(challenge, acceptedPins: pin.map { [$0] } ?? [])
        if answer.result == .mismatched || answer.result == .noCertificate {
            state.withLock { _ = $0.pinMismatchTasks.insert(task.taskIdentifier) }
        }
        logChallenge(level: "task", challenge: challenge, descriptor: descriptor, result: answer.result)
        completionHandler(answer.disposition, answer.credential)
    }

    private func logChallenge(level: String, challenge: URLAuthenticationChallenge, descriptor: TaskDescriptor?, result: PinnedTrustEvaluator.Result?) {
        var fields = [
            "level": level, "method": challenge.protectionSpace.authenticationMethod, "host": challenge.protectionSpace.host,
            "port": String(challenge.protectionSpace.port), "app_state": appState(),
            "result": result.map { "\($0)" } ?? "default_handling",
        ]
        if let descriptor { fields["job"] = descriptor.jobID; fields["part"] = descriptor.partKey.description }
        log.record("trust_challenge", fields)
    }

    public func urlSession(
        _ session: URLSession, task: URLSessionTask, willPerformHTTPRedirection response: HTTPURLResponse,
        newRequest request: URLRequest, completionHandler: @escaping @Sendable (URLRequest?) -> Void
    ) {
        completionHandler(nil)  // a redirect never inherits the pinned trust (plan 14.3)
    }

    public func urlSession(
        _ session: URLSession, task: URLSessionTask, willBeginDelayedRequest request: URLRequest,
        completionHandler: @escaping @Sendable (URLSession.DelayedRequestDisposition, URLRequest?) -> Void
    ) {
        // A retry scheduled with earliestBeginDate: start it only if its job still wants the part.
        let wanted: Bool = TaskDescriptor.parse(task.taskDescription).map { descriptor in
            state.withLock { state in
                state.records[descriptor.jobID]?.wantsParts == true
                    && state.runtimes[descriptor.jobID]?.isVerified(descriptor.partKey) == false
            }
        } ?? false
        completionHandler(wanted ? .continueLoading : .cancel, nil)
    }

    // MARK: Delegate: bytes

    public func urlSession(
        _ session: URLSession, downloadTask: URLSessionDownloadTask, didWriteData bytesWritten: Int64,
        totalBytesWritten: Int64, totalBytesExpectedToWrite: Int64
    ) {
        guard let descriptor = TaskDescriptor.parse(downloadTask.taskDescription) else { return }
        let overrun: Bool = state.withLock { state in
            guard var runtime = state.runtimes[descriptor.jobID], let (_, part) = runtime.part(descriptor.partKey) else { return false }
            if totalBytesWritten > part.length {
                state.outcomes[downloadTask.taskIdentifier] = .failed(
                    descriptor.partKey, .bodyLengthMismatch(expected: part.length, received: totalBytesWritten))
                runtime.receivedInFlight[downloadTask.taskIdentifier] = nil
                state.runtimes[descriptor.jobID] = runtime
                return true
            }
            runtime.receivedInFlight[downloadTask.taskIdentifier] = totalBytesWritten
            state.runtimes[descriptor.jobID] = runtime
            return false
        }
        // More bytes than the part: stop receiving (only possible while the app is running).
        if overrun { downloadTask.cancel() }
    }

    public func urlSession(_ session: URLSession, downloadTask: URLSessionDownloadTask, didFinishDownloadingTo location: URL) {
        guard let descriptor = TaskDescriptor.parse(downloadTask.taskDescription) else {
            log.record("download_discarded", ["reason": "foreign_task"])
            return  // the system deletes the file when this method returns
        }
        // Test only: the system failed this task itself, so no file reaches the app (see Options.injectedTaskError).
        if options.injectedTaskError?(descriptor) != nil { return }
        let key = descriptor.partKey
        let outcome: TaskOutcome = state.withLock { state in
            if let earlier = state.outcomes[downloadTask.taskIdentifier] { return earlier }  // overrun
            guard let job = state.records[descriptor.jobID], job.wantsParts, var runtime = state.runtimes[descriptor.jobID],
                let (asset, part) = runtime.part(key)
            else { return .discarded("job_not_downloading") }
            if runtime.isVerified(key) { return .discarded("part_already_verified") }
            guard let response = downloadTask.response as? HTTPURLResponse else { return .failed(key, .transport("no response")) }
            // 1. Head checks: a 200, 412, 416, wrong Content-Range, other ETag or an encoding is rejected here
            //    and its bytes are never opened.
            let expectation = PartResponseValidator.Expectation(part: part, asset: asset)
            if let failure = PartResponseValidator.validateHead(
                status: response.statusCode, header: { response.value(forHTTPHeaderField: $0) }, expectation: expectation)
            {
                return .failed(key, failure)
            }
            guard var store = runtime.stores[asset.assetID] else { return .discarded("no_staging") }
            // 2. Move synchronously: the system deletes `location` when this method returns.
            let incoming = store.incomingDirectory.appendingPathComponent("part-\(part.index)-\(CanonicalID.make()).download")
            do {
                try FileManager.default.moveItem(at: location, to: incoming)
            } catch {
                // This device's storage, not the network (review finding R1-05): a full disk pauses the job
                // with insufficient_space at once; another local error is retried, then storage_unavailable.
                return .failed(key, StagingError.isOutOfSpace(error) ? .localStorageFull : .localWriteFailed("move"))
            }
            // 3. Length and digest, then the verified-only journal: commit copies the bytes into the staging
            //    file at the part's offset while re-hashing them, orders the write to disk, and only then
            //    records the part. It deletes the moved file whatever the result.
            let size = ((try? FileManager.default.attributesOfItem(atPath: incoming.path))?[.size] as? NSNumber)?.int64Value ?? -1
            guard size == part.length else {
                try? FileManager.default.removeItem(at: incoming)
                return .failed(key, .bodyLengthMismatch(expected: part.length, received: size))
            }
            // The commit (copy, hash, write barrier, journal) runs with the lock held; its duration is logged with
            // the part (`commit_ms`) because the transfer screen waits for it (report finding 20, checklist step 11).
            let commitStarted = ContinuousClock.now
            do throws(StagingError) {
                try store.commit(part: part, from: incoming)
            } catch {
                switch error {
                case .digestMismatchOnCommit: return .failed(key, .digestMismatch)
                case .noSpace: return .failed(key, .localStorageFull)
                default: return .failed(key, .localWriteFailed("staging"))
                }
            }
            let commitTook = ContinuousClock.now - commitStarted
            runtime.stores[asset.assetID] = store
            state.runtimes[descriptor.jobID] = runtime
            return .verified(key, commitMilliseconds: Int(commitTook.components.seconds * 1000 + commitTook.components.attoseconds / 1_000_000_000_000_000))
        }
        state.withLock { $0.outcomes[downloadTask.taskIdentifier] = outcome }
    }

    public func urlSession(_ session: URLSession, task: URLSessionTask, didCompleteWithError reported: (any Error)?) {
        guard let descriptor = TaskDescriptor.parse(task.taskDescription) else { return }
        let key = descriptor.partKey
        let injected = options.injectedTaskError?(descriptor)
        let error = injected ?? reported
        // Read outside the lock (see availableSpace); used by the reservation before the next request and to
        // classify a system download that could not be stored.
        let available = availableSpace()
        state.withLock { state in
            if injected != nil { state.outcomes[task.taskIdentifier] = nil }
            let recorded = state.outcomes.removeValue(forKey: task.taskIdentifier)
            let pinMismatch = state.pinMismatchTasks.remove(task.taskIdentifier) != nil
            if !state.reconciled { state.completedBeforeReconciliation.insert(task.taskIdentifier) }
            var wasOutstanding = false
            if var runtime = state.runtimes[descriptor.jobID] {
                if runtime.outstanding[key] == task.taskIdentifier {
                    runtime.outstanding[key] = nil
                    wasOutstanding = true
                }
                runtime.tasks[task.taskIdentifier] = nil
                runtime.receivedInFlight[task.taskIdentifier] = nil
                state.runtimes[descriptor.jobID] = runtime
            }
            let outcome: TaskOutcome
            if pinMismatch {
                outcome = .failed(key, .sourceIdentityChanged)
            } else if let recorded {
                outcome = recorded
            } else if let error {
                let nsError = error as NSError
                if nsError.domain == NSURLErrorDomain, nsError.code == NSURLErrorCancelled, !wasOutstanding {
                    // Cancelled by this coordinator (pause, cancel, reconciliation): already accounted for.
                    outcome = .discarded("cancelled")
                } else if let local = systemDownloadStorageFailure(
                    error, partLength: state.runtimes[descriptor.jobID]?.part(key)?.1.length ?? 0, available: available)
                {
                    log.record("system_download_not_stored", [
                        "job": descriptor.jobID, "part": key.description, "error": "\(nsError.domain) \(nsError.code)",
                        "failure": "\(local)",
                    ])
                    outcome = .failed(key, local)
                } else {
                    outcome = .failed(key, .transport("\(nsError.domain) \(nsError.code)"))
                }
            } else {
                outcome = .failed(key, .transport("no file delivered"))
            }
            handleLocked(&state, descriptor: descriptor, outcome: outcome, appState: appState(), available: available)
        }
    }

    public func urlSession(_ session: URLSession, task: URLSessionTask, didFinishCollecting metrics: URLSessionTaskMetrics) {
        guard let descriptor = TaskDescriptor.parse(task.taskDescription) else { return }
        for transaction in metrics.transactionMetrics {
            log.record("task_metrics", [
                "job": descriptor.jobID, "part": descriptor.partKey.description, "attempt": String(descriptor.attempt),
                "tls": transaction.negotiatedTLSProtocolVersion.map { String(describing: $0.rawValue) } ?? "none",
                "protocol": transaction.networkProtocolName ?? "none", "reused_connection": String(transaction.isReusedConnection),
                "fetch_type": String(transaction.resourceFetchType.rawValue),
            ])
        }
    }

    public func urlSession(_ session: URLSession, taskIsWaitingForConnectivity task: URLSessionTask) {
        log.record("waiting_for_connectivity", ["task": task.taskDescription ?? "foreign"])
    }

    public func urlSessionDidFinishEvents(forBackgroundURLSession session: URLSession) {
        let (completion, waiting) = state.withLock { state -> ((@Sendable () -> Void)?, Bool) in
            let completion = state.backgroundCompletion
            state.backgroundCompletion = nil
            // A full-file check started by these events runs outside the lock; hold the completion until it
            // has published its result, so the system does not suspend the app half way through (R2-04).
            if let completion, !state.assembling.isEmpty {
                let earlier = state.completionAfterAssembly
                state.completionAfterAssembly = { earlier?(); completion() }
                return (nil, true)
            }
            return (completion, false)
        }
        log.record("background_events_finished", [
            "app_state": appState(), "had_completion": String(completion != nil || waiting), "waiting_for_assembly": String(waiting),
        ])
        if let completion { DispatchQueue.main.async { completion() } }
    }

    // MARK: Outcomes

    /// The system could not store a part's response on this device (review finding R2-02). For a background
    /// session the system's transfer daemon writes the whole body into the app's container before
    /// `didFinishDownloadingTo`; when that write fails the task completes with an error and the app never sees
    /// a file. Such a failure is this phone's storage, never "Mac unreachable": an out-of-space error in any
    /// shape (ENOSPC or EDQUOT, also as an NSURLError's underlying error) is `.localStorageFull`; another
    /// NSURLError file error (cannot create, open, close, write, remove or move the file) is `.localStorageFull`
    /// when the volume has less free space than the part, otherwise `.localWriteFailed` (retried, then
    /// `storage_unavailable`). Nil for anything else.
    func systemDownloadStorageFailure(_ error: any Error, partLength: Int64, available: Int64?) -> PartFailure? {
        if StagingError.isOutOfSpace(error) { return .localStorageFull }
        let nsError = error as NSError
        let fileErrors = [
            NSURLErrorCannotCreateFile, NSURLErrorCannotOpenFile, NSURLErrorCannotCloseFile, NSURLErrorCannotWriteToFile,
            NSURLErrorCannotRemoveFile, NSURLErrorCannotMoveFile,
        ]
        guard nsError.domain == NSURLErrorDomain, fileErrors.contains(nsError.code) else { return nil }
        if let available, available < partLength + 1_048_576 {
            return .localStorageFull
        }
        return .localWriteFailed("system_download")
    }

    private func handleLocked(
        _ state: inout State, descriptor: TaskDescriptor, outcome: TaskOutcome, appState: String, available: Int64?
    ) {
        let jobID = descriptor.jobID
        switch outcome {
        case .discarded(let reason):
            if reason != "cancelled" {
                log.record("download_discarded", ["job": jobID, "part": descriptor.partKey.description, "reason": reason])
            }
            if state.records[jobID]?.wantsParts == true { topUpLocked(&state, jobID: jobID, available: available) }
        case .verified(let key, let commitMilliseconds):
            log.record("part_verified", [
                "job": jobID, "part": key.description, "attempt": String(descriptor.attempt), "app_state": appState,
                "commit_ms": String(commitMilliseconds),
            ])
            guard let runtime = state.runtimes[jobID] else { return }
            if runtime.verifiedParts.count == runtime.allParts.count {
                finalizeLocked(&state, jobID: jobID)
            } else {
                topUpLocked(&state, jobID: jobID, available: available)
            }
        case .failed(let key, let failure):
            log.record("part_failed", [
                "job": jobID, "part": key.description, "attempt": String(descriptor.attempt), "failure": "\(failure)",
                "app_state": appState,
            ])
            guard var job = state.records[jobID], job.wantsParts else { return }
            switch failure.recovery {
            case .retryPart:
                let attempts = (job.failedAttempts[key.description] ?? 0) + 1
                job.failedAttempts[key.description] = attempts
                if attempts >= options.maxAttemptsPerPart {
                    saveLocked(&state, job)
                    pauseLocked(&state, jobID: jobID, reason: failure.exhaustedRetriesReason, event: "paused")
                    return
                }
                if case .transport = failure, let count = sources.source(job.sourceID)?.endpoints.count, count > 1 {
                    job.endpointIndex = (job.endpointIndex + 1) % count  // try the next address
                }
                saveLocked(&state, job)
                topUpLocked(&state, jobID: jobID, available: available)
            case .refreshManifest:
                job.state = .refreshing
                saveLocked(&state, job)
                cancelTasksLocked(&state, jobID: jobID)
                log.record("manifest_refresh_needed", ["job": jobID, "failure": "\(failure)"])
                let coordinator = self
                Task { coordinator.startRefresh(jobID: jobID) }
            case .pause(let reason):
                pauseLocked(&state, jobID: jobID, reason: reason, event: "paused")
            }
        }
    }

    // MARK: Scheduling

    private func topUpLocked(_ state: inout State, jobID: String, available: Int64?) {
        guard state.reconciled, let job = state.records[jobID], job.wantsParts, let runtime = state.runtimes[jobID] else { return }
        let missing = runtime.allParts.filter { !runtime.isVerified($0) && runtime.outstanding[$0] == nil }
        let capacity = max(0, options.window - runtime.outstanding.count)
        let next = missing.prefix(capacity)
        guard !next.isEmpty else { return }
        // Plan 15.4 reservation before every new request, not only when the job is created or resumed: other
        // apps may have used the space meanwhile (review finding R2-02). Pauses with insufficient_space.
        guard spaceShortfallLocked(&state, jobID: jobID, available: available) == nil else { return }
        for key in next { enqueueLocked(&state, jobID: jobID, key: key) }
    }

    private func enqueueLocked(_ state: inout State, jobID: String, key: PartKey) {
        guard let session = state.session, var job = state.records[jobID], job.wantsParts, var runtime = state.runtimes[jobID],
            runtime.outstanding[key] == nil, let (asset, part) = runtime.part(key)
        else { return }
        guard let source = sources.source(job.sourceID), !source.endpoints.isEmpty else {
            pauseLocked(&state, jobID: jobID, reason: .reauthenticationRequired, event: "blocked")
            return
        }
        let token: String
        switch readToken(job.sourceID) {
        case .token(let value): token = value
        case .blocked(let reason):
            pauseLocked(&state, jobID: jobID, reason: reason, event: "blocked")
            return
        }
        let endpoint = source.endpoints[job.endpointIndex % source.endpoints.count]
        guard let base = endpoint.baseURL(),
            var components = URLComponents(url: base, resolvingAgainstBaseURL: false)
        else { return }
        components.path = "/v1/assets/\(asset.assetID)/content"
        guard let url = components.url else { return }
        let expectation = PartResponseValidator.Expectation(part: part, asset: asset)
        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        request.setValue(expectation.rangeHeader, forHTTPHeaderField: "Range")
        request.setValue(asset.etag, forHTTPHeaderField: "If-Match")
        request.setValue("identity", forHTTPHeaderField: "Accept-Encoding")
        let failed = job.failedAttempts[key.description] ?? 0
        let descriptor = TaskDescriptor(jobID: jobID, assetID: asset.assetID, partIndex: part.index, attempt: failed + 1)
        let task = session.downloadTask(with: request)
        task.taskDescription = descriptor.encoded
        task.countOfBytesClientExpectsToSend = 1_024
        task.countOfBytesClientExpectsToReceive = part.length + 4_096
        if failed > 0 {
            task.earliestBeginDate = Date().addingTimeInterval(options.retryBaseDelay * Double(failed))
        }
        runtime.outstanding[key] = task.taskIdentifier
        runtime.tasks[task.taskIdentifier] = task
        state.runtimes[jobID] = runtime
        job.updatedAt = Date()
        state.records[jobID] = job
        task.resume()
        log.record("part_requested", [
            "job": jobID, "part": key.description, "attempt": String(descriptor.attempt), "host": endpoint.host,
            "port": String(endpoint.port), "app_state": appState(),
        ])
    }

    private func cancelTasksLocked(_ state: inout State, jobID: String) {
        guard var runtime = state.runtimes[jobID] else { return }
        for task in runtime.tasks.values { task.cancel() }
        runtime.tasks = [:]
        runtime.outstanding = [:]
        runtime.receivedInFlight = [:]
        state.runtimes[jobID] = runtime
    }

    private func pauseLocked(_ state: inout State, jobID: String, reason: PauseReason, event: String) {
        guard var job = state.records[jobID], !job.isTerminal else { return }
        cancelTasksLocked(&state, jobID: jobID)
        job.state = .paused
        job.pauseReason = reason
        saveLocked(&state, job)
        log.record(event, [
            "job": jobID, "reason": reason.rawValue,
            "verified_parts": String(state.runtimes[jobID]?.verifiedParts.count ?? 0), "app_state": appState(),
        ])
        if reason == .sourceUnreachable { checkLocalNetworkLocked(&state, jobID: jobID) }
    }

    private func saveLocked(_ state: inout State, _ job: JobRecord) {
        var job = job
        job.updatedAt = Date()
        state.records[job.jobID] = job
        do { try jobStore.save(job) } catch { log.record("job_save_failed", ["job": job.jobID]) }
    }

    // MARK: Assembly and import

    /// Journalled assembly: the job is recorded as `assembling` first; each asset's staging journal
    /// records the full-digest check and final rename (PartStagingStore.finalize, which also recovers a
    /// stop between the rename and its journal entry); only then is the job `ready_for_import`.
    ///
    /// The full-file SHA-256 reads every byte of the item (5 GiB for the large fixture), so it runs on the
    /// assembly queue, never under the state lock that `jobViews()` (the transfer screen, on the main thread)
    /// takes (review finding R2-04). Under the lock the job is only marked `assembling` and the check is
    /// scheduled; `publishAssembly` applies the result under the lock afterwards. One check per job at a time.
    private func finalizeLocked(_ state: inout State, jobID: String) {
        guard var job = state.records[jobID], let runtime = state.runtimes[jobID] else { return }
        if job.state != .assembling {
            job.state = .assembling
            saveLocked(&state, job)
        }
        guard !state.assembling.contains(jobID) else { return }  // already running; it publishes to this job
        state.assembling.insert(jobID)
        log.record("assembly_started", ["job": jobID, "app_state": appState()])
        let manifest = runtime.manifest
        let stores = runtime.stores
        assemblyQueue.async { [self] in
            let clock = ContinuousClock()
            let began = clock.now
            var finished = stores
            var failure: (assetID: String, error: StagingError)?
            for asset in manifest.assets {
                guard var store = finished[asset.assetID] else {
                    failure = (asset.assetID, .incomplete)
                    break
                }
                do throws(StagingError) {
                    _ = try store.finalize()
                    finished[asset.assetID] = store
                } catch {
                    finished[asset.assetID] = store
                    failure = (asset.assetID, error)
                    break
                }
            }
            publishAssembly(jobID: jobID, manifest: manifest, stores: finished, failure: failure, duration: clock.now - began)
        }
    }

    /// Applies a full-file check made outside the lock. The staging stores' new state (final file recorded, or
    /// every part forgotten after a mismatch) is kept whenever the job still has staging for the same version;
    /// the job moves on only if it is still `assembling` (a pause or cancel meanwhile wins: a cancelled job has
    /// no staging any more, and a paused one finds its finished file when resumed).
    private func publishAssembly(
        jobID: String, manifest: TransferManifest, stores: [String: PartStagingStore],
        failure: (assetID: String, error: StagingError)?, duration: Duration
    ) {
        let milliseconds = String(duration.components.seconds * 1000 + duration.components.attoseconds / 1_000_000_000_000_000)
        let held = state.withLock { state -> (@Sendable () -> Void)? in
            state.assembling.remove(jobID)
            applyAssemblyLocked(&state, jobID: jobID, manifest: manifest, stores: stores, failure: failure, milliseconds: milliseconds)
            guard state.assembling.isEmpty else { return nil }
            defer { state.completionAfterAssembly = nil }
            return state.completionAfterAssembly
        }
        if let held {
            log.record("background_events_completed_after_assembly", ["job": jobID])
            DispatchQueue.main.async { held() }
        }
    }

    private func applyAssemblyLocked(
        _ state: inout State, jobID: String, manifest: TransferManifest, stores: [String: PartStagingStore],
        failure: (assetID: String, error: StagingError)?, milliseconds: String
    ) {
        guard var runtime = state.runtimes[jobID], runtime.manifest.itemVersionID == manifest.itemVersionID else {
            log.record("assembly_result_dropped", ["job": jobID, "reason": "staging_gone_or_version_changed"])
            return
        }
        for (assetID, store) in stores { runtime.stores[assetID] = store }
        state.runtimes[jobID] = runtime
        guard var job = state.records[jobID], job.state == .assembling else {
            log.record("assembly_result_kept", ["job": jobID, "job_state": state.records[jobID]?.state.rawValue ?? "none"])
            return
        }
        if let failure {
            log.record("final_digest_failed", [
                "job": jobID, "asset": failure.assetID, "error": "\(failure.error)", "milliseconds": milliseconds,
            ])
            job.state = .downloading
            state.records[jobID] = job
            let reason: PauseReason = switch failure.error {
            case .finalDigestMismatch: .finalDigestMismatch
            case .noSpace: .insufficientSpace
            default: .storageUnavailable
            }
            pauseLocked(&state, jobID: jobID, reason: reason, event: "paused")
            return
        }
        job.state = .readyForImport
        saveLocked(&state, job)
        log.record("assembly_verified", [
            "job": jobID, "bytes": String(manifest.totalBytes), "assets": String(manifest.assets.count),
            "milliseconds": milliseconds, "app_state": appState(),
        ])
        importLocked(&state, jobID: jobID)
    }

    private func importLocked(_ state: inout State, jobID: String) {
        guard var job = state.records[jobID], job.state == .readyForImport, let runtime = state.runtimes[jobID] else { return }
        let assets = runtime.manifest.assets.compactMap { asset -> StubImporter.VerifiedAsset? in
            guard let store = runtime.stores[asset.assetID], store.isFinalVerified else { return nil }
            return .init(assetID: asset.assetID, url: store.verifiedURL, sha256: asset.sha256, length: asset.length)
        }
        guard assets.count == runtime.manifest.assets.count else { return }
        do {
            let outcome = try importer.importVerified(
                jobID: jobID, itemID: job.itemID, itemVersionID: job.itemVersionID, assets: assets)
            let record: StubImporter.Record
            let firstImport: Bool
            switch outcome {
            case .imported(let value): (record, firstImport) = (value, true)
            case .alreadyImported(let value): (record, firstImport) = (value, false)
            }
            job.state = .imported
            if job.receiptIDs[Receipt.State.downloadedToPhone.rawValue] == nil {
                job.receiptIDs[Receipt.State.downloadedToPhone.rawValue] = CanonicalID.make()
                job.receiptIDs[Receipt.State.importedIntoSylvia.rawValue] = CanonicalID.make()
            }
            saveLocked(&state, job)
            state.runtimes[jobID] = nil
            jobStore.deleteStaging(jobID)
            log.record(firstImport ? "imported" : "import_already_recorded", [
                "job": jobID, "import": record.importID, "version": record.itemVersionID,
                "completions": String(record.completions), "duplicate_requests": String(record.duplicateRequests),
            ])
            let coordinator = self
            Task { await coordinator.sendReceipts(jobID: jobID) }
        } catch {
            log.record("import_failed", ["job": jobID, "error": "\(error)"])
        }
    }

    // MARK: Receipts

    private func retryPendingReceipts() {
        let pending = state.withLock { state in
            state.records.values.filter { $0.state == .imported && !$0.receiptIDs.isEmpty && !$0.receiptsAcknowledged }.map(\.jobID)
        }
        for jobID in pending {
            let coordinator = self
            Task { await coordinator.sendReceipts(jobID: jobID) }
        }
    }

    /// Tells the Mac "downloaded to phone" and "imported into Sylvia" with stable receipt IDs, so a retry
    /// after a crash is acknowledged as a duplicate rather than counted twice.
    func sendReceipts(jobID: String) async {
        guard let job = state.withLock({ $0.records[jobID] }), job.state == .imported,
            let client = client(sourceID: job.sourceID, endpointIndex: job.endpointIndex)
        else { return }
        var acknowledged = true
        // A retried receipt must be byte-identical to the first (same ID and body), so its time comes from the
        // importer's durable record, not from the job's last-modified time.
        let occurredAt = importer.record(itemVersionID: job.itemVersionID)?.importedAt ?? job.createdAt
        for receiptState in [Receipt.State.downloadedToPhone, .importedIntoSylvia] {
            guard let receiptID = job.receiptIDs[receiptState.rawValue] else { continue }
            let receipt = Receipt(
                receiptID: receiptID, queueEntryID: job.queueEntryID, itemID: job.itemID, itemVersionID: job.itemVersionID, state: receiptState,
                occurredAt: occurredAt)
            do {
                let ack = try await client.postReceipt(receipt)
                log.record("receipt_acknowledged", [
                    "job": jobID, "state": receiptState.rawValue, "duplicate": String(ack.duplicate),
                    "queue_entry": job.queueEntryID ?? "none", "entry_state": ack.entryState?.rawValue ?? "none",
                ])
            } catch {
                acknowledged = false
                log.record("receipt_pending", ["job": jobID, "state": receiptState.rawValue, "error": "\(error)"])
            }
        }
        guard acknowledged else { return }
        state.withLock { state in
            guard var job = state.records[jobID] else { return }
            job.receiptsAcknowledged = true
            saveLocked(&state, job)
        }
    }

    // MARK: Manifests

    func startRefresh(jobID: String) {
        let begin = state.withLock { state -> Bool in
            guard state.records[jobID]?.state == .refreshing, !state.refreshing.contains(jobID) else { return false }
            state.refreshing.insert(jobID)
            return true
        }
        guard begin else { return }
        let coordinator = self
        Task { await coordinator.refresh(jobID: jobID) }
    }

    private func refresh(jobID: String) async {
        defer { _ = state.withLock { $0.refreshing.remove(jobID) } }
        guard let job = state.withLock({ $0.records[jobID] }) else { return }
        let manifest: TransferManifest
        do {
            manifest = try await fetchManifest(sourceID: job.sourceID, itemID: job.itemID, endpointIndex: job.endpointIndex)
        } catch {
            state.withLock { state in
                guard var current = state.records[jobID], current.state == .refreshing else { return }
                current.state = .downloading
                state.records[jobID] = current
                pauseLocked(&state, jobID: jobID, reason: TransferEngine.pauseReason(for: error), event: "paused")
            }
            return
        }
        let available = availableSpace()
        state.withLock { state in
            guard var current = state.records[jobID], current.state == .refreshing else { return }
            current.manifestRefreshes += 1
            if current.manifestRefreshes > options.maxManifestRefreshes {
                current.state = .downloading
                state.records[jobID] = current
                pauseLocked(&state, jobID: jobID, reason: .manifestInvalid, event: "paused")
                return
            }
            let previous = current.itemVersionID
            do { try jobStore.saveManifest(manifest, jobID: jobID) } catch {
                log.record("job_save_failed", ["job": jobID])
                return
            }
            current.itemVersionID = manifest.itemVersionID
            current.failedAttempts = [:]
            current.state = .downloading
            // Unlike launch and resume, a version change re-hashes the kept parts under the lock: saving the new
            // manifest, the record and the runtime must stay one step against a concurrent pause or cancel. It is
            // rare (the Mac's file changed) and the job is not downloading meanwhile.
            guard let (runtime, reconciliation) = openRuntime(for: current, verify: true) else {
                current.state = .downloading
                state.records[jobID] = current
                pauseLocked(&state, jobID: jobID, reason: .manifestInvalid, event: "paused")
                return
            }
            // Asset folders the new version no longer lists hold bytes of no use: remove them.
            let staging = jobStore.stagingRoot(jobID)
            let wanted = Set(manifest.assets.map(\.assetID))
            for name in (try? FileManager.default.contentsOfDirectory(atPath: staging.path)) ?? [] where !wanted.contains(name) {
                try? FileManager.default.removeItem(at: staging.appendingPathComponent(name))
            }
            state.runtimes[jobID] = runtime
            saveLocked(&state, current)
            log.record(previous == manifest.itemVersionID ? "manifest_unchanged" : "version_changed", [
                "job": jobID, "from": previous, "to": manifest.itemVersionID, "kept_parts": String(reconciliation.keptParts),
                "discarded_parts": String(reconciliation.discardedParts),
            ])
            if runtime.verifiedParts.count == runtime.allParts.count {
                finalizeLocked(&state, jobID: jobID)
            } else {
                topUpLocked(&state, jobID: jobID, available: available)
            }
        }
    }

    private func fetchManifest(sourceID: String, itemID: String, endpointIndex: Int) async throws(ClientError) -> TransferManifest {
        guard let client = client(sourceID: sourceID, endpointIndex: endpointIndex) else { throw .notPaired }
        let clock = ContinuousClock()
        let started = clock.now
        while true {
            do {
                return try await client.manifest(itemID: itemID)
            } catch {
                guard case .http(503, "preparing") = error, clock.now - started < options.maxPreparationWait else { throw error }
                log.record("source_preparing", ["item": itemID])
                do { try await Task.sleep(for: options.preparationPollInterval) } catch { throw .cancelled }
            }
        }
    }

    /// Opens the staging stores for a job's persisted manifest. Nil when the manifest cannot be read.
    private func openRuntime(for job: JobRecord, verify: Bool) -> (Runtime, (keptParts: Int, discardedParts: Int))? {
        let manifest: TransferManifest
        do { manifest = try jobStore.loadManifest(for: job) } catch {
            log.record("manifest_unreadable", ["job": job.jobID])
            return nil
        }
        var stores: [String: PartStagingStore] = [:]
        var kept = 0
        var discarded = 0
        do {
            try DurableFile.createDirectory(jobStore.stagingRoot(job.jobID))
            for asset in manifest.assets {
                let (store, reconciliation) = try PartStagingStore.open(
                    root: jobStore.stagingRoot(job.jobID), asset: asset, itemVersionID: manifest.itemVersionID, verifyExistingParts: verify)
                stores[asset.assetID] = store
                kept += reconciliation.keptParts
                discarded += reconciliation.discardedParts
            }
        } catch {
            log.record("staging_unavailable", ["job": job.jobID])
            return nil
        }
        return (Runtime(manifest: manifest, stores: stores), (kept, discarded))
    }

    // MARK: Credentials

    private func credentialStatus(_ sourceID: String) -> ReconciliationPlanner.Credential {
        guard sources.source(sourceID) != nil else { return .missing }
        switch readToken(sourceID) {
        case .token: return .available
        case .blocked(.deviceLocked): return .locked
        case .blocked: return .missing
        }
    }

    enum TokenRead {
        case token(String)
        case blocked(PauseReason)
    }

    /// The token is read from the Keychain for every new task, so a deleted (revoked) credential stops
    /// new requests at once. If the Keychain refuses with errSecInteractionNotAllowed the job is blocked
    /// as `device_locked`, never downgraded or treated as revoked. Defensive only: before the first unlock
    /// the job store is unreadable too and `start()` defers, so no job is loaded while the token is locked.
    private func readToken(_ sourceID: String) -> TokenRead {
        do {
            guard let token = try credentials.token(sourceID: sourceID) else { return .blocked(.reauthenticationRequired) }
            return .token(token)
        } catch let error as KeychainError where error.status == errSecInteractionNotAllowed {
            return .blocked(.deviceLocked)
        } catch {
            return .blocked(.reauthenticationRequired)
        }
    }
}
