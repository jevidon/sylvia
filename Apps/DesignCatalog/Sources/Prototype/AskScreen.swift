import SwiftUI
import SylviaDesign

/// Ask about this passage (Section 13.1, 13.4, 14.4; board "Ask about this passage"): the context
/// scope as chips with a plain statement of what is sent, the evidence, the endpoint disclosure,
/// then the request lifecycle in the vocabulary's words: "Draft · not sent", "Sending to {host}",
/// the Generated answer with resolved and unresolved citation chips and "Complete", or
/// "Interrupted · partial answer" keeping what arrived. Nothing is sent anywhere: the answer is a
/// fixture played back in parts.
struct AskScreen: View {
    @Environment(PrototypeModel.self) private var model

    var body: some View {
        @Bindable var model = model
        SubPage("ask", title: "Ask about this passage", backTitle: "Reader") {
            // Once sent, the scope is fixed: only the scope that was used is shown.
            FilterChips(model.askPhase == .draft ? AskScope.chips : AskScope.chips.filter { $0.id == model.askScope },
                        selection: $model.askScope)
            BodyText(AskScope.explanation(model.askScope), role: .callout, muted: true)
            SylviaCard {
                VStack(alignment: .leading, spacing: Spacing.xs) {
                    MarkerRow(MarkerRow.Configuration(marker: .quote, details: Fixtures.readerSource + ["c1"]))
                    QuoteBlock(text: Fixtures.selected)
                }
            }
            SylviaCard {
                ViewThatFits(in: .horizontal) {
                    HStack(alignment: .firstTextBaseline, spacing: Spacing.s) { endpoint }
                    VStack(alignment: .leading, spacing: Spacing.xs) { endpoint }
                }
            }
            switch model.askPhase {
            case .draft:
                draft
            case .sending:
                question
                StatusPill(.pending(.sendingTo(host: Fixtures.host)))
                Button("Stop") { model.stopAsking() }
                    .buttonStyle(.sylvia(.secondary))
            case .answering(let received, let finished):
                question
                answer(received: received, status: finished ? .complete : nil)
                if finished {
                    Button("Ask another question") { model.resetAsk() }
                        .buttonStyle(.sylvia(.secondary))
                } else {
                    Button("Stop") { model.stopAsking() }
                        .buttonStyle(.sylvia(.secondary))
                }
            case .interrupted(let received):
                question
                if received > 0 {
                    answer(received: received, status: .interruptedPartialAnswer)
                } else {
                    StatusPill(.attention(.interruptedPartialAnswer))
                }
                Button("Ask again") { model.resetAsk() }
                    .buttonStyle(.sylvia(.secondary))
            }
        }
    }

    @ViewBuilder private var endpoint: some View {
        BodyText(Status.endpoint(host: Fixtures.host, kind: .hosted, model: Fixtures.model).text(), role: .callout)
        Button("Change") {}
            .buttonStyle(.sylvia(.quiet, fillsWidth: false))
    }

    @ViewBuilder private var draft: some View {
        @Bindable var model = model
        SylviaTextField("Question", text: $model.askQuestion, prompt: "Ask about this passage")
        StatusPill(.pending(.draftNotSent))
        Button {
            model.send()
        } label: {
            Label { Text("Send to \(Fixtures.host)") } icon: { Image(systemName: ControlSymbol.send.systemName) }
        }
        .buttonStyle(.sylvia(.primary))
        .disabled(model.askQuestion.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
    }

    private var question: some View {
        SylviaCard {
            BodyText(model.askQuestion)
        }
    }

    private func answer(received: Int, status: Status?) -> some View {
        CaptureCard(.generated(question: model.askQuestion, answer: Array(Fixtures.answer.prefix(received)), status: status),
                    details: [Fixtures.host, Fixtures.model], timestamp: nil)
    }
}

/// Context scope chips (Section 4.4.6 "Context scope") and what each one sends.
enum AskScope {
    static let chips: [FilterChip<Status>] = [Status.scopeSelectedPassage, .scopePassageAndNearbyText,
                                             .scopeRelevantPassagesFromWork].map { FilterChip($0, label: $0.text()) }

    static func explanation(_ scope: Status) -> String {
        switch scope {
        case .scopePassageAndNearbyText:
            "The passage and the paragraphs around it are sent. Nothing from your notes or your library."
        case .scopeRelevantPassagesFromWork:
            "Passages from this book that match your question are found on your phone and sent with it. Nothing from your notes or your library."
        default:
            "Only the passage below is sent. Nothing else from the book, your notes or your library."
        }
    }
}
