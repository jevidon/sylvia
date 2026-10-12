import CoreGraphics
import Foundation
import UIKit

// Proposed `ReaderSession` contract (plan 9.1, ADR-0004). Everything here is reader-neutral: the Readium
// implementation lives in `ReadiumReaderSession`; a PDF or text reader would implement the same protocol.

/// A reader location. `json` is the reader's own locator (for Readium, its `Locator` JSON) and is opaque outside
/// the adapter; the other fields are copies for display and for the portable anchor envelope.
public struct ReaderLocator: Sendable, Equatable, Codable {
    public var json: String
    public var href: String
    public var mediaType: String?
    public var progression: Double?
    public var totalProgression: Double?
    public var position: Int?
    public var textBefore: String?
    public var textHighlight: String?
    public var textAfter: String?
    public var otherLocationKeys: [String]
}

/// A selection captured from the reader. `exactText` is the reader's selected string, untrimmed and untruncated.
public struct ReaderSelection: Sendable, Equatable {
    public var locator: ReaderLocator
    public var exactText: String
    public var prefix: String
    public var suffix: String
    public var frame: CGRect?
}

/// A saved highlight as the reader should draw it. The record itself lives in Sylvia's database (plan 9.1).
public struct HighlightPresentation: Sendable, Equatable, Hashable {
    public var id: String
    public var locator: ReaderLocator

    public init(id: String, locator: ReaderLocator) {
        self.id = id
        self.locator = locator
    }

    public func hash(into hasher: inout Hasher) { hasher.combine(id) }
}

public enum ReaderTheme: String, Sendable, Codable, CaseIterable { case paper, night }

public enum ReaderTypeface: String, Sendable, Codable, CaseIterable {
    /// Literata (bundled, variable), the default reading face (plan 4.4.3).
    case literata
    /// The platform serif (New York on Apple platforms, CSS `ui-serif`).
    case systemSerif
    /// The platform sans (SF Pro, CSS `-apple-system`).
    case systemSans
    /// The publication's own fonts.
    case publisher
}

/// Reader settings from plan 4.4.3. Sizes are in points at the default Dynamic Type size.
public struct ReaderSettings: Sendable, Equatable, Codable {
    public static let fontSizeRange: ClosedRange<Double> = 14 ... 28
    /// Four line-spacing steps; step 1 is the Reading role's 19/30.
    public static let lineHeights: [Double] = [1.35, 30.0 / 19.0, 1.8, 2.0]
    /// Three margin widths (Readium `pageMargins` factor).
    public static let marginFactors: [Double] = [0.75, 1.0, 1.5]

    public var typeface: ReaderTypeface = .literata
    public var fontSizePoints: Double = 19
    public var lineSpacingStep: Int = 1
    public var marginStep: Int = 1
    public var theme: ReaderTheme = .paper
    public var scroll: Bool = false
    public var publisherStyles: Bool = false

    public init() {}
}

public enum ReaderOpenError: Error, Equatable, Sendable, CustomStringConvertible {
    /// The file is not a regular file (directory, symlink, missing).
    case notARegularFile
    /// The archive failed preflight (plan 8.3); codes from `ZIPPreflightViolation.code`.
    case unsafeArchive([String])
    /// Readium could not retrieve or parse the asset.
    case unreadable(String)
    /// The asset is not an EPUB.
    case notAnEPUB
    /// Content protection Sylvia does not support (plan 8.3): never circumvented.
    case unsupportedProtection(scheme: String, algorithms: [String])
    /// Outside the compatibility subset (for example fixed layout).
    case unsupportedLayout(String)

    public var description: String {
        switch self {
        case .notARegularFile: "not a regular file"
        case let .unsafeArchive(codes): "unsafe archive: \(codes.joined(separator: ", "))"
        case let .unreadable(reason): "unreadable: \(reason)"
        case .notAnEPUB: "not an EPUB"
        case let .unsupportedProtection(scheme, algorithms): "unsupported protection \(scheme) \(algorithms)"
        case let .unsupportedLayout(layout): "unsupported layout \(layout)"
        }
    }

    /// The import state machine's terminal state for this error (plan 8.2).
    public var importState: String {
        switch self {
        case .unsafeArchive, .notAnEPUB, .unsupportedProtection, .unsupportedLayout: "unsupported"
        case .notARegularFile, .unreadable: "failed_final"
        }
    }
}

/// Opaque token; observation stops when it is released or `cancel()` is called.
@MainActor public final class ReaderObservation {
    private var onCancel: (() -> Void)?
    init(onCancel: @escaping () -> Void) { self.onCancel = onCancel }
    public func cancel() { onCancel?(); onCancel = nil }
}

/// The reader contract Sylvia's reading screen is written against (plan 9.1).
@MainActor public protocol ReaderSession: AnyObject {
    /// The view controller rendering the publication.
    var viewController: UIViewController { get }
    /// Current reading position, once the first page is laid out.
    var currentLocator: ReaderLocator? { get }
    /// Current text selection as the reader reports it, or nil.
    var currentSelection: ReaderSelection? { get }
    /// The selection to save: exact text plus a locator whose resource the adapter has confirmed against the
    /// document holding the selection. Nil when there is no selection or it changed while being captured.
    func captureSelection() async -> ReaderSelection?

    func navigate(to locator: ReaderLocator) async -> Bool
    func goForward() async -> Bool
    func goBackward() async -> Bool
    /// Follows an internal link, remembering the current position for `returnFromLink()`.
    func followLink(href: String) async -> Bool
    /// Returns to the position saved by the most recent link, footnote or search jump.
    func returnFromLink() async -> Bool

    func clearSelection()
    /// Declares the complete set of highlights to draw (removing a highlight = applying the set without it).
    func apply(highlights: [HighlightPresentation])
    func apply(settings: ReaderSettings)

    /// Searches the publication text; each result's locator reopens the passage.
    func search(_ query: String) async throws -> [ReaderLocator]

    /// Position changes as the user reads.
    func observePositions(_ handler: @escaping @MainActor (ReaderLocator) -> Void) -> ReaderObservation
}
