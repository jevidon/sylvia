import CryptoKit
import Darwin
import Foundation
import SylviaTransferCore

/// The Mac's source index and immutable prepared snapshots (plan 15.4, 16.2).
///
/// - Items come from user-selected roots: each top-level regular file is a single item; each top-level
///   folder is a group item whose regular files (recursively, sorted by relative path) are its ordered
///   members. Hidden files and symbolic links are skipped; nothing outside a root is ever opened.
/// - IDs are opaque UUIDs recorded in the index. A client never supplies a path: it sends an ID, the
///   index maps it to a path that came from enumeration.
/// - Preparing an item clones each member into the state directory (APFS `clonefile`, falling back to a
///   full copy on volumes without clones) and hashes the clone, never the original. The clone is
///   immutable for the life of the version, so a changing original can never mix bytes of two versions.
/// - Every manifest and content request re-checks the original's file stamp (size, mtime, ctime, inode,
///   device). A change invalidates the version: old ETags then fail If-Match with 412, and the next
///   manifest request prepares a new version with a new ID.
public actor SourceLibrary {
    struct FileStamp: Codable, Equatable, Sendable {
        var size: Int64
        var mtimeNanoseconds: Int64
        var ctimeNanoseconds: Int64
        var inode: UInt64
        var device: Int64

        enum CodingKeys: String, CodingKey {
            case size
            case mtimeNanoseconds = "mtime_ns"
            case ctimeNanoseconds = "ctime_ns"
            case inode
            case device
        }
    }

    struct MemberRecord: Codable, Sendable {
        var assetID: String
        var relativePath: String
        enum CodingKeys: String, CodingKey {
            case assetID = "asset_id"
            case relativePath = "relative_path"
        }
    }

    struct ItemRecord: Codable, Sendable {
        var itemID: String
        var kind: ItemKind
        var title: String
        var rootIndex: Int
        var relativePath: String
        var members: [MemberRecord]
        enum CodingKeys: String, CodingKey {
            case itemID = "item_id"
            case kind
            case title
            case rootIndex = "root_index"
            case relativePath = "relative_path"
            case members
        }
    }

    struct AssetVersion: Codable, Sendable {
        var assetID: String
        var displayName: String
        var mediaType: String
        var length: Int64
        var sha256: String
        var stamp: FileStamp
        var cloned: Bool
        /// Part digests keyed by part size in bytes (as text).
        var partDigests: [String: [String]]
        enum CodingKeys: String, CodingKey {
            case assetID = "asset_id"
            case displayName = "display_name"
            case mediaType = "media_type"
            case length
            case sha256
            case stamp
            case cloned
            case partDigests = "part_digests"
        }
        var etag: String { ETag.forContentDigest(sha256) }
    }

    struct ItemVersion: Codable, Sendable {
        var itemVersionID: String
        var itemID: String
        var createdAt: Date
        var assets: [AssetVersion]
        enum CodingKeys: String, CodingKey {
            case itemVersionID = "item_version_id"
            case itemID = "item_id"
            case createdAt = "created_at"
            case assets
        }
    }

    struct IndexFile: Codable {
        var items: [ItemRecord]
        var versions: [ItemVersion]
    }

    /// What the content endpoint needs to serve one asset version: the snapshot is already open, so a
    /// later invalidation cannot remove it between the version check and the read.
    public struct ServeInfo: Sendable {
        let descriptor: SnapshotDescriptor
        public let length: Int64

        /// Reads bytes from the open snapshot (tests).
        @_spi(Testing) public func read(offset: Int64, count: Int) -> [UInt8] {
            var bytes = [UInt8](repeating: 0, count: count)
            let read = bytes.withUnsafeMutableBytes { pread(descriptor.fd, $0.baseAddress, count, off_t(offset)) }
            return Array(bytes.prefix(max(0, read)))
        }
        public let etag: String
        public let mediaType: String
        public let assetID: String
    }

    public enum ServeLookup: Sendable {
        case unknown
        /// The asset exists but has no valid prepared version (never prepared, changed, or removed).
        case noCurrentVersion
        case current(ServeInfo)
    }

    public enum LibraryError: Error, Equatable, Sendable {
        case unknownItem
        case sourceUnavailable
        case sourceKeepsChanging
        case emptyFile
        case tooLarge
        case io(String)
    }

    public let roots: [URL]
    let stateDirectory: URL
    let defaultPartSize: Int64
    private let now: @Sendable () -> Date
    private var items: [String: ItemRecord] = [:]
    private var versions: [String: ItemVersion] = [:]  // current version by item ID
    private var preparing: [String: Task<ItemVersion, any Error>] = [:]
    private var lastScan: Date?
    /// Test hook: called after each member is cloned and before it is hashed.
    var afterSnapshotHook: (@Sendable (String) async -> Void)?

    var indexURL: URL { stateDirectory.appendingPathComponent("index.json") }
    var snapshotsDirectory: URL { stateDirectory.appendingPathComponent("snapshots", isDirectory: true) }

    public init(roots: [URL], stateDirectory: URL, defaultPartSize: Int64, now: @escaping @Sendable () -> Date) throws {
        // realpath, not resolvingSymlinksInPath (which strips "/private" and so would not compare equal
        // with the realpath of a file inside the root).
        self.roots = roots.map { root in
            guard let resolved = realpath(root.path, nil) else { return root.standardizedFileURL }
            defer { free(resolved) }
            return URL(fileURLWithPath: String(cString: resolved), isDirectory: true)
        }
        self.stateDirectory = stateDirectory
        self.defaultPartSize = defaultPartSize
        self.now = now
        try FileManager.default.createDirectory(at: stateDirectory.appendingPathComponent("snapshots"), withIntermediateDirectories: true)
        if let index = try DurableFile.read(IndexFile.self, from: stateDirectory.appendingPathComponent("index.json")) {
            items = Dictionary(uniqueKeysWithValues: index.items.map { ($0.itemID, $0) })
            versions = Dictionary(uniqueKeysWithValues: index.versions.map { ($0.itemID, $0) })
        }
    }

    // MARK: Index

    /// Enumerates the roots. Keeps the IDs of paths already known; never hashes.
    public func scan() throws {
        var known: [String: ItemRecord] = [:]
        for record in items.values { known["\(record.rootIndex)/\(record.relativePath)"] = record }
        var scanned: [String: ItemRecord] = [:]
        let fileManager = FileManager.default
        for (rootIndex, root) in roots.enumerated() {
            let entries = (try? fileManager.contentsOfDirectory(
                at: root, includingPropertiesForKeys: [.isRegularFileKey, .isDirectoryKey, .isSymbolicLinkKey],
                options: [.skipsHiddenFiles])) ?? []
            for entry in entries.sorted(by: { $0.lastPathComponent < $1.lastPathComponent }) {
                let values = try? entry.resourceValues(forKeys: [.isRegularFileKey, .isDirectoryKey, .isSymbolicLinkKey])
                if values?.isSymbolicLink == true { continue }
                let name = entry.lastPathComponent
                let key = "\(rootIndex)/\(name)"
                if values?.isRegularFile == true {
                    var record = known[key] ?? ItemRecord(
                        itemID: CanonicalID.make(), kind: .single, title: Self.title(fromFileName: name),
                        rootIndex: rootIndex, relativePath: name, members: [])
                    let existing = record.members.first?.assetID
                    record.members = [MemberRecord(assetID: existing ?? CanonicalID.make(), relativePath: name)]
                    scanned[record.itemID] = record
                } else if values?.isDirectory == true {
                    let memberPaths = Self.regularFiles(under: entry).map { "\(name)/\($0)" }
                    guard !memberPaths.isEmpty else { continue }
                    var record = known[key] ?? ItemRecord(
                        itemID: CanonicalID.make(), kind: .group, title: Self.sanitizedLabel(name, limit: 512),
                        rootIndex: rootIndex, relativePath: name, members: [])
                    let previous = Dictionary(uniqueKeysWithValues: record.members.map { ($0.relativePath, $0.assetID) })
                    record.members = memberPaths.prefix(TransferProtocol.maximumAssetsPerItem).map {
                        MemberRecord(assetID: previous[$0] ?? CanonicalID.make(), relativePath: $0)
                    }
                    scanned[record.itemID] = record
                }
            }
        }
        items = scanned
        versions = versions.filter { scanned[$0.key] != nil }
        lastScan = now()
        try persist()
    }

    func scanIfStale(maximumAge: TimeInterval = 2) throws {
        if let lastScan, now().timeIntervalSince(lastScan) < maximumAge { return }
        try scan()
    }

    public func catalog(after cursor: String?, limit: Int) throws -> (items: [CatalogItem], next: String?) {
        try scanIfStale()
        let sorted = items.keys.sorted()
        let start = cursor.map { after in sorted.firstIndex { $0 > after } ?? sorted.count } ?? 0
        let page = sorted[start...].prefix(limit)
        let entries = page.compactMap { id in items[id].map(catalogItem) }
        let next = (start + page.count < sorted.count) ? page.last : nil
        return (entries, next)
    }

    private func catalogItem(_ record: ItemRecord) -> CatalogItem {
        var total: Int64 = 0
        var modified = Date(timeIntervalSince1970: 0)
        var available = true
        for member in record.members {
            guard let stamp = try? Self.stamp(of: url(for: record, member: member)) else {
                available = false
                continue
            }
            total += stamp.size
            modified = max(modified, Date(timeIntervalSince1970: TimeInterval(stamp.mtimeNanoseconds) / 1e9))
        }
        let version = validVersion(for: record)
        return CatalogItem(
            itemID: record.itemID, kind: record.kind, title: record.title, assetCount: record.members.count,
            totalBytes: total, modifiedAt: Date(timeIntervalSince1970: modified.timeIntervalSince1970.rounded(.down)),
            currentVersionID: version?.itemVersionID,
            preparationState: !available ? .sourceUnavailable : (version == nil ? .notPrepared : .ready))
    }

    public func title(of itemID: String) -> String? { items[itemID]?.title }

    /// Title, size and current version of one item (for device-inbox entries).
    public func summary(itemID: String) -> (title: String, totalBytes: Int64, currentVersionID: String?)? {
        guard let record = items[itemID] else { return nil }
        let item = catalogItem(record)
        return (item.title, item.totalBytes, item.currentVersionID)
    }

    public func knows(itemID: String) -> Bool { items[itemID] != nil }

    // MARK: Versions

    /// Returns the current version if every member's original is unchanged and its snapshot exists;
    /// otherwise drops the version (its clones are deleted; open readers keep their file descriptors).
    private func validVersion(for record: ItemRecord) -> ItemVersion? {
        guard let version = versions[record.itemID] else { return nil }
        guard version.assets.count == record.members.count else {
            invalidate(record.itemID)
            return nil
        }
        for (member, asset) in zip(record.members, version.assets) {
            let current = try? Self.stamp(of: url(for: record, member: member))
            let snapshot = snapshotURL(version: version.itemVersionID, asset: asset.assetID)
            guard member.assetID == asset.assetID, current == asset.stamp,
                FileManager.default.fileExists(atPath: snapshot.path)
            else {
                invalidate(record.itemID)
                return nil
            }
        }
        return version
    }

    private func invalidate(_ itemID: String) {
        guard let old = versions.removeValue(forKey: itemID) else { return }
        try? FileManager.default.removeItem(at: snapshotsDirectory.appendingPathComponent(old.itemVersionID))
        try? persist()
    }

    /// Prepares (or reuses) the current immutable version of an item.
    public func prepare(itemID: String) async throws(LibraryError) -> String {
        try await currentVersion(itemID: itemID).itemVersionID
    }

    func currentVersion(itemID: String) async throws(LibraryError) -> ItemVersion {
        if items[itemID] == nil { try? scan() }
        guard let record = items[itemID] else { throw .unknownItem }
        if let version = validVersion(for: record) { return version }
        if let running = preparing[itemID] {
            do { return try await running.value } catch { throw Self.libraryError(error) }
        }
        let versionID = CanonicalID.make()
        let directory = snapshotsDirectory.appendingPathComponent(versionID, isDirectory: true)
        let members = record.members.map { (assetID: $0.assetID, name: $0.relativePath) }
        let root = roots[record.rootIndex]
        let partSize = defaultPartSize
        let created = now()
        let hook = afterSnapshotHook
        let task = Task.detached(priority: .utility) { () throws -> ItemVersion in
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            var assets: [AssetVersion] = []
            for member in members {
                let destination = directory.appendingPathComponent(member.assetID)
                let (stamp, cloned) = try Self.snapshot(root: root, relativePath: member.name, destination: destination)
                if let hook { await hook(member.assetID) }
                let (sha, parts) = try Self.hash(file: destination, partSize: partSize)
                assets.append(AssetVersion(
                    assetID: member.assetID, displayName: Self.displayName(member.name), mediaType: Self.mediaType(member.name),
                    length: stamp.size, sha256: sha, stamp: stamp, cloned: cloned, partDigests: [String(partSize): parts]))
            }
            return ItemVersion(itemVersionID: versionID, itemID: itemID, createdAt: created, assets: assets)
        }
        preparing[itemID] = task
        defer { preparing.removeValue(forKey: itemID) }
        let version: ItemVersion
        do {
            version = try await task.value
        } catch {
            try? FileManager.default.removeItem(at: directory)
            throw Self.libraryError(error)
        }
        if let old = versions[itemID], old.itemVersionID != version.itemVersionID {
            try? FileManager.default.removeItem(at: snapshotsDirectory.appendingPathComponent(old.itemVersionID))
        }
        versions[itemID] = version
        do { try persist() } catch { throw .io("index") }
        return version
    }

    /// Builds the manifest of the current version, computing part digests for `partSize` if needed.
    public func manifest(itemID: String, sourceID: String, partSize: Int64?) async throws(LibraryError) -> TransferManifest {
        var version = try await currentVersion(itemID: itemID)
        guard let record = items[itemID] else { throw .unknownItem }
        let size = partSize ?? defaultPartSize
        for index in version.assets.indices where version.assets[index].partDigests[String(size)] == nil {
            let snapshot = snapshotURL(version: version.itemVersionID, asset: version.assets[index].assetID)
            let digests: [String]
            do {
                digests = try await Task.detached(priority: .utility) { try Self.hash(file: snapshot, partSize: size).parts }.value
            } catch {
                throw .io("hash")
            }
            version.assets[index].partDigests[String(size)] = digests
        }
        if versions[itemID]?.itemVersionID == version.itemVersionID {
            versions[itemID] = version
            try? persist()
        }
        var assets: [TransferManifest.Asset] = []
        for (ordinal, asset) in version.assets.enumerated() {
            guard let digests = asset.partDigests[String(size)] else { throw .io("digests") }
            let slices = PartPlan.slices(length: asset.length, partSize: size)
            guard slices.count == digests.count, slices.count <= TransferProtocol.maximumPartsPerAsset else { throw .tooLarge }
            assets.append(TransferManifest.Asset(
                assetID: asset.assetID, ordinal: ordinal, displayName: asset.displayName, mediaType: asset.mediaType,
                length: asset.length, etag: asset.etag, sha256: asset.sha256, partSize: size,
                parts: zip(slices, digests).map { .init(index: $0.index, offset: $0.offset, length: $0.length, sha256: $1) }))
        }
        guard assets.allSatisfy({ $0.length > 0 }) else { throw .emptyFile }
        return TransferManifest(
            sourceID: sourceID, itemID: itemID, itemVersionID: version.itemVersionID, createdAt: version.createdAt,
            grouping: .init(kind: record.kind, title: record.title), coverAssetID: nil, assets: assets)
    }

    /// Looks up the version to serve for an asset, re-checking the original first, and opens its snapshot
    /// while still inside the actor (invalidation also runs inside the actor, so the two cannot interleave).
    public func serveInfo(assetID: String) -> ServeLookup {
        guard let record = items.values.first(where: { $0.members.contains { $0.assetID == assetID } }) else { return .unknown }
        guard let version = validVersion(for: record),
            let asset = version.assets.first(where: { $0.assetID == assetID })
        else { return .noCurrentVersion }
        let path = snapshotURL(version: version.itemVersionID, asset: assetID).path
        let fd = open(path, O_RDONLY | O_NOFOLLOW | O_CLOEXEC)
        guard fd >= 0 else {
            invalidate(record.itemID)
            return .noCurrentVersion
        }
        let descriptor = SnapshotDescriptor(fd: fd)
        // The snapshot is never written after it was hashed; a different size means it was damaged.
        var info = stat()
        guard fstat(fd, &info) == 0, (info.st_mode & S_IFMT) == S_IFREG, Int64(info.st_size) == asset.length else {
            invalidate(record.itemID)
            return .noCurrentVersion
        }
        return .current(ServeInfo(
            descriptor: descriptor, length: asset.length, etag: asset.etag, mediaType: asset.mediaType, assetID: assetID))
    }

    /// Whether the version's members were cloned (true) or copied (false), for evidence.
    public func snapshotsWereCloned(itemID: String) -> Bool? {
        versions[itemID].map { $0.assets.allSatisfy(\.cloned) }
    }

    public func setAfterSnapshotHook(_ hook: (@Sendable (String) async -> Void)?) { afterSnapshotHook = hook }

    // MARK: Helpers

    private func url(for record: ItemRecord, member: MemberRecord) -> URL {
        roots[record.rootIndex].appendingPathComponent(member.relativePath, isDirectory: false)
    }

    private func snapshotURL(version: String, asset: String) -> URL {
        snapshotsDirectory.appendingPathComponent(version).appendingPathComponent(asset)
    }

    private func persist() throws {
        try DurableFile.write(
            IndexFile(items: items.values.sorted { $0.itemID < $1.itemID }, versions: versions.values.sorted { $0.itemID < $1.itemID }),
            to: indexURL)
    }

    static func libraryError(_ error: any Error) -> LibraryError {
        if let error = error as? LibraryError { return error }
        return .io(String(describing: type(of: error)))
    }

    /// The original's identity at a moment. `lstat`, so a final symbolic link is never followed.
    static func stamp(of url: URL) throws(LibraryError) -> FileStamp {
        var info = stat()
        guard lstat(url.path, &info) == 0 else { throw .sourceUnavailable }
        return try stamp(info)
    }

    static func stamp(descriptor: Int32) throws(LibraryError) -> FileStamp {
        var info = stat()
        guard fstat(descriptor, &info) == 0 else { throw .sourceUnavailable }
        return try stamp(info)
    }

    private static func stamp(_ info: stat) throws(LibraryError) -> FileStamp {
        guard (info.st_mode & S_IFMT) == S_IFREG else { throw .sourceUnavailable }
        return FileStamp(
            size: Int64(info.st_size),
            mtimeNanoseconds: Int64(info.st_mtimespec.tv_sec) * 1_000_000_000 + Int64(info.st_mtimespec.tv_nsec),
            ctimeNanoseconds: Int64(info.st_ctimespec.tv_sec) * 1_000_000_000 + Int64(info.st_ctimespec.tv_nsec),
            inode: UInt64(info.st_ino), device: Int64(info.st_dev))
    }

    /// Opens `relativePath` below `root` one component at a time with O_NOFOLLOW, so no symbolic link
    /// anywhere on the path is followed and the file opened lies inside the root by construction, even if
    /// a folder is swapped for a link between the scan and this call. Returns a descriptor of a regular file.
    static func openContained(root: URL, relativePath: String) throws(LibraryError) -> Int32 {
        let components = relativePath.split(separator: "/", omittingEmptySubsequences: false).map(String.init)
        guard !components.isEmpty, components.allSatisfy({ !$0.isEmpty && $0 != "." && $0 != ".." }) else {
            throw .sourceUnavailable
        }
        var current = open(root.path, O_RDONLY | O_DIRECTORY | O_CLOEXEC)
        guard current >= 0 else { throw .sourceUnavailable }
        for (position, component) in components.enumerated() {
            let isLast = position == components.count - 1
            // O_NONBLOCK on the last component: opening a FIFO placed there must not block.
            let flags = isLast ? (O_RDONLY | O_NOFOLLOW | O_NONBLOCK | O_CLOEXEC) : (O_RDONLY | O_DIRECTORY | O_NOFOLLOW | O_CLOEXEC)
            let next = openat(current, component, flags)
            close(current)
            guard next >= 0 else { throw .sourceUnavailable }
            current = next
        }
        var info = stat()
        guard fstat(current, &info) == 0, (info.st_mode & S_IFMT) == S_IFREG else {
            close(current)
            throw .sourceUnavailable
        }
        return current
    }

    /// Clones the original at `root/relativePath` to `destination` (copying where the volume cannot
    /// clone) from an open descriptor, and returns the original's stamp, retrying while the original
    /// changes during the copy. The clone is what gets hashed and served; the original is never served.
    static func snapshot(root: URL, relativePath: String, destination: URL) throws -> (FileStamp, cloned: Bool) {
        for _ in 0..<3 {
            let source = try openContained(root: root, relativePath: relativePath)
            defer { close(source) }
            let before = try stamp(descriptor: source)
            guard before.size > 0 else { throw LibraryError.emptyFile }
            unlink(destination.path)
            var cloned = true
            if fclonefileat(source, AT_FDCWD, destination.path, UInt32(CLONE_NOOWNERCOPY)) != 0 {
                let code = errno
                guard code == ENOTSUP || code == EXDEV else { throw LibraryError.io("fclonefileat errno \(code)") }
                cloned = false
                let output = open(destination.path, O_WRONLY | O_CREAT | O_EXCL | O_NOFOLLOW | O_CLOEXEC, 0o600)
                guard output >= 0 else { throw LibraryError.io("open errno \(errno)") }
                defer { close(output) }
                guard fcopyfile(source, output, nil, copyfile_flags_t(COPYFILE_DATA)) == 0 else {
                    throw LibraryError.io("fcopyfile errno \(errno)")
                }
            }
            let after = try stamp(descriptor: source)
            if before == after {
                chmod(destination.path, 0o400)
                return (before, cloned)
            }
        }
        unlink(destination.path)
        throw LibraryError.sourceKeepsChanging
    }

    /// Streams a file once, returning its SHA-256 and the SHA-256 of each part. Memory: one 1 MiB buffer.
    static func hash(file: URL, partSize: Int64) throws -> (sha256: String, parts: [String]) {
        let handle = try FileHandle(forReadingFrom: file)
        defer { try? handle.close() }
        var whole = SHA256()
        var part = SHA256()
        var inPart: Int64 = 0
        var parts: [String] = []
        while true {
            let chunk: Data = try autoreleasepool { try handle.read(upToCount: 1_048_576) ?? Data() }
            if chunk.isEmpty { break }
            whole.update(data: chunk)
            var offset = 0
            while offset < chunk.count {
                let take = min(chunk.count - offset, Int(partSize - inPart))
                part.update(data: chunk[chunk.startIndex + offset..<chunk.startIndex + offset + take])
                inPart += Int64(take)
                offset += take
                if inPart == partSize {
                    parts.append(Hex.encode(part.finalize()))
                    part = SHA256()
                    inPart = 0
                }
            }
        }
        if inPart > 0 { parts.append(Hex.encode(part.finalize())) }
        return (Hex.encode(whole.finalize()), parts)
    }

    static func regularFiles(under directory: URL) -> [String] {
        guard let enumerator = FileManager.default.enumerator(
            at: directory, includingPropertiesForKeys: [.isRegularFileKey, .isSymbolicLinkKey],
            options: [.skipsHiddenFiles, .skipsPackageDescendants])
        else { return [] }
        let base = directory.standardizedFileURL.path
        var paths: [String] = []
        for case let url as URL in enumerator {
            let values = try? url.resourceValues(forKeys: [.isRegularFileKey, .isSymbolicLinkKey])
            guard values?.isSymbolicLink != true, values?.isRegularFile == true else { continue }
            let path = url.standardizedFileURL.path
            guard path.hasPrefix(base + "/") else { continue }
            paths.append(String(path.dropFirst(base.count + 1)))
        }
        return paths.sorted()
    }

    static func title(fromFileName name: String) -> String {
        let base = (name as NSString).deletingPathExtension
        return sanitizedLabel(base.isEmpty ? name : base, limit: TransferProtocol.maximumTitleLength)
    }

    static func displayName(_ relativePath: String) -> String {
        sanitizedLabel((relativePath as NSString).lastPathComponent, limit: TransferProtocol.maximumDisplayNameLength)
    }

    static func sanitizedLabel(_ text: String, limit: Int) -> String {
        var scalars = String.UnicodeScalarView()
        for scalar in text.unicodeScalars where scalar.properties.generalCategory != .control && scalar != "/" && scalar != "\\" {
            if scalars.count == limit { break }
            scalars.append(scalar)
        }
        let label = String(scalars)
        return label.isEmpty ? "Untitled" : label
    }

    static func mediaType(_ name: String) -> String {
        switch (name as NSString).pathExtension.lowercased() {
        case "epub": "application/epub+zip"
        case "pdf": "application/pdf"
        case "mp3": "audio/mpeg"
        case "m4a", "m4b", "mp4": "audio/mp4"
        case "aac": "audio/aac"
        case "txt": "text/plain"
        case "md", "markdown": "text/markdown"
        case "jpg", "jpeg": "image/jpeg"
        case "png": "image/png"
        case "zip", "sylviapack": "application/zip"
        default: "application/octet-stream"
        }
    }
}
