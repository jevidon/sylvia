import SwiftUI
import SylviaDesign

/// Thoughts (Section 4.1, 4.4.5): every capture kind with its marker treatment, the filter chips
/// that reuse the marker labels verbatim, search over saved thoughts, recent activity first.
struct ThoughtsScreen: View {
    @Environment(PrototypeModel.self) private var model
    @State private var filter: LabelKey = .filterAll
    @State private var query = ""

    var body: some View {
        AuditedScreen("thoughts") {
            ScrollView {
                VStack(alignment: .leading, spacing: Spacing.m) {
                    // The board's pencil (a free-standing note) needs a capture subject the package
                    // does not have yet; the prototype leaves it out rather than fake it.
                    AreaTitle(LabelKey.areaThoughts.localized)
                    SylviaTextField("Search thoughts", text: $query, prompt: "Search quotes, notes and answers",
                                    symbol: .search)
                    if !query.isEmpty {
                        // Search coverage is stated, never implied (Section 4.4.6).
                        BodyText(Status.savedThoughtsOnly.text(), role: .caption, muted: true)
                    }
                    FilterChips(ThoughtFilters.chips, selection: $filter)
                    let shown = ThoughtFilters.apply(filter, query: query, to: model.allThoughts)
                    if shown.isEmpty {
                        BodyText("No thoughts match.", role: .callout, muted: true)
                    }
                    ForEach(Fixtures.Thought.Day.allCases, id: \.self) { day in
                        let items = shown.filter { $0.day == day }
                        if !items.isEmpty {
                            SectionLabel(day.label)
                            ForEach(items) { thought in
                                ThoughtCard(thought: thought)
                            }
                        }
                    }
                }
                .screenGutter()
                .padding(.vertical, Spacing.m)
            }
            .background(ColorToken.ground.color.ignoresSafeArea())
            .statusBarGround()
            .sylviaScreenChrome()
        }
    }
}

/// The Thoughts filter chips: the marker labels verbatim (Section 4.4.5).
enum ThoughtFilters {
    static let chips: [FilterChip<LabelKey>] = [
        LabelKey.filterAll, .filterQuotes, .filterNotes, .filterAudio, .filterGenerated, .filterWords,
    ].map { FilterChip($0, label: $0.localized) }

    static func marker(for filter: LabelKey) -> Marker? {
        switch filter {
        case .filterQuotes: .quote
        case .filterNotes: .note
        case .filterAudio: .audio
        case .filterGenerated: .generated
        case .filterWords: .word
        default: nil
        }
    }

    static func apply(_ filter: LabelKey, query: String, to thoughts: [Fixtures.Thought]) -> [Fixtures.Thought] {
        thoughts.filter { thought in
            if let marker = marker(for: filter), thought.content.marker != marker { return false }
            let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
            return trimmed.isEmpty || thought.searchText.localizedCaseInsensitiveContains(trimmed)
        }
    }
}

/// One thought as a capture card; audio cards preview in place without moving the main position.
struct ThoughtCard: View {
    let thought: Fixtures.Thought
    @State private var previewing = false

    var body: some View {
        CaptureCard(thought.content, details: thought.details, timestamp: thought.time, isPlaying: previewing,
                    onPlay: { previewing.toggle() })
    }
}

extension Fixtures.Thought {
    /// The text search matches against (the thought's own words and its source).
    var searchText: String {
        let body: String
        switch content {
        case .quote(let text, let note): body = text + " " + (note ?? "")
        case .note(let text): body = text
        case .audio(_, _, let transcript, let note): body = (transcript ?? "") + " " + (note ?? "")
        case .generated(let question, let answer, _):
            body = question + " " + answer.compactMap { if case .text(let t) = $0 { t } else { nil } }.joined()
        case .word(let headword, let sentence, let note): body = headword + " " + sentence + " " + (note ?? "")
        }
        return body + " " + details.joined(separator: " ")
    }
}

extension PrototypeModel {
    /// Thoughts saved in this session first, then the fixtures.
    var allThoughts: [Fixtures.Thought] { savedThoughts + Fixtures.thoughts }
}
