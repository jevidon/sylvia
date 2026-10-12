import Foundation

/// The seven markers of plan Section 4.4.5: five capture kinds and two statuses.
public enum Marker: String, CaseIterable, Sendable, Codable {
    case quote
    case note
    case audio
    case generated
    case word
    case attention
    case pending

    public enum Category: String, Sendable, Codable {
        case captureKind = "capture_kind"
        case status
    }

    public enum Frame: String, Sendable, Codable {
        case none
        /// 1pt dashed frame in the marker's text color (Generated).
        case dashed
        /// A tinted row (Attention).
        case tintedRow = "tinted_row"
    }

    public var category: Category {
        switch self {
        case .quote, .note, .audio, .generated, .word: .captureKind
        case .attention, .pending: .status
        }
    }

    public var glyph: Glyph {
        switch self {
        case .quote: .typeset("\u{201C}", face: .literata, equivalentSymbol: "quote.opening")
        case .note: .systemSymbol("pencil.tip")
        case .audio: .systemSymbol("waveform")
        case .generated: .customSymbol(.prompt)
        case .word: .systemSymbol("book")
        case .attention: .systemSymbol("exclamationmark.triangle")
        case .pending: .systemSymbol("circle.fill")
        }
    }

    /// The marker's label in sentence case. It is displayed through the Micro role, which
    /// uppercases it ("QUOTE"); VoiceOver reads the sentence-case text.
    public var labelKey: LabelKey {
        switch self {
        case .quote: .markerQuote
        case .note: .markerNote
        case .audio: .markerAudio
        case .generated: .markerGenerated
        case .word: .markerWord
        case .attention: .markerAttention
        case .pending: .markerPendingQueued
        }
    }

    /// Other labels the marker may carry ("QUEUED / WAITING" for Pending).
    public var alternateLabelKeys: [LabelKey] {
        self == .pending ? [.markerPendingWaiting] : []
    }

    public var textColor: ColorToken {
        switch self {
        case .quote: .markerQuoteText
        case .note: .markerNoteText
        case .audio: .markerAudioText
        case .generated: .markerGeneratedText
        case .word: .markerWordText
        case .attention: .markerAttentionText
        case .pending: .markerPendingText
        }
    }

    /// Note has no tint, ever (Section 4.4.5).
    public var tint: ColorToken? {
        switch self {
        case .quote: .markerQuoteTint
        case .note: nil
        case .audio: .markerAudioTint
        case .generated: .markerGeneratedTint
        case .word: .markerWordTint
        case .attention: .markerAttentionTint
        case .pending: .markerPendingTint
        }
    }

    public var frame: Frame {
        switch self {
        case .generated: .dashed
        case .attention: .tintedRow
        default: .none
        }
    }

    /// The typeface treatment of the capture body (Section 4.4.5).
    public var body: BodyTreatment {
        switch self {
        case .quote:
            BodyTreatment(face: .literata, roles: [.reading, .body], weight: nil,
                          description: "Exact text in Literata, Reading or Body size, on the quote tint, radius 8")
        case .note:
            BodyTreatment(face: .system, roles: [.body], weight: nil,
                          description: "The user's words in the system face; no tint")
        case .audio:
            BodyTreatment(face: nil, roles: [], weight: nil,
                          description: "A tinted block with a round play control and a waveform; never rendered as text")
        case .generated:
            BodyTreatment(face: .system, roles: [.body], weight: 600,
                          description: "Question in Body 600, answer in Body; citation chips inline")
        case .word:
            BodyTreatment(face: .literata, roles: [.body], weight: 600,
                          description: "Headword in Literata 600, then the source sentence and the user's note")
        case .attention:
            BodyTreatment(face: .system, roles: [.body], weight: nil,
                          description: "Reason in Body; one or two actions")
        case .pending:
            BodyTreatment(face: .system, roles: [.caption], weight: nil,
                          description: "Caption; quiet by design")
        }
    }

    /// Portable capture `kind` strings (Appendix A.1) that map to this marker. Only `text_quote`
    /// appears in the plan; the others are proposed here for the capture-envelope schema.
    public var captureKinds: [String] {
        switch self {
        case .quote: ["text_quote"]
        case .note: ["note"]
        case .audio: ["audio_capture"]
        case .generated: ["generated_answer"]
        case .word: ["word"]
        case .attention, .pending: []
        }
    }

    /// Thoughts filter chip label (Section 4.4.5: All, Quotes, Notes, Audio, Generated, Words).
    public var filterLabelKey: LabelKey? {
        switch self {
        case .quote: .filterQuotes
        case .note: .filterNotes
        case .audio: .filterAudio
        case .generated: .filterGenerated
        case .word: .filterWords
        case .attention, .pending: nil
        }
    }
}

public struct BodyTreatment: Sendable, Hashable {
    public let face: Face?
    public let roles: [TypeRole]
    /// A weight that differs from the role's (for example the Generated question in Body 600).
    public let weight: Int?
    public let description: String
}

/// How a marker glyph is drawn.
public enum Glyph: Sendable, Hashable {
    /// An SF Symbol on Apple platforms.
    case systemSymbol(String)
    /// A `sylvia.*` custom symbol shipped in the design package.
    case customSymbol(CustomSymbol)
    /// A character set in a typeface (the Quote mark in Literata), with the SF Symbol that other
    /// platforms may treat as its equivalent.
    case typeset(String, face: Face, equivalentSymbol: String)

    /// The identifier exported in `marker.<kind>.glyph` (Appendix A.5).
    public var identifier: String {
        switch self {
        case .systemSymbol(let name): name
        case .customSymbol(let symbol): symbol.rawValue
        case .typeset(_, _, let equivalent): equivalent
        }
    }
}

/// Result of mapping a capture's portable `kind` string to a marker.
public struct MarkerResolution: Sendable, Hashable {
    public let marker: Marker
    /// The raw kind when it was not recognized; the label to show instead of the marker's own.
    public let unrecognizedKind: String?

    public var isRecognized: Bool { unrecognizedKind == nil }
}

extension Marker {
    /// Maps a portable capture kind to its marker. Matching is exact and case-sensitive. A kind this
    /// client does not recognize renders with the Pending marker and its raw kind as the label,
    /// never as a Quote (Appendix A.1).
    public static func resolve(captureKind kind: String) -> MarkerResolution {
        for marker in Marker.allCases where marker.captureKinds.contains(kind) {
            return MarkerResolution(marker: marker, unrecognizedKind: nil)
        }
        return MarkerResolution(marker: .pending, unrecognizedKind: kind)
    }
}

/// Status glyphs used by pills (Section 4.4.7): dot, check, triangle.
public enum StatusGlyph: String, Sendable, Codable, CaseIterable {
    case dot
    case check
    case triangle

    public var systemSymbol: String {
        switch self {
        case .dot: "circle.fill"
        case .check: "checkmark"
        case .triangle: "exclamationmark.triangle"
        }
    }
}

/// Custom symbols with no SF Symbol (Section 4.4.5). Geometry is taken from the boards in
/// `Docs/Design/canvas` (24-unit view box, 1.75 stroke, round caps and joins).
public enum CustomSymbol: String, CaseIterable, Sendable, Codable {
    /// The Generated prompt glyph: a chevron and an underscore.
    case prompt = "sylvia.prompt"
    /// The bracket capture glyph of the mini-player and player: brackets around three bars.
    case capture = "sylvia.capture"

    /// Polylines in the boards' 24 x 24 view box (y down).
    public var polylines: [[SymbolPoint]] {
        switch self {
        case .prompt:
            // Board path: M5 7l5 5-5 5 / M12 17h7
            [[SymbolPoint(5, 7), SymbolPoint(10, 12), SymbolPoint(5, 17)],
             [SymbolPoint(12, 17), SymbolPoint(19, 17)]]
        case .capture:
            // Board path: M7 4H4v16h3 M17 4h3v16h-3 / M9 10v4 M12 8v8 M15 11v2
            [[SymbolPoint(7, 4), SymbolPoint(4, 4), SymbolPoint(4, 20), SymbolPoint(7, 20)],
             [SymbolPoint(17, 4), SymbolPoint(20, 4), SymbolPoint(20, 20), SymbolPoint(17, 20)],
             [SymbolPoint(9, 10), SymbolPoint(9, 14)],
             [SymbolPoint(12, 8), SymbolPoint(12, 16)],
             [SymbolPoint(15, 11), SymbolPoint(15, 13)]]
        }
    }

    /// Board source the geometry was copied from.
    public var boardSource: String {
        switch self {
        case .prompt: "Docs/Design/canvas/Thoughts.dc.html (Generated marker)"
        case .capture: "Docs/Design/canvas/Player.dc.html (Capture button)"
        }
    }

    /// Stroke widths in template units (100 pt type) for the three interpolation masters.
    /// Regular matches the stroke of system symbols such as `chevron.right` at the same size.
    /// The capture glyph's Black master is narrower so its three bars, 12 units apart, stay apart.
    public var masterStrokeWidths: (ultralight: Double, regular: Double, black: Double) {
        switch self {
        case .prompt: (2.6, 8.0, 17.0)
        case .capture: (2.6, 8.0, 10.5)
        }
    }

    public var accessibilityLabelKey: LabelKey {
        switch self {
        case .prompt: .symbolPrompt
        case .capture: .symbolCapture
        }
    }
}

public struct SymbolPoint: Sendable, Hashable {
    public let x: Double
    public let y: Double
    public init(_ x: Double, _ y: Double) {
        self.x = x
        self.y = y
    }
}

/// Typographic cover assignment (Section 4.4.2): five fields, chosen by a stable hash of the
/// work title, title in Paper.
public enum CoverFields {
    /// FNV-1a, 32-bit, over the UTF-8 bytes of the title in Unicode NFC. Stable across platforms
    /// and launches (Swift's `hashValue` is not).
    public static func fnv1a32(_ title: String) -> UInt32 {
        var hash: UInt32 = 0x811C_9DC5
        for byte in title.precomposedStringWithCanonicalMapping.utf8 {
            hash ^= UInt32(byte)
            hash = hash &* 0x0100_0193
        }
        return hash
    }

    public static func index(forTitle title: String) -> Int {
        Int(fnv1a32(title) % UInt32(ColorToken.coverFields.count))
    }

    public static func field(forTitle title: String) -> ColorToken {
        ColorToken.coverFields[index(forTitle: title)]
    }

    public static let assignmentRule = "fnv1a32(utf8(nfc(title))) mod 5; fields in listed order; title color cover_title"
}
