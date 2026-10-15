import Foundation
import SwiftUI
import Testing
#if canImport(UIKit)
import UIKit
#elseif canImport(AppKit)
import AppKit
#endif
@testable import SylviaDesign

/// Component logic that does not need rendering (host and simulator): rating storage, audio
/// ranges, save states and dismissal, pills, badges, marker rows, covers, motion and the symbol and
/// metric tables (plan Section 4.4.4-4.4.7, 10.2, 11.1, 12).
@Suite("Component logic")
@MainActor
struct ComponentLogicTests {
    // MARK: Rating (stored as integer 1-10; clearing is nil, never zero)

    @Test("Rating stores 1-10 only; zero and eleven are not ratings")
    func ratingRange() {
        #expect(RatingValue(storedValue: 0) == nil)
        #expect(RatingValue(storedValue: 11) == nil)
        #expect(RatingValue(storedValue: -1) == nil)
        for v in 1...10 { #expect(RatingValue(storedValue: v)?.stars == Double(v) / 2) }
    }

    @Test("Star fills for every value, and none for no rating")
    func ratingFills() {
        #expect((0..<5).map { RatingValue.fill(star: $0, value: nil) } == Array(repeating: .empty, count: 5))
        #expect((0..<5).map { RatingValue.fill(star: $0, value: RatingValue(storedValue: 7)) }
            == [.full, .full, .full, .half, .empty])
        #expect((0..<5).map { RatingValue.fill(star: $0, value: RatingValue(storedValue: 1)) }
            == [.half, .empty, .empty, .empty, .empty])
        #expect((0..<5).map { RatingValue.fill(star: $0, value: RatingValue(storedValue: 10)) }
            == Array(repeating: .full, count: 5))
        // Every value draws a distinct sequence of the three shapes.
        let sequences = (1...10).map { v in (0..<5).map { RatingValue.fill(star: $0, value: RatingValue(storedValue: v)) } }
        #expect(Set(sequences.map { $0.map(\.rawValue).joined(separator: ",") }).count == 10)
        #expect(Set(RatingValue.StarFill.allCases.map(\.systemSymbol)).count == 3)
    }

    @Test("Tapping a star sets it full, tapping a full star sets its half; VoiceOver steps by halves")
    func ratingInteraction() {
        #expect(RatingValue.tapping(star: 2, current: nil).storedValue == 6)
        #expect(RatingValue.tapping(star: 2, current: RatingValue(storedValue: 6)).storedValue == 5)
        #expect(RatingValue.tapping(star: 2, current: RatingValue(storedValue: 5)).storedValue == 6)
        #expect(RatingValue.tapping(star: 0, current: RatingValue(storedValue: 2)).storedValue == 1)
        #expect(RatingValue.incremented(nil).storedValue == 1)
        #expect(RatingValue.incremented(RatingValue(storedValue: 10)).storedValue == 10)
        #expect(RatingValue.decremented(RatingValue(storedValue: 1))?.storedValue == 1, "decrement never clears")
        #expect(RatingValue.decremented(nil) == nil)
    }

    @Test("Rating accessibility value")
    func ratingSpoken() {
        let en = Locale(identifier: "en_US")
        #expect(RatingView.accessibilityValue(RatingValue(storedValue: 7), locale: en) == "3.5 of 5 stars")
        #expect(RatingView.accessibilityValue(RatingValue(storedValue: 4), locale: en) == "2 of 5 stars")
        #expect(RatingView.accessibilityValue(nil, locale: en) == "No rating")
    }

    // MARK: Audio range (Section 10.2: preceding 30 s, clamped; up to 120 s; numeric controls)

    @Test("Default capture is the preceding 30 seconds, clamped to the source")
    func audioRangeDefault() {
        let r = AudioRange.preceding(position: 702_000, sourceDuration: 3_600_000)
        #expect(r.startMilliseconds == 672_000 && r.endMilliseconds == 702_000)
        let early = AudioRange.preceding(position: 10_000, sourceDuration: 3_600_000)
        #expect(early.startMilliseconds == 0 && early.endMilliseconds == 10_000)
        let past = AudioRange.preceding(position: 4_000_000, sourceDuration: 3_600_000)
        #expect(past.endMilliseconds == 3_600_000 && past.lengthMilliseconds == 30_000)
    }

    @Test("Range rules hold under any sequence of moves: inside the source, 1-120 s, start before end")
    func audioRangeProperty() {
        var generator = SplitMix64(seed: 0x5EED)
        for _ in 0..<200 {
            let duration = Int64(generator.next() % 7_200_000) + 1_000
            var range = AudioRange.preceding(position: Int64(generator.next() % UInt64(duration + 1)), sourceDuration: duration)
            for _ in 0..<100 {
                let edge: AudioRange.Edge = generator.next() % 2 == 0 ? .start : .end
                let steps = Int(generator.next() % 301) - 150
                range = range.moving(edge, by: steps)
                #expect(range.startMilliseconds >= 0)
                #expect(range.endMilliseconds <= range.sourceDurationMilliseconds)
                #expect(range.lengthMilliseconds >= AudioRange.minimumLengthMilliseconds)
                #expect(range.lengthMilliseconds <= AudioRange.maximumLengthMilliseconds)
            }
        }
    }

    @Test("Moving one edge leaves the other unless a limit forces it")
    func audioRangeMoves() {
        let r = AudioRange(start: 672_000, end: 702_000, sourceDuration: 3_600_000)
        #expect(r.moving(.start, by: -1).startMilliseconds == 671_000)
        #expect(r.moving(.start, by: -1).endMilliseconds == 702_000)
        #expect(r.moving(.end, by: 3).endMilliseconds == 705_000)
        // Extending the start past 120 s stops at 120 s.
        #expect(r.moving(.start, by: -500).lengthMilliseconds == 120_000)
        #expect(r.moving(.start, by: 500).lengthMilliseconds == 1_000)
        #expect(!AudioRange(start: 0, end: 30_000, sourceDuration: 60_000).canMove(.start, by: -1))
        #expect(AudioRange(start: 0, end: 30_000, sourceDuration: 60_000).canMove(.start, by: 1))
    }

    @Test("Timecodes in the Monospace format")
    func timecodes() {
        #expect(Timecode.text(milliseconds: 672_000) == "11:12.0")
        #expect(Timecode.text(milliseconds: 3_723_550) == "1:02:03.5")
        #expect(Timecode.text(milliseconds: 30_000, tenths: false) == "0:30")
        #expect(Timecode.text(milliseconds: -5) == "0:00.0")
    }

    // MARK: Capture sheet (never dismisses with unsaved text; the button label is the save state)

    @Test("The sheet cannot be dismissed while it holds unsaved text")
    func dismissal() {
        var draft = CaptureDraft()
        #expect(draft.canDismiss, "an empty draft can close")
        draft.note = "   \n"
        #expect(draft.canDismiss, "whitespace is not text")
        draft.note = "A thought"
        #expect(!draft.canDismiss)
        draft.beginSave()
        #expect(!draft.canDismiss, "saving is not saved")
        draft.commitFailed()
        #expect(!draft.canDismiss, "a failed save keeps the text and the sheet")
        #expect(draft.saveState == .failed)
        draft.beginSave()
        let time = Date(timeIntervalSince1970: 1_790_000_000)
        draft.commitSucceeded(at: time, savedNote: "A thought")
        #expect(draft.canDismiss)
        #expect(draft.saveState == .saved(time))
        draft.note = "A thought, edited"
        draft.noteChanged()
        #expect(!draft.canDismiss)
        #expect(draft.saveState == .draft)
    }

    @Test("A commit of older text does not mark newer text saved")
    func staleCommit() {
        var draft = CaptureDraft(note: "First")
        draft.beginSave()
        draft.note = "First and second"
        draft.commitSucceeded(at: Date(timeIntervalSince1970: 0), savedNote: "First")
        #expect(draft.saveState == .draft)
        #expect(!draft.canDismiss)
    }

    @Test("The primary button's label is the save state, from the vocabulary; never Done")
    func saveLabels() {
        let en = Locale(identifier: "en_GB"), utc = TimeZone(identifier: "UTC")!
        let time = Date(timeIntervalSince1970: 1_790_000_000) // 14:13 UTC
        #expect(CaptureSaveState.draft.label(locale: en, timeZone: utc) == "Save")
        #expect(CaptureSaveState.saving.label(locale: en, timeZone: utc) == "Saving…")
        #expect(CaptureSaveState.saved(time).label(locale: en, timeZone: utc) == Status.savedAt(time).text(locale: en, timeZone: utc))
        #expect(CaptureSaveState.saved(time).label(locale: en, timeZone: utc).hasPrefix("Saved"))
        #expect(CaptureSaveState.failed.label(locale: en, timeZone: utc) == "Not saved · your text is still here")
        let labels = [CaptureSaveState.draft, .saving, .saved(time), .failed].map { $0.label(locale: en, timeZone: utc) }
        #expect(!labels.contains { $0.localizedCaseInsensitiveContains("done") })
        #expect(CaptureSaveState.saved(time).glyph == .check)
        #expect(CaptureSaveState.failed.glyph == .triangle)
    }

    @Test("\"Saved {time}\" sets exactly the time in the Monospace face; other states have no font run (R1-04)",
          arguments: ["en_GB", "en_US", "de_DE", "ja_JP"])
    func savedTimeIsMonospaced(localeIdentifier: String) {
        let locale = Locale(identifier: localeIdentifier), utc = TimeZone(identifier: "UTC")!
        let time = Date(timeIntervalSince1970: 1_790_000_000)
        let mono = Font.system(.body, design: .monospaced)
        let saved = CaptureSaveState.saved(time)
        let text = SaveStateLabel.attributed(saved, monospacedFont: mono, locale: locale, timeZone: utc)
        #expect(String(text.characters) == saved.label(locale: locale, timeZone: utc))
        let timeText = saved.timeText(locale: locale, timeZone: utc)
        #expect(timeText == TimestampText.time(time, locale: locale, timeZone: utc))
        var monospacedRuns: [String] = []
        for run in text.runs {
            let font: Font? = run.font
            if let font {
                #expect(font == mono)
                monospacedRuns.append(String(text[run.range].characters))
            }
        }
        #expect(monospacedRuns == [timeText ?? "-"], "the time and nothing else is in the Monospace face")
        for state in [CaptureSaveState.draft, .saving, .failed] {
            #expect(state.timeText(locale: locale, timeZone: utc) == nil)
            let plain = SaveStateLabel.attributed(state, monospacedFont: mono, locale: locale, timeZone: utc)
            var fontRuns = 0
            for run in plain.runs {
                let font: Font? = run.font
                if font != nil { fontRuns += 1 }
            }
            #expect(fontRuns == 0, "\(state) has no Monospace run")
        }
    }

    // MARK: Pills, badges, marker rows

    @Test("Every import state maps to a pill with a glyph, its phrase and its tint, except cancelled")
    func pills() {
        for state in ImportState.allCases {
            let config = StatusPill.Configuration(importState: state, source: "Studio")
            if state == .cancelled {
                #expect(config == nil)
                continue
            }
            guard let config else { Issue.record("\(state) has no pill"); continue }
            #expect(!config.text.isEmpty)
            #expect(config.fill.isTint, "\(state): fill \(config.fill) is not a tint")
            switch config.glyph {
            case .dot: #expect([.created, .acquiring, .staged, .validating, .identifying, .committing, .waitingForSource].contains(state))
            case .check: #expect(state == .ready)
            case .triangle: #expect([.needsReview, .waitingForSpace, .unsupported, .failedRetryable, .failedFinal].contains(state))
            }
        }
        #expect(StatusPill.Configuration(importState: .waitingForSource, source: "Studio")?.text == "Waiting for Studio")
        #expect(StatusPill.Configuration(importState: .ready, indexingContinues: true)?.text == "Ready · indexing continues")
    }

    @Test("Availability badges: solid for on this device, dashed otherwise")
    func availability() {
        #expect(!Availability.onThisDevice.isDashed)
        #expect(Availability.notOnThisDevice(source: "Studio").isDashed)
        #expect(Availability.recordOnly.isDashed)
        #expect(Availability.notOnThisDevice(source: "Studio").status.text() == "Not on this device · from Studio")
    }

    @Test("Marker rows: label, details and time; an unknown kind shows Pending with its raw kind")
    func markerRows() {
        let row = MarkerRow.Configuration(marker: .quote, details: ["Middlemarch", "Bk II, ch. 20"], timestamp: "14:02")
        #expect(row.text == "Quote · Middlemarch · Bk II, ch. 20")
        #expect(row.accessibilityText == "Quote, Middlemarch, Bk II, ch. 20, 14:02")
        let unknown = MarkerRow.Configuration(captureKind: "sketch", details: ["Walden"])
        #expect(unknown.marker == .pending)
        #expect(unknown.label == "sketch")
        #expect(unknown.glyph != Marker.quote.glyph.identifier)
        #expect(unknown.text == "sketch · Walden")
        #expect(unknown.accessibilityText == "sketch, Walden")
    }

    @Test("An empty or white-space kind still shows and speaks a label (R1-06)",
          arguments: ["", " ", "\t\n", "\u{3000}"])
    func emptyKindLabel(kind: String) {
        let row = MarkerRow.Configuration(captureKind: kind, details: ["Walden"], timestamp: "14:02")
        #expect(row.marker == .pending)
        #expect(row.label == "Unknown kind")
        #expect(row.label == LabelKey.markerUnknownKind.localized)
        #expect(row.text == "Unknown kind · Walden")
        #expect(row.accessibilityText == "Unknown kind, Walden, 14:02")
        let bare = MarkerRow.Configuration(captureKind: kind)
        #expect(bare.text == "Unknown kind")
        #expect(bare.accessibilityText == "Unknown kind")
    }

    @Test("Generated answers speak resolved and unresolved citations differently")
    func citationsSpoken() {
        let text = GeneratedAnswer.accessibilityText([.text("A"), .citation(Citation("c1", isResolved: true)),
                                                      .text("B"), .citation(Citation("c2", isResolved: false))])
        #expect(text.contains("Citation c1"))
        #expect(text.contains("Unresolved citation c2"))
    }

    // MARK: Fitting text (T51: no word broken inside at accessibility sizes)

    #if canImport(UIKit)
    @Test("FittingText keeps the size when the widest word fits and steps down only as far as needed")
    func fittingText() {
        // 362 pt: an iPhone 17 screen (402 pt) less two 20 pt gutters.
        let width: CGFloat = 362
        // Fits: unchanged at every size.
        #expect(FittingText.fittedSize("Walden", role: .title, width: width, size: .accessibility5, boldText: false)
            == .accessibility5)
        #expect(FittingText.fittedSize("Middlemarch", role: .title, width: width, size: .large, boldText: false) == .large)
        // "Middlemarch" in Title at AX5 (58 pt) is wider than 362 pt: a smaller step that fits.
        let fitted = FittingText.fittedSize("Middlemarch", role: .title, width: width, size: .accessibility5,
                                            boldText: false)
        #expect(fitted < .accessibility5 && fitted >= .large)
        let style = { (size: DynamicTypeSize) in
            TypeRole.title.resolved(contentSize: UIContentSizeCategory(size), boldText: false)
        }
        #expect(FittingText.widestWord(["Middlemarch"], style: style(.accessibility5)) > width - 1)
        #expect(FittingText.widestWord(["Middlemarch"], style: style(fitted)) <= width - 1)
        // The largest such step: one step larger does not fit.
        let steps = DynamicTypeSize.allCases
        let larger = steps[steps.firstIndex(of: fitted)! + 1]
        #expect(FittingText.widestWord(["Middlemarch"], style: style(larger)) > width - 1)
        // Never below the default size, even when nothing fits.
        #expect(FittingText.fittedSize("Middlemarch", role: .title, width: 40, size: .accessibility5, boldText: false)
            == .large)
        // Bold Text widens the word, so it never fits at a larger step than regular text.
        let bold = FittingText.fittedSize("Middlemarch", role: .title, width: width, size: .accessibility5, boldText: true)
        #expect(bold <= fitted)
    }
    #endif

    // MARK: Covers

    @Test("Cover fields come from FNV-1a over NFC UTF-8, stable and independent of composition")
    func covers() {
        // Reference FNV-1a 32-bit vectors.
        #expect(CoverFields.fnv1a32("") == 0x811C_9DC5)
        #expect(CoverFields.fnv1a32("a") == 0xE40C_292C)
        #expect(CoverFields.fnv1a32("foobar") == 0xBF9C_F968)
        // Composed and decomposed forms of the same title get the same field.
        #expect(CoverFields.field(forTitle: "Les Mis\u{E9}rables") == CoverFields.field(forTitle: "Les Mise\u{301}rables"))
        let cover = TypographicCover(title: "Middlemarch", author: "George Eliot", shape: .list, width: 112)
        #expect(cover.field == CoverFields.field(forTitle: "Middlemarch"))
        #expect(abs(cover.height - 168) < 0.001, "2:3 in lists")
        #expect(TypographicCover(title: "Walden", author: nil, shape: .square, width: 96).height == 96)
        #expect(TypographicCover(title: "Walden", author: nil, shape: .square, width: 40).isThumbnail)
    }

    @Test("Cover titles shrink so the longest word fits, down to 60%")
    func coverTitleFit() {
        for (title, width) in [("Middlemarch", 112.0), ("Meditations", 96.0), ("Walden", 112.0), ("The Brothers Karamazov", 112.0)] {
            let w = CGFloat(width)
            let size = TypographicCover.titleSize(title: title, width: w)
            let available = w * (1 - 2 * CoverLayout.insetScale)
            let widest = title.split(separator: " ").map { TypographicCover.wordWidth(String($0), size: size) }.max()!
            #expect(widest <= available, "\(title) at \(width): \(widest) > \(available)")
            #expect(size <= w * CoverLayout.titleScale)
        }
        #expect(abs(TypographicCover.titleSize(title: "Walden", width: 112) - 112 * CoverLayout.titleScale) < 0.001)
        let floor = TypographicCover.titleSize(title: "Honorificabilitudinitatibus", width: 56.5)
        #expect(abs(floor - 56.5 * CoverLayout.titleScale * CoverLayout.minimumTitleScaleFactor) < 0.001)
    }

    // MARK: Motion, symbols, metrics, buttons

    @Test("Reduce Motion removes every component animation")
    func reduceMotion() {
        for spec in [Motion.sheet, Motion.highlight, Motion.progressRule] {
            #expect(SylviaMotion.animation(spec, reduceMotion: true) == nil)
            #expect(SylviaMotion.animation(spec, reduceMotion: false) != nil)
        }
    }

    @Test("Waveform levels are deterministic and within range")
    func waveform() {
        let a = Waveform.levels(seed: "middlemarch", count: 40), b = Waveform.levels(seed: "middlemarch", count: 40)
        #expect(a == b)
        #expect(a != Waveform.levels(seed: "walden", count: 40))
        #expect(a.allSatisfy { $0 >= ComponentMetrics.waveformMinimumLevel && $0 <= 1 })
    }

    @Test("Every control symbol exists on this platform")
    func controlSymbols() {
        for symbol in ControlSymbol.allCases {
            #if canImport(UIKit)
            #expect(UIImage(systemName: symbol.systemName) != nil, "\(symbol.systemName)")
            #else
            #expect(NSImage(systemSymbolName: symbol.systemName, accessibilityDescription: nil) != nil, "\(symbol.systemName)")
            #endif
        }
        #expect(Set(ControlSymbol.allCases.map(\.systemName)).count == ControlSymbol.allCases.count)
    }

    @Test("Component metrics sit on the 4 pt grid or are stated exceptions")
    func metrics() {
        // Off-grid by design: 22 pt pill minimum (plan: 22-26), 50 pt buttons (plan), 3 pt rule (plan 2-3),
        // 2 pt waveform bars, 1 pt insets and strike, 5 pt grabber, 3 pt dash gap, 2 pt dash and bar widths.
        let exceptions: Set<String> = ["pill_minimum_height", "button_height", "progress_rule_thickness",
                                       "waveform_bar_width", "chip_vertical_inset", "strikethrough_width",
                                       "grabber_height", "dash_gap"]
        for metric in ComponentMetrics.all where !exceptions.contains(metric.name) {
            #expect(metric.points.truncatingRemainder(dividingBy: Spacing.grid) == 0, "\(metric.name) = \(metric.points)")
        }
        #expect(Set(ComponentMetrics.all.map(\.name)).count == ComponentMetrics.all.count)
        #expect(ComponentMetrics.buttonHeight == 50 && ComponentMetrics.minimumTarget == 44)
        #expect((22...26).contains(ComponentMetrics.pillMinimumHeight))
        #expect((2...3).contains(ComponentMetrics.progressRuleThickness))
        #expect((12...14).contains(ComponentMetrics.cardPadding))
        #expect(ComponentMetrics.miniPlayerGap == 12)
    }

    @Test("Button roles as Section 4.4.7 states them")
    func buttonRoles() {
        #expect(SylviaButtonRole.primary.fill == .pine && SylviaButtonRole.primary.foreground == .pineOn)
        #expect(SylviaButtonRole.primary.border == nil && SylviaButtonRole.primary.minimumHeight == 50)
        #expect(SylviaButtonRole.secondary.fill == nil && SylviaButtonRole.secondary.border == .hairline)
        #expect(SylviaButtonRole.secondary.foreground == .ink)
        #expect(SylviaButtonRole.quiet.fill == nil && SylviaButtonRole.quiet.border == nil)
        #expect(SylviaButtonRole.quiet.foreground == .pine && SylviaButtonRole.quiet.minimumHeight >= 44)
        #expect(SylviaButtonRole.destructive.foreground == .markerAttentionText)
        #expect(SylviaButtonRole.destructive.border == .markerAttentionText && SylviaButtonRole.destructive.fill == nil)
    }

    @Test("Areas: labels, symbols and Command-1/2/3")
    func areas() {
        #expect(SylviaArea.allCases.map(\.label) == ["Library", "Thoughts", "Inbox"])
        #expect(SylviaArea.allCases.map(\.keyboardShortcut.character) == ["1", "2", "3"])
        #expect(Set(SylviaArea.allCases.map(\.systemSymbol)).count == 3)
    }

    /// A clock the gate tests advance by hand.
    @MainActor
    final class ManualClock {
        var instant = ContinuousClock.now
        func advance(_ duration: Duration) { instant = instant.advanced(by: duration) }
    }

    /// A whole touch on the control: down, then lifted. Whether the Button then runs its action
    /// (a tap, or a press the viewer did not take over) is up to each test.
    private func touch(_ gate: LiftActivationGate) {
        gate.touchBegan()
        gate.touchLifted()
    }

    @Test("Large content viewer lift: the gate knows whether the Button's own action ran during the press (R2-02)")
    func liftActivationGate() {
        let gate = LiftActivationGate()
        var runs = 0
        // A tap: the Button ran for this press.
        touch(gate)
        gate.run { runs += 1 }
        #expect(gate.buttonActionRanDuringPress)
        // A long press the viewer took over: the Button's action did not run, so the lift activates.
        touch(gate)
        #expect(!gate.buttonActionRanDuringPress)
        gate.liftSettled(press: gate.liftedPress) { runs += 1 }
        #expect(gate.liftActivatedDuringPress)
        // A long press that ended as a normal tap: the Button ran, so the lift must not run it again.
        touch(gate)
        gate.run { runs += 1 }
        gate.liftSettled(press: gate.liftedPress) { runs += 1 }
        #expect(gate.buttonActionRanDuringPress && !gate.liftActivatedDuringPress)
        // The next press starts clean.
        gate.touchBegan()
        #expect(!gate.buttonActionRanDuringPress && !gate.liftActivatedDuringPress)
        #expect(runs == 3)
    }

    @Test("Large content viewer lift: one activation per press in either order, also when the Button's action arrives late (R3-02)")
    func liftActivationEitherOrder() {
        let clock = ManualClock()
        let gate = LiftActivationGate(now: { clock.instant })
        var runs = 0
        // 1. Button first, lift after the settle delay: one run.
        touch(gate)
        gate.run { runs += 1 }
        clock.advance(LargeContentViewerLift.settleDelay)
        gate.liftSettled(press: gate.liftedPress) { runs += 1 }
        #expect(runs == 1)
        // 2. Lift first (the main thread was busy for longer than the settle delay), then the same
        // press's Button action 400 ms later: the late action is dropped. One run.
        touch(gate)
        let second = gate.liftedPress
        clock.advance(LargeContentViewerLift.settleDelay)
        gate.liftSettled(press: second) { runs += 1 }
        clock.advance(.milliseconds(400))
        gate.run { runs += 1 }
        #expect(runs == 2)
        // 3. A second lift activation for the same press never runs.
        gate.liftSettled(press: second) { runs += 1 }
        #expect(runs == 2)
        // 4. A tap right after a press the viewer took over: the tap's touch lifts before its
        // action arrives, so the action is the tap's and runs, even within the window.
        touch(gate)
        gate.liftSettled(press: gate.liftedPress) { runs += 1 }
        touch(gate)
        gate.run { runs += 1 }
        #expect(runs == 4)
        // 5. A new touch begins while the late action of a lift-activated press is still on its
        // way (a busy main thread): the action belongs to the press that lifted and is dropped;
        // the new touch's own action, after it lifts, runs. Two presses, two runs.
        touch(gate)
        gate.liftSettled(press: gate.liftedPress) { runs += 1 }
        gate.touchBegan()
        gate.run { runs += 1 }
        #expect(runs == 5)
        gate.touchLifted()
        gate.run { runs += 1 }
        #expect(runs == 6)
        // 6. A press's Button action arrives after the next touch began and before the press's
        // lift activation settles: it is taken for the press that lifted, so that lift does not
        // run as well.
        touch(gate)
        let seventh = gate.liftedPress
        gate.touchBegan()
        gate.run { runs += 1 }
        clock.advance(LargeContentViewerLift.settleDelay)
        gate.liftSettled(press: seventh) { runs += 1 }
        #expect(runs == 7)
        // 7. A lift activation settles for its press after a new touch began: it runs for its own
        // press, and the new touch's action runs once that touch lifts. Two presses, two runs.
        gate.touchLifted()  // the press that began in 6 lifts; the viewer took it over (no action)
        let eighth = gate.liftedPress
        gate.touchBegan()
        gate.liftSettled(press: eighth) { runs += 1 }
        gate.touchLifted()
        gate.run { runs += 1 }
        #expect(runs == 9)
    }

    @Test("Large content viewer lift: the window, and the two stated limits of the gate (R3-02)")
    func liftActivationLimits() {
        let clock = ManualClock()
        let gate = LiftActivationGate(now: { clock.instant })
        var runs = 0
        // Only one late action is dropped, and only within the window: a touch-free action (a
        // keyboard or VoiceOver) with no touch lifting since is taken for the late action and
        // dropped; the next one runs.
        touch(gate)
        gate.liftSettled(press: gate.liftedPress) { runs += 1 }
        clock.advance(LargeContentViewerLift.lateActionWindow)
        gate.run { runs += 1 }
        gate.run { runs += 1 }
        #expect(runs == 2)
        // Later than the window after a lift activation, it runs.
        touch(gate)
        gate.liftSettled(press: gate.liftedPress) { runs += 1 }
        clock.advance(LargeContentViewerLift.lateActionWindow + .milliseconds(1))
        gate.run { runs += 1 }
        #expect(runs == 4)
        // Limit 1 (stated): a touch-free action during a press's settle delay is taken for that
        // press's own action, so the lift activation does not run as well (one activation for two).
        touch(gate)
        let fifth = gate.liftedPress
        gate.run { runs += 1 }
        clock.advance(LargeContentViewerLift.settleDelay)
        gate.liftSettled(press: fifth) { runs += 1 }
        #expect(runs == 5)
        // Limit 2 (stated): if a whole later tap lifts before the late action of a lift-activated
        // press arrives, that late action is taken for the tap's and runs, so the earlier press
        // activates twice; the tap's own action runs too.
        touch(gate)
        gate.liftSettled(press: gate.liftedPress) { runs += 1 }
        touch(gate)
        gate.run { runs += 1 }
        gate.run { runs += 1 }
        #expect(runs == 8)
        #expect(LargeContentViewerLift.lateActionWindow > LargeContentViewerLift.settleDelay)
    }

    @Test("Large content viewer lift: the item under the finger is found from the item frames (R2-02)")
    func liftItemAtPoint() {
        let frames: [SylviaArea: CGRect] = [
            .library: CGRect(x: 0, y: 0, width: 100, height: 50),
            .thoughts: CGRect(x: 100, y: 0, width: 100, height: 50),
            .inbox: CGRect(x: 200, y: 0, width: 100, height: 50),
        ]
        #expect(SylviaArea.item(at: CGPoint(x: 10, y: 25), in: frames) == .library)
        #expect(SylviaArea.item(at: CGPoint(x: 150, y: 25), in: frames) == .thoughts)
        #expect(SylviaArea.item(at: CGPoint(x: 299, y: 49), in: frames) == .inbox)
        // Outside every item (above the bar, or past its end): nothing is activated.
        #expect(SylviaArea.item(at: CGPoint(x: 150, y: -5), in: frames) == nil)
        #expect(SylviaArea.item(at: CGPoint(x: 301, y: 25), in: frames) == nil)
        #expect(SylviaArea.item(at: CGPoint(x: 150, y: 25), in: [:]) == nil)
    }
}

/// A small deterministic generator for the property tests.
struct SplitMix64 {
    var state: UInt64
    init(seed: UInt64) { state = seed }
    mutating func next() -> UInt64 {
        state &+= 0x9E37_79B9_7F4A_7C15
        var z = state
        z = (z ^ (z >> 30)) &* 0xBF58_476D_1CE4_E5B9
        z = (z ^ (z >> 27)) &* 0x94D0_49BB_1331_11EB
        return z ^ (z >> 31)
    }
}
