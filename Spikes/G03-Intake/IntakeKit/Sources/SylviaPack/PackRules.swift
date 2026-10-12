import Foundation

/// Fixed entry names and order of a .sylviapack v1 archive.
public enum PackLayout {
    public static let manifestEntry = "sylviapack/manifest.json"
    public static let manifestDigestEntry = "sylviapack/manifest.sha256"
    public static let contentPrefix = "content/"
    /// The two manifest entries precede the content entries.
    public static let reservedEntryCount = 2
    public static let fileExtension = "sylviapack"
}

/// Proposed safety limits (plan 8.3). Configurable; the defaults are the plan's numbers where it gives one.
public struct PackLimits: Sendable, Equatable {
    /// Total ZIP entries, manifest entries included (plan 8.3: 10,000 archive entries).
    public var maxEntries = 10_000
    public var maxManifestBytes = 1 << 20
    /// Central directory bytes. 10,000 entries with 1 KiB paths and ZIP64 extras fit well inside this.
    public var maxCentralDirectoryBytes = 24 << 20
    public var maxAudioFile: UInt64 = 20 << 30          // plan 8.3
    public var maxPDF: UInt64 = 2 << 30                 // plan 8.3
    public var maxEPUB: UInt64 = 1 << 30                // plan 8.3 bounds expanded EPUB content at 1 GiB
    public var maxText: UInt64 = 256 << 20
    public var maxCover: UInt64 = 32 << 20
    public var maxTotalSize: UInt64 = 200 << 30
    public var maxAudioMembersPerGroup = 500            // plan 8.3
    /// Deflated entries only: uncompressed / compressed. Stored entries are 1 by construction.
    public var maxCompressionRatio: UInt64 = 100
    /// Below this uncompressed size the per-entry ratio check does not apply (tiny repetitive text compresses well).
    public var ratioCheckFloor: UInt64 = 1 << 20
    /// All deflated entries together may expand to at most `maxCompressionRatio` times their compressed bytes plus
    /// this allowance. Without it, content split into many entries at or below `ratioCheckFloor` escapes the ratio
    /// check (a 2.6 MB pack of 2,000 one-MiB entries of zeros declares 2 GiB). With it, everything a pack can make
    /// extraction write is bounded by its stored bytes, 100 times its deflated bytes, and this allowance.
    public var aggregateExpansionAllowance: UInt64 = 16 << 20
    /// Free space kept beyond the content when extracting (the same margin as a share-extension handoff).
    public var extractionSpaceMargin: UInt64 = 64 << 20

    public init() {}

    public func maxFileSize(for kind: PackManifest.Kind) -> UInt64 {
        switch kind {
        case .audio: maxAudioFile
        case .pdf: maxPDF
        case .epub: maxEPUB
        case .text, .markdown: maxText
        case .cover: maxCover
        }
    }
}

/// Every reason a bundle is refused. `code` values are stable and appear in logs and tests; `detail` never
/// contains a path or file name from the bundle.
public struct PackRejection: Error, Equatable, Sendable, CustomStringConvertible {
    public enum Code: String, Sendable, CaseIterable {
        case notARegularFile = "not_a_regular_file"
        case truncated = "truncated_or_not_a_pack"          // no end record exactly at the end of the file
        case archiveComment = "archive_comment"
        case multiDisk = "multi_disk"
        case tooManyEntries = "too_many_entries"
        case centralDirectoryTooLarge = "central_directory_too_large"
        case malformedStructure = "malformed_structure"
        case layoutGap = "layout_gap_or_overlap"
        case localHeaderMismatch = "local_header_mismatch"
        case encryptedEntry = "encrypted_entry"
        case unsupportedFeature = "unsupported_feature"       // data descriptors, unknown flags, versions
        case unsupportedCompression = "unsupported_compression"
        case specialEntry = "special_entry"                   // directory, symlink, device, FIFO, socket
        case executableEntry = "executable_entry"
        case unsafePath = "unsafe_path"
        case duplicatePath = "duplicate_path"
        case pathConflict = "path_conflict"
        case missingManifest = "missing_manifest"
        case manifestTooLarge = "manifest_too_large"
        case manifestDigestMismatch = "manifest_digest_mismatch"
        case manifestInvalid = "manifest_invalid"
        case unsupportedVersion = "unsupported_version"
        case unexpectedEntry = "unexpected_entry"
        case missingEntry = "missing_entry"
        case entryOrderMismatch = "entry_order_mismatch"
        case declaredSizeMismatch = "declared_size_mismatch"  // header size differs from the manifest
        case storedSizeMismatch = "stored_size_mismatch"      // stored entry whose compressed and uncompressed sizes differ
        case expansionLimit = "expansion_limit"
        case limitExceeded = "limit_exceeded"
        case actualSizeMismatch = "actual_size_mismatch"      // bytes produced differ from what was declared
        case crcMismatch = "crc_mismatch"
        case contentDigestMismatch = "content_digest_mismatch"
        case libraryDisagreement = "library_disagreement"
        case ioError = "io_error"
        case destinationExists = "destination_exists"
        /// Not a fault of the bundle: the destination volume lacks the space to extract it (plan 8.4).
        case insufficientSpace = "insufficient_space"
    }

    public let code: Code
    public let detail: String
    /// For `insufficientSpace`: the additional bytes the volume must free (plan 8.4: name the space required).
    public let additionalBytesNeeded: UInt64?

    public init(_ code: Code, _ detail: String = "", additionalBytesNeeded: UInt64? = nil) {
        self.code = code
        self.detail = detail
        self.additionalBytesNeeded = additionalBytesNeeded
    }

    public var description: String { detail.isEmpty ? code.rawValue : "\(code.rawValue): \(detail)" }
}

/// Path rules for manifest paths and archive entry names.
///
/// A manifest path is at most 15 components and 512 bytes; a content entry's name is `content/` + that path, so
/// archive entry names are at most 16 components and 520 bytes, and every path the manifest rules accept gives an
/// entry name the entry rules accept (contract `sylviapack-manifest` v1, ADR-0010 section 2). 512 bytes rather
/// than more because extraction joins the path to a container directory and the result must stay below PATH_MAX
/// (1024 bytes on Apple platforms): the extraction directory is about 180 bytes on a device and about 250 on the
/// simulator.
public enum PackPath {
    public static let maxManifestPathBytes = 512
    public static let maxManifestPathDepth = 15
    public static let maxBytes = maxManifestPathBytes + PackLayout.contentPrefix.utf8.count     // 520
    public static let maxComponentBytes = 255
    public static let maxDepth = maxManifestPathDepth + 1                                        // 16

    /// A manifest file path (relative to `content/`).
    public static func validateManifestPath(_ path: String) throws(PackRejection) {
        try validate(path, maxBytes: maxManifestPathBytes, maxDepth: maxManifestPathDepth)
    }

    /// A full archive entry name.
    public static func validate(_ path: String, maxBytes: Int = PackPath.maxBytes, maxDepth: Int = PackPath.maxDepth) throws(PackRejection) {
        guard !path.isEmpty, path.utf8.count <= maxBytes else { throw PackRejection(.unsafePath, "length") }
        // Compare bytes: Swift's String == treats canonically equivalent strings as equal.
        guard Array(path.utf8) == Array(path.precomposedStringWithCanonicalMapping.utf8) else {
            throw PackRejection(.unsafePath, "not Unicode NFC")
        }
        guard !path.hasPrefix("/") else { throw PackRejection(.unsafePath, "absolute") }
        for scalar in path.unicodeScalars {
            if scalar.value < 0x20 || scalar.value == 0x7F || scalar == "\\" || scalar == ":" {
                throw PackRejection(.unsafePath, "forbidden character U+\(String(scalar.value, radix: 16, uppercase: true))")
            }
        }
        let components = path.split(separator: "/", omittingEmptySubsequences: false)
        guard components.count <= maxDepth else { throw PackRejection(.unsafePath, "too deep") }
        for component in components {
            guard !component.isEmpty else { throw PackRejection(.unsafePath, "empty component") }
            guard component != ".", component != ".." else { throw PackRejection(.unsafePath, "dot component") }
            guard component.utf8.count <= maxComponentBytes else { throw PackRejection(.unsafePath, "component length") }
        }
    }

    /// Two paths collide on a case-insensitive or normalization-insensitive file system if their keys match.
    public static func collisionKey(_ path: String) -> String {
        path.precomposedStringWithCanonicalMapping.folding(options: [.caseInsensitive], locale: nil)
    }

    /// Rejects a path that is both a file and a directory prefix of another path ("a" and "a/b").
    public static func checkNoFileDirectoryConflicts(_ paths: [String]) throws(PackRejection) {
        let files = Set(paths.map(collisionKey))
        for path in paths {
            var prefix = ""
            let components = collisionKey(path).split(separator: "/")
            for component in components.dropLast() {
                prefix += prefix.isEmpty ? String(component) : "/" + component
                if files.contains(prefix) { throw PackRejection(.pathConflict, "a file is also used as a folder") }
            }
        }
    }
}
