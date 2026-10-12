import SwiftUI
import SylviaDesign

/// Uses the design package for every color, size and status, so the linter reports nothing.
/// Comments may mention Color(red: 1, green: 0, blue: 0), Font.system(size: 12), "#F4F2ED"
/// and "Saved" without findings.
struct GoodView: View {
    let status: Status = .saved
    let fnvPrime: UInt32 = 0x0100_0193 // a hex integer that is not a color
    let fnvOffset: UInt32 = 0x811C9DC5

    var body: some View {
        VStack(spacing: Spacing.steps[1]) {
            Text(status.text())
                .sylviaFont(.body)
                .foregroundStyle(ColorToken.ink.color)
            Text(verbatim: "Middlemarch") // a title, not a status
                .sylviaFont(.title)
            Text(verbatim: "Chapter 20 of 86")
            Text(verbatim: "Done reading Middlemarch?") // contains a forbidden word, but is not that phrase
            Text(verbatim: "Ready to pair") // a single-word phrase only matches the whole string
            Text(verbatim: "Complete the setup") /* block comment: .system(size: 9) "Error" */
            Image(systemName: "book")
                .font(.body)
            Text(Status.indexingChapters(indexed: 12, total: 40).text())
        }
        .accessibilityIdentifier("library.ready_indexing")
        .tint(ColorToken.pine.color)
    }
}

/// Near-misses for the stricter rules of review round 1: identifiers with a phrase after a dot,
/// a phrase word inside a sentence, Color.clear as a spacer, Font.Weight.black, button roles named
/// primary and secondary, and token colors in color modifiers.
struct GoodNearMisses: View {
    private let weights: [Font.Weight] = [.ultraLight, .regular, .black]

    var body: some View {
        VStack {
            Text(verbatim: "Error handling is in chapter 3")
                .accessibilityIdentifier("ask.generated")
            Text(verbatim: "Ready to pair.")
            Color.clear.frame(width: 1, height: 1)
            Text(verbatim: "x").fontWeight(.black)
            Button(action: {}) { Text(Status.saved.text()) }
                .buttonStyle(.sylvia(.secondary))
            Rectangle()
                .fill(ColorToken.pine.color)
                .shadow(color: ColorToken.shadow.color, radius: Elevation.radius)
                .tint(ColorToken.pine.color)
            Text(verbatim: "api.example.com")
        }
    }
}

let sentence = "Color is never the only carrier of meaning."
let hashtag = "#readinglist"
let interpolatedOnly = "\(Spacing.gutterPhone)"

/// Near-misses for the whole-file rules of review round 2: calls wrapped over lines with token
/// values, ternaries that choose layout edges, button roles or token colors, labels inside nested
/// calls, Markdown around a title, an identifier with underscores, color types in declarations,
/// and sizes that are not font sizes.
struct GoodWrapped: View {
    let compact = true

    var body: some View {
        VStack {
            Text(
                verbatim: "Middlemarch")
                .sylviaFont(
                    .title)
            Text(verbatim: "x")
                .padding(compact ? .horizontal : .vertical)
                .buttonStyle(.sylvia(compact ? .primary : .secondary))
                .opacity(compact ? 1 : 0.5)
                .background(StatusPill(compact ? .ready : .queued))
                .overlay(SylviaButtonLabel(role: .secondary))
                .foregroundStyle(compact
                    ? ColorToken.ink.color
                    : ColorToken.muted.color)
                .overlay(alignment: .top) { Rectangle().fill(ColorToken.hairline.color) }
                .frame(
                    width: Spacing.steps[2],
                    height: Spacing.steps[2])
            Text(verbatim: "snake_case_identifier")
            Text("**Middlemarch**, chapter 20")
        }
    }
}

extension UIColor {}
func tokenColor() -> UIColor { UIColor(ColorToken.pine.color) }
var tokenSwiftUIColor: Color { ColorToken.pine.color }
let tokenAssignment: Color = ColorToken.ink.color
let blackWeight: Font.Weight = .black
let coverRect = CGRect(origin: .zero, size: CGSize(width: 2, height: 3))
let roleChoice: SylviaButtonRole = Bool.random() ? .primary : .secondary
