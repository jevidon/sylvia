import Foundation

/// The outer container of a `.sylviabackup`.
///
/// Stage 0 implements only the directory bundle. The single-file container will use the archive
/// implementation the G0.3 workstream chooses in ADR-0010; it plugs in here and must present the
/// same directory tree to `BackupValidator` (unpacking with the same path rules, into a work
/// directory, never over the library).
public protocol BackupContainer: Sendable {
    /// Turns a finished, verified staging directory into the final container at `destination`,
    /// atomically: either the complete container exists at `destination` or nothing does.
    func finalize(stagingDirectory: URL, destination: URL) throws
    /// Presents `container` as a directory tree for validation. May unpack into `workDirectory`.
    func open(_ container: URL, workDirectory: URL) throws -> URL
}

/// A `.sylviabackup` directory bundle (macOS treats it as a package; Files shows a folder).
public struct DirectoryBundleContainer: BackupContainer {
    public init() {}

    public func finalize(stagingDirectory: URL, destination: URL) throws {
        if FileManager.default.fileExists(atPath: destination.path) {
            throw BackupError.destinationExists(destination.lastPathComponent)
        }
        // The staging directory is created beside the destination, so this is a same-volume rename.
        try DurableFile.rename(stagingDirectory, to: destination)
        try DurableFile.syncDirectory(destination.deletingLastPathComponent())
    }

    public func open(_ container: URL, workDirectory: URL) throws -> URL {
        let values = try? container.resourceValues(forKeys: [.isDirectoryKey, .isSymbolicLinkKey])
        guard values?.isSymbolicLink != true else { throw BackupError.symlinkInBundle(".") }
        guard values?.isDirectory == true else { throw BackupError.notABundle("not a directory") }
        return container
    }
}

/// A file-level validated bundle.
public struct ValidatedBundle: Sendable {
    public let root: URL
    public let manifest: BackupManifest
    public let manifestSHA256: String
}

/// Validates a bundle's manifest and files without opening the database (plan 17.4, T46).
public enum BackupValidator {
    public static func validate(_ root: URL) throws -> ValidatedBundle {
        let fm = FileManager.default
        let manifestURL = root.appending(path: BackupManifest.fileName, directoryHint: .notDirectory)
        try requireRegularFile(manifestURL, display: BackupManifest.fileName, missing: .manifestMissing)
        let manifestSize = fm.sizeOfFile(at: manifestURL)
        guard manifestSize <= BackupManifest.maximumBytes else { throw BackupError.manifestTooLarge(manifestSize) }
        let data = try Data(contentsOf: manifestURL)
        let manifest = try validateManifest(data)

        // Every listed file: a regular file reached without any symbolic link, with the recorded
        // size and digest.
        for entry in manifest.files {
            let url = try resolve(entry.path, in: root)
            try requireRegularFile(url, display: entry.path, missing: .missingFile(entry.path))
            let (digest, size) = try Digest.sha256Hex(fileAt: url)
            guard size == entry.byte_count else {
                throw BackupError.sizeMismatch(path: entry.path, expected: entry.byte_count, actual: size)
            }
            guard digest == entry.sha256 else { throw BackupError.digestMismatch(path: entry.path) }
        }

        // Nothing in the bundle that the manifest does not describe, and no links anywhere.
        try checkTree(root, listed: Set(manifest.files.map(\.path)))
        return ValidatedBundle(root: root, manifest: manifest, manifestSHA256: Digest.sha256Hex(data))
    }

    /// Everything about a manifest that can be checked without the bundle's files: the version
    /// gate, every rule of the `backup-manifest.v1` contract, and this build's own limits (known
    /// migrations and tables). `ManifestContractTests` runs it on the contract's fixtures.
    public static func validateManifest(_ data: Data) throws -> BackupManifest {
        // Version gate first, from a minimal decode, so a newer manifest is reported as such even if
        // its other fields changed shape.
        struct Header: Decodable { var schema_version: Int?; var format: String? }
        let header: Header
        do { header = try JSONDecoder().decode(Header.self, from: data) } catch {
            throw BackupError.manifestUnreadable("not a JSON object")
        }
        guard header.format == BackupManifest.formatName else { throw BackupError.unsupportedFormat(header.format ?? "none") }
        guard let version = header.schema_version else { throw BackupError.invalidField("schema_version") }
        guard version == BackupManifest.currentSchemaVersion else { throw BackupError.unsupportedManifestVersion(version) }

        let manifest: BackupManifest
        do { manifest = try JSONDecoder().decode(BackupManifest.self, from: data) } catch {
            throw BackupError.manifestUnreadable(String(describing: error).prefix(200).description)
        }
        try validateFields(manifest)

        // Every listed path: safe, unique ignoring case, and the exact location its role allows.
        var seen = Set<String>()
        for entry in manifest.files {
            guard BundlePath.isSafeRelativePath(entry.path) else { throw BackupError.unsafePath(entry.path) }
            guard seen.insert(entry.path.lowercased()).inserted else { throw BackupError.duplicatePath(entry.path) }
            guard BundlePath.matchesRole(entry.path, entry.role) else {
                throw BackupError.roleMismatch(path: entry.path, role: entry.role.rawValue)
            }
        }
        let databases = manifest.files.filter { $0.role == .database_snapshot }.count
        guard databases == 1 else { throw BackupError.databaseCount(databases) }
        return manifest
    }

    static func validateFields(_ m: BackupManifest) throws {
        guard EntityID.isValid(m.backup_id) else { throw BackupError.invalidField("backup_id") }
        guard EntityID.isValid(m.originating_device_id) else { throw BackupError.invalidField("originating_device_id") }
        guard RFC3339.isValid(m.created_at) else { throw BackupError.invalidField("created_at") }
        // Contract: migrations are 1+ unique identifiers matching ^[a-z0-9][a-z0-9-]{0,127}$.
        guard !m.library.migrations.isEmpty, Set(m.library.migrations).count == m.library.migrations.count,
              m.library.migrations.allSatisfy(isMigrationIdentifier) else {
            throw BackupError.invalidField("library.migrations")
        }
        let unknown = m.library.migrations.filter { !LibrarySchema.knownIdentifiers.contains($0) }
        if m.library.schema_version > LibrarySchema.currentVersion || !unknown.isEmpty {
            throw BackupError.newerLibrarySchema(found: m.library.schema_version, supported: LibrarySchema.currentVersion,
                                                 unknownMigrations: unknown)
        }
        guard m.library.schema_version >= 1,
              LibrarySchema.version(forApplied: Set(m.library.migrations)) == m.library.schema_version else {
            throw BackupError.invalidField("library.schema_version")
        }
        guard m.snapshot.change_journal_seq >= 0 else { throw BackupError.invalidField("snapshot.change_journal_seq") }
        guard m.snapshot.method == BackupManifest.snapshotMethod else { throw BackupError.invalidField("snapshot.method") }
        guard !m.counts.isEmpty else { throw BackupError.invalidField("counts") }
        // Contract: included_classes are 1+ unique storage classes; excluded_classes are unique
        // objects with a storage class and a 1-500 character reason.
        guard !m.included_classes.isEmpty, Set(m.included_classes).count == m.included_classes.count,
              m.included_classes.allSatisfy(BackupManifest.storageClasses.contains) else {
            throw BackupError.invalidField("included_classes")
        }
        for exclusion in m.excluded_classes where !BackupManifest.storageClasses.contains(exclusion.class)
            || !(1...500).contains(exclusion.reason.count) {
            throw BackupError.invalidField("excluded_classes")
        }
        guard Set(m.excluded_classes.map { [$0.class, $0.reason] }).count == m.excluded_classes.count else {
            throw BackupError.invalidField("excluded_classes")
        }
        guard (1...100_000).contains(m.files.count) else { throw BackupError.invalidField("files") }
        for entry in m.files {
            guard Digest.isHex64(entry.sha256) else { throw BackupError.invalidField("files.sha256") }
            guard entry.byte_count >= 0 else { throw BackupError.invalidField("files.byte_count") }
        }
        for (table, count) in m.counts {
            guard LibrarySchema.tables.contains(where: { $0.name == table }), count >= 0 else {
                throw BackupError.invalidField("counts.\(table)")
            }
        }
        for asset in m.excluded_media where !(EntityID.isValid(asset.asset_id) && Digest.isHex64(asset.sha256)
                                                && asset.byte_count >= 0 && (1...255).contains(asset.media_type.count)) {
            throw BackupError.invalidField("excluded_media")
        }
        // Contract: complete is true exactly when no original was left out.
        guard m.complete == m.excluded_media.isEmpty else { throw BackupError.invalidField("complete") }
        guard m.encryption == "none" else { throw BackupError.invalidField("encryption") }
    }

    static func isMigrationIdentifier(_ value: String) -> Bool {
        let bytes = Array(value.utf8)
        guard (1...128).contains(bytes.count) else { return false }
        func lowerAlnum(_ b: UInt8) -> Bool { (48...57).contains(b) || (97...122).contains(b) }
        return lowerAlnum(bytes[0]) && bytes.dropFirst().allSatisfy { lowerAlnum($0) || $0 == UInt8(ascii: "-") }
    }

    /// Joins a validated relative path to `root` and checks no component is a symbolic link and the
    /// result stays inside `root` after resolution. The path need not exist: a listed file that is
    /// missing is reported by `requireRegularFile` as missing, not here as unsafe.
    static func resolve(_ path: String, in root: URL) throws -> URL {
        // The manifest stage has already refused any other path; refused here too, so that the
        // containment check below never meets a `..`, `.` or empty component.
        guard BundlePath.isSafeRelativePath(path) else { throw BackupError.unsafePath(path) }
        var url = root
        for component in path.split(separator: "/") {
            url = url.appending(path: String(component), directoryHint: .notDirectory)
            if let values = try? url.resourceValues(forKeys: [.isSymbolicLinkKey]), values.isSymbolicLink == true {
                throw BackupError.symlinkInBundle(path)
            }
        }
        guard isInside(url, root) else { throw BackupError.unsafePath(path) }
        return url
    }

    /// Whether `url` lies inside `root` once every symbolic link in either path is resolved, whether
    /// or not `url` exists. Both paths are resolved by realpath(3) (`CanonicalPath`), never by
    /// Foundation's `resolvingSymlinksInPath`, which also drops a leading `/private`, but only from a
    /// path that exists: under /private/var (an iPhone's temporary and container folders) an existing
    /// root and a missing file inside it then had different prefixes, and the missing file was
    /// reported as an unsafe path (device run of 26 October 2026, `PrivatePathTests`).
    static func isInside(_ url: URL, _ root: URL) -> Bool {
        guard let resolvedRoot = CanonicalPath.of(root), let resolved = CanonicalPath.of(url) else { return false }
        return CanonicalPath.relative(resolved, to: resolvedRoot) != nil
    }

    static func requireRegularFile(_ url: URL, display: String, missing: BackupError) throws {
        var info = stat()
        guard lstat(url.path, &info) == 0 else { throw missing }
        if (info.st_mode & S_IFMT) == S_IFLNK { throw BackupError.symlinkInBundle(display) }
        guard (info.st_mode & S_IFMT) == S_IFREG else { throw BackupError.notARegularFile(display) }
    }

    static func checkTree(_ root: URL, listed: Set<String>) throws {
        // An enumeration error (for example an unreadable directory) would otherwise end the walk
        // early and silently, letting unlisted files through. Record it, keep walking, and fail
        // after the walk.
        let unreadable = EnumerationErrors()
        guard let enumerator = FileManager.default.enumerator(
            at: root, includingPropertiesForKeys: [.isSymbolicLinkKey, .isRegularFileKey, .isDirectoryKey], options: [],
            errorHandler: { url, _ in unreadable.append(url); return true }) else {
            throw BackupError.notABundle("cannot enumerate")
        }
        // Each item's path below the root: its folder resolved by realpath(3) (`CanonicalPath`; the folder exists, it
        // is being walked) joined to the item's own name, which is never resolved, so that a link, dangling or not, is
        // reported as a link below. Comparing Foundation's `standardizedFileURL` paths failed under /private/var: the
        // enumerator names items /private/var/... whichever way the root is named, and /private is dropped only from
        // a path that exists, so a dangling link kept it and the bundle was refused as an unsafe path, with the link's
        // absolute path (review of 26 October 2026, finding F3).
        guard let rootPath = CanonicalPath.of(root) else { throw BackupError.notABundle("cannot resolve its folder") }
        func relativePath(_ url: URL) -> String? {
            guard let folder = CanonicalPath.of(url.deletingLastPathComponent()) else { return nil }
            return CanonicalPath.relative((folder.hasSuffix("/") ? folder : folder + "/") + url.lastPathComponent, to: rootPath)
        }
        for case let url as URL in enumerator {
            guard let relative = relativePath(url) else { throw BackupError.unsafePath(url.lastPathComponent) }
            let values = try url.resourceValues(forKeys: [.isSymbolicLinkKey, .isRegularFileKey, .isDirectoryKey])
            if values.isSymbolicLink == true { throw BackupError.symlinkInBundle(relative) }
            if values.isDirectory == true { continue }
            if relative == BackupManifest.fileName || url.lastPathComponent == ".DS_Store" { continue }
            guard values.isRegularFile == true else { throw BackupError.notARegularFile(relative) }
            guard listed.contains(relative) else { throw BackupError.unlistedFile(relative) }
        }
        if let first = unreadable.urls.first {
            throw BackupError.notABundle("cannot read \(relativePath(first) ?? first.lastPathComponent)")
        }
    }
}

/// Collects enumeration errors from `FileManager`'s error handler.
final class EnumerationErrors: @unchecked Sendable {
    private let lock = NSLock()
    private var stored: [URL] = []
    func append(_ url: URL) { lock.withLock { stored.append(url) } }
    var urls: [URL] { lock.withLock { stored } }
}
