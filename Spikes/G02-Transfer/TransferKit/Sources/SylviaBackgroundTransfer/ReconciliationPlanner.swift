import Foundation
import SylviaTransferCore

/// Launch reconciliation (plan 6.4, 15.5): decides, from persisted jobs, verified parts on disk and the
/// system's outstanding background tasks, which tasks to keep, which to cancel, which parts to request
/// again and which jobs to finish or block. Pure, so every rule is unit tested on the host.
///
/// Rules:
/// - A task whose description does not parse, or names an unknown or finished job, is cancelled.
/// - A task for a job that is not downloading (paused, refreshing, cancelled, assembling, ready, imported)
///   is cancelled; its verified parts stay on disk.
/// - A task for a part that is already verified, or not in the job's current manifest, is cancelled.
/// - Two tasks for the same part: the newest attempt is kept, the others are cancelled.
/// - A downloading job whose credential is missing or revoked is blocked (re-pairing), and one whose
///   Keychain refuses to answer is blocked (unlock); in both cases its tasks are cancelled and verified
///   bytes kept. The second rule is defensive: before the first unlock the job store is unreadable as
///   well, and the coordinator does not plan at all then (it defers its launch, so nothing is cancelled).
/// - Parts that are neither verified nor covered by a kept task are requested again, up to the window.
/// - A job interrupted while fetching a new manifest fetches it again.
/// - A downloading job with every part verified, or a job interrupted while assembling, is finalized;
///   a job ready for import is handed to the importer again (the importer is idempotent).
public enum ReconciliationPlanner {
    public enum Credential: Hashable, Sendable {
        case available
        case missing
        case locked
    }

    public struct JobSnapshot: Hashable, Sendable {
        public var jobID: String
        public var state: JobRecord.State
        /// Every part of the current manifest, in download order. Nil when the manifest cannot be read.
        public var parts: [PartKey]?
        public var verified: Set<PartKey>
        public var credential: Credential

        public init(jobID: String, state: JobRecord.State, parts: [PartKey]?, verified: Set<PartKey>, credential: Credential) {
            self.jobID = jobID
            self.state = state
            self.parts = parts
            self.verified = verified
            self.credential = credential
        }
    }

    public struct OutstandingTask: Hashable, Sendable {
        public var taskIdentifier: Int
        public var taskDescription: String?

        public init(taskIdentifier: Int, taskDescription: String?) {
            self.taskIdentifier = taskIdentifier
            self.taskDescription = taskDescription
        }
    }

    public enum CancelReason: String, Hashable, Sendable {
        case foreign = "foreign_task"
        case unknownJob = "unknown_job"
        case jobNotDownloading = "job_not_downloading"
        case partAlreadyVerified = "part_already_verified"
        case partNotInManifest = "part_not_in_manifest"
        case duplicate = "duplicate_task"
        case jobBlocked = "job_blocked"
    }

    public struct Plan: Equatable, Sendable {
        public var cancel: [Int: CancelReason] = [:]
        public var adopt: [Int: TaskDescriptor] = [:]
        public var enqueue: [String: [PartKey]] = [:]
        public var finalize: [String] = []
        public var importReady: [String] = []
        /// Jobs interrupted while fetching a new manifest: fetch it again.
        public var refresh: [String] = []
        public var block: [String: PauseReason] = [:]

        public init() {}

        public var adoptedCount: Int { adopt.count }
        public var enqueuedCount: Int { enqueue.values.reduce(0) { $0 + $1.count } }
    }

    /// - Parameter window: maximum outstanding tasks per downloading job (adopted plus new).
    public static func plan(jobs: [JobSnapshot], tasks: [OutstandingTask], window: Int) -> Plan {
        var plan = Plan()
        let byID = Dictionary(jobs.map { ($0.jobID, $0) }, uniquingKeysWith: { first, _ in first })

        // Which jobs are blocked before any task is considered.
        for job in jobs where job.state == .downloading {
            if job.parts == nil {
                plan.block[job.jobID] = .manifestInvalid
            } else if job.credential == .missing {
                plan.block[job.jobID] = .reauthenticationRequired
            } else if job.credential == .locked {
                plan.block[job.jobID] = .deviceLocked
            }
        }

        // Tasks: keep only one per wanted part of a downloading, unblocked job.
        var keptByPart: [String: [PartKey: (Int, TaskDescriptor)]] = [:]
        for task in tasks.sorted(by: { $0.taskIdentifier < $1.taskIdentifier }) {
            guard let descriptor = TaskDescriptor.parse(task.taskDescription) else {
                plan.cancel[task.taskIdentifier] = .foreign
                continue
            }
            guard let job = byID[descriptor.jobID] else {
                plan.cancel[task.taskIdentifier] = .unknownJob
                continue
            }
            if plan.block[job.jobID] != nil {
                plan.cancel[task.taskIdentifier] = .jobBlocked
                continue
            }
            guard job.state == .downloading, let parts = job.parts else {
                plan.cancel[task.taskIdentifier] = .jobNotDownloading
                continue
            }
            let key = descriptor.partKey
            guard parts.contains(key) else {
                plan.cancel[task.taskIdentifier] = .partNotInManifest
                continue
            }
            if job.verified.contains(key) {
                plan.cancel[task.taskIdentifier] = .partAlreadyVerified
                continue
            }
            if let existing = keptByPart[job.jobID]?[key] {
                // Keep the newest attempt; the older one belongs to a superseded request.
                if descriptor.attempt > existing.1.attempt {
                    plan.cancel[existing.0] = .duplicate
                    keptByPart[job.jobID]?[key] = (task.taskIdentifier, descriptor)
                } else {
                    plan.cancel[task.taskIdentifier] = .duplicate
                }
                continue
            }
            keptByPart[job.jobID, default: [:]][key] = (task.taskIdentifier, descriptor)
        }
        for (_, parts) in keptByPart {
            for (_, kept) in parts { plan.adopt[kept.0] = kept.1 }
        }

        // Jobs: request missing parts, finish complete ones.
        for job in jobs.sorted(by: { $0.jobID < $1.jobID }) {
            if plan.block[job.jobID] != nil { continue }
            switch job.state {
            case .downloading:
                guard let parts = job.parts else { continue }
                let missing = parts.filter { !job.verified.contains($0) }
                if missing.isEmpty {
                    plan.finalize.append(job.jobID)
                    continue
                }
                let covered = Set(keptByPart[job.jobID]?.keys.map { $0 } ?? [])
                let capacity = max(0, window - covered.count)
                let wanted = missing.filter { !covered.contains($0) }.prefix(capacity)
                if !wanted.isEmpty { plan.enqueue[job.jobID] = Array(wanted) }
            case .assembling:
                plan.finalize.append(job.jobID)
            case .readyForImport:
                plan.importReady.append(job.jobID)
            case .refreshing:
                plan.refresh.append(job.jobID)
            case .paused, .imported, .cancelled:
                continue
            }
        }
        return plan
    }
}
