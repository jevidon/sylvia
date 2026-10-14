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

/// Near-misses for the list and shape-style rules of review round 3: gradients and shape styles
/// built from tokens, a list of button roles that are not colors, and a colors: label whose value
/// is not a list literal.
struct GoodStyles: View {
    private let roles: [SylviaButtonRole] = [.primary, .secondary]
    private let tokenColors: [Color] = [ColorToken.pine.color, ColorToken.ink.color]

    var body: some View {
        VStack {
            Circle().fill(LinearGradient(colors: [ColorToken.pine.color, ColorToken.ink.color],
                                         startPoint: .top, endPoint: .bottom))
            Circle().fill(Gradient(colors: tokenColors))
            Text(verbatim: "x").listItemTint(ColorToken.pine.color)
            Rectangle().fill(AnyShapeStyle(ColorToken.ink.color))
            Rectangle().fill(AnyShapeStyle(roles.isEmpty ? ColorToken.ink.color : ColorToken.pine.color))
        }
    }
}

let tokenStyle: some ShapeStyle = ColorToken.pine.color
var tokenStyleProperty: some ShapeStyle { ColorToken.ink.color }

/// Near-misses for the second round 3 pass: `.fill`, `.placeholder`, `.selection` and `.fixed`
/// where they are not colors, the environment styles `.tint` and `.foreground` (set from tokens),
/// a `??` default that is not a color, token arguments to the ListItemTint factories and to
/// mix(with:), and arrays and dictionaries of values that are not colors. Clean here means no
/// literal color; a gradient built from tokens is still against Section 4.4.2 ("no gradients"),
/// which is a review rule, not a lint rule (ADR-0013 Section 8).
struct GoodStylesSecondPass: View {
    let sizes: [CGFloat] = []

    var body: some View {
        VStack {
            Image(systemName: "star").symbolVariant(.fill)
            Image(systemName: "star").resizable().aspectRatio(contentMode: .fill)
            Text(verbatim: "x").redacted(reason: .placeholder)
            Text(verbatim: "x").textSelection(.enabled)
            LazyVGrid(columns: [GridItem(.fixed(80)), GridItem(.flexible())]) { EmptyView() }
            Text(verbatim: "x").foregroundStyle(.tint)
            Circle().fill(.foreground)
            Text(verbatim: "x").frame(width: sizes.first ?? .zero)
            Text(verbatim: "x").listItemTint(.fixed(ColorToken.pine.color))
            Text(verbatim: "x").foregroundStyle(ColorToken.ink.color.mix(with: ColorToken.ground.color, by: 0.2))
            Rectangle().fill(LinearGradient(colors: sizes.isEmpty ? [ColorToken.ink.color] : [ColorToken.pine.color],
                                            startPoint: .top, endPoint: .bottom))
            Canvas { context, size in
                context.fill(Path(CGRect(origin: .zero, size: size)), with: .color(ColorToken.pine.color))
            }
        }
    }
}

let rolesByName: [String: SylviaButtonRole] = ["save": .primary, "cancel": .secondary]
let roleLists: [SylviaButtonRole] = Bool.random() ? [.primary] : [.secondary]
let tokenWrapped: AnyShapeStyle = .init(ColorToken.ink.color)
let tokenColorsByArea: [String: Color] = ["library": ColorToken.pine.color, "inbox": ColorToken.ink.color]
var tokenTints: [Color] { [ColorToken.pine.color, ColorToken.ink.color] }
let fillMode: ContentMode = .fill
