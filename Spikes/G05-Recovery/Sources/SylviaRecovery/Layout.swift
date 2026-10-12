import Foundation

/// On-disk layout of one Sylvia installation (plan 7.4, 17.1).
///
/// Everything lives under one private root (Application Support/Sylvia on device), never in
/// Finder-exposed Documents. The `Library` directory is the unit that a restore swaps; staging,
/// recovery copies and restore work directories sit beside it on the same volume so every swap is
/// a same-volume `rename`.
///
/// ```text
/// <root>/
///   installation.json          originating device ID (not part of the library; never restored)
///   Library/                   active library (swap unit)
///     library.sqlite (+ -wal, -shm)
///     migration-putback.json   written before a snapshot-guarded migration; reconciled on next open
///     Blobs/excerpts/<sha256>.<ext>   retained excerpt audio (permanent knowledge)
///     Blobs/covers/<sha256>.<ext>     canonical cover thumbnails (kept with the knowledge)
///     Media/<asset-id>/<file>          original media (user-managed, removable)
///   Staging/                   in-progress writes, renamed into place when complete
///   Recovery/                  pre-migration snapshots, failed-<id>/ files a put-back replaced,
///                              and pre-restore library copies
///   RestoreWork/<uuid>/Library  temporary library built and validated before a restore swap
///   restore-intent.json        written before the restore swap; reconciled on next launch
/// ```
public struct LibraryLayout: Sendable, Hashable {
    public let root: URL

    public init(root: URL) {
        self.root = root.standardizedFileURL
    }

    /// The production location: `Application Support/Sylvia`.
    public static func applicationSupport() throws -> LibraryLayout {
        let base = try FileManager.default.url(
            for: .applicationSupportDirectory, in: .userDomainMask, appropriateFor: nil, create: true)
        return LibraryLayout(root: base.appending(path: "Sylvia", directoryHint: .isDirectory))
    }

    public var libraryDirectory: URL { root.appending(path: "Library", directoryHint: .isDirectory) }
    public var databaseURL: URL { libraryDirectory.appending(path: "library.sqlite", directoryHint: .notDirectory) }
    public var walURL: URL { libraryDirectory.appending(path: "library.sqlite-wal", directoryHint: .notDirectory) }
    public var shmURL: URL { libraryDirectory.appending(path: "library.sqlite-shm", directoryHint: .notDirectory) }
    /// Inside `Library/`, so a restore swap moves it with the library it describes.
    public var migrationPutBackIntentURL: URL { libraryDirectory.appending(path: "migration-putback.json", directoryHint: .notDirectory) }
    public var blobsDirectory: URL { libraryDirectory.appending(path: "Blobs", directoryHint: .isDirectory) }
    public var excerptBlobsDirectory: URL { blobsDirectory.appending(path: "excerpts", directoryHint: .isDirectory) }
    public var coverBlobsDirectory: URL { blobsDirectory.appending(path: "covers", directoryHint: .isDirectory) }
    public var mediaDirectory: URL { libraryDirectory.appending(path: "Media", directoryHint: .isDirectory) }
    public var stagingDirectory: URL { root.appending(path: "Staging", directoryHint: .isDirectory) }
    public var recoveryDirectory: URL { root.appending(path: "Recovery", directoryHint: .isDirectory) }
    public var restoreWorkDirectory: URL { root.appending(path: "RestoreWork", directoryHint: .isDirectory) }
    public var restoreIntentURL: URL { root.appending(path: "restore-intent.json", directoryHint: .notDirectory) }
    public var installationURL: URL { root.appending(path: "installation.json", directoryHint: .notDirectory) }

    /// Directories every installation needs, created with the protection class.
    public var managedDirectories: [URL] {
        [root, libraryDirectory, blobsDirectory, excerptBlobsDirectory, coverBlobsDirectory, mediaDirectory,
         stagingDirectory, recoveryDirectory, restoreWorkDirectory]
    }
}
