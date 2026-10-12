import Foundation
import SylviaTransferCore

/// The Mac's durable outbound queue and receipt ledger (plan 15.1, 16.2).
///
/// "Send to device" adds an entry; the entry survives restarts (atomic JSON file) and waits until the
/// phone lists its inbox. Receipts are idempotent by `receipt_id`. The three acknowledgements stay
/// separate: an entry is "queued on Mac" when added, "observed" when the phone lists it, "downloaded to
/// phone" only on that receipt, and "imported into Sylvia" only on that receipt. HTTP delivery of bytes
/// is never treated as an import. An import failure keeps the entry for retry. Nothing here deletes or
/// modifies a source file.
public actor OutboundQueue {
    public struct Entry: Codable, Hashable, Sendable {
        public var queueEntryID: String
        public var sequence: Int
        public var deviceID: String
        public var itemID: String
        public var itemVersionID: String?
        public var queuedAt: Date
        public var state: DeliveryState
        public var lastFailure: Receipt.Failure?
        public var updatedAt: Date

        enum CodingKeys: String, CodingKey {
            case queueEntryID = "queue_entry_id"
            case sequence
            case deviceID = "device_id"
            case itemID = "item_id"
            case itemVersionID = "item_version_id"
            case queuedAt = "queued_at"
            case state
            case lastFailure = "last_failure"
            case updatedAt = "updated_at"
        }
    }

    struct ReceiptRecord: Codable, Hashable {
        var receiptID: String
        var deviceID: String
        var bodySHA256: String
        var ack: ReceiptAck
        enum CodingKeys: String, CodingKey {
            case receiptID = "receipt_id"
            case deviceID = "device_id"
            case bodySHA256 = "body_sha256"
            case ack
        }
    }

    struct StateFile: Codable {
        var nextSequence: Int
        var entries: [Entry]
        var receipts: [ReceiptRecord]
        enum CodingKeys: String, CodingKey {
            case nextSequence = "next_sequence"
            case entries
            case receipts
        }
    }

    public enum ReceiptError: Error, Equatable, Sendable {
        case conflict          // same receipt_id, different body
        case unknownEntry      // not this device's entry
        case mismatch          // receipt names a different item than the entry
        case invalid
        case storageFailure
    }

    private let url: URL?
    private let now: @Sendable () -> Date
    private var state: StateFile

    public init(stateURL: URL?, now: @escaping @Sendable () -> Date) throws {
        url = stateURL
        self.now = now
        state = try stateURL.flatMap { try DurableFile.read(StateFile.self, from: $0) }
            ?? StateFile(nextSequence: 1, entries: [], receipts: [])
    }

    /// Adds an item to a device's queue ("Queued on Mac"). Persisted before returning.
    public func enqueue(itemID: String, itemVersionID: String?, deviceID: String) throws -> Entry {
        let entry = Entry(
            queueEntryID: CanonicalID.make(), sequence: state.nextSequence, deviceID: deviceID, itemID: itemID,
            itemVersionID: itemVersionID, queuedAt: now(), state: .queuedOnMac, lastFailure: nil, updatedAt: now())
        state.nextSequence += 1
        state.entries.append(entry)
        try persist()
        return entry
    }

    /// Entries for a device after `cursor` (a sequence number), oldest first. Listing marks queued
    /// entries as observed; it never implies download or import.
    public func inbox(deviceID: String, afterSequence: Int, limit: Int) throws -> (entries: [Entry], nextSequence: Int?) {
        let mine = state.entries.filter { $0.deviceID == deviceID && $0.sequence > afterSequence }.sorted { $0.sequence < $1.sequence }
        let page = Array(mine.prefix(limit))
        var changed = false
        for entry in page where entry.state == .queuedOnMac {
            update(entry.queueEntryID) { $0.state = .observedByPhone }
            changed = true
        }
        if changed { try persist() }
        let refreshed = page.compactMap { entry in state.entries.first { $0.queueEntryID == entry.queueEntryID } }
        return (refreshed, mine.count > page.count ? page.last?.sequence : nil)
    }

    /// Points an entry at a newer immutable version after the original changed.
    public func repoint(queueEntryID: String, to itemVersionID: String) throws {
        update(queueEntryID) { $0.itemVersionID = itemVersionID }
        try persist()
    }

    public func apply(_ receipt: Receipt, from deviceID: String, bodySHA256: String) throws(ReceiptError) -> ReceiptAck {
        guard receipt.schemaVersion == 1, CanonicalID.isValid(receipt.receiptID), CanonicalID.isValid(receipt.itemID),
            CanonicalID.isValid(receipt.itemVersionID), receipt.queueEntryID.map(CanonicalID.isValid) ?? true,
            (receipt.state == .importFailed) == (receipt.failure != nil),
            receipt.failure.map(Self.isValid) ?? true
        else { throw .invalid }
        if let previous = state.receipts.first(where: { $0.receiptID == receipt.receiptID }) {
            guard previous.deviceID == deviceID, previous.bodySHA256 == bodySHA256 else { throw .conflict }
            var ack = previous.ack
            ack.duplicate = true
            return ack
        }
        var entryState: DeliveryState?
        if let entryID = receipt.queueEntryID {
            guard let entry = state.entries.first(where: { $0.queueEntryID == entryID && $0.deviceID == deviceID }) else {
                throw .unknownEntry
            }
            guard entry.itemID == receipt.itemID else { throw .mismatch }
            let next = Self.transition(from: entry.state, on: receipt.state)
            update(entryID) {
                $0.state = next
                $0.lastFailure = receipt.state == .importFailed ? receipt.failure : nil
                $0.updatedAt = self.now()
            }
            entryState = next
        }
        let ack = ReceiptAck(receiptID: receipt.receiptID, queueEntryID: receipt.queueEntryID, entryState: entryState, duplicate: false)
        state.receipts.append(ReceiptRecord(receiptID: receipt.receiptID, deviceID: deviceID, bodySHA256: bodySHA256, ack: ack))
        do { try persist() } catch { throw .storageFailure }
        return ack
    }

    public func entries() -> [Entry] { state.entries.sorted { $0.sequence < $1.sequence } }

    /// receipt.v1: `code` is `^[a-z][a-z0-9_]{0,63}$`; `message` is 1 to 512 characters (no control characters,
    /// since the Mac shows it).
    static func isValid(_ failure: Receipt.Failure) -> Bool {
        let code = Array(failure.code.utf8)
        guard let first = code.first, (0x61...0x7A).contains(first), code.count <= 64,
            code.allSatisfy({ (0x61...0x7A).contains($0) || (0x30...0x39).contains($0) || $0 == 0x5F })
        else { return false }
        let message = failure.message.unicodeScalars
        return !message.isEmpty && message.count <= 512 && !message.contains { $0.properties.generalCategory == .control }
    }

    /// Receipts never move an entry backwards: a late "downloaded" after "imported" leaves it imported.
    static func transition(from current: DeliveryState, on receipt: Receipt.State) -> DeliveryState {
        switch receipt {
        case .downloadedToPhone:
            return current == .importedIntoSylvia ? current : .downloadedToPhone
        case .importedIntoSylvia:
            return .importedIntoSylvia
        case .importFailed:
            return current == .importedIntoSylvia ? current : .importFailed
        }
    }

    private func update(_ entryID: String, _ change: (inout Entry) -> Void) {
        guard let index = state.entries.firstIndex(where: { $0.queueEntryID == entryID }) else { return }
        change(&state.entries[index])
    }

    private func persist() throws {
        guard let url else { return }
        try DurableFile.write(state, to: url)
    }
}
