import Foundation

/// SF Symbols used by the component library for controls and navigation (Section 4.4.7), so no
/// component names a symbol inline and other platforms can map the same set. Marker and status
/// glyphs are defined with their markers (``Marker/glyph``, ``StatusGlyph``); the bracket capture
/// glyph is the custom symbol `sylvia.capture`. Exported under `components.control_symbols`.
public enum ControlSymbol: String, CaseIterable, Sendable, Codable {
    // Primary areas (tab bar and iPad sidebar), as the boards draw them.
    case areaLibrary = "books.vertical"
    case areaThoughts = "quote.opening"
    case areaInbox = "tray"
    // Navigation bar and reader chrome.
    case back = "chevron.left"
    case search = "magnifyingglass"
    case settings = "gearshape"
    case readerSettings = "textformat.size"
    case bookmark = "bookmark"
    case bookmarkSet = "bookmark.fill"
    // Playback.
    case play = "play.fill"
    case pause = "pause.fill"
    // Numeric steppers (audio range start and end).
    case stepEarlier = "minus"
    case stepLater = "plus"
    // Capture sheet "Look up" (the same open book as the Word marker).
    case lookUp = "book"
    // Rating stars: filled, leading half filled, outline (three shapes, so the value reads without color).
    case starFull = "star.fill"
    case starHalf = "star.leadinghalf.filled"
    case starEmpty = "star"
    // Screen controls added for the design catalog prototype (G0.6 part 3; proposals for review).
    case disclosure = "chevron.right"
    case dismiss = "chevron.down"
    case more = "ellipsis"
    case edit = "pencil"
    case importFile = "arrow.down.to.line"
    case connectMac = "laptopcomputer"
    case skipBack = "gobackward.30"
    case skipForward = "goforward.30"
    case send = "arrow.up"
    case sleepTimer = "moon"
    case chapters = "list.bullet"
    case thoughtsPane = "sidebar.right"

    /// The SF Symbol name.
    public var systemName: String { rawValue }

    /// Where the symbol is used (exported for other platforms).
    public var use: String {
        switch self {
        case .areaLibrary: "Library area in the tab bar and sidebar"
        case .areaThoughts: "Thoughts area in the tab bar and sidebar"
        case .areaInbox: "Inbox area in the tab bar and sidebar"
        case .back: "Back button (navigation bar, reader chrome)"
        case .search: "Search (navigation bar, reader chrome)"
        case .settings: "Settings (navigation bar)"
        case .readerSettings: "Large content viewer image of the reader's \"Aa\" button"
        case .bookmark: "Reader bookmark, not set"
        case .bookmarkSet: "Reader bookmark, set"
        case .play: "Play (mini-player, audio block)"
        case .pause: "Pause (mini-player, audio block)"
        case .stepEarlier: "Move an audio range edge earlier"
        case .stepLater: "Move an audio range edge later"
        case .lookUp: "Look up action"
        case .starFull: "Rating star, full"
        case .starHalf: "Rating star, half"
        case .starEmpty: "Rating star, empty"
        case .disclosure: "Disclosure chevron on a row that opens a detail view (Inbox rows, action cards)"
        case .dismiss: "Close a full-screen player"
        case .more: "More actions (navigation bar)"
        case .edit: "Edit a record; Add a record in onboarding"
        case .importFile: "Import a book (onboarding; navigation bar in Library and Inbox)"
        case .connectMac: "Connect a Mac; a paired Mac in the Inbox"
        case .skipBack: "Player: back 30 seconds"
        case .skipForward: "Player: forward 30 seconds"
        case .send: "Send a question (Ask)"
        case .sleepTimer: "Player sleep timer"
        case .chapters: "Player chapters"
        case .thoughtsPane: "Show or hide the reader's Thoughts pane (iPad, regular width)"
        }
    }
}

/// Text that is a glyph rather than a phrase: the reader settings button shows "Aa" (Section
/// 4.4.7) and is labelled "Reader settings" for VoiceOver.
public enum GlyphText {
    public static let readerSettings = "Aa"
}
