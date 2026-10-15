import Foundation
import SylviaDesign

// Static fixture data for the interaction prototype. Every work is in the public domain in the USA
// (Middlemarch, Walden, Meditations as on the boards; Moby-Dick, The Count of Monte Cristo,
// Montaigne's Essays in Cotton's translation, The Brothers Karamazov in Garnett's translation,
// Frankenstein and Leaves of Grass as Inbox titles). Quotations are the works' own text. Names of
// sources ("Studio") and the example AI endpoint (example.com) are fixture data; nothing is sent.

enum WorkID: String, CaseIterable, Hashable, Sendable {
    case middlemarch, walden, meditations, mobyDick, karamazov
}

enum EditionKind: Sendable, Hashable {
    case epub, audiobook

    var label: String {
        switch self {
        case .epub: "EPUB"
        case .audiobook: "Audiobook"
        }
    }

    var symbol: ControlSymbol {
        switch self {
        case .epub: .lookUp
        case .audiobook: .play
        }
    }
}

struct Edition: Identifiable, Sendable, Hashable {
    let id: String
    let kind: EditionKind
    let source: String
    let size: String
    let position: String?
    var availability: Availability
}

struct HistoryEntry: Identifiable, Sendable, Hashable {
    let id: Int
    let date: String
    let text: String
}

struct Work: Identifiable, Sendable, Hashable {
    let id: WorkID
    let title: String
    let author: String
    let meta: String
    var rating: RatingValue?
    var editions: [Edition]
    let history: [HistoryEntry]
    let readingLine: String?
    let filters: Set<LibraryFilter>

    /// The work's availability as the Library row shows it: on this device when any edition is.
    var availability: Availability {
        if editions.contains(where: { $0.availability == .onThisDevice }) { return .onThisDevice }
        if let remote = editions.first(where: { if case .notOnThisDevice = $0.availability { true } else { false } }) {
            return remote.availability
        }
        return .recordOnly
    }
}

enum LibraryFilter: String, CaseIterable, Hashable, Sendable {
    case all, reading, listening, onDevice
}

enum Fixtures {
    static let source = "Studio"
    static let host = "api.example.com"
    static let model = "example-model-1"

    /// Example state sentences: the reason, next-step and status-detail sentences the prototype
    /// shows beside a vocabulary phrase. They are fixture text, not vocabulary. Plan Section 4.4.9
    /// says no view declares a literal state string and a screen requests every status phrase
    /// through the vocabulary; the vocabulary has no reasons, next steps or details yet (report
    /// Open questions 4 and 12), so the prototype keeps every such sentence here, in one place, for
    /// review, and a product screen must take them from the vocabulary once it has them (ADR-0013
    /// Section 11, exception 1). The status phrases themselves always come from the vocabulary
    /// (`Status`, `Vocabulary`), and the design lint rejects a phrase literal here as anywhere.
    enum ExampleCopy {
        /// Player: the excerpt was preserved (after its range).
        static let excerptKeptAfterRemoval = "Kept even if you remove the audiobook."
        /// Audio capture detail: the edited excerpt was preserved.
        static let excerptKeptIfRemoved = "Kept even if the audiobook is removed."
        /// Player: the excerpt failed, the moment (bookmark) survived.
        static let excerptUnreadableMomentKept = "The audiobook file could not be read. The moment itself is kept."
        /// Audio capture detail: the edited excerpt failed.
        static let excerptUnreadable = "The audiobook file could not be read."
        /// Player and audio capture detail: the moment itself was not written (Open question 12).
        static let momentNotWritten = "The moment could not be written, so nothing was kept. Tap to try again."
        /// Impact report: why waiting is the safe choice.
        static let pendingExcerptReason = "One excerpt is still being preserved."
        static let pendingExcerptNextStep = "Removing now would lose its audio. Waiting is the safe choice."
        /// Inbox detail of a verifying item: nothing for the user to do.
        static let verifyingNothingToDo = "Nothing to do here. The book is offered once every part matches."
        /// Inbox: the source Mac's connection.
        static let sourceConnected = "Connected on the local network · 2 waiting there"
    }

    static let works: [Work] = [
        Work(id: .middlemarch, title: "Middlemarch", author: "George Eliot",
             meta: "1871 to 1872 · English · A Study of Provincial Life",
             rating: RatingValue(storedValue: 9),
             editions: [
                Edition(id: "mm-epub", kind: .epub, source: "Standard Ebooks", size: "1.2 MB",
                        position: "Book II, ch. 20 · 38%", availability: .onThisDevice),
                Edition(id: "mm-audio", kind: .audiobook, source: "LibriVox recording", size: "35 files · 32h 10m · 1.9 GB",
                        position: "Part 14 · 20h 58m left", availability: .onThisDevice),
             ],
             history: [
                HistoryEntry(id: 1, date: "12 Aug 2026", text: "2nd read started · listening and reading"),
                HistoryEntry(id: 2, date: "3 Mar 2019", text: "1st read finished · paperback, added by hand"),
             ],
             readingLine: "Book II, ch. 20", filters: [.all, .reading, .listening, .onDevice]),
        Work(id: .walden, title: "Walden", author: "Henry David Thoreau", meta: "1854 · English",
             rating: nil,
             editions: [Edition(id: "wa-epub", kind: .epub, source: "Standard Ebooks", size: "0.6 MB",
                                position: "62%", availability: .onThisDevice)],
             history: [HistoryEntry(id: 1, date: "2 Sep 2026", text: "1st read started")],
             readingLine: "Reading · 62%", filters: [.all, .reading, .onDevice]),
        Work(id: .meditations, title: "Meditations", author: "Marcus Aurelius",
             meta: "c. 170 to 180 · translated by George Long",
             rating: RatingValue(storedValue: 9),
             editions: [],
             history: [HistoryEntry(id: 1, date: "14 Nov 2024", text: "1st read finished · paperback, added by hand")],
             readingLine: "Finished 2024", filters: [.all]),
        Work(id: .mobyDick, title: "Moby-Dick", author: "Herman Melville", meta: "1851 · English",
             rating: nil,
             editions: [Edition(id: "md-audio", kind: .audiobook, source: "LibriVox recording", size: "136 files · 24h 50m · 1.4 GB",
                                position: nil, availability: .notOnThisDevice(source: source))],
             history: [HistoryEntry(id: 1, date: "30 Sep 2026", text: "Added from Studio")],
             readingLine: nil, filters: [.all, .listening]),
        Work(id: .karamazov, title: "The Brothers Karamazov", author: "Fyodor Dostoevsky",
             meta: "1880 · translated by Constance Garnett", rating: nil,
             editions: [Edition(id: "bk-epub", kind: .epub, source: "Studio", size: "2.1 MB", position: nil,
                                availability: .onThisDevice)],
             history: [HistoryEntry(id: 1, date: "Today", text: "Imported from Studio")],
             readingLine: nil, filters: [.all, .onDevice]),
    ]

    // MARK: Reader

    static let chapterLabel = "Book II · Old and Young · Chapter 20"
    static let readerParagraphs: [String] = [
        "Not that this inward amazement of Dorothea's was anything very exceptional: many souls in their young nudity are tumbled out among incongruities and left to \"find their feet\" among them, while their elders go about their business.",
        "Nor can I suppose that when Mrs. Casaubon is discovered in a fit of weeping six weeks after her wedding, the situation will be regarded as tragic. Some discouragement, some faintness of heart at the new real future which replaces the imaginary, is not unusual, and we do not expect people to be deeply moved by what is not unusual.",
        "That element of tragedy which lies in the very fact of frequency, has not yet wrought itself into the coarse emotion of mankind; and perhaps our frames could hardly bear much of it. If we had a keen vision and feeling of all ordinary human life, it would be like hearing the grass grow and the squirrel's heart beat, and we should die of that roar which lies on the other side of silence. As it is, the quickest of us walk about well wadded with stupidity.",
    ]
    /// The saved highlight in paragraph 1 (Ochre fill and underline).
    static let highlighted = "many souls in their young nudity are tumbled out among incongruities and left to \"find their feet\" among them,"
    /// The passage the prototype selects in paragraph 3.
    static let selected = "If we had a keen vision and feeling of all ordinary human life, it would be like hearing the grass grow and the squirrel's heart beat, and we should die of that roar which lies on the other side of silence."
    static let readerSource = ["Middlemarch", "Book II, ch. 20"]

    // MARK: Thoughts

    static let question = "What does \"the roar which lies on the other side of silence\" mean here?"
    static let answer: [AnswerSegment] = [
        .text("Eliot is describing a limit on perception. If we could feel \"all ordinary human life\" at full strength, it would be as overwhelming as \"hearing the grass grow and the squirrel's heart beat\""),
        .citation(Citation("c1", isResolved: true)),
        .text(". The \"roar\" is the total weight of other people's inner lives; \"silence\" is the ordinary numbness that protects us from it"),
        .citation(Citation("c2", isResolved: false)),
        .text("."),
    ]

    struct Thought: Identifiable, Sendable, Hashable {
        let id: String
        let content: CaptureCardContent
        let details: [String]
        let time: String
        let day: Day
        let work: WorkID

        enum Day: String, CaseIterable, Sendable { case today, yesterday, earlier

            var label: String {
                switch self {
                case .today: "Today"
                case .yesterday: "Yesterday"
                case .earlier: "Earlier"
                }
            }
        }
    }

    static let thoughts: [Thought] = [
        Thought(id: "t-quote", content: .quote(text: selected, yourNote: "Eliot's case for partial sympathy: total perception would destroy us."),
                details: ["Middlemarch", "Bk II, ch. 20"], time: "14:02", day: .today, work: .middlemarch),
        Thought(id: "t-audio", content: .audio(durationSeconds: 30, waveformSeed: "middlemarch-14-1140", transcript: nil,
                                               yourNote: "Lydgate's \"spots of commonness\". Worth finding the exact wording."),
                details: ["Middlemarch", "Part 14"], time: "11:40", day: .today, work: .middlemarch),
        Thought(id: "t-generated", content: .generated(question: "What does Thoreau mean by \"live deliberately\"?", answer: [
                    .text("He means choosing the terms of one's life rather than accepting them: to \"front only the essential facts of life\""),
                    .citation(Citation("c1", isResolved: true)),
                    .text("."),
                ], status: .complete),
                details: ["Walden", host, model], time: "21:15", day: .yesterday, work: .walden),
        Thought(id: "t-note", content: .note(text: "Casaubon's \"Key to all Mythologies\" as a portrait of a project that cannot end."),
                details: ["Middlemarch", "Book I, ch. 10"], time: "Sat", day: .earlier, work: .middlemarch),
        Thought(id: "t-word", content: .word(headword: "incongruities", sentence: readerParagraphs[0],
                                             yourNote: "Eliot's word for the gap between hope and circumstance."),
                details: ["Middlemarch", "Bk II, ch. 20"], time: "Fri", day: .earlier, work: .middlemarch),
        Thought(id: "t-meditations", content: .quote(text: "Begin the morning by saying to thyself, I shall meet with the busy-body, the ungrateful, arrogant, deceitful, envious, unsocial.", yourNote: nil),
                details: ["Meditations", "Book II"], time: "Thu", day: .earlier, work: .meditations),
        Thought(id: "t-walden", content: .quote(text: "I went to the woods because I wished to live deliberately, to front only the essential facts of life, and see if I could not learn what it had to teach, and not, when I came to die, discover that I had not lived.", yourNote: nil),
                details: ["Walden", "Where I Lived"], time: "Wed", day: .earlier, work: .walden),
    ]

    // MARK: Inbox

    enum InboxItemID: String, CaseIterable, Hashable, Sendable {
        case monteCristo, essays, karamazov, frankenstein, walden, leaves, mobyDick
    }

    struct InboxItem: Identifiable, Sendable, Hashable {
        let id: InboxItemID
        let title: String
        let kind: String?
        var state: ImportState
        var indexingContinues: Bool = false
        let detail: String?
        var progress: Double?
        let section: Section
        /// The full reason and next steps behind Resolve (Needs attention) or the review choice.
        let reason: String?
        let nextSteps: [String]

        enum Section: String, CaseIterable, Sendable { case transfers, review, fromSource }
    }

    static let inbox: [InboxItem] = [
        InboxItem(id: .monteCristo, title: "The Count of Monte Cristo", kind: "audiobook", state: .acquiring, detail: nil,
                  progress: 0.6, section: .transfers, reason: nil, nextSteps: []),
        InboxItem(id: .essays, title: "Essays", kind: "EPUB", state: .validating,
                  detail: "Checking each part against the Mac's digest", progress: nil, section: .transfers,
                  reason: "Each part is checked against the digest the Mac recorded before the book is offered.", nextSteps: []),
        InboxItem(id: .karamazov, title: "The Brothers Karamazov", kind: "EPUB", state: .ready, indexingContinues: true,
                  detail: nil, progress: nil, section: .transfers, reason: nil, nextSteps: []),
        InboxItem(id: .frankenstein, title: "Frankenstein.epub", kind: nil, state: .unsupported, detail: "Protected by DRM",
                  progress: nil, section: .transfers,
                  reason: "This EPUB is protected by DRM, so Sylvia cannot open its text.",
                  nextSteps: ["Import a copy without DRM, for example the Standard Ebooks edition.",
                              "Or remove this item. Nothing else in your library changes."]),
        InboxItem(id: .walden, title: "Walden", kind: "EPUB", state: .needsReview,
                  detail: "Looks like a work already in your library", progress: nil, section: .review,
                  reason: "Same title and author as Walden in your library, different file. Nothing is merged until you choose.",
                  nextSteps: []),
        InboxItem(id: .leaves, title: "Leaves of Grass", kind: "EPUB", state: .waitingForSource,
                  detail: "Studio is asleep. Nothing to do here.", progress: nil, section: .fromSource, reason: nil, nextSteps: []),
        InboxItem(id: .mobyDick, title: "Moby-Dick", kind: "audiobook", state: .created,
                  detail: "Starts after the current transfer", progress: nil, section: .fromSource, reason: nil, nextSteps: []),
    ]

    /// Bytes of the Monte Cristo transfer: 5.2 GB in total.
    static let monteCristoTotal: Int64 = 5_200_000_000
}
