import Foundation

// Wire payloads of the source service (Contracts/openapi/source-service.v1.yaml). Each mirrors a
// JSON Schema in Contracts/schemas/. Unknown fields are ignored on decode (plan 15.3: tolerate
// additive optional fields).

/// GET /v1/capabilities. Unauthenticated, so it carries no library data (plan 15.3).
public struct Capabilities: Codable, Hashable, Sendable {
    public struct PartSizes: Codable, Hashable, Sendable {
        public var defaultBytes: Int64
        public var minimumBytes: Int64
        public var maximumBytes: Int64
        enum CodingKeys: String, CodingKey {
            case defaultBytes = "default_bytes"
            case minimumBytes = "min_bytes"
            case maximumBytes = "max_bytes"
        }
        public init(defaultBytes: Int64, minimumBytes: Int64, maximumBytes: Int64) {
            self.defaultBytes = defaultBytes
            self.minimumBytes = minimumBytes
            self.maximumBytes = maximumBytes
        }
    }

    public struct Limits: Codable, Hashable, Sendable {
        public var maximumPartsPerAsset: Int
        public var maximumPartsPerManifest: Int
        public var maximumAssetsPerItem: Int
        public var maximumPageLimit: Int
        public var maximumRequestBodyBytes: Int
        enum CodingKeys: String, CodingKey {
            case maximumPartsPerAsset = "max_parts_per_asset"
            case maximumPartsPerManifest = "max_parts_per_manifest"
            case maximumAssetsPerItem = "max_assets_per_item"
            case maximumPageLimit = "max_page_limit"
            case maximumRequestBodyBytes = "max_request_body_bytes"
        }
        public init(
            maximumPartsPerAsset: Int, maximumPartsPerManifest: Int, maximumAssetsPerItem: Int,
            maximumPageLimit: Int, maximumRequestBodyBytes: Int
        ) {
            self.maximumPartsPerAsset = maximumPartsPerAsset
            self.maximumPartsPerManifest = maximumPartsPerManifest
            self.maximumAssetsPerItem = maximumAssetsPerItem
            self.maximumPageLimit = maximumPageLimit
            self.maximumRequestBodyBytes = maximumRequestBodyBytes
        }
    }

    public var schemaVersion: Int
    public var protocolVersion: ProtocolVersion
    public var supportedMajorVersions: [Int]
    public var sourceID: String
    public var partSize: PartSizes
    public var limits: Limits
    public var authScheme: String
    public var scopes: [Scope]
    public var pinAlgorithm: String

    enum CodingKeys: String, CodingKey {
        case schemaVersion = "schema_version"
        case protocolVersion = "protocol_version"
        case supportedMajorVersions = "supported_major_versions"
        case sourceID = "source_id"
        case partSize = "part_size"
        case limits
        case authScheme = "auth_scheme"
        case scopes
        case pinAlgorithm = "pin_algorithm"
    }

    public init(sourceID: String, partSize: PartSizes) {
        schemaVersion = 1
        protocolVersion = TransferProtocol.version
        supportedMajorVersions = [TransferProtocol.major]
        self.sourceID = sourceID
        self.partSize = partSize
        limits = Limits(
            maximumPartsPerAsset: TransferProtocol.maximumPartsPerAsset,
            maximumPartsPerManifest: TransferProtocol.maximumPartsPerManifest,
            maximumAssetsPerItem: TransferProtocol.maximumAssetsPerItem,
            maximumPageLimit: TransferProtocol.maximumPageLimit,
            maximumRequestBodyBytes: TransferProtocol.maximumRequestBodyBytes)
        authScheme = "bearer"
        scopes = TransferProtocol.allScopes
        pinAlgorithm = "spki-sha256"
    }

    /// Picks the part size to request: the preference clamped into the source's range and rounded
    /// down to a whole MiB; nil if the source speaks no compatible major version.
    public func negotiatedPartSize(preferred: Int64 = TransferProtocol.defaultPartSize) -> Int64? {
        guard supportedMajorVersions.contains(TransferProtocol.major) else { return nil }
        let low = max(partSize.minimumBytes, TransferProtocol.minimumPartSize)
        let high = min(partSize.maximumBytes, TransferProtocol.maximumPartSize)
        guard low <= high else { return nil }
        let clamped = min(max(preferred, low), high)
        let rounded = clamped / TransferProtocol.mebibyte * TransferProtocol.mebibyte
        return rounded >= low ? rounded : nil
    }
}

/// POST /v1/pair request. `invitation_secret` is a credential: it is sent once, over the pinned
/// connection, and is never logged or persisted by either side (plan 15.2).
public struct PairRequest: Codable, Hashable, Sendable {
    public var schemaVersion: Int
    public var invitationID: String
    public var invitationSecret: String
    public var sourceID: String
    public var deviceID: String
    public var deviceName: String

    enum CodingKeys: String, CodingKey {
        case schemaVersion = "schema_version"
        case invitationID = "invitation_id"
        case invitationSecret = "invitation_secret"
        case sourceID = "source_id"
        case deviceID = "device_id"
        case deviceName = "device_name"
    }

    public init(invitationID: String, invitationSecret: String, sourceID: String, deviceID: String, deviceName: String) {
        schemaVersion = 1
        self.invitationID = invitationID
        self.invitationSecret = invitationSecret
        self.sourceID = sourceID
        self.deviceID = deviceID
        self.deviceName = deviceName
    }
}

/// POST /v1/pair response. The token is stored only in the device Keychain (ADR-0008).
public struct PairResponse: Codable, Hashable, Sendable {
    public var schemaVersion: Int
    public var sourceID: String
    public var deviceID: String
    public var token: String
    public var tokenType: String
    public var scopes: [Scope]
    public var spkiSHA256: String
    public var pairedAt: Date

    enum CodingKeys: String, CodingKey {
        case schemaVersion = "schema_version"
        case sourceID = "source_id"
        case deviceID = "device_id"
        case token
        case tokenType = "token_type"
        case scopes
        case spkiSHA256 = "spki_sha256"
        case pairedAt = "paired_at"
    }

    public init(sourceID: String, deviceID: String, token: String, scopes: [Scope], spkiSHA256: String, pairedAt: Date) {
        schemaVersion = 1
        self.sourceID = sourceID
        self.deviceID = deviceID
        self.token = token
        tokenType = "bearer"
        self.scopes = scopes
        self.spkiSHA256 = spkiSHA256
        self.pairedAt = pairedAt
    }
}

public enum PreparationState: String, Codable, Hashable, Sendable {
    case notPrepared = "not_prepared"
    case ready
    case sourceUnavailable = "source_unavailable"
}

public enum ItemKind: String, Codable, Hashable, Sendable {
    case single
    case group
}

public struct CatalogItem: Codable, Hashable, Sendable {
    public var itemID: String
    public var kind: ItemKind
    public var title: String
    public var assetCount: Int
    public var totalBytes: Int64
    public var modifiedAt: Date
    public var currentVersionID: String?
    public var preparationState: PreparationState

    enum CodingKeys: String, CodingKey {
        case itemID = "item_id"
        case kind
        case title
        case assetCount = "asset_count"
        case totalBytes = "total_bytes"
        case modifiedAt = "modified_at"
        case currentVersionID = "current_version_id"
        case preparationState = "preparation_state"
    }

    public init(
        itemID: String, kind: ItemKind, title: String, assetCount: Int, totalBytes: Int64, modifiedAt: Date,
        currentVersionID: String?, preparationState: PreparationState
    ) {
        self.itemID = itemID
        self.kind = kind
        self.title = title
        self.assetCount = assetCount
        self.totalBytes = totalBytes
        self.modifiedAt = modifiedAt
        self.currentVersionID = currentVersionID
        self.preparationState = preparationState
    }

    public func encode(to encoder: any Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(itemID, forKey: .itemID)
        try container.encode(kind, forKey: .kind)
        try container.encode(title, forKey: .title)
        try container.encode(assetCount, forKey: .assetCount)
        try container.encode(totalBytes, forKey: .totalBytes)
        try container.encode(modifiedAt, forKey: .modifiedAt)
        try container.encode(currentVersionID, forKey: .currentVersionID)  // explicit null
        try container.encode(preparationState, forKey: .preparationState)
    }
}

public struct CatalogPage: Codable, Hashable, Sendable {
    public var schemaVersion: Int
    public var items: [CatalogItem]
    public var nextCursor: String?

    enum CodingKeys: String, CodingKey {
        case schemaVersion = "schema_version"
        case items
        case nextCursor = "next_cursor"
    }

    public init(items: [CatalogItem], nextCursor: String?) {
        schemaVersion = 1
        self.items = items
        self.nextCursor = nextCursor
    }

    public func encode(to encoder: any Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(schemaVersion, forKey: .schemaVersion)
        try container.encode(items, forKey: .items)
        try container.encode(nextCursor, forKey: .nextCursor)
    }
}

/// Delivery states shown by the companion (plan 15.1, 16.2). The three acknowledgements
/// "Queued on Mac", "Downloaded to phone" and "Imported into Sylvia" are distinct; "observed"
/// only means the phone has listed the entry.
public enum DeliveryState: String, Codable, Hashable, Sendable {
    case queuedOnMac = "queued_on_mac"
    case observedByPhone = "observed_by_phone"
    case downloadedToPhone = "downloaded_to_phone"
    case importedIntoSylvia = "imported_into_sylvia"
    case importFailed = "import_failed"
}

public struct InboxEntry: Codable, Hashable, Sendable {
    public var queueEntryID: String
    public var itemID: String
    public var itemVersionID: String?
    public var title: String
    public var totalBytes: Int64
    public var queuedAt: Date
    public var state: DeliveryState

    enum CodingKeys: String, CodingKey {
        case queueEntryID = "queue_entry_id"
        case itemID = "item_id"
        case itemVersionID = "item_version_id"
        case title
        case totalBytes = "total_bytes"
        case queuedAt = "queued_at"
        case state
    }

    public init(
        queueEntryID: String, itemID: String, itemVersionID: String?, title: String, totalBytes: Int64,
        queuedAt: Date, state: DeliveryState
    ) {
        self.queueEntryID = queueEntryID
        self.itemID = itemID
        self.itemVersionID = itemVersionID
        self.title = title
        self.totalBytes = totalBytes
        self.queuedAt = queuedAt
        self.state = state
    }

    public func encode(to encoder: any Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(queueEntryID, forKey: .queueEntryID)
        try container.encode(itemID, forKey: .itemID)
        try container.encode(itemVersionID, forKey: .itemVersionID)
        try container.encode(title, forKey: .title)
        try container.encode(totalBytes, forKey: .totalBytes)
        try container.encode(queuedAt, forKey: .queuedAt)
        try container.encode(state, forKey: .state)
    }
}

public struct DeviceInboxPage: Codable, Hashable, Sendable {
    public var schemaVersion: Int
    public var entries: [InboxEntry]
    public var nextCursor: String?

    enum CodingKeys: String, CodingKey {
        case schemaVersion = "schema_version"
        case entries
        case nextCursor = "next_cursor"
    }

    public init(entries: [InboxEntry], nextCursor: String?) {
        schemaVersion = 1
        self.entries = entries
        self.nextCursor = nextCursor
    }

    public func encode(to encoder: any Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(schemaVersion, forKey: .schemaVersion)
        try container.encode(entries, forKey: .entries)
        try container.encode(nextCursor, forKey: .nextCursor)
    }
}

/// POST /v1/receipts. `receipt_id` is the idempotency key: a retried receipt with the same ID and
/// body is acknowledged again without changing state; the same ID with a different body is a conflict.
public struct Receipt: Codable, Hashable, Sendable {
    public enum State: String, Codable, Hashable, Sendable {
        case downloadedToPhone = "downloaded_to_phone"
        case importedIntoSylvia = "imported_into_sylvia"
        case importFailed = "import_failed"
    }

    public struct Failure: Codable, Hashable, Sendable {
        public var code: String
        public var message: String
        public init(code: String, message: String) {
            self.code = code
            self.message = message
        }
    }

    public var schemaVersion: Int
    public var receiptID: String
    public var queueEntryID: String?
    public var itemID: String
    public var itemVersionID: String
    public var state: State
    public var occurredAt: Date
    public var failure: Failure?

    enum CodingKeys: String, CodingKey {
        case schemaVersion = "schema_version"
        case receiptID = "receipt_id"
        case queueEntryID = "queue_entry_id"
        case itemID = "item_id"
        case itemVersionID = "item_version_id"
        case state
        case occurredAt = "occurred_at"
        case failure
    }

    public init(
        receiptID: String, queueEntryID: String?, itemID: String, itemVersionID: String, state: State,
        occurredAt: Date, failure: Failure? = nil
    ) {
        schemaVersion = 1
        self.receiptID = receiptID
        self.queueEntryID = queueEntryID
        self.itemID = itemID
        self.itemVersionID = itemVersionID
        self.state = state
        self.occurredAt = occurredAt
        self.failure = failure
    }

    public func encode(to encoder: any Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(schemaVersion, forKey: .schemaVersion)
        try container.encode(receiptID, forKey: .receiptID)
        try container.encode(queueEntryID, forKey: .queueEntryID)  // explicit null
        try container.encode(itemID, forKey: .itemID)
        try container.encode(itemVersionID, forKey: .itemVersionID)
        try container.encode(state, forKey: .state)
        try container.encode(occurredAt, forKey: .occurredAt)
        try container.encodeIfPresent(failure, forKey: .failure)
    }
}

public struct ReceiptAck: Codable, Hashable, Sendable {
    public var schemaVersion: Int
    public var receiptID: String
    public var queueEntryID: String?
    public var entryState: DeliveryState?
    public var duplicate: Bool

    enum CodingKeys: String, CodingKey {
        case schemaVersion = "schema_version"
        case receiptID = "receipt_id"
        case queueEntryID = "queue_entry_id"
        case entryState = "entry_state"
        case duplicate
    }

    public init(receiptID: String, queueEntryID: String?, entryState: DeliveryState?, duplicate: Bool) {
        schemaVersion = 1
        self.receiptID = receiptID
        self.queueEntryID = queueEntryID
        self.entryState = entryState
        self.duplicate = duplicate
    }

    public func encode(to encoder: any Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(schemaVersion, forKey: .schemaVersion)
        try container.encode(receiptID, forKey: .receiptID)
        try container.encode(queueEntryID, forKey: .queueEntryID)
        try container.encode(entryState, forKey: .entryState)
        try container.encode(duplicate, forKey: .duplicate)
    }
}

/// Every non-2xx response body. Messages never contain secrets, file paths or titles (plan 18.1).
public struct ErrorBody: Codable, Hashable, Sendable {
    public struct Detail: Codable, Hashable, Sendable {
        public var code: String
        public var message: String
        public var retryable: Bool
        public var retryAfterSeconds: Int?
        enum CodingKeys: String, CodingKey {
            case code
            case message
            case retryable
            case retryAfterSeconds = "retry_after_seconds"
        }
    }

    public var schemaVersion: Int
    public var error: Detail

    enum CodingKeys: String, CodingKey {
        case schemaVersion = "schema_version"
        case error
    }

    public init(code: String, message: String, retryable: Bool, retryAfterSeconds: Int? = nil) {
        schemaVersion = 1
        error = Detail(code: code, message: message, retryable: retryable, retryAfterSeconds: retryAfterSeconds)
    }
}
