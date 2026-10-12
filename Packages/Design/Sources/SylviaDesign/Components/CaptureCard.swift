import SwiftUI

/// One citation in a generated answer (Section 13.4).
public struct Citation: Sendable, Hashable {
    /// The chip label, for example "c1".
    public let label: String
    /// False when the ID did not resolve against the context pack: the chip is struck through,
    /// grey and not a link, and an explanation follows the answer.
    public let isResolved: Bool

    public init(_ label: String, isResolved: Bool) {
        self.label = label
        self.isResolved = isResolved
    }
}

/// A run of a generated answer: text or an inline citation chip.
public enum AnswerSegment: Sendable, Hashable {
    case text(String)
    case citation(Citation)
}

/// What a capture card shows (Section 4.4.5 body treatments).
public enum CaptureCardContent: Sendable, Hashable {
    /// Exact captured wording in Literata on the quote tint; the user's note under it.
    case quote(text: String, yourNote: String?)
    /// The user's own words in the system face; no tint, ever.
    case note(text: String)
    /// A tinted block with a round play control and a waveform; never rendered as text. Without a
    /// transcript the card says "No transcript".
    case audio(durationSeconds: Int, waveformSeed: String, transcript: String?, yourNote: String?)
    /// Question in Body 600, answer in Body with inline citation chips; dashed frame.
    case generated(question: String, answer: [AnswerSegment], status: Status?)
    /// Headword in Literata 600, then the source sentence and the user's note.
    case word(headword: String, sentence: String, yourNote: String?)

    public var marker: Marker {
        switch self {
        case .quote: .quote
        case .note: .note
        case .audio: .audio
        case .generated: .generated
        case .word: .word
        }
    }
}

/// A capture card (Section 4.4.7): surface, hairline border (the dashed Generated frame for
/// generated answers), radius 14, 12 pt padding; marker row, body per Section 4.4.5, optional
/// "Your note" line, timestamp in Monospace.
public struct CaptureCard: View {
    public let content: CaptureCardContent
    public let marker: MarkerRow.Configuration
    let isPlaying: Bool
    let onPlay: () -> Void
    let onOpenCitation: (String) -> Void

    /// `details` follow the marker label (source label first; for audio the duration is added;
    /// for generated, provider and model). `timestamp` is shown in Monospace.
    public init(_ content: CaptureCardContent, details: [String], timestamp: String?,
                isPlaying: Bool = false, onPlay: @escaping () -> Void = {},
                onOpenCitation: @escaping (String) -> Void = { _ in }) {
        self.content = content
        var details = details
        if case .audio(let seconds, _, _, _) = content {
            details.append(Durations.text(seconds: seconds))
        }
        self.marker = MarkerRow.Configuration(marker: content.marker, details: details, timestamp: timestamp)
        self.isPlaying = isPlaying
        self.onPlay = onPlay
        self.onOpenCitation = onOpenCitation
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: Spacing.xs) {
            MarkerRow(marker)
            cardBody
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(ComponentMetrics.cardPadding)
        .sylviaFill(.surface, .card)
        .sylviaBorder(.card, color: content.marker == .generated ? .markerGeneratedText : .hairline,
                      dashed: content.marker == .generated)
        .accessibilityElement(children: .contain)
        .sylviaAuditRegion("card")
    }

    @ViewBuilder private var cardBody: some View {
        switch content {
        case .quote(let text, let note):
            QuoteBlock(text: text)
            if let note { YourNoteLine(note: note) }
        case .note(let text):
            Text(text)
                .sylviaFont(.body)
                .foregroundStyle(ColorToken.ink.color)
                .fixedSize(horizontal: false, vertical: true)
        case .audio(_, let seed, let transcript, let note):
            AudioBlock(seed: seed, isPlaying: isPlaying, onPlay: onPlay)
            if let note { YourNoteLine(note: note) }
            if let transcript {
                VStack(alignment: .leading, spacing: Spacing.xxs) {
                    Text(LabelKey.audioTranscript.localized)
                        .sylviaFont(.micro)
                        .foregroundStyle(ColorToken.muted.color)
                    Text(transcript)
                        .sylviaFont(.body)
                        .foregroundStyle(ColorToken.ink.color)
                }
                .accessibilityElement(children: .combine)
            } else {
                // On the card surface, never on the tint: muted fails contrast on tints (ADR-0013 §3).
                Text(LabelKey.audioNoTranscript.localized)
                    .sylviaFont(.caption)
                    .foregroundStyle(ColorToken.muted.color)
            }
        case .generated(let question, let answer, let status):
            Text(question)
                .sylviaFont(.body, weight: Marker.generated.body.weight)
                .foregroundStyle(ColorToken.ink.color)
                .fixedSize(horizontal: false, vertical: true)
            GeneratedAnswer(segments: answer, onOpenCitation: onOpenCitation)
            if let status {
                Text(status.text())
                    .sylviaFont(.caption)
                    .foregroundStyle(ColorToken.muted.color)
            }
        case .word(let headword, let sentence, let note):
            Text(headword)
                .sylviaFont(.reading, weight: Marker.word.body.weight)
                .foregroundStyle(ColorToken.ink.color)
            Text(sentence)
                .sylviaFont(.reading, readingSize: ReadingSize(points: TypeRole.body.spec.size))
                .foregroundStyle(ColorToken.ink.color)
                .fixedSize(horizontal: false, vertical: true)
            if let note { YourNoteLine(note: note) }
        }
    }
}

/// Exact quoted text in Literata on the quote tint, radius 8 (Section 4.4.5). `size` is the Reading
/// role at the reader's size, or Body size inside lists.
public struct QuoteBlock: View {
    let text: String
    let readingSize: ReadingSize

    public init(text: String, readingSize: ReadingSize = .default) {
        self.text = text
        self.readingSize = readingSize
    }

    public var body: some View {
        Text(text)
            .sylviaFont(.reading, readingSize: readingSize)
            .foregroundStyle(ColorToken.ink.color)
            .fixedSize(horizontal: false, vertical: true)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(Spacing.s)
            .sylviaFill(.markerQuoteTint, .block)
            .sylviaAuditRegion("quote.block")
    }
}

/// "Your note · …" in the system face (Section 4.4.5): the prefix in muted, the note in ink.
public struct YourNoteLine: View {
    let note: String

    public init(note: String) {
        self.note = note
    }

    public var body: some View {
        let prefix = LabelKey.captureYourNote.localized
        Text("\(Text(prefix + Microcopy.separator).foregroundStyle(ColorToken.muted.color))\(Text(note).foregroundStyle(ColorToken.ink.color))")
            .sylviaFont(.body)
            .fixedSize(horizontal: false, vertical: true)
            .accessibilityLabel(Text("\(prefix), \(note)"))
    }
}

/// The audio block (Section 4.4.5): audio tint, radius 8, a round play control and a waveform.
/// Preview playback never moves the main listening position (Section 10.3); that is the caller's
/// player's job, and the control says "Play excerpt".
public struct AudioBlock: View {
    let seed: String
    let isPlaying: Bool
    let onPlay: () -> Void

    public init(seed: String, isPlaying: Bool, onPlay: @escaping () -> Void) {
        self.seed = seed
        self.isPlaying = isPlaying
        self.onPlay = onPlay
    }

    public var body: some View {
        HStack(spacing: Spacing.s) {
            Button(action: onPlay) {
                Image(systemName: (isPlaying ? ControlSymbol.pause : ControlSymbol.play).systemName)
                    .sylviaFont(.body)
                    .foregroundStyle(ColorToken.surface.color)
                    .frame(width: ComponentMetrics.playControl, height: ComponentMetrics.playControl)
                    .background(Circle().fill(Marker.audio.textColor.color))
                    .contentShape(Circle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel(Text((isPlaying ? LabelKey.controlPauseExcerpt : LabelKey.controlPlayExcerpt).localized))
            .sylviaAuditRegion("audio.play")
            Waveform(seed: seed)
                .frame(height: ComponentMetrics.waveformHeight)
                .accessibilityHidden(true)
                .sylviaAuditRegion("audio.waveform")
        }
        .padding(Spacing.s)
        .frame(maxWidth: .infinity, alignment: .leading)
        .sylviaFill(.markerAudioTint, .block)
        .sylviaAuditRegion("audio.block")
    }
}

/// Deterministic waveform bars in the audio color. Levels come from an FNV-1a hash of `seed`, so a
/// capture always draws the same shape (a decorative stand-in until real levels are stored).
struct Waveform: View {
    let seed: String

    static func levels(seed: String, count: Int) -> [Double] {
        var state = CoverFields.fnv1a32(seed)
        return (0..<count).map { _ in
            state ^= state << 13
            state ^= state >> 17
            state ^= state << 5
            let unit = Double(state % 1000) / 999
            return ComponentMetrics.waveformMinimumLevel + (1 - ComponentMetrics.waveformMinimumLevel) * unit
        }
    }

    var body: some View {
        Canvas { context, size in
            let pitch = ComponentMetrics.waveformBarWidth + ComponentMetrics.waveformBarGap
            let count = max(Int(size.width / pitch), 1)
            let levels = Self.levels(seed: seed, count: count)
            for (index, level) in levels.enumerated() {
                let height = max(size.height * level, ComponentMetrics.waveformBarWidth)
                let rect = CGRect(x: Double(index) * pitch, y: (size.height - height) / 2,
                                  width: ComponentMetrics.waveformBarWidth, height: height)
                context.fill(Capsule().path(in: rect), with: .color(Marker.audio.textColor.color))
            }
        }
    }
}

/// Marks a citation run inside a generated answer.
struct CitationChipAttribute: TextAttribute {
    let isResolved: Bool
}

/// Draws chip backgrounds behind citation runs: the generated tint for resolved citations, the
/// pending tint for unresolved ones.
struct CitationChipRenderer: TextRenderer {
    let resolvedFill: Color
    let unresolvedFill: Color

    func draw(layout: Text.Layout, in context: inout GraphicsContext) {
        for line in layout {
            for run in line {
                if let chip = run[CitationChipAttribute.self] {
                    let rect = run.typographicBounds.rect.insetBy(dx: 0, dy: -ComponentMetrics.chipVerticalInset)
                    context.fill(Capsule().path(in: rect), with: .color(chip.isResolved ? resolvedFill : unresolvedFill))
                }
                context.draw(run)
            }
        }
    }
}

/// A generated answer with inline citation chips (Section 4.4.5, 13.4). Resolved chips are links
/// that open the cited snippet; unresolved chips are struck through, grey and inert, and a one-line
/// explanation follows the answer.
public struct GeneratedAnswer: View {
    let segments: [AnswerSegment]
    let onOpenCitation: (String) -> Void
    @Environment(\.colorScheme) private var colorScheme

    public init(segments: [AnswerSegment], onOpenCitation: @escaping (String) -> Void) {
        self.segments = segments
        self.onOpenCitation = onOpenCitation
    }

    static let citationScheme = "sylvia-citation"

    /// The answer as spoken: chips read as "Citation c1" or "Unresolved citation c2".
    public static func accessibilityText(_ segments: [AnswerSegment]) -> String {
        segments.map { segment in
            switch segment {
            case .text(let text): return text
            case .citation(let c):
                let key: FormatKey = c.isResolved ? .citationResolved : .citationUnresolved
                return " " + VocabularyCatalog.render(key.rawValue, arguments: [.string(c.label)], locale: .current) + " "
            }
        }.joined()
    }

    var hasUnresolved: Bool {
        segments.contains { if case .citation(let c) = $0 { !c.isResolved } else { false } }
    }

    var answerText: Text {
        var result = Text(verbatim: "")
        for segment in segments {
            switch segment {
            case .text(let text):
                result = Text("\(result)\(Text(verbatim: text).foregroundStyle(ColorToken.ink.color))")
            case .citation(let citation):
                // Narrow no-break spaces pad the label inside its chip.
                var label = AttributedString("\u{202F}\(citation.label)\u{202F}")
                if citation.isResolved {
                    label.link = URL(string: "\(Self.citationScheme):\(citation.label)")
                    label.foregroundColor = Marker.generated.textColor.color
                } else {
                    label.foregroundColor = Marker.pending.textColor.color
                    label.strikethroughStyle = Text.LineStyle(pattern: .solid, color: Marker.pending.textColor.color)
                }
                let chip = Text(label).customAttribute(CitationChipAttribute(isResolved: citation.isResolved))
                result = Text("\(result)\(chip)")
            }
        }
        return result
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: Spacing.xs) {
            answerText
                .sylviaFont(.body)
                .tint(Marker.generated.textColor.color)
                .textRenderer(CitationChipRenderer(resolvedFill: Marker.generated.tint!.color,
                                                   unresolvedFill: Marker.pending.tint!.color))
                .fixedSize(horizontal: false, vertical: true)
                .environment(\.openURL, OpenURLAction { url in
                    guard url.scheme == Self.citationScheme else { return .systemAction }
                    onOpenCitation(url.absoluteString.replacingOccurrences(of: "\(Self.citationScheme):", with: ""))
                    return .handled
                })
                .accessibilityLabel(Text(Self.accessibilityText(segments)))
                .accessibilityActions {
                    ForEach(resolvedLabels, id: \.self) { label in
                        Button(VocabularyCatalog.render(FormatKey.citationResolved.rawValue,
                                                        arguments: [.string(label)], locale: .current)) {
                            onOpenCitation(label)
                        }
                    }
                }
                .sylviaAuditRegion("generated.answer")
            if hasUnresolved {
                Text(LabelKey.citationUnresolvedExplanation.localized)
                    .sylviaFont(.caption)
                    .foregroundStyle(ColorToken.muted.color)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    private var resolvedLabels: [String] {
        segments.compactMap { if case .citation(let c) = $0, c.isResolved { c.label } else { nil } }
    }
}
