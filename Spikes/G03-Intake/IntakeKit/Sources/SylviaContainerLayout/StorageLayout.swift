import Foundation
import SylviaIntakeCore

/// Where every storage class lives on device (plan 16.4, 17.1, 18.1).
///
///   Documents/                            Finder-visible (UIFileSharingEnabled): inbound drop area ONLY
///   Library/Application Support/Sylvia/   private, backed up
///       Database/library.sqlite (+ -wal, -shm)
///       Knowledge/Notes, Knowledge/Retained   permanent knowledge
///       Media/                                 committed originals
///       Staging/ (journal.json, Staged/, Rejected/, Abandoned/, Extracting/)   excluded from backup
///   <App Group>/Intake/Handoffs/          share-extension inbox (private to the app and its extension), excluded
///                                         from backup like Staging
public struct StorageLayout: Sendable {
    public let documents: URL
    public let applicationSupport: URL
    public let appGroup: URL?

    public init(documents: URL, applicationSupport: URL, appGroup: URL?) {
        self.documents = documents
        self.applicationSupport = applicationSupport
        self.appGroup = appGroup
    }

    /// The real container on device or simulator.
    public static func current(appGroupIdentifier: String?) throws -> StorageLayout {
        let fm = FileManager.default
        let documents = try fm.url(for: .documentDirectory, in: .userDomainMask, appropriateFor: nil, create: true)
        let support = try fm.url(for: .applicationSupportDirectory, in: .userDomainMask, appropriateFor: nil, create: true)
        let group = appGroupIdentifier.flatMap { fm.containerURL(forSecurityApplicationGroupIdentifier: $0) }
        return StorageLayout(documents: documents, applicationSupport: support.appendingPathComponent("Sylvia", isDirectory: true),
                             appGroup: group)
    }

    public var databaseDirectory: URL { applicationSupport.appendingPathComponent("Database", isDirectory: true) }
    public var database: URL { databaseDirectory.appendingPathComponent("library.sqlite") }
    public var notes: URL { applicationSupport.appendingPathComponent("Knowledge/Notes", isDirectory: true) }
    public var retainedKnowledge: URL { applicationSupport.appendingPathComponent("Knowledge/Retained", isDirectory: true) }
    public var media: URL { applicationSupport.appendingPathComponent("Media", isDirectory: true) }
    public var staging: URL { applicationSupport.appendingPathComponent("Staging", isDirectory: true) }
    public var journal: URL { staging.appendingPathComponent("journal.json") }
    public var extracting: URL { staging.appendingPathComponent("Extracting", isDirectory: true) }
    public var handoffInbox: URL? { appGroup?.appendingPathComponent("Intake/Handoffs", isDirectory: true) }

    /// Every private location, for the layout audit.
    public var privateLocations: [(name: String, url: URL)] {
        var list: [(String, URL)] = [
            ("database", databaseDirectory), ("notes", notes), ("retained knowledge", retainedKnowledge),
            ("media", media), ("staging", staging),
        ]
        if let handoffInbox { list.append(("handoff inbox", handoffInbox)) }
        return list
    }

    /// Staging-class locations (plan 17.1): private staging and the share-extension handoff inbox. Both hold bytes
    /// that are either still held by their source or about to be committed, so they are excluded from device backup.
    public var backupExcludedLocations: [URL] {
        [staging] + (handoffInbox.map { [$0] } ?? [])
    }

    /// Creates the private directories. Staging and the handoff inbox are excluded from device backup (rebuildable
    /// or recoverable from the source, plan 17.1/17.5); knowledge, database and media stay backup-eligible. On iOS every private
    /// directory gets complete-until-first-user-authentication protection so authorized background work can
    /// run after first unlock (plan 18.1); new files inherit it.
    public func bootstrap() throws {
        let fm = FileManager.default
        for (_, url) in privateLocations {
            try fm.createDirectory(at: url, withIntermediateDirectories: true)
        }
        for url in backupExcludedLocations {
            try VolumeSpace.excludeFromBackup(url)
        }
        #if os(iOS)
        for (_, url) in privateLocations {
            try fm.setAttributes([.protectionKey: FileProtectionType.completeUntilFirstUserAuthentication], ofItemAtPath: url.path)
        }
        #endif
    }
}

/// Checks that the container follows the rules above. Used by the in-app test (simulator) and the host tests.
public enum LayoutAudit {
    public struct Violation: Equatable, Sendable, CustomStringConvertible {
        public let rule: String
        public let detail: String
        public var description: String { "\(rule): \(detail)" }
    }

    /// File name suffixes that must never appear under Documents.
    static let privateSuffixes = [".sqlite", ".sqlite-wal", ".sqlite-shm", "journal.json", "handoff.json"]

    public static func audit(_ layout: StorageLayout, infoDictionary: [String: Any]?) -> [Violation] {
        var violations: [Violation] = []
        let documents = layout.documents.standardizedFileURL.resolvingSymlinksInPath().path
        for (name, url) in layout.privateLocations {
            let path = url.standardizedFileURL.resolvingSymlinksInPath().path
            if path == documents || path.hasPrefix(documents + "/") {
                violations.append(.init(rule: "private data outside Documents", detail: "\(name) is under Documents"))
            }
        }
        if let enumerator = FileManager.default.enumerator(atPath: layout.documents.path) {
            while let relative = enumerator.nextObject() as? String {
                let lower = relative.lowercased()
                if privateSuffixes.contains(where: { lower.hasSuffix($0) }) {
                    violations.append(.init(rule: "Documents is an inbound drop area only", detail: "found a private file type"))
                }
            }
        }
        for url in layout.backupExcludedLocations where FileManager.default.fileExists(atPath: url.path) {
            if !VolumeSpace.isExcludedFromBackup(url) {
                violations.append(.init(rule: "staging-class data is excluded from device backup",
                                        detail: "\(url.lastPathComponent) is backup-eligible"))
            }
        }
        if let info = infoDictionary {
            if info["UIFileSharingEnabled"] as? Bool != true {
                violations.append(.init(rule: "Info.plist", detail: "UIFileSharingEnabled must be true"))
            }
            if info["LSSupportsOpeningDocumentsInPlace"] as? Bool != false {
                violations.append(.init(rule: "Info.plist", detail: "LSSupportsOpeningDocumentsInPlace must be present and false"))
            }
        }
        return violations
    }
}
