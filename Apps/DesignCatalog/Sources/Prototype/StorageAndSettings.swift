import SwiftUI
import SylviaDesign

/// Storage for one work (Section 17.2; board "Storage, remove-download sheet"): the four separate
/// removal actions in the vocabulary's words, each removal behind an impact report that names what
/// is freed, what is kept and anything pending, with the safe choice as the primary button.
struct StorageScreen: View {
    let id: WorkID
    @Environment(PrototypeModel.self) private var model

    var body: some View {
        @Bindable var model = model
        if let work = model.work(id) {
            SubPage("storage", title: nil, backTitle: work.title) {
                FittingText("Storage", role: .title)
                    .foregroundStyle(ColorToken.ink.color)
                    .accessibilityAddTraits(.isHeader)
                SylviaCard(padded: false) {
                    ForEach(Array(work.editions.enumerated()), id: \.element.id) { offset, edition in
                        if offset > 0 { SylviaRule() }
                        StorageRow(title: "\(edition.kind.label) download",
                                   detail: Microcopy.joined([edition.size, edition.availability.status.text()]),
                                   action: edition.availability == .onThisDevice ? Status.removeDownload.text() : nil) {
                            model.impactReport = edition.kind == .audiobook ? .audiobook : .epub
                        }
                    }
                    SylviaRule()
                    StorageRow(title: "Excerpt audio", detail: Microcopy.joined(["4 excerpts", "12 MB"]),
                               action: Status.removeExcerptAudio.text()) { model.impactReport = .excerpts }
                    SylviaRule()
                    StorageRow(title: "Retained text", detail: "Kept for search and quotes · 2.3 MB",
                               action: Status.manageRetainedText.text()) {}
                }
                BodyText("Removing a download never removes your thoughts, history, rating or recommendations.",
                         role: .caption, muted: true)
                Button(Status.deleteRecordAndThoughts.text()) { model.impactReport = .record }
                    .buttonStyle(.sylvia(.destructive))
                    .padding(.top, Spacing.xl)
            }
            .sylviaSheet(isPresented: Binding(get: { model.impactReport != nil }, set: { if !$0 { model.impactReport = nil } }),
                         canDismiss: true) {
                SheetPage("impactReport") { impactReport(work: work) }
            }
        }
    }

    @ViewBuilder private func impactReport(work: Work) -> some View {
        switch model.impactReport {
        case .audiobook:
            ImpactReport(title: "Remove the audiobook download?", lines: [
                ImpactLine(1, "Frees 1.9 GB on this phone."),
                ImpactLine(2, "Keeps 23 thoughts, 4 audio excerpts, your history, rating and recommendations."),
                ImpactLine(3, "Can be downloaded again from \(Fixtures.source), last seen today."),
            ], pending: .init(reason: Fixtures.ExampleCopy.pendingExcerptReason,
                              nextStep: Fixtures.ExampleCopy.pendingExcerptNextStep),
            safeChoice: .init("Wait, then remove") { model.impactReport = nil },
            secondary: .init("Cancel") { model.impactReport = nil },
            destructive: .init("Remove now and lose that excerpt") {
                model.removeDownload(.audiobook, of: work.id)
                model.impactReport = nil
            })
        case .epub:
            ImpactReport(title: "Remove the EPUB download?", lines: [
                ImpactLine(1, "Frees 1.2 MB on this phone."),
                ImpactLine(2, "Keeps your quotes with their exact text, your notes, history and rating."),
                ImpactLine(3, "Book text search stops until the EPUB is back."),
            ], pending: nil,
            safeChoice: .init("Keep the download") { model.impactReport = nil },
            destructive: .init(Status.removeDownload.text()) {
                model.removeDownload(.epub, of: work.id)
                model.impactReport = nil
            })
        case .excerpts:
            ImpactReport(title: Status.removeExcerptAudio.text() + "?", lines: [
                ImpactLine(1, "Frees 12 MB on this phone."),
                ImpactLine(2, "Keeps each audio thought's time range and your notes; they play again only from the audiobook."),
            ], pending: nil,
            safeChoice: .init("Keep the excerpt audio") { model.impactReport = nil },
            destructive: .init(Status.removeExcerptAudio.text()) { model.impactReport = nil })
        case .record:
            ImpactReport(title: "Delete \(work.title) and its thoughts?", lines: [
                ImpactLine(1, "Deletes the record, its history, rating and 23 thoughts from this phone."),
                ImpactLine(2, "Files on \(Fixtures.source) are not touched."),
            ], pending: nil,
            safeChoice: .init("Keep the record") { model.impactReport = nil },
            destructive: .init(Status.deleteRecordAndThoughts.text()) {
                model.impactReport = nil
                model.deleteRecord(work.id)
            })
        case nil:
            EmptyView()
        }
    }
}

/// One storage line: what it is, its size and where it is, and one removal action.
private struct StorageRow: View {
    let title: String
    let detail: String
    let action: String?
    let perform: () -> Void

    var body: some View {
        ViewThatFits(in: .horizontal) {
            HStack(alignment: .center, spacing: Spacing.s) { parts }
            VStack(alignment: .leading, spacing: Spacing.xs) { parts }
        }
        .padding(.horizontal, ComponentMetrics.cardPadding)
        .padding(.vertical, Spacing.s)
    }

    @ViewBuilder private var parts: some View {
        VStack(alignment: .leading, spacing: Spacing.xxs) {
            Text(title).sylviaFont(.body, weight: ComponentMetrics.labelWeight).foregroundStyle(ColorToken.ink.color)
                .fixedSize(horizontal: false, vertical: true)
            Text(detail).sylviaFont(.caption).foregroundStyle(ColorToken.muted.color)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityElement(children: .combine)
        if let action {
            Button(action, action: perform)
                .buttonStyle(.sylvia(.quiet, fillsWidth: false))
        }
    }
}

/// Settings in the prototype: the controls that make failure states reachable (a failed save, a
/// failed excerpt, an interrupted answer, a slow write), and the way back to onboarding.
struct SettingsScreen: View {
    @Environment(PrototypeModel.self) private var model

    var body: some View {
        @Bindable var model = model
        SubPage("settings", title: LabelKey.navSettings.localized, backTitle: LabelKey.areaLibrary.localized) {
            BodyText("This is a prototype with fixture data. These controls make the failure states reachable.",
                     role: .callout, muted: true)
            SectionLabel("Prototype controls")
            SylviaCard {
                toggle("Next save fails", isOn: $model.nextSaveFails)
                toggle("Next excerpt is not preserved", isOn: $model.nextExcerptFails)
                toggle("Next audio moment is not written", isOn: $model.nextMomentFails)
                toggle("Next answer is interrupted", isOn: $model.nextAnswerInterrupted)
                toggle("Slow writes (5 seconds)", isOn: Binding(get: { model.writeDuration >= .seconds(5) },
                                                                set: { model.writeDuration = $0 ? .seconds(5) : .milliseconds(1500) }))
            }
            SylviaCard(padded: false) {
                CardRow("Show onboarding") {
                    model.libraryPath.removeAll()
                    model.showsOnboarding = true
                }
                if let leave = model.onLeave {
                    SylviaRule()
                    CardRow("Leave the prototype", caption: "Back to the design catalog") { leave() }
                }
            }
        }
    }

    private func toggle(_ title: String, isOn: Binding<Bool>) -> some View {
        Toggle(isOn: isOn) {
            Text(title).sylviaFont(.body).foregroundStyle(ColorToken.ink.color)
                .fixedSize(horizontal: false, vertical: true)
        }
        .tint(ColorToken.pine.color)
        .frame(minHeight: ComponentMetrics.minimumTarget)
    }
}
