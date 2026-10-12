import Foundation

/// Free space and backup classification for intake storage.
///
/// Required-reason APIs (plan 18.2): `availableCapacity` reads the volume's available capacity, which is in Apple's
/// "disk space" category (NSPrivacyAccessedAPICategoryDiskSpace). ADR-0010 lists what the app and the extension
/// will have to declare.
public enum VolumeSpace {
    /// Available bytes on the volume holding `url` (or its nearest existing ancestor), or nil when unknown.
    /// iOS: capacity for important usage (what the system will free up for a user-initiated import).
    public static let availableCapacity: @Sendable (URL) -> UInt64? = { url in
        var probe = url
        // The volume can only be asked about a path that exists; walk up to the nearest existing ancestor.
        while !FileManager.default.fileExists(atPath: probe.path), probe.pathComponents.count > 1 {
            probe = probe.deletingLastPathComponent()
        }
        #if os(iOS)
        let values = try? probe.resourceValues(forKeys: [.volumeAvailableCapacityForImportantUsageKey])
        return values?.volumeAvailableCapacityForImportantUsage.map { UInt64(max(0, $0)) }
        #else
        let values = try? probe.resourceValues(forKeys: [.volumeAvailableCapacityKey])
        return values?.volumeAvailableCapacity.map { UInt64(max(0, $0)) }
        #endif
    }

    /// Bytes still missing when `needed` bytes must fit in `available`; nil when they fit or `available` is unknown.
    public static func shortfall(needed: UInt64, available: UInt64?) -> UInt64? {
        guard let available, needed > available else { return nil }
        return needed - available
    }

    /// Marks a directory (and so everything inside it) as excluded from device backup. Staging-class data
    /// (plan 17.1: partial transfers, import bundles, commit journals) is either rebuildable or still held by its
    /// source, so it is kept out of iCloud and computer backups (plan 17.5).
    public static func excludeFromBackup(_ url: URL) throws {
        var target = url
        var values = URLResourceValues()
        values.isExcludedFromBackup = true
        try target.setResourceValues(values)
    }

    public static func isExcludedFromBackup(_ url: URL) -> Bool {
        var fresh = url
        fresh.removeAllCachedResourceValues()
        return (try? fresh.resourceValues(forKeys: [.isExcludedFromBackupKey]).isExcludedFromBackup) == true
    }
}
