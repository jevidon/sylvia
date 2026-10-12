import Darwin
import Foundation

/// The share extension's write sequence, in order. Every step is a fault-injection point (plan 8.1, T07).
public enum HandoffWriteStep: String, CaseIterable, Sendable, Codable {
    case checkSpace                 // free-space check before copying an item whose size is known
    case createStagingDirectory     // Handoffs/<id>/ and Handoffs/<id>/items/
    case openSource                 // open the provider's file
    case createDestination          // items/<n>.<ext>, O_EXCL
    case readChunk                  // each read from the source
    case writeChunk                 // each write to the destination
    case syncItem                   // F_FULLFSYNC of the copied item
    case closeItem                  // close(2) of the copied item (errors are checked)
    case verifyItem                 // byte count and source-unchanged check
    case syncItemsDirectory         // make the item entries durable
    case writeManifestTemporary     // handoff.json.tmp-<uuid>
    case syncManifestTemporary      // F_FULLFSYNC of the temporary manifest
    case renameManifest             // rename to handoff.json (no replace): the commit point
    case syncHandoffDirectory       // make the rename durable; only after this is receipt reported
}

/// What an injected fault does.
public enum FaultMode: String, Sendable, Codable {
    /// Throw an I/O error; the writer runs its normal failure path (cleanup, no receipt).
    case error
    /// Simulate process death: throw `SimulatedProcessDeath`, which the writer must not clean up after,
    /// leaving exactly the bytes a killed extension would leave.
    case abandon
    /// Really die: SIGKILL this process at the step (used by the host kill-at-every-step script).
    case kill
}

/// Thrown by `FaultMode.abandon`. The writer rethrows it without running cleanup.
public struct SimulatedProcessDeath: Error, Sendable {
    public let step: HandoffWriteStep
    public init(step: HandoffWriteStep) { self.step = step }
}

public protocol FaultInjecting: Sendable {
    /// Called at every step; `ordinal` counts calls of the same step (chunks, items) from 1.
    func reach(_ step: HandoffWriteStep) throws
}

/// No faults: the production configuration.
public struct NoFaults: FaultInjecting {
    public init() {}
    public func reach(_ step: HandoffWriteStep) throws {}
}

/// Fails the `occurrence`-th time `step` is reached.
public final class StepFault: FaultInjecting, @unchecked Sendable {
    public let step: HandoffWriteStep
    public let occurrence: Int
    public let mode: FaultMode
    private let lock = NSLock()
    private var counts: [HandoffWriteStep: Int] = [:]
    private(set) public var fired = false

    public init(step: HandoffWriteStep, occurrence: Int = 1, mode: FaultMode) {
        self.step = step
        self.occurrence = occurrence
        self.mode = mode
    }

    public func reach(_ reached: HandoffWriteStep) throws {
        let hit: Bool = lock.withLock {
            counts[reached, default: 0] += 1
            let hit = reached == step && counts[reached] == occurrence
            if hit { fired = true }
            return hit
        }
        guard hit else { return }
        switch mode {
        case .error: throw IntakeIOError("injected fault at \(step.rawValue)", code: EIO)
        case .abandon: throw SimulatedProcessDeath(step: step)
        case .kill:
            kill(getpid(), SIGKILL)
            // SIGKILL cannot be caught; this line is never reached.
            fatalError("SIGKILL returned")
        }
    }

    /// How many times each step was reached (lets tests assert that every step actually ran).
    public var reachedCounts: [HandoffWriteStep: Int] { lock.withLock { counts } }
}
