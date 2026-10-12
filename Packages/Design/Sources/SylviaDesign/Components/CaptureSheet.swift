import SwiftUI

/// Where a capture's save stands (Section 4.4.6 "Saving a thought"; Section 11.1). The sheet's
/// primary button shows it as its label.
public enum CaptureSaveState: Sendable, Hashable {
    /// Nothing saved yet: the button says "Save".
    case draft
    /// The capture transaction is running: "Saving…".
    case saving
    /// The durable commit succeeded at this time: "Saved 14:02". Set only from the commit
    /// callback (I-03).
    case saved(Date)
    /// The commit failed: "Not saved · your text is still here". The text stays; the button retries.
    case failed

    /// The button label.
    public func label(locale: Locale = .current, timeZone: TimeZone = .current) -> String {
        switch self {
        case .draft: LabelKey.actionSave.localized
        case .saving: Status.saving.text(locale: locale, timeZone: timeZone)
        case .saved(let date): Status.savedAt(date).text(locale: locale, timeZone: timeZone)
        case .failed: Status.notSaved.text(locale: locale, timeZone: timeZone)
        }
    }

    /// The commit time as it appears inside ``label(locale:timeZone:)`` ("14:02" in "Saved 14:02"),
    /// set in the Monospace face (Section 4.4.6: times in Monospace); nil for the other states.
    public func timeText(locale: Locale = .current, timeZone: TimeZone = .current) -> String? {
        guard case .saved(let date) = self else { return nil }
        return TimestampText.time(date, locale: locale, timeZone: timeZone)
    }

    /// The glyph beside the label: a check once saved, the triangle after a failure.
    public var glyph: StatusGlyph? {
        switch self {
        case .saved: .check
        case .failed: .triangle
        case .draft, .saving: nil
        }
    }
}

/// The draft behind the capture sheet: the note text, the text last committed, and the save state.
/// It decides whether the sheet may be dismissed: never while it holds unsaved text (Section 4.4.4,
/// 11.1).
public struct CaptureDraft: Sendable, Hashable {
    public var note: String
    /// The note as of the last durable commit; nil before the first one.
    public private(set) var committedNote: String?
    public private(set) var saveState: CaptureSaveState

    public init(note: String = "") {
        self.note = note
        self.committedNote = nil
        self.saveState = .draft
    }

    /// True while the note holds text that is not durably saved.
    public var hasUnsavedText: Bool {
        let trimmed = note.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return false }
        if case .saved = saveState, committedNote == note { return false }
        return true
    }

    /// The sheet may be dismissed (by swipe or programmatically) only without unsaved text.
    public var canDismiss: Bool { !hasUnsavedText }

    /// Call when the user edits the note: a saved capture goes back to draft if the text changed.
    public mutating func noteChanged() {
        if case .saved = saveState, committedNote != note { saveState = .draft }
    }

    public mutating func beginSave() { saveState = .saving }

    /// Call only from the durable commit callback.
    public mutating func commitSucceeded(at date: Date, savedNote: String) {
        committedNote = savedNote
        saveState = note == savedNote ? .saved(date) : .draft
    }

    public mutating func commitFailed() { saveState = .failed }
}

/// The sheet surface shared by the capture sheet and the impact report (Section 4.4.4): surface,
/// 22 pt top radius, grabber, title in the Heading role, primary action at the bottom.
///
/// On its own (snapshots, the design catalog's samples) it draws the surface, the 22 pt top
/// corners and the one shadow. Presented with ``SwiftUI/View/sylviaSheet(isPresented:canDismiss:content:)``
/// the presentation already supplies the surface and the corners, so the container draws no shape
/// of its own: a second rounded edge and shadow inside the presented sheet would show where the
/// content ends.
public struct SylviaSheetContainer<Content: View>: View {
    let title: String
    let content: Content
    @Environment(\.sylviaSheetIsPresented) private var isPresented

    public init(title: String, @ViewBuilder content: () -> Content) {
        self.title = title
        self.content = content()
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: Spacing.m) {
            Capsule()
                .fill(ColorToken.hairline.color)
                .frame(width: ComponentMetrics.grabberWidth, height: ComponentMetrics.grabberHeight)
                .frame(maxWidth: .infinity)
                .accessibilityHidden(true)
            FittingText(title, role: .heading)
                .foregroundStyle(ColorToken.ink.color)
                .accessibilityAddTraits(.isHeader)
            content
        }
        .padding(.horizontal, Spacing.l)
        .padding(.top, Spacing.xs)
        .padding(.bottom, Spacing.l)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background {
            if !isPresented {
                UnevenRoundedRectangle(topLeadingRadius: Radius.sheet.value, topTrailingRadius: Radius.sheet.value,
                                       style: .continuous)
                    .fill(ColorToken.surface.color)
                    .sylviaElevation()
            }
        }
    }
}

extension EnvironmentValues {
    /// True inside a sheet presented with `sylviaSheet`: the presentation draws the sheet surface.
    @Entry public var sylviaSheetIsPresented: Bool = false
}

extension View {
    /// Presents a Sylvia sheet: 22 pt radius, surface background, no system grabber (the
    /// container draws its own), and interactive dismissal disabled while `canDismiss` is false.
    /// The presentation is the surface, so a ``SylviaSheetContainer`` inside draws no shape of its own.
    public func sylviaSheet<Sheet: View>(isPresented: Binding<Bool>, canDismiss: Bool,
                                         @ViewBuilder content: @escaping () -> Sheet) -> some View {
        sheet(isPresented: isPresented) {
            content()
                .environment(\.sylviaSheetIsPresented, true)
                .presentationCornerRadius(Radius.sheet.value)
                .presentationBackground(ColorToken.surface.color)
                .presentationDragIndicator(.hidden)
                .interactiveDismissDisabled(!canDismiss)
        }
    }
}

/// What the capture sheet captures (Section 4.1 reader/player sheet).
public enum CaptureSubject: Sendable, Hashable {
    /// Selected text, kept exactly (Literata on the quote tint).
    case quote(text: String)
    /// An audio range with numeric start and end controls.
    case audio(AudioRange)

    public var marker: Marker {
        switch self {
        case .quote: .quote
        case .audio: .audio
        }
    }
}

/// The capture sheet shell (Section 4.4.7): marker row, quote block or audio range, the "Your
/// note" field, Look up and Ask, and a primary button whose label is the save state. The sheet
/// never dismisses with unsaved text: present it with ``SwiftUI/View/sylviaSheet(isPresented:canDismiss:content:)``
/// and `draft.canDismiss`. Save state changes are announced once to VoiceOver.
public struct CaptureSheet: View {
    @Binding var draft: CaptureDraft
    @Binding var subject: CaptureSubject
    let source: [String]
    let onSave: () -> Void
    let onClose: () -> Void
    let onLookUp: () -> Void
    let onAsk: () -> Void

    public init(draft: Binding<CaptureDraft>, subject: Binding<CaptureSubject>, source: [String],
                onSave: @escaping () -> Void, onClose: @escaping () -> Void,
                onLookUp: @escaping () -> Void, onAsk: @escaping () -> Void) {
        self._draft = draft
        self._subject = subject
        self.source = source
        self.onSave = onSave
        self.onClose = onClose
        self.onLookUp = onLookUp
        self.onAsk = onAsk
    }

    public var body: some View {
        SylviaSheetContainer(title: LabelKey.captureSheetTitle.localized) {
            VStack(alignment: .leading, spacing: Spacing.m) {
                MarkerRow(MarkerRow.Configuration(marker: subject.marker, details: source))
                switch subject {
                case .quote(let text):
                    QuoteBlock(text: text)
                case .audio:
                    AudioRangeControls(range: audioRange)
                }
                noteField
                ViewThatFits(in: .horizontal) {
                    HStack(spacing: Spacing.l) { secondaryActions }
                    VStack(alignment: .leading, spacing: 0) { secondaryActions }
                }
                primaryButton
            }
        }
        .onChange(of: draft.saveState) { _, state in
            switch state {
            case .saved, .failed:
                AccessibilityNotification.Announcement(state.label()).post()
            case .draft, .saving:
                break
            }
        }
    }

    private var audioRange: Binding<AudioRange> {
        Binding {
            if case .audio(let range) = subject { return range }
            return AudioRange(start: 0, end: AudioRange.defaultLengthMilliseconds,
                              sourceDuration: AudioRange.defaultLengthMilliseconds)
        } set: { subject = .audio($0) }
    }

    private var noteField: some View {
        VStack(alignment: .leading, spacing: Spacing.xs) {
            Text(LabelKey.captureYourNote.localized)
                .sylviaFont(.micro)
                .foregroundStyle(ColorToken.pine.color)
                .accessibilityHidden(true)
            TextField(LabelKey.captureYourNote.localized, text: $draft.note, axis: .vertical)
                .sylviaFont(.body)
                .foregroundStyle(ColorToken.ink.color)
                .padding(Spacing.s)
                .sylviaFill(.ground, .control)
                .sylviaBorder(.control)
                // Explicit: inside a scroll view the field's title alone did not reach the
                // accessibility tree (found by the catalog's UI tests, G0.6 part 3).
                .accessibilityLabel(Text(LabelKey.captureYourNote.localized))
                .onChange(of: draft.note) { _, _ in draft.noteChanged() }
                .sylviaAuditRegion("sheet.note")
        }
    }

    @ViewBuilder private var secondaryActions: some View {
        Button(action: onLookUp) {
            Label { Text(LabelKey.actionLookUp.localized) } icon: { Image(systemName: ControlSymbol.lookUp.systemName) }
        }
        .buttonStyle(.sylvia(.quiet))
        Button(action: onAsk) {
            Label { Text(LabelKey.actionAsk.localized) } icon: { CustomSymbol.prompt.image.accessibilityHidden(true) }
        }
        .buttonStyle(.sylvia(.quiet))
    }

    private var primaryButton: some View {
        CaptureSaveButton(state: draft.saveState, onSave: onSave, onClose: onClose)
    }
}

/// The capture sheet's primary button (Section 4.4.7): its label is the save state. "Save" before
/// the first save; "Saving…" (disabled) during the transaction; "Saved 14:02" with a check after
/// the durable commit (tapping closes the sheet); "Not saved · your text is still here" with the
/// triangle after a failure (tapping retries). No "Done": the vocabulary forbids it here.
public struct CaptureSaveButton: View {
    let state: CaptureSaveState
    let onSave: () -> Void
    let onClose: () -> Void

    public init(state: CaptureSaveState, onSave: @escaping () -> Void, onClose: @escaping () -> Void) {
        self.state = state
        self.onSave = onSave
        self.onClose = onClose
    }

    public var body: some View {
        Button {
            switch state {
            case .draft, .failed: onSave()
            case .saved: onClose()
            case .saving: break
            }
        } label: {
            HStack(spacing: Spacing.xs) {
                if let glyph = state.glyph {
                    glyph.image.accessibilityHidden(true)
                }
                SaveStateLabel(state: state)
            }
        }
        .buttonStyle(.sylvia(.primary))
        // "Saving…" is a status the user has to read: the button cannot be pressed during the
        // transaction, but it keeps full contrast instead of the disabled fade (R1-03).
        .disabled(state == .saving)
        .sylviaButtonBusy(state == .saving)
        .accessibilityHint(Text(hint))
        .sylviaAuditRegion("sheet.primary")
    }

    private var hint: String {
        switch state {
        case .failed: LabelKey.actionSaveAgainHint.localized
        case .saved: LabelKey.actionCloseHint.localized
        case .draft, .saving: ""
        }
    }
}

/// The save button's label: the vocabulary phrase, with the commit time of "Saved {time}" set in
/// the Monospace face at the label's size and weight (Section 4.4.6; ADR-0013 Section 6).
struct SaveStateLabel: View {
    let state: CaptureSaveState
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @Environment(\.legibilityWeight) private var legibilityWeight

    var body: some View {
        Text(Self.attributed(state, monospacedFont: Font(monospacedStyle.ctFont())))
    }

    private var monospacedStyle: ResolvedTypeStyle {
        TypeRoleModifier.resolve(.body, dynamicTypeSize: dynamicTypeSize, legibilityWeight: legibilityWeight,
                                 monospaced: true, weight: ComponentMetrics.labelWeight)
    }

    /// The label with the time run (if any) in `monospacedFont`; the rest keeps the button's font.
    static func attributed(_ state: CaptureSaveState, monospacedFont: Font,
                           locale: Locale = .current, timeZone: TimeZone = .current) -> AttributedString {
        var text = AttributedString(state.label(locale: locale, timeZone: timeZone))
        if let time = state.timeText(locale: locale, timeZone: timeZone),
           let range = text.range(of: time, options: .backwards) {
            text[range].font = monospacedFont
        }
        return text
    }
}

/// Numeric start and end controls for an audio range (Section 10.2, 18.3: edit audio start and
/// end numerically, no precision dragging). Each value is adjustable with VoiceOver and has
/// earlier/later buttons of at least 44 pt.
public struct AudioRangeControls: View {
    @Binding var range: AudioRange

    public init(range: Binding<AudioRange>) {
        self._range = range
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: Spacing.s) {
            ViewThatFits(in: .horizontal) {
                HStack(alignment: .top, spacing: Spacing.m) { edges }
                VStack(alignment: .leading, spacing: Spacing.s) { edges }
            }
            HStack(alignment: .firstTextBaseline, spacing: Spacing.xs) {
                Text(LabelKey.captureLength.localized)
                    .sylviaFont(.caption)
                Text(Timecode.text(milliseconds: range.lengthMilliseconds, tenths: false))
                    .sylviaFont(.caption, monospaced: true)
            }
            .foregroundStyle(ColorToken.muted.color)
            .accessibilityElement(children: .combine)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    @ViewBuilder private var edges: some View {
        EdgeControl(title: LabelKey.captureStart.localized, value: range.startMilliseconds,
                    earlier: LabelKey.controlStartEarlier.localized, later: LabelKey.controlStartLater.localized,
                    canEarlier: range.canMove(.start, by: -1), canLater: range.canMove(.start, by: 1)) {
            range = range.moving(.start, by: $0)
        }
        EdgeControl(title: LabelKey.captureEnd.localized, value: range.endMilliseconds,
                    earlier: LabelKey.controlEndEarlier.localized, later: LabelKey.controlEndLater.localized,
                    canEarlier: range.canMove(.end, by: -1), canLater: range.canMove(.end, by: 1)) {
            range = range.moving(.end, by: $0)
        }
    }
}

struct EdgeControl: View {
    let title: String
    let value: Int64
    let earlier: String
    let later: String
    let canEarlier: Bool
    let canLater: Bool
    let move: (Int) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: Spacing.xxs) {
            Text(title)
                .sylviaFont(.caption, weight: ComponentMetrics.labelWeight)
                .foregroundStyle(ColorToken.ink.color)
                .accessibilityHidden(true)
            // The value never breaks inside a timecode: when the stepper row does not fit (large
            // text), the value takes its own line above the two buttons.
            ViewThatFits(in: .horizontal) {
                HStack(spacing: Spacing.xxs) {
                    earlierButton
                    valueField
                    laterButton
                }
                VStack(alignment: .leading, spacing: Spacing.xxs) {
                    valueField
                    HStack(spacing: Spacing.xxs) {
                        earlierButton
                        laterButton
                    }
                }
            }
        }
    }

    private var earlierButton: some View {
        stepButton(systemImage: ControlSymbol.stepEarlier.systemName, label: earlier, enabled: canEarlier, steps: -1)
    }

    private var laterButton: some View {
        stepButton(systemImage: ControlSymbol.stepLater.systemName, label: later, enabled: canLater, steps: 1)
    }

    private var valueField: some View {
        Text(Timecode.text(milliseconds: value))
            .sylviaFont(.body, monospaced: true)
            .foregroundStyle(ColorToken.ink.color)
            .fixedSize()
            .padding(.horizontal, Spacing.xs)
            .frame(minHeight: ComponentMetrics.minimumTarget)
            .sylviaFill(.surface, .control)
            .sylviaBorder(.control)
            .accessibilityLabel(Text(title))
            .accessibilityValue(Text(Timecode.text(milliseconds: value)))
            .accessibilityAdjustableAction { direction in
                switch direction {
                case .increment: move(1)
                case .decrement: move(-1)
                @unknown default: break
                }
            }
    }

    private func stepButton(systemImage: String, label: String, enabled: Bool, steps: Int) -> some View {
        Button { move(steps) } label: {
            Image(systemName: systemImage)
                .sylviaFont(.body)
                .foregroundStyle(ColorToken.ink.color)
                .frame(minWidth: ComponentMetrics.minimumTarget, minHeight: ComponentMetrics.minimumTarget)
                .sylviaFill(.surface, .control)
                .sylviaBorder(.control)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(!enabled)
        .opacity(enabled ? 1 : ComponentMetrics.disabledOpacity)
        .accessibilityLabel(Text(label))
    }
}
