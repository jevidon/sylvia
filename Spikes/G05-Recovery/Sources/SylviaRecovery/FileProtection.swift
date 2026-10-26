import Foundation

/// Data protection for every persistent file Sylvia writes (plan 18.1, T50).
///
/// Chosen class: `completeUntilFirstUserAuthentication` (class C). Authorized background
/// playback and background transfers after first unlock must be able to read media and write the
/// database while the phone is locked, which rules out `complete` (class A) for the library. The
/// tradeoff (files readable while locked once the device has been unlocked once since boot) is
/// recorded in ADR-0012.
///
/// How each file gets the class:
/// * Directories are created with the class, so files created inside them inherit it. SQLite
///   creates `library.sqlite`, `-wal` and `-shm` itself (GRDB does not expose SQLite's
///   `SQLITE_OPEN_FILEPROTECTION_*` open flags), so inheritance from `Library/` is what protects
///   them; `LibraryStore` then sets and verifies the class explicitly on all three.
/// * Files Sylvia writes itself (blobs, manifests, exports, intents) are written with the
///   matching `Data.WritingOptions` and verified. Files Sylvia copies (imported media, bundle
///   blobs, restore copies, snapshots put back) are created the same way by `copyFile`, never
///   with `FileManager.copyItem`, which keeps the source file's class.
/// * Class C is also the platform default for new files on macOS and for app files on iOS, so a
///   class-C readback alone cannot show that this code applied anything. The discriminating
///   evidence is a run of the same flow with the non-default class B supplied through
///   `StoreOptions.protector` (`DataProtectionTests.everyFileProtectedNonDefault`). Class A cannot
///   be used for the library (SQLite's SHM file does not take it), and that run needs class B keys,
///   so it is skipped on a host whose screen is locked; the CI drop-in fails when its evidence line
///   is missing.
/// * Nothing ever lowers the class to make a locked-device operation succeed. A file that cannot
///   be given the class is an error, not a fallback.
///
/// Readback: macOS (host tests) reports the class of every file and directory faithfully. The iOS
/// Simulator does not: directories report no class, and regular files report class C even when
/// created in a class-B directory (`DataProtectionTests.inheritance`). In a simulator build only, an
/// item that reports no class is therefore accepted after the class was requested. A different
/// reported class is still an error everywhere, and device builds always require the readback to
/// match (device checklist, T50). Files are created inside protected directories so that they have
/// the class from the start; whether `setAttributes` can change an existing file's class is what
/// `DataProtectionTests.mismatchDetected` records.
public struct FileProtector: Sendable {
    public let protection: FileProtectionType

    /// False only in the iOS Simulator, whose protection-class readback is not faithful.
    public static var platformReportsProtection: Bool {
        #if targetEnvironment(simulator)
        return false
        #else
        return true
        #endif
    }

    public init(protection: FileProtectionType = .completeUntilFirstUserAuthentication) {
        self.protection = protection
    }

    public static let library = FileProtector()

    /// The `Data.WritingOptions` that create a file with the class. Only classes A, B and C have
    /// one; any other class is refused before anything is written, never mapped to an unprotected
    /// write (ADR-0015 TM-F1).
    public var writingOptions: Data.WritingOptions {
        get throws {
            switch protection {
            case .complete: return .completeFileProtection
            case .completeUnlessOpen: return .completeFileProtectionUnlessOpen
            case .completeUntilFirstUserAuthentication: return .completeFileProtectionUntilFirstUserAuthentication
            default: throw ProtectionError.unsupportedClass(protection.rawValue)
            }
        }
    }

    /// Refuses any class other than A, B and C, on the directory and protect paths as `writingOptions`
    /// does on the write and copy paths, before anything is created or changed. Without it a protector
    /// built with another class (`StoreOptions.protector` is public) would create directories, and set
    /// the class of the database files, with that class and then verify against it (M0 final review
    /// SEC-06; TM-F1 had closed only the write and copy paths).
    func requireSupportedClass() throws {
        _ = try writingOptions
    }

    /// Creates the directory (and parents) with the protection class, or applies the class if it
    /// already exists.
    public func ensureDirectory(_ url: URL) throws {
        try requireSupportedClass()
        let fm = FileManager.default
        var isDirectory: ObjCBool = false
        if fm.fileExists(atPath: url.path, isDirectory: &isDirectory) {
            guard isDirectory.boolValue else { throw ProtectionError.notADirectory(url.lastPathComponent) }
            try protect(url)
        } else {
            try fm.createDirectory(at: url, withIntermediateDirectories: true,
                                   attributes: [.protectionKey: protection])
            try verify(url)
        }
    }

    /// Sets the class on an existing file or directory and verifies it.
    public func protect(_ url: URL) throws {
        try requireSupportedClass()
        if try protectionClass(of: url) == protection { return }
        do {
            try FileManager.default.setAttributes([.protectionKey: protection], ofItemAtPath: url.path)
        } catch {
            throw ProtectionError.cannotApply(url.lastPathComponent, String(describing: error))
        }
        try verify(url)
    }

    /// Writes `data` with the protection class. `atomic` uses Foundation's same-directory temp file
    /// and rename. A file whose class does not read back is removed, so no unprotected bytes stay
    /// on disk (ADR-0015 TM-F1).
    public func write(_ data: Data, to url: URL, atomic: Bool = true) throws {
        var options = try writingOptions
        if atomic { options.insert(.atomic) }
        try data.write(to: url, options: options)
        do {
            try verify(url)
        } catch {
            try? FileManager.default.removeItem(at: url)
            throw error
        }
    }

    /// Copies the regular file at `source` into a new file at `destination` that is created with
    /// the protection class, then verifies the class. `FileManager.copyItem` must not be used for
    /// files Sylvia keeps: it clones the source and keeps the source's class (shown on the host:
    /// a class-C file copied into a class-B directory stays class C). The source is opened without following a link in
    /// its last component (`O_NOFOLLOW`) and must be a regular file at the moment it is opened, so a
    /// bundle changed after validation cannot substitute a link, FIFO or device for the file itself.
    /// `O_NOFOLLOW` covers the last component only: a folder above the file that is swapped for a
    /// link after the caller's checks is followed (security review of 26 October 2026, finding S5;
    /// left as it was, a request to the technical lead). A restore still keeps only a copy with the
    /// manifest's size and digest (`BackupRestorer.prepare`). Fails if `destination` exists.
    public func copyFile(from source: URL, to destination: URL) throws {
        let fd = open(source.path, O_RDONLY | O_NOFOLLOW | O_NONBLOCK | O_CLOEXEC)
        guard fd >= 0 else { throw FileSystemError.posix("open", source.lastPathComponent, errno) }
        let input = FileHandle(fileDescriptor: fd, closeOnDealloc: true)
        defer { try? input.close() }
        var info = stat()
        guard fstat(fd, &info) == 0 else { throw FileSystemError.posix("fstat", source.lastPathComponent, errno) }
        guard (info.st_mode & S_IFMT) == S_IFREG else {
            throw FileSystemError.posix("copy", "\(source.lastPathComponent) is not a regular file", EINVAL)
        }
        var options = try writingOptions
        options.insert(.withoutOverwriting)
        try Data().write(to: destination, options: options)
        do {
            try verify(destination)
            let output = try FileHandle(forWritingTo: destination)
            defer { try? output.close() }
            while let chunk = try input.read(upToCount: 1 << 20), !chunk.isEmpty {
                try output.write(contentsOf: chunk)
            }
            try output.close()
            try verify(destination)
        } catch {
            try? FileManager.default.removeItem(at: destination)
            throw error
        }
    }

    /// Copies the directory tree at `source` into a new directory `destination`, which must not exist:
    /// every directory is created with the protection class (`ensureDirectory`) and every regular file
    /// by `copyFile`, so each item gets this protector's class whatever the source item's class was.
    /// A symbolic link or any other kind of item fails the copy, and a failed copy is removed. For a
    /// library tree copied from a template (the crash drills, the tests): `FileManager.copyItem` keeps
    /// each source file's class (device run of 26 October 2026: a fixture copied out of the app bundle
    /// had no class, and the open refused it). Extended attributes are not copied; the open sets the
    /// backup exclusion of the directories that need it again.
    ///
    /// Whether the destination is inside the source is decided on both paths resolved by realpath(3)
    /// (`CanonicalPath`), so links are followed and /private is kept however the folders are named; a
    /// destination that cannot be placed that way is refused. Foundation's `standardizedFileURL` drops
    /// /private only from a path that exists: under /private/var, as an iPhone names its folders, the
    /// existing source and a destination inside it that did not exist yet differed in prefix, and the
    /// copy went on into itself (review of 26 October 2026, finding F1).
    public func copyTree(from source: URL, to destination: URL) throws {
        try requireSupportedClass()
        let fm = FileManager.default
        guard let sourcePath = CanonicalPath.of(source), let destinationPath = CanonicalPath.of(destination) else {
            throw FileSystemError.posix("copy", "\(destination.lastPathComponent): a path that cannot be resolved", EINVAL)
        }
        guard destinationPath != sourcePath, CanonicalPath.relative(destinationPath, to: sourcePath) == nil else {
            throw FileSystemError.posix("copy", "\(destination.lastPathComponent) is inside \(source.lastPathComponent)", EINVAL)
        }
        var info = stat()
        guard lstat(source.path, &info) == 0 else { throw FileSystemError.posix("lstat", source.lastPathComponent, errno) }
        guard (info.st_mode & S_IFMT) == S_IFDIR else {
            throw FileSystemError.posix("copy", "\(source.lastPathComponent) is not a directory", ENOTDIR)
        }
        guard lstat(destination.path, &info) != 0, errno == ENOENT else {
            throw FileSystemError.posix("copy", "\(destination.lastPathComponent) already exists", EEXIST)
        }
        do {
            try ensureDirectory(destination)
            try copyContents(of: source, into: destination)
        } catch {
            try? fm.removeItem(at: destination)
            throw error
        }
    }

    private func copyContents(of directory: URL, into target: URL) throws {
        for name in try FileManager.default.contentsOfDirectory(atPath: directory.path).sorted() {
            let from = directory.appending(path: name, directoryHint: .notDirectory)
            let to = target.appending(path: name, directoryHint: .notDirectory)
            var info = stat()
            guard lstat(from.path, &info) == 0 else { throw FileSystemError.posix("lstat", name, errno) }
            switch info.st_mode & S_IFMT {
            case S_IFDIR:
                try ensureDirectory(to)
                try copyContents(of: from, into: to)
            case S_IFREG:
                try copyFile(from: from, to: to)
            default:
                throw FileSystemError.posix("copy", "\(name) is not a regular file or a directory", EINVAL)
            }
        }
    }

    public func protectionClass(of url: URL) throws -> FileProtectionType? {
        // A URL caches the resource values it has read, so a reading through the URL that read the class
        // before `setAttributes` would return the old class (finding F-1). Drop the cached value first.
        var fresh = url
        fresh.removeCachedResourceValue(forKey: .fileProtectionKey)
        let values = try fresh.resourceValues(forKeys: [.fileProtectionKey])
        guard let value = values.fileProtection else { return nil }
        // URLFileProtection and FileProtectionType are distinct string enums with different raw
        // values ("NSURLFileProtection…" vs "NSFileProtection…"); map them explicitly.
        switch value {
        case .complete: return .complete
        case .completeUnlessOpen: return .completeUnlessOpen
        case .completeUntilFirstUserAuthentication: return .completeUntilFirstUserAuthentication
        case .none: return FileProtectionType.none
        default:
            // Any other class (for example iOS 17's completeWhenUserInactive) keeps its URL raw value,
            // so it can never compare equal to the class Sylvia requires.
            return FileProtectionType(rawValue: value.rawValue)
        }
    }

    public func verify(_ url: URL) throws {
        let actual = try protectionClass(of: url)
        if actual == nil && !Self.platformReportsProtection { return }
        guard actual == protection else {
            throw ProtectionError.mismatch(url.lastPathComponent, expected: protection.rawValue,
                                           actual: actual?.rawValue ?? "none reported")
        }
    }
}

public enum ProtectionError: Error, Equatable, CustomStringConvertible {
    case notADirectory(String)
    case cannotApply(String, String)
    case mismatch(String, expected: String, actual: String)
    case unsupportedClass(String)

    public var description: String {
        switch self {
        case .notADirectory(let name): return "protection: \(name) is not a directory"
        case .cannotApply(let name, let why): return "protection: cannot apply class to \(name): \(why)"
        case .mismatch(let name, let expected, let actual):
            return "protection: \(name) has \(actual), expected \(expected)"
        case .unsupportedClass(let value): return "protection: \(value) has no protected writing option; nothing was written"
        }
    }
}
