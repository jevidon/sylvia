import Foundation
import Testing
@testable import SylviaDesignTokens

@Suite("Marker set (plan 4.4.5, Appendix A.1)")
struct MarkerTests {
    @Test("Seven markers: five capture kinds and two statuses")
    func sevenMarkers() {
        #expect(Marker.allCases.count == 7)
        #expect(Marker.allCases.filter { $0.category == .captureKind } == [.quote, .note, .audio, .generated, .word])
        #expect(Marker.allCases.filter { $0.category == .status } == [.attention, .pending])
    }

    @Test("Glyphs, labels, frames and tints per the table")
    func table() {
        #expect(Marker.quote.glyph == .typeset("\u{201C}", face: .literata, equivalentSymbol: "quote.opening"))
        #expect(Marker.note.glyph == .systemSymbol("pencil.tip"))
        #expect(Marker.audio.glyph == .systemSymbol("waveform"))
        #expect(Marker.generated.glyph == .customSymbol(.prompt))
        #expect(Marker.word.glyph == .systemSymbol("book"))
        #expect(Marker.attention.glyph == .systemSymbol("exclamationmark.triangle"))
        #expect(Marker.pending.glyph == .systemSymbol("circle.fill"))

        let labels = Marker.allCases.map { $0.labelKey.text.uppercased() }
        #expect(labels == ["QUOTE", "NOTE", "AUDIO", "GENERATED", "WORD", "NEEDS ATTENTION", "QUEUED"])
        #expect(Marker.pending.alternateLabelKeys.map { $0.text.uppercased() } == ["WAITING"])

        #expect(Marker.allCases.filter { $0.frame == .dashed } == [.generated])
        #expect(Marker.note.tint == nil, "Note has no tint, ever")
        #expect(Marker.allCases.filter { $0.tint == nil } == [.note])
        #expect(Marker.word.textColor.aliasRoot == Marker.quote.textColor.aliasRoot, "Word shares the quote colors")
        #expect(Marker.quote.body.face == .literata)
        #expect(Marker.note.body.face == .system)
        #expect(Marker.audio.body.face == nil, "Audio is never rendered as text")
        #expect(Marker.generated.body.weight == 600)
        #expect(Marker.word.body.face == .literata && Marker.word.body.weight == 600)
    }

    @Test("Without color, every marker still differs by glyph and by label (T53 precondition)")
    func distinguishableWithoutColor() {
        let glyphs = Marker.allCases.map(\.glyph.identifier)
        #expect(Set(glyphs).count == glyphs.count)
        let labels = Marker.allCases.map(\.labelKey.rawValue)
        #expect(Set(labels).count == labels.count)
        // Quote and Audio tints collapse to similar greys in grayscale; glyph, label and body form differ.
        #expect(Marker.quote.glyph != Marker.audio.glyph)
        #expect(Marker.quote.body.face != Marker.audio.body.face)
    }

    @Test("Thoughts filter chips reuse the labels: All, Quotes, Notes, Audio, Generated, Words")
    func filterChips() {
        let chips = [LabelKey.filterAll.text] + Marker.allCases.compactMap(\.filterLabelKey).map(\.text)
        #expect(chips == ["All", "Quotes", "Notes", "Audio", "Generated", "Words"])
    }

    @Test("Known capture kinds map one-to-one onto the five capture markers")
    func knownKinds() {
        let mapping = Marker.allCases.flatMap { m in m.captureKinds.map { ($0, m) } }
        #expect(mapping.count == 5)
        #expect(Set(mapping.map(\.0)).count == 5)
        for (kind, marker) in mapping {
            #expect(Marker.resolve(captureKind: kind) == MarkerResolution(marker: marker, unrecognizedKind: nil))
        }
        #expect(Marker.resolve(captureKind: "text_quote").marker == .quote, "the A.1 sketch's kind")
    }

    @Test("Unknown kinds render as Pending with the raw kind, never as Quote",
          arguments: ["podcast_clip", "TEXT_QUOTE", "text_quote ", "quote", "", "\u{1F4D6}", "highlight"])
    func unknownKind(kind: String) {
        let resolution = Marker.resolve(captureKind: kind)
        #expect(resolution.marker == .pending)
        #expect(resolution.unrecognizedKind == kind)
        #expect(!resolution.isRecognized)
    }

    @Test("Random strings never resolve to Quote unless they are exactly text_quote")
    func randomKinds() {
        var generator = SystemRandomNumberGenerator()
        let alphabet = Array("abcdefghijklmnopqrstuvwxyz_ABCQUOTE")
        for _ in 0..<2000 {
            let length = Int.random(in: 0...12, using: &generator)
            let kind = String((0..<length).map { _ in alphabet.randomElement(using: &generator)! })
            let resolution = Marker.resolve(captureKind: kind)
            if kind != "text_quote" { #expect(resolution.marker != .quote, "\(kind)") }
        }
    }

    @Test("Custom symbols: the prompt and bracket glyphs from the boards")
    func customSymbols() {
        #expect(CustomSymbol.allCases.map(\.rawValue) == ["sylvia.prompt", "sylvia.capture"])
        #expect(CustomSymbol.prompt.polylines.count == 2, "chevron and underscore")
        #expect(CustomSymbol.capture.polylines.count == 5, "two brackets and three bars")
        #expect(CustomSymbol.prompt.accessibilityLabelKey.text == "Generated")
        #expect(CustomSymbol.capture.accessibilityLabelKey.text == "Capture")
        for symbol in CustomSymbol.allCases {
            let w = symbol.masterStrokeWidths
            #expect(w.ultralight < w.regular && w.regular < w.black)
        }
    }

    @Test("Status pill glyphs: dot, check, triangle")
    func statusGlyphs() {
        #expect(StatusGlyph.dot.systemSymbol == "circle.fill")
        #expect(StatusGlyph.check.systemSymbol == "checkmark")
        #expect(StatusGlyph.triangle.systemSymbol == "exclamationmark.triangle")
    }

    @Test("Cover field assignment is a stable FNV-1a hash of the NFC title")
    func coverHash() {
        #expect(CoverFields.fnv1a32("") == 0x811C_9DC5)
        #expect(CoverFields.fnv1a32("a") == 0xE40C_292C)
        #expect(CoverFields.fnv1a32("foobar") == 0xBF9C_F968)
        #expect(CoverFields.index(forTitle: "Caf\u{E9}") == CoverFields.index(forTitle: "Cafe\u{301}"))
        let titles = ["Middlemarch", "Walden", "Meditations", "Moby-Dick", "The Odyssey", "Frankenstein",
                      "Essays", "The Brothers Karamazov", "On the Shortness of Life", "The Count of Monte Cristo"]
        let used = Set(titles.map { CoverFields.index(forTitle: $0) })
        #expect(used.allSatisfy { (0..<5).contains($0) })
        #expect(used.count > 1, "titles spread across fields")
    }
}

@Suite("Type roles (plan 4.4.3)")
struct TypeRoleTokenTests {
    @Test("The role table")
    func table() {
        let expected: [(TypeRole, Face, Int, Double, Double, TextStyle)] = [
            (.display, .literata, 600, 34, 40, .largeTitle),
            (.title, .literata, 600, 28, 34, .title1),
            (.heading, .literata, 500, 22, 28, .title2),
            (.reading, .literata, 400, 19, 30, .body),
            (.body, .system, 400, 17, 23, .body),
            (.callout, .system, 500, 15, 20, .subheadline),
            (.caption, .system, 400, 13, 18, .footnote),
            (.micro, .system, 600, 11, 14, .caption2),
        ]
        #expect(TypeRole.allCases.count == expected.count)
        for (role, face, weight, size, line, style) in expected {
            let s = role.spec
            #expect(s.face == face && s.weight == weight && s.size == size && s.lineHeight == line
                && s.textStyle == style, "\(role)")
        }
        #expect(TypeRole.display.spec.tracking == -0.015)
        #expect(TypeRole.title.spec.tracking == -0.01)
        #expect(TypeRole.micro.spec.tracking == 0.08)
        #expect(TypeRole.allCases.filter(\.spec.uppercase) == [.micro])
    }

    @Test("System roles sit at their text style's default size, so they track system roles exactly")
    func systemDefaults() {
        for role in TypeRole.allCases where role != .reading {
            #expect(role.spec.size == role.spec.textStyle.iOSDefaultPointSize, "\(role)")
        }
    }

    @Test("Reading size: 19 by default, user range 14-28, clamped")
    func readingSize() {
        #expect(ReadingSize.default.points == 19)
        #expect(ReadingSize(points: 10).points == 14)
        #expect(ReadingSize(points: 40).points == 28)
        #expect(ReadingSize(points: 22.5).points == 22.5)
    }

    @Test("Bold Text adds 200 to every weight, capped at 900")
    func boldText() {
        #expect(BoldText.weight(400, boldText: true) == 600)
        #expect(BoldText.weight(500, boldText: true) == 700)
        #expect(BoldText.weight(600, boldText: true) == 800)
        #expect(BoldText.weight(800, boldText: true) == 900)
        #expect(BoldText.weight(600, boldText: false) == 600)
    }

    @Test("Literata optical size follows the point size within the axis")
    func opticalSize() {
        #expect(LiterataFont.opticalSize(forPointSize: 19) == 19)
        #expect(LiterataFont.opticalSize(forPointSize: 5) == 7)
        #expect(LiterataFont.opticalSize(forPointSize: 90) == 72)
    }

    @Test("Shape, space, elevation and motion (plan 4.4.4)")
    func layout() {
        #expect(Spacing.steps == [4, 8, 12, 16, 20, 24, 32])
        #expect(Spacing.steps.allSatisfy { $0.truncatingRemainder(dividingBy: Spacing.grid) == 0 })
        #expect(Spacing.gutterPhone == 20 && Spacing.gutterPad == 32)
        #expect(Radius.allCases.map(\.points) == [8, 10, 12, 14, 22, nil])
        #expect(Elevation.shadowX == 0 && Elevation.shadowY == 8 && Elevation.shadowBlur == 24)
        #expect(Motion.sheet.durationMilliseconds == 200 && Motion.sheet.curve == .easeOut && Motion.sheet.statedInPlan)
        #expect(Motion.highlight.durationMilliseconds == 120)
        #expect(!Motion.progressRule.statedInPlan, "progress-rule timing is a proposal")
    }
}
