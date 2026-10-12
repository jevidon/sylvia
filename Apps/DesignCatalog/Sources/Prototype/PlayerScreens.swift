import SwiftUI
import SylviaDesign

/// The player as a full-screen flow: the player, then the audio capture detail pushed on top.
struct PlayerFlow: View {
    @Environment(PrototypeModel.self) private var model

    var body: some View {
        @Bindable var model = model
        NavigationStack(path: $model.playerPath) {
            PlayerScreen().destinations()
        }
    }
}

/// Player with the capture control (Section 10, 4.4.7; board "Player with capture control"). The
/// capture control keeps the moment first ("Moment saved · preserving audio"), then reports the
/// preserved excerpt ("Audio excerpt saved") or the failure with its retry ("Excerpt not
/// preserved · Retry"), in the vocabulary's words (Section 4.4.6 "Capturing audio").
struct PlayerScreen: View {
    @Environment(PrototypeModel.self) private var model

    var body: some View {
        AuditedScreen("player") {
            VStack(spacing: 0) {
                SylviaNavigationBar(title: "Now playing", trailing: [
                    SylviaBarItem(systemImage: ControlSymbol.dismiss.systemName, label: "Close player") { close() },
                ])
                ScrollView {
                    VStack(alignment: .leading, spacing: Spacing.m) {
                        TypographicCover(title: "Middlemarch", author: "George Eliot", shape: .square,
                                         width: ComponentMetrics.playerCover)
                            .frame(maxWidth: .infinity)
                        FittingText("Middlemarch", role: .title)
                            .foregroundStyle(ColorToken.ink.color)
                            .accessibilityAddTraits(.isHeader)
                        BodyText(Microcopy.joined(["George Eliot", "LibriVox recording", "35 files"]), role: .callout, muted: true)
                        ProgressRule(fraction: 0.4, position: .part(14, of: 35), secondsRemaining: 20 * 3600 + 58 * 60)
                        transport
                        FlowButtons()
                        Button {
                            model.captureMoment()
                        } label: {
                            Label { Text(LabelKey.symbolCapture.localized) } icon: {
                                CustomSymbol.capture.image.accessibilityHidden(true)
                            }
                        }
                        .buttonStyle(.sylvia(.secondary))
                        .accessibilityLabel(Text(LabelKey.controlCaptureRecent.localized))
                        .disabled(model.excerptPhase == .preserving)
                        excerptStatus
                    }
                    .screenGutter()
                    .padding(.vertical, Spacing.m)
                }
            }
            .background(ColorToken.ground.color.ignoresSafeArea())
            .sylviaScreenChrome()
        }
    }

    private var transport: some View {
        @Bindable var model = model
        return HStack(spacing: Spacing.xl) {
            SylviaIconButton(systemImage: ControlSymbol.skipBack.systemName, label: "Back 30 seconds") {}
            PlayPauseButton(isPlaying: model.isPlaying) { model.isPlaying.toggle() }
            SylviaIconButton(systemImage: ControlSymbol.skipForward.systemName, label: "Forward 30 seconds") {}
        }
        .frame(maxWidth: .infinity)
    }

    @ViewBuilder private var excerptStatus: some View {
        let range = Microcopy.joined([Timecode.text(milliseconds: model.audioRange.startMilliseconds) + " to "
            + Timecode.text(milliseconds: model.audioRange.endMilliseconds)])
        switch model.excerptPhase {
        case .none:
            EmptyView()
        case .preserving:
            StatusBanner(.pending(.momentSavedPreservingAudio), detail: range)
        case .saved:
            StatusBanner(.ready(.audioExcerptSaved), detail: range + ". " + Fixtures.ExampleCopy.excerptKeptAfterRemoval,
                         actionTitle: "Open") { model.playerPath.append(.audioCapture) }
        case .failed:
            // The phrase names the action: the whole banner retries.
            StatusBanner(.attention(.excerptNotPreserved),
                         detail: Fixtures.ExampleCopy.excerptUnreadableMomentKept) {
                model.captureMoment()
            }
        case .momentNotSaved:
            // Nothing was written, so no "saved" phrase and no "Excerpt not preserved" (which says
            // the bookmark survived). The vocabulary has no phrase for this yet (report, Open
            // question 12); the attention status with a plain detail stands in, and tapping retries.
            StatusBanner(.attention(.needsAttention),
                         detail: Fixtures.ExampleCopy.momentNotWritten) {
                model.captureMoment()
            }
        }
    }

    private func close() {
        model.playerOpen = false
        model.playerPath.removeAll()
        if model.startedInPlayer { model.onLeave?() }
    }
}

/// Speed, sleep timer and chapters as secondary buttons: one centered row when it fits (the
/// board), else speed and sleep on one row with chapters under them, else (accessibility sizes)
/// one full-width button per row.
private struct FlowButtons: View {
    @Environment(PrototypeModel.self) private var model

    var body: some View {
        ViewThatFits(in: .horizontal) {
            HStack(spacing: Spacing.xs) {
                speed(fills: false)
                sleep(fills: false)
                chapters(fills: false)
            }
            VStack(spacing: Spacing.xs) {
                HStack(spacing: Spacing.xs) {
                    speed(fills: false)
                    sleep(fills: false)
                }
                chapters(fills: false)
            }
            VStack(spacing: Spacing.xs) {
                speed(fills: true)
                sleep(fills: true)
                chapters(fills: true)
            }
        }
        .frame(maxWidth: .infinity)
    }

    private func speed(fills: Bool) -> some View {
        Button(rateText(model.playbackRate)) {
            model.playbackRate = model.playbackRate >= 2 ? 1 : model.playbackRate + 0.25
        }
        .buttonStyle(.sylvia(.secondary, fillsWidth: fills))
        .accessibilityLabel(Text("Speed"))
        .accessibilityValue(Text(rateText(model.playbackRate)))
    }

    // Sleep timer and chapters are inert in the prototype (no playback engine); the report lists them.
    private func sleep(fills: Bool) -> some View {
        Button {} label: {
            Label { Text("Sleep · Off") } icon: { Image(systemName: ControlSymbol.sleepTimer.systemName) }
        }
        .buttonStyle(.sylvia(.secondary, fillsWidth: fills))
    }

    private func chapters(fills: Bool) -> some View {
        Button {} label: {
            Label { Text("Chapters") } icon: { Image(systemName: ControlSymbol.chapters.systemName) }
        }
        .buttonStyle(.sylvia(.secondary, fillsWidth: fills))
    }
}

/// Audio capture detail (Section 10.2, 10.3; board "Audio capture detail"): the excerpt with its
/// play control (preview never moves the main position), numeric start and end, its save state,
/// the transcript state (no transcript is ever invented), and the note.
struct AudioCaptureScreen: View {
    @Environment(PrototypeModel.self) private var model
    @State private var previewing = false

    var body: some View {
        @Bindable var model = model
        SubPage("audioCapture", title: "Audio capture", backTitle: "Player") {
            MarkerRow(MarkerRow.Configuration(marker: .audio, details: ["Middlemarch", "Part 14",
                                                                         Durations.text(seconds: Int(model.audioRange.lengthMilliseconds / 1000))],
                                              timestamp: "11:40"))
            AudioBlock(seed: "middlemarch-14-1112", isPlaying: previewing) { previewing.toggle() }
            BodyText("Plays only this excerpt. Your place in the book does not move.", role: .caption, muted: true)
            AudioRangeControls(range: $model.audioRange)
            if model.audioRange != model.savedAudioRange {
                // A changed range is not saved until the new excerpt is preserved.
                Button(LabelKey.actionSave.localized) { model.preserveEditedRange() }
                    .buttonStyle(.sylvia(.primary))
                    .disabled(model.excerptPhase == .preserving)
            }
            switch model.excerptPhase {
            case .preserving:
                StatusBanner(.pending(.momentSavedPreservingAudio))
            case .saved where model.audioRange == model.savedAudioRange:
                StatusBanner(.ready(.audioExcerptSaved), detail: Fixtures.ExampleCopy.excerptKeptIfRemoved)
            case .failed:
                StatusBanner(.attention(.excerptNotPreserved), detail: Fixtures.ExampleCopy.excerptUnreadable) {
                    model.preserveEditedRange()
                }
            case .momentNotSaved:
                StatusBanner(.attention(.needsAttention),
                             detail: Fixtures.ExampleCopy.momentNotWritten) {
                    model.preserveEditedRange()
                }
            default:
                EmptyView()
            }
            SectionLabel(LabelKey.audioTranscript.localized)
            SylviaCard {
                VStack(alignment: .leading, spacing: Spacing.xs) {
                    BodyText(LabelKey.audioNoTranscript.localized, role: .body)
                    BodyText("No speech service is set up. Transcribing would send only this excerpt to a service you choose, never the audiobook.",
                             role: .callout, muted: true)
                    ViewThatFits(in: .horizontal) {
                        HStack(spacing: Spacing.m) { transcriptButtons }
                        VStack(alignment: .leading, spacing: 0) { transcriptButtons }
                    }
                }
            }
            SectionLabel(LabelKey.captureYourNote.localized)
            if let note = model.audioNote {
                SylviaCard { BodyText(note) }
            }
            Button(model.audioNote == nil ? "Add a note" : "Edit the note") { model.openCapture(.audioNote) }
                .buttonStyle(.sylvia(.secondary))
        }
        .sylviaSheet(isPresented: model.captureSheetBinding(.audioNote), canDismiss: model.draft.canDismiss) {
            SheetPage("captureSheet") {
                CaptureSheet(draft: $model.draft, subject: $model.captureSubject, source: ["Middlemarch", "Part 14"],
                             onSave: model.save, onClose: model.closeCapture, onLookUp: {}, onAsk: {})
            }
        }
    }

    @ViewBuilder private var transcriptButtons: some View {
        Button("Set up transcription") {}
            .buttonStyle(.sylvia(.quiet, fillsWidth: false))
        Button("Type what you heard") {}
            .buttonStyle(.sylvia(.quiet, fillsWidth: false))
    }
}
