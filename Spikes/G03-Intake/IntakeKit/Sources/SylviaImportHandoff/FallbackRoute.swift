import Foundation

/// The actionable alternative the share extension shows when it cannot finish safely (plan 8.1, gate G0.3).
/// It never says the item was received. Strings here are Stage 0 harness copy; the product moves them into
/// SylviaDesign's status vocabulary (plan 4.4.6 has no share-extension entries yet; see the G0.3 report).
public struct FallbackRoute: Sendable, Equatable {
    public struct Alternative: Sendable, Equatable {
        public let title: String
        public let steps: [String]
    }

    public let headline: String
    public let reason: String
    public let alternatives: [Alternative]

    public static let notReceivedHeadline = "Not received. Nothing was saved to Sylvia."

    public static let saveToFilesThenImport = Alternative(
        title: "Save to Files, then import in Sylvia",
        steps: [
            "In the app you shared from, choose Save to Files (or Export, or Open in) and save the file to On My iPhone or iCloud Drive.",
            "Open Sylvia and choose Import, then Files, and pick the saved file.",
            "If the file is in iCloud Drive and shows a cloud icon, wait until it has downloaded.",
        ]
    )

    public static let sendFromMac = Alternative(
        title: "Send it from your Mac",
        steps: [
            "Put the file on your Mac and add it in Sylvia for Mac.",
            "Send it over your local network, or choose Prepare for cable transfer and copy the bundle in Finder (Files, then Sylvia).",
            "Open Sylvia and import it from the Inbox.",
        ]
    )

    public static func `for`(_ failure: HandoffFailure) -> FallbackRoute {
        let reason: String
        var alternatives = [saveToFilesThenImport, sendFromMac]
        switch failure {
        case .noSupportedItem:
            reason = "Sylvia imports EPUB, PDF, text, Markdown and audio files. This share did not include one."
        case .notADurableFile:
            reason = "The app you shared from offered a link or a temporary preview, not a file Sylvia can keep."
        case .folderNotFile:
            // An EPUB stored unpacked (a package folder). Whether the app's own Files import accepts such folders is an
            // open product decision (G0.3 report), so only the Mac route is offered.
            reason = "The app you shared from offered this book as a folder (an EPUB stored unpacked), not as a single file. Sharing can only take single files."
            alternatives = [sendFromMac]
        case .providerFailed:
            reason = "The app you shared from could not hand over the file."
        case .providerTimedOut:
            reason = "The app you shared from stopped sending the file before it arrived."
        case let .insufficientSpace(needed):
            if let needed {
                let formatted = ByteCountFormatter.string(fromByteCount: Int64(clamping: needed), countStyle: .file)
                reason = "There is not enough free space on this iPhone. Free up \(formatted) more and share again."
            } else {
                reason = "There is not enough free space on this iPhone. Free up space and share again."
            }
            alternatives = [sendFromMac, saveToFilesThenImport]
        case let .itemTooLarge(limit):
            let formatted = ByteCountFormatter.string(fromByteCount: Int64(clamping: limit), countStyle: .file)
            // The same per-file limit applies on every route (Files, Mac, cable bundle), so no alternative is
            // offered: suggesting one would promise an import that cannot succeed.
            reason = "The file is larger than Sylvia's \(formatted) limit for a single file, so Sylvia cannot import it by any route."
            alternatives = []
        case .sourceChanged:
            reason = "The file changed while it was being copied. Share it again once it has finished saving."
        case .cancelled:
            reason = "The copy was cancelled."
        case .writeFailed:
            reason = "Sylvia could not write its copy of the file."
        case .tooManyItems:
            reason = "Share at most \(HandoffManifest.maxItems) files at a time."
        }
        return FallbackRoute(headline: notReceivedHeadline, reason: reason, alternatives: alternatives)
    }
}
