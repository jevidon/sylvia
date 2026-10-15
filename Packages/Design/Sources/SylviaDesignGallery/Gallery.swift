#if os(iOS)
import SwiftUI
import UIKit
import SylviaDesign

// The component samples shared by the snapshot tests (SylviaDesignSnapshotTests) and the design
// catalog app (Apps/DesignCatalog), so the catalog shows on a device exactly what the references
// show (G0.6 part 3; ADR-0013 Section 9). Sample names are the snapshot names; keep them stable.

/// Layout facts of the reference device the samples are framed for.
public enum GalleryLayout {
    /// iPhone 17 width in points (the snapshot reference device, ADR-0013 Section 9).
    public static let phoneWidth: CGFloat = 402
}

/// Sample content: public-domain text (Middlemarch, Walden, Meditations) as on the boards.
public enum SampleText {
    public static let quote = "If we had a keen vision and feeling of all ordinary human life, it would be like hearing the grass grow and the squirrel's heart beat, and we should die of that roar which lies on the other side of silence."
    public static let note = "Eliot's case for partial sympathy: total perception would destroy us. Set against Thoreau's \"deliberately\", who wants more vision; she counts its cost."
    public static let shortNote = "Eliot's case for partial sympathy: total perception would destroy us."
    public static let question = "What does \"the roar which lies on the other side of silence\" mean here?"
    /// The saved highlight in ``reading`` (as on the reader board).
    public static let highlighted = "many souls in their young nudity are tumbled out among incongruities and left to \"find their feet\" among them,"
    /// The selected words in ``quote``.
    public static let selected = "we should die of that roar which lies on the other side of silence."
    public static let reading = "Not that this inward amazement of Dorothea's was anything very exceptional: many souls in their young nudity are tumbled out among incongruities and left to \"find their feet\" among them, while their elders go about their business."

    /// 14:02 today, in the simulator's time zone, so "Saved" shows the same clock time on any day.
    public static var savedTime: Date {
        Calendar.current.date(bySettingHour: 14, minute: 2, second: 0, of: Date(timeIntervalSince1970: 1_790_000_000))!
    }
}

/// A component sample: what the snapshot shows and how it is framed.
@MainActor
public struct Sample {
    public let name: String
    /// The canvas width in points.
    public let width: CGFloat
    /// A fixed height, or nil to fit the content.
    public let height: CGFloat?
    public let sizeClass: UIUserInterfaceSizeClass
    public let content: AnyView

    /// Framed on the ground with the iPhone gutter (20 pt), or edge to edge for bars and sheets.
    init(_ name: String, width: CGFloat = GalleryLayout.phoneWidth, height: CGFloat? = nil, gutter: Bool = true,
         sizeClass: UIUserInterfaceSizeClass = .compact, @ViewBuilder content: () -> some View) {
        self.name = name
        self.width = width
        self.height = height
        self.sizeClass = sizeClass
        let body = content()
        self.content = AnyView(
            body
                .padding(gutter ? Spacing.gutterPhone : 0)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(ColorToken.ground.color)
        )
    }
}

/// Every Section 4.4.7 component, with the states the tests compare.
@MainActor
public enum Gallery {
    /// Sample names, in order (a test checks they match ``samples``).
    public nonisolated static let names: [String] = [
        "buttons", "statusPills", "availabilityBadges", "markerRows", "captureCard.quote", "captureCard.note",
        "captureCard.audio", "captureCard.generated", "captureCard.word", "rating", "progressRule", "tabBar",
        "navigationBar", "sidebar", "miniPlayer", "captureSheet.quote", "captureSheet.audio",
        "captureSheet.saveStates", "selectionMenu", "typographicCover", "readerChrome", "impactReport",
        // Part 3: screen parts the interaction prototype is built from (ADR-0013 Section 11).
        "areaTitle", "card", "filterChips", "inboxRows", "textField", "statusBanners", "readingParagraph",
        "playPauseButton", "actionCards",
    ]

    public static func sample(_ name: String) -> Sample {
        guard let s = samples.first(where: { $0.name == name }) else { preconditionFailure("no sample \(name)") }
        return s
    }

    public static let pillStates: [(String, StatusPill.Configuration)] = [
        ("queued", StatusPill.Configuration(importState: .created)!),
        ("receiving", StatusPill.Configuration(importState: .acquiring)!),
        ("verifying", StatusPill.Configuration(importState: .validating)!),
        ("preparing", StatusPill.Configuration(importState: .committing)!),
        ("waiting", StatusPill.Configuration(importState: .waitingForSource, source: "Studio")!),
        ("ready", StatusPill.Configuration(importState: .ready)!),
        ("readyIndexing", StatusPill.Configuration(importState: .ready, indexingContinues: true)!),
        ("needsReview", StatusPill.Configuration(importState: .needsReview)!),
        ("needsAttention", StatusPill.Configuration(importState: .failedRetryable)!),
    ]

    public static let markerRows: [(String, MarkerRow.Configuration)] = [
        ("quote", .init(marker: .quote, details: ["Middlemarch", "Bk II, ch. 20"], timestamp: "14:02")),
        ("note", .init(marker: .note, details: ["Middlemarch"], timestamp: "14:05")),
        ("audio", .init(marker: .audio, details: ["Middlemarch", "Part 14", "0:30"], timestamp: "11:40")),
        ("generated", .init(marker: .generated, details: ["Walden", "api.example.com"], timestamp: "21:15")),
        ("word", .init(marker: .word, details: ["Meditations"], timestamp: "09:12")),
        ("attention", .init(marker: .attention, details: [])),
        ("pending", .init(marker: .pending, details: [])),
        ("unknownKind", .init(captureKind: "sketch", details: ["Walden"], timestamp: "08:00")),
    ]

    /// The Thoughts filter chips (Section 4.4.5: the marker labels, verbatim).
    public static let thoughtFilters: [FilterChip<LabelKey>] = [
        LabelKey.filterAll, .filterQuotes, .filterNotes, .filterAudio, .filterGenerated, .filterWords,
    ].map { FilterChip($0, label: $0.localized) }

    public static let buttonRoles: [SylviaButtonRole] = [.primary, .secondary, .quiet, .destructive]

    public static var samples: [Sample] {
        [
            Sample("buttons") {
                VStack(spacing: Spacing.s) {
                    Button("Continue") {}.buttonStyle(.sylvia(.primary))
                        .environment(\.sylviaAuditScope, "primary")
                    Button("Read") {}.buttonStyle(.sylvia(.secondary))
                        .environment(\.sylviaAuditScope, "secondary")
                    Button("Attach another edition") {}.buttonStyle(.sylvia(.quiet))
                        .environment(\.sylviaAuditScope, "quiet")
                    Button(Status.deleteRecordAndThoughts.text()) {}.buttonStyle(.sylvia(.destructive))
                        .environment(\.sylviaAuditScope, "destructive")
                        .padding(.top, Spacing.xl)
                }
            },
            Sample("statusPills") {
                VStack(alignment: .leading, spacing: Spacing.xs) {
                    ForEach(pillStates, id: \.0) { name, config in
                        StatusPill(config).environment(\.sylviaAuditScope, name)
                    }
                }
            },
            Sample("availabilityBadges") {
                VStack(alignment: .leading, spacing: Spacing.xs) {
                    AvailabilityBadge(.onThisDevice).environment(\.sylviaAuditScope, "onDevice")
                    AvailabilityBadge(.notOnThisDevice(source: "Studio")).environment(\.sylviaAuditScope, "notOnDevice")
                    AvailabilityBadge(.recordOnly).environment(\.sylviaAuditScope, "recordOnly")
                }
            },
            Sample("markerRows") {
                VStack(alignment: .leading, spacing: Spacing.s) {
                    ForEach(markerRows, id: \.0) { name, config in
                        MarkerRow(config).environment(\.sylviaAuditScope, name)
                    }
                    AttentionRow(reason: "One excerpt is still being preserved.",
                                 nextStep: "Removing now would lose its audio. Waiting is the safe choice.")
                }
            },
            Sample("captureCard.quote") {
                CaptureCard(.quote(text: SampleText.quote, yourNote: SampleText.shortNote),
                            details: ["Middlemarch", "Bk II, ch. 20"], timestamp: "14:02")
            },
            Sample("captureCard.note") {
                CaptureCard(.note(text: SampleText.note), details: ["Middlemarch"], timestamp: "14:05")
            },
            Sample("captureCard.audio") {
                VStack(spacing: Spacing.s) {
                    CaptureCard(.audio(durationSeconds: 30, waveformSeed: "middlemarch-14-1140", transcript: nil,
                                       yourNote: "Lydgate's \"spots of commonness\". Worth finding the exact wording."),
                                details: ["Middlemarch", "Part 14"], timestamp: "11:40")
                    CaptureCard(.audio(durationSeconds: 42, waveformSeed: "meditations-02", transcript:
                                        "Begin the morning by saying to thyself, I shall meet with the busy-body.",
                                       yourNote: nil),
                                details: ["Meditations", "Section 2"], timestamp: "07:15", isPlaying: true)
                }
            },
            Sample("captureCard.generated") {
                CaptureCard(.generated(question: SampleText.question, answer: [
                    .text("Eliot is describing a limit on perception. If we could feel \"all ordinary human life\" at full strength, it would be as overwhelming as \"hearing the grass grow\""),
                    .citation(Citation("c1", isResolved: true)),
                    .text(". The \"roar\" is the weight of other inner lives"),
                    .citation(Citation("c2", isResolved: false)),
                    .text("."),
                ], status: .complete), details: ["Middlemarch", "api.example.com", "example-model-1"], timestamp: "21:15")
            },
            Sample("captureCard.word") {
                CaptureCard(.word(headword: "incongruities", sentence: SampleText.reading,
                                  yourNote: "Eliot's word for the gap between hope and circumstance."),
                            details: ["Middlemarch", "Bk II, ch. 20"], timestamp: "09:12")
            },
            Sample("rating") {
                VStack(alignment: .leading, spacing: Spacing.s) {
                    RatingView(RatingValue(storedValue: 9)).environment(\.sylviaAuditScope, "nine")
                    RatingView(RatingValue(storedValue: 4)).environment(\.sylviaAuditScope, "four")
                    RatingView(nil).environment(\.sylviaAuditScope, "none")
                    RatingView(value: .constant(RatingValue(storedValue: 7))).environment(\.sylviaAuditScope, "editable")
                }
            },
            Sample("progressRule") {
                VStack(alignment: .leading, spacing: Spacing.l) {
                    ProgressRule(fraction: 0.38, position: .chapter(20, of: 86), secondsRemaining: 12 * 60)
                    ProgressRule(fraction: 0.4, position: .part(14, of: 35), secondsRemaining: 20 * 3600 + 58 * 60)
                    ProgressRule(fraction: 0.6)
                }
            },
            Sample("tabBar", gutter: false) {
                VStack(spacing: Spacing.l) {
                    SylviaTabBar(selection: .constant(.library), inboxNeedsAttention: false)
                    SylviaTabBar(selection: .constant(.thoughts), inboxNeedsAttention: true)
                }
            },
            Sample("navigationBar", gutter: false) {
                VStack(spacing: Spacing.l) {
                    SylviaNavigationBar(trailing: [.search {}, .settings {}])
                    SylviaNavigationBar(title: "Ask about this passage", backTitle: "Reader", onBack: {})
                }
            },
            Sample("sidebar", width: ComponentMetrics.sidebarWidth, height: 420, gutter: false, sizeClass: .regular) {
                SylviaSidebar(selection: .constant(.thoughts), inboxNeedsAttention: true)
            },
            Sample("miniPlayer") {
                MiniPlayer(title: "Middlemarch", author: "George Eliot", caption: "Part 14 · 1.25×",
                           secondsRemaining: 20 * 3600 + 58 * 60, isPlaying: true,
                           onOpen: {}, onCapture: {}, onPlayPause: {})
                    .padding(.bottom, Spacing.xl)
            },
            Sample("captureSheet.quote", gutter: false) {
                CaptureSheetSample(subject: .quote(text: SampleText.quote), note: SampleText.shortNote, state: .draft)
            },
            Sample("captureSheet.audio", gutter: false) {
                CaptureSheetSample(subject: .audio(AudioRange(start: 672_000, end: 702_000, sourceDuration: 3_600_000)),
                                   note: "", state: .draft)
            },
            Sample("captureSheet.saveStates") {
                VStack(spacing: Spacing.s) {
                    CaptureSaveButton(state: .draft, onSave: {}, onClose: {})
                        .environment(\.sylviaAuditScope, "draft")
                    CaptureSaveButton(state: .saving, onSave: {}, onClose: {})
                        .environment(\.sylviaAuditScope, "saving")
                    CaptureSaveButton(state: .saved(SampleText.savedTime), onSave: {}, onClose: {})
                        .environment(\.sylviaAuditScope, "saved")
                    CaptureSaveButton(state: .failed, onSave: {}, onClose: {})
                        .environment(\.sylviaAuditScope, "failed")
                }
            },
            Sample("selectionMenu") {
                SelectionMenu { _ in }
            },
            Sample("typographicCover") {
                // Two rows, so the sample fits the narrowest iPhone iOS 26 supports (375 pt) in the
                // design catalog.
                VStack(alignment: .leading, spacing: Spacing.m) {
                    HStack(alignment: .top, spacing: Spacing.m) {
                        TypographicCover(title: "Middlemarch", author: "George Eliot", shape: .list, width: 112)
                        TypographicCover(title: "Walden", author: "Henry David Thoreau", shape: .list, width: 112)
                    }
                    HStack(alignment: .top, spacing: Spacing.m) {
                        TypographicCover(title: "Meditations", author: "Marcus Aurelius", shape: .square, width: 96)
                        TypographicCover(title: "Moby-Dick", author: nil, shape: .square, width: ComponentMetrics.miniPlayerCover)
                    }
                }
            },
            Sample("readerChrome", gutter: false) {
                ReaderChrome(title: "Middlemarch", isBookmarked: true,
                             progress: ProgressRule(fraction: 0.38, position: .chapter(20, of: 86), secondsRemaining: 12 * 60),
                             onBack: {}, onSettings: {}, onBookmark: {}, onSearch: {}) {
                    Text(SampleText.reading)
                        .sylviaFont(.reading)
                        .foregroundStyle(ColorToken.ink.color)
                        .padding(.horizontal, Spacing.l)
                        .padding(.vertical, Spacing.s)
                }
            },
            Sample("impactReport", gutter: false) {
                ImpactReport(title: "Remove the audiobook download?", lines: [
                    ImpactLine(1, "Frees 1.9 GB on this phone."),
                    ImpactLine(2, "Keeps 23 thoughts, 4 audio excerpts, your history, rating and recommendations."),
                    ImpactLine(3, "Can be downloaded again from Studio, last seen today."),
                ], pending: .init(reason: "One excerpt is still being preserved.",
                                  nextStep: "Removing now would lose its audio. Waiting is the safe choice."),
                safeChoice: .init("Wait, then remove") {}, secondary: .init("Cancel") {},
                destructive: .init("Remove now and lose that excerpt") {})
            },
            Sample("areaTitle") {
                VStack(alignment: .leading, spacing: Spacing.s) {
                    AreaTitle(LabelKey.areaLibrary.localized, trailing: [.search {}, .settings {}])
                    SectionLabel("Continue")
                    SylviaRule()
                    SectionLabel("Queued on Studio")
                }
            },
            Sample("card") {
                VStack(spacing: Spacing.s) {
                    SylviaCard {
                        Text("Middlemarch").sylviaFont(.title).foregroundStyle(ColorToken.ink.color)
                        Text("George Eliot · 2nd read").sylviaFont(.callout).foregroundStyle(ColorToken.muted.color)
                    }
                    SylviaCard(padded: false) {
                        Text("Audiobook download").sylviaFont(.body).foregroundStyle(ColorToken.ink.color)
                            .padding(ComponentMetrics.cardPadding)
                        SylviaRule()
                        Text("EPUB download").sylviaFont(.body).foregroundStyle(ColorToken.ink.color)
                            .padding(ComponentMetrics.cardPadding)
                    }
                }
            },
            Sample("filterChips") {
                VStack(alignment: .leading, spacing: Spacing.s) {
                    FilterChips(thoughtFilters, selection: .constant(LabelKey.filterAll))
                    FilterChips(thoughtFilters, selection: .constant(LabelKey.filterQuotes))
                }
            },
            Sample("inboxRows") {
                SylviaCard(padded: false) {
                    InboxRow(title: "The Count of Monte Cristo", kind: "audiobook",
                             pill: StatusPill.Configuration(importState: .acquiring)!,
                             detail: Status.bytesVerified(verified: 3_100_000_000, total: 5_200_000_000).text(),
                             detailIsValue: true, progress: 0.6,
                             trailing: .action(title: LabelKey.controlPause.localized, symbol: .pause) {})
                    SylviaRule()
                    InboxRow(title: "Essays", kind: "EPUB", pill: StatusPill.Configuration(importState: .validating)!,
                             detail: "Checking each part against the Mac's digest", trailing: .disclosure {})
                    SylviaRule()
                    InboxRow(title: "The Brothers Karamazov", kind: "EPUB",
                             pill: StatusPill.Configuration(importState: .ready, indexingContinues: true)!,
                             detail: Status.indexingChapters(indexed: 9, total: 96).text(),
                             trailing: .action(title: "Open") {})
                    SylviaRule()
                    InboxRow(title: "Frankenstein.epub", pill: StatusPill.Configuration(importState: .unsupported)!,
                             detail: "Protected by DRM", trailing: .action(title: "Resolve") {})
                    SylviaRule()
                    InboxRow(title: "Walden", kind: "EPUB", pill: StatusPill.Configuration(importState: .needsReview)!,
                             detail: "Looks like a work already in your library", trailing: .disclosure {})
                    SylviaRule()
                    InboxRow(title: "Leaves of Grass", kind: "EPUB",
                             pill: StatusPill.Configuration(importState: .waitingForSource, source: "Studio")!,
                             detail: "Studio is asleep")
                }
            },
            Sample("textField") {
                VStack(spacing: Spacing.s) {
                    SylviaTextField("Search", text: .constant(""), prompt: "Search quotes, notes and answers",
                                    symbol: .search)
                    SylviaTextField("Question", text: .constant(SampleText.question), prompt: "Ask a follow-up")
                }
            },
            Sample("statusBanners") {
                VStack(spacing: Spacing.s) {
                    StatusBanner(.pending(.momentSavedPreservingAudio), detail: "11:12.0 to 11:42.0")
                    StatusBanner(.ready(.audioExcerptSaved), detail: "Kept even if you remove the audiobook.",
                                 actionTitle: "Add note") {}
                    StatusBanner(.attention(.excerptNotPreserved), detail: "The audiobook file could not be read.") {}
                }
            },
            Sample("readingParagraph") {
                VStack(alignment: .leading, spacing: Spacing.m) {
                    ReadingParagraph(SampleText.reading, highlighted: SampleText.highlighted, marksSavedThought: true)
                        .environment(\.sylviaAuditScope, "highlight")
                    ReadingParagraph(SampleText.quote, selected: SampleText.selected)
                        .environment(\.sylviaAuditScope, "selection")
                }
            },
            Sample("playPauseButton") {
                HStack(spacing: Spacing.xl) {
                    PlayPauseButton(isPlaying: true) {}.environment(\.sylviaAuditScope, "playing")
                    PlayPauseButton(isPlaying: false) {}.environment(\.sylviaAuditScope, "paused")
                    PlayPauseButton(isPlaying: false, diameter: ComponentMetrics.playControl) {}
                        .environment(\.sylviaAuditScope, "small")
                }
            },
            Sample("actionCards") {
                VStack(spacing: Spacing.s) {
                    ActionCard(symbol: .importFile, title: "Import a book",
                               detail: "EPUB, PDF or audiobook from Files, AirDrop or a link.") {}
                    ActionCard(symbol: .connectMac, title: "Connect a Mac",
                               detail: "Pair once. Pull books over your network or a cable.") {}
                }
            },
        ]
    }
}

/// A capture sheet with fixed state for snapshots.
public struct CaptureSheetSample: View {
    @State var draft: CaptureDraft
    @State var subject: CaptureSubject

    public init(subject: CaptureSubject, note: String, state: CaptureSaveState) {
        var draft = CaptureDraft(note: note)
        switch state {
        case .draft: break
        case .saving: draft.beginSave()
        case .saved(let date): draft.beginSave(); draft.commitSucceeded(at: date, savedNote: note)
        case .failed: draft.beginSave(); draft.commitFailed()
        }
        _draft = State(initialValue: draft)
        _subject = State(initialValue: subject)
    }

    public var body: some View {
        CaptureSheet(draft: $draft, subject: $subject, source: ["Middlemarch", "Book II, ch. 20"],
                     onSave: {}, onClose: {}, onLookUp: {}, onAsk: {})
    }
}
#endif
