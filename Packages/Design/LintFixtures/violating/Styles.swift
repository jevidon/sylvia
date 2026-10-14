import SwiftUI

// Review round 3 (R3-01): palette names in gradient color lists, list item tints and values typed
// as a shape style. The first three lines in the body and the first declaration below are the
// reviewer's probe; every marked line must be reported with exactly the rule its marker names.

struct BadStyles: View {
    let on = true

    var body: some View {
        VStack {
            Circle().fill(LinearGradient(colors: [.red, .blue], startPoint: .top, endPoint: .bottom)) // lint-expect: named-color
            Circle().fill(Gradient(colors: [.red, .blue])) // lint-expect: named-color
            Text(verbatim: "x").listItemTint(.red) // lint-expect: named-color
            Rectangle().fill(RadialGradient(colors: [ColorToken.pine.color, .black], center: .center, startRadius: 0, endRadius: 1)) // lint-expect: named-color
            Rectangle().fill(AngularGradient(colors: [on ? .green : ColorToken.ink.color], center: .center)) // lint-expect: named-color
            Rectangle().fill(LinearGradient(
                colors: [
                    ColorToken.pine.color,
                    .mint, // lint-expect: named-color
                ],
                startPoint: .top, endPoint: .bottom))
            Rectangle().fill(AnyShapeStyle(.teal)) // lint-expect: named-color
            Rectangle().fill(AnyShapeStyle(on ? .indigo : ColorToken.ink.color)) // lint-expect: named-color
            Text(verbatim: "x").presentationBackground(.yellow) // lint-expect: named-color
            Text(verbatim: "x").listSectionSeparatorTint(.gray) // lint-expect: named-color
        }
    }
}

let q: some ShapeStyle = .red // lint-expect: named-color
let anyStyle: any ShapeStyle = .orange // lint-expect: named-color
var styleProperty: some ShapeStyle { .purple } // lint-expect: named-color
func styleFunction() -> some ShapeStyle { return .pink } // lint-expect: named-color
let chosenStyle: some ShapeStyle = Bool.random() ? ColorToken.ink.color : .brown // lint-expect: named-color
let palette: [Color] = [.cyan, ColorToken.ink.color] // lint-expect: named-color
let mesh = MeshGradient(width: 2, height: 1, points: [[0, 0], [1, 0]], colors: [.white, .black]) // lint-expect: named-color

// Review round 3, second pass (the same classes, further spellings): the ListItemTint factories
// that listItemTint also takes, SwiftUI's semantic styles that resolve to system colors, a
// nil-coalescing default, mix(with:), a gradient built with a ShapeStyle factory, conditional and
// concatenated list literals, the Canvas shading .color(...), arrays of colors returned by a
// computed property or a function, a dictionary whose values are colors, and a shape style built
// with its own .init.
struct BadStylesSecondPass: View {
    let custom: Color? = nil

    var body: some View {
        VStack {
            Text(verbatim: "x").listItemTint(.fixed(.red)) // lint-expect: named-color
            Text(verbatim: "x").listItemTint(ListItemTint.preferred(.blue)) // lint-expect: named-color
            Text(verbatim: "x").foregroundStyle(.separator) // lint-expect: named-color
            Text(verbatim: "x").foregroundStyle(.link) // lint-expect: named-color
            Rectangle().fill(.placeholder) // lint-expect: named-color
            Text(verbatim: "x").background(.selection) // lint-expect: named-color
            Text(verbatim: "x").background(.windowBackground) // lint-expect: named-color
            Text(verbatim: "x").background(.fill.secondary) // lint-expect: named-color
            Text(verbatim: "x").background(.background) // lint-expect: named-color
            Text(verbatim: "x").foregroundStyle(custom ?? .secondary) // lint-expect: named-color
            Text(verbatim: "x").foregroundStyle(ColorToken.ink.color.mix(with: .white, by: 0.2)) // lint-expect: named-color
            Text(verbatim: "x").foregroundStyle(ColorToken.ink.color.mix(with: custom == nil ? ColorToken.pine.color : .black, by: 0.2)) // lint-expect: named-color
            Circle().fill(.ellipticalGradient(colors: [.green, .mint])) // lint-expect: named-color
            Rectangle().fill(LinearGradient(colors: custom == nil ? [.black, .gray] : [ColorToken.ink.color], startPoint: .top, endPoint: .bottom)) // lint-expect: named-color
            Rectangle().fill(LinearGradient(colors: [ColorToken.ink.color] + [.white], startPoint: .top, endPoint: .bottom)) // lint-expect: named-color
            Canvas { context, size in context.fill(Path(CGRect(origin: .zero, size: size)), with: .color(.red)) } // lint-expect: named-color
            Canvas { context, size in context.stroke(Path(CGRect(origin: .zero, size: size)), with: .color(red: 1, green: 0, blue: 0)) } // lint-expect: color-components
        }
    }
}

let schemeTints: [Color] = Bool.random() ? [ColorToken.ink.color] : [.white] // lint-expect: named-color
let wrappedStyle: AnyShapeStyle = .init(.red) // lint-expect: named-color

var computedTints: [Color] { [.red, ColorToken.ink.color] } // lint-expect: named-color
func returnedTints() -> [Color] { return [ColorToken.pine.color, .orange] } // lint-expect: named-color
let tintsByArea: [String: Color] = ["library": ColorToken.pine.color, "inbox": .red] // lint-expect: named-color
let fallbackColor: Color? = nil ?? .yellow // lint-expect: named-color
let separatorStyle: some ShapeStyle = .separator // lint-expect: named-color
