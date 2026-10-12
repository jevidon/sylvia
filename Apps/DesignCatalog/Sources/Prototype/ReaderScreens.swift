import SwiftUI
import SylviaDesign

/// The reader as a full-screen flow: the reader, then Ask about this passage pushed on top.
struct ReaderFlow: View {
    @Environment(PrototypeModel.self) private var model

    var body: some View {
        @Bindable var model = model
        NavigationStack(path: $model.readerPath) {
            ReaderScreen().destinations()
        }
    }
}

/// Reader with a static passage (Section 9.1, 4.4.7): minimal chrome, the saved highlight with its
/// underline and margin dot, a selection with the selection menu, the capture sheet, and on iPad in
/// regular width the Thoughts pane beside the text (Section 4.1: "adapt to a side pane on iPad").
struct ReaderScreen: View {
    @Environment(PrototypeModel.self) private var model
    @Environment(\.horizontalSizeClass) private var sizeClass

    var body: some View {
        @Bindable var model = model
        AuditedScreen("reader") {
            HStack(spacing: 0) {
                ReaderChrome(title: "Middlemarch", isBookmarked: model.bookmarked,
                             progress: ProgressRule(fraction: 0.38, position: .chapter(20, of: 86), secondsRemaining: 12 * 60),
                             onBack: closeReader, onSettings: {}, onBookmark: { model.bookmarked.toggle() },
                             onSearch: {}) {
                    ScrollViewReader { proxy in
                        ScrollView {
                            VStack(alignment: .leading, spacing: Spacing.m) {
                                SectionLabel(Fixtures.chapterLabel)
                                ReadingParagraph(Fixtures.readerParagraphs[0], highlighted: Fixtures.highlighted,
                                                 marksSavedThought: true)
                                ReadingParagraph(Fixtures.readerParagraphs[1])
                                selectableParagraph
                                if model.selectionActive {
                                    SelectionMenu { action in model.selectionAction(action) }
                                        .frame(maxWidth: .infinity)
                                        .id(Self.selectionMenuID)
                                }
                            }
                            .padding(.horizontal, sizeClass == .regular ? Spacing.gutterPad : Spacing.gutterPhone)
                            .padding(.vertical, Spacing.s)
                        }
                        // The selection menu belongs beside the selection: bring it into view
                        // when a passage is selected (no animation; Section 4.4.4 motion rules).
                        .task { if model.selectionActive { proxy.scrollTo(Self.selectionMenuID, anchor: .bottom) } }
                        .onChange(of: model.selectionActive) { _, active in
                            if active { proxy.scrollTo(Self.selectionMenuID, anchor: .bottom) }
                        }
                    }
                }
                .overlay(alignment: .topTrailing) {
                    if sizeClass == .regular && !model.readerPaneVisible {
                        SylviaIconButton(systemImage: ControlSymbol.thoughtsPane.systemName, label: "Show thoughts") {
                            model.readerPaneVisible = true
                        }
                        .padding(.top, ComponentMetrics.minimumTarget + Spacing.xs)
                        .padding(.trailing, Spacing.xs)
                    }
                }
                if sizeClass == .regular && model.readerPaneVisible {
                    ReaderThoughtsPane()
                        .frame(width: ComponentMetrics.readerPaneWidth)
                }
            }
            .background(ColorToken.ground.color.ignoresSafeArea())
            .sylviaScreenChrome()
        }
        .sylviaSheet(isPresented: model.captureSheetBinding(.quote), canDismiss: model.draft.canDismiss) {
            SheetPage("captureSheet") {
                CaptureSheet(draft: $model.draft, subject: $model.captureSubject, source: Fixtures.readerSource,
                             onSave: model.save, onClose: model.closeCapture,
                             onLookUp: { model.switchCapture(to: .word) },
                             onAsk: { model.askFromCapture() })
            }
        }
        .sylviaSheet(isPresented: model.captureSheetBinding(.word), canDismiss: model.draft.canDismiss) {
            SheetPage("lookUp") { LookUpSheet() }
        }
    }

    private static let selectionMenuID = "selectionMenu"

    /// The third paragraph: tapping it selects the passage the prototype captures (a stand-in for
    /// the text selection the reader adapter provides).
    private var selectableParagraph: some View {
        Button { model.selectionActive = true } label: {
            ReadingParagraph(Fixtures.readerParagraphs[2], selected: model.selectionActive ? Fixtures.selected : nil)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityHint(Text("Selects a passage"))
    }

    /// Leaves the reader only when no unsaved text would be lost (Section 11.1).
    private func closeReader() {
        guard model.draft.canDismiss else { return }
        model.readerOpen = false
        model.selectionActive = false
        model.readerPath.removeAll()
        if model.startedInReader { model.onLeave?() }
    }
}

/// The iPad reader's Thoughts pane (board "iPad reader with Thoughts pane").
struct ReaderThoughtsPane: View {
    @Environment(PrototypeModel.self) private var model
    @State private var filter: LabelKey = .filterAll

    var body: some View {
        let thoughts = ThoughtFilters.apply(filter, query: "", to: model.allThoughts.filter { $0.work == .middlemarch })
        VStack(spacing: 0) {
            ScrollView {
                VStack(alignment: .leading, spacing: Spacing.m) {
                    HStack(alignment: .firstTextBaseline, spacing: Spacing.xs) {
                        Text("In this book")
                            .sylviaFont(.heading)
                            .foregroundStyle(ColorToken.ink.color)
                            .accessibilityAddTraits(.isHeader)
                            .frame(maxWidth: .infinity, alignment: .leading)
                        SylviaIconButton(systemImage: ControlSymbol.thoughtsPane.systemName, label: "Hide thoughts",
                                         isSelected: true) { model.readerPaneVisible = false }
                    }
                    FilterChips(ThoughtFilters.chips, selection: $filter)
                    ForEach(thoughts) { ThoughtCard(thought: $0) }
                    if thoughts.isEmpty {
                        BodyText("No thoughts match.", role: .callout, muted: true)
                    }
                }
                .padding(Spacing.l)
            }
            SylviaRule()
            VStack(spacing: Spacing.xs) {
                Button {
                    model.selectionActive = true
                    model.readerPath.append(.ask)
                } label: {
                    Label { Text("Ask about the selection") } icon: { CustomSymbol.prompt.image.accessibilityHidden(true) }
                }
                .buttonStyle(.sylvia(.primary))
                BodyText("Sends only the passage you selected.", role: .caption, muted: true)
            }
            .padding(Spacing.l)
        }
        .background(ColorToken.ground.color)
        .overlay(alignment: .leading) {
            // The pane's divider: a vertical hairline (Section 4.4.4: rules separate).
            Rectangle()
                .fill(ColorToken.hairline.color)
                .frame(width: Hairline.width)
                .accessibilityHidden(true)
        }
    }
}

/// Look up a word (Section 4.3 J-01 "lookup"; Section 4.4.5 Word marker): the headword, a short
/// definition, the source sentence and an optional note, saved as a Word thought with the same
/// durable-save states as the capture sheet.
struct LookUpSheet: View {
    @Environment(PrototypeModel.self) private var model

    var body: some View {
        @Bindable var model = model
        SylviaSheetContainer(title: "incongruities") {
                MarkerRow(MarkerRow.Configuration(marker: .word, details: Fixtures.readerSource))
                BodyText("Things that do not fit together, or do not suit their surroundings.")
                BodyText("From the dictionary on your phone. Nothing is sent.", role: .caption, muted: true)
                QuoteBlock(text: Fixtures.readerParagraphs[0])
                SylviaTextField(LabelKey.captureYourNote.localized, text: $model.draft.note, prompt: "Why this word")
                    .onChange(of: model.draft.note) { _, _ in model.draft.noteChanged() }
                CaptureSaveButton(state: model.draft.saveState, onSave: model.save, onClose: model.closeCapture)
        }
    }
}
