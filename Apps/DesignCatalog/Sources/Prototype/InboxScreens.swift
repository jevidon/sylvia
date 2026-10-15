import SwiftUI
import SylviaDesign

/// Inbox in layout B (Section 4.1): compact rows with one trailing action or a disclosure, transfer
/// progress as a rule along the row's bottom edge, the import-state vocabulary of Section 4.4.6.
/// A Needs attention row's action is Resolve, which opens the full reason and next steps.
struct InboxScreen: View {
    @Environment(PrototypeModel.self) private var model

    var body: some View {
        AuditedScreen("inbox") {
            ScrollView {
                VStack(alignment: .leading, spacing: Spacing.m) {
                    AreaTitle(LabelKey.areaInbox.localized)
                    SylviaCard {
                        HStack(alignment: .firstTextBaseline, spacing: Spacing.s) {
                            Image(systemName: ControlSymbol.connectMac.systemName)
                                .sylviaFont(.body)
                                .foregroundStyle(ColorToken.ink.color)
                                .accessibilityHidden(true)
                            VStack(alignment: .leading, spacing: Spacing.xxs) {
                                BodyText(Microcopy.joined([Fixtures.source, "Mac"]), role: .body)
                                BodyText(Fixtures.ExampleCopy.sourceConnected, role: .caption, muted: true)
                            }
                        }
                        .accessibilityElement(children: .combine)
                    }
                    ForEach(Fixtures.InboxItem.Section.allCases, id: \.self) { section in
                        let items = model.inbox.filter { $0.section == section }
                        if !items.isEmpty {
                            SectionLabel(title(section))
                            SylviaCard(padded: false) {
                                ForEach(Array(items.enumerated()), id: \.element.id) { offset, item in
                                    if offset > 0 { SylviaRule() }
                                    row(item)
                                }
                            }
                        }
                    }
                }
                .screenGutter()
                .padding(.vertical, Spacing.m)
            }
            .background(ColorToken.ground.color.ignoresSafeArea())
            .statusBarGround()
            .sylviaScreenChrome()
        }
    }

    private func title(_ section: Fixtures.InboxItem.Section) -> String {
        switch section {
        case .transfers: "Transfers"
        // Section 4.4.6: needs_review items are "listed in the Inbox section of the same name".
        case .review: Status.needsReview.text()
        case .fromSource: "From \(Fixtures.source)"
        }
    }

    private func row(_ item: Fixtures.InboxItem) -> InboxRow {
        let pill = StatusPill.Configuration(importState: item.state, indexingContinues: item.indexingContinues,
                                            source: Fixtures.source)!
        switch item.id {
        case .monteCristo:
            let verified = Int64(Double(Fixtures.monteCristoTotal) * (item.progress ?? 0))
            let receiving = item.state == .acquiring
            return InboxRow(title: item.title, kind: item.kind, pill: pill,
                            detail: Status.bytesVerified(verified: verified, total: Fixtures.monteCristoTotal).text(),
                            detailIsValue: true, progress: item.progress,
                            trailing: .action(title: (receiving ? LabelKey.controlPause : LabelKey.controlPlay).localized,
                                              symbol: receiving ? .pause : .play) {
                                model.togglePause(item.id)
                            })
        case .karamazov:
            return InboxRow(title: item.title, kind: item.kind, pill: pill,
                            detail: Status.indexingChapters(indexed: 9, total: 96).text(),
                            trailing: .action(title: "Open") { model.inboxPath.append(.work(.karamazov)) })
        case .frankenstein:
            return InboxRow(title: item.title, kind: item.kind, pill: pill, detail: item.detail,
                            trailing: .action(title: "Resolve") { model.inboxPath.append(.inboxItem(item.id)) })
        case .essays, .walden:
            return InboxRow(title: item.title, kind: item.kind, pill: pill, detail: item.detail,
                            trailing: .disclosure { model.inboxPath.append(.inboxItem(item.id)) })
        case .leaves, .mobyDick:
            return InboxRow(title: item.title, kind: item.kind, pill: pill, detail: item.detail)
        }
    }
}

/// The detail behind Resolve (the full reason and every next step) and behind a row that needs a
/// review choice (Section 4.1, 8.2).
struct InboxDetailScreen: View {
    let id: Fixtures.InboxItemID
    @Environment(PrototypeModel.self) private var model

    var body: some View {
        let item = model.inbox.first { $0.id == id } ?? Fixtures.inbox.first { $0.id == id }!
        let presentation = item.state.presentation(indexingContinues: item.indexingContinues)
        SubPage("inbox.\(id.rawValue)", title: nil, backTitle: LabelKey.areaInbox.localized) {
            FittingText(Microcopy.joined([item.title, item.kind ?? ""]), role: .title)
                .foregroundStyle(ColorToken.ink.color)
                .accessibilityAddTraits(.isHeader)
            if let pill = StatusPill.Configuration(importState: item.state, indexingContinues: item.indexingContinues,
                                                   source: Fixtures.source) {
                StatusPill(pill)
            }
            if presentation?.requiresReasonAndNextStep == true, let reason = item.reason {
                AttentionRow(reason: reason, nextStep: item.nextSteps.joined(separator: "\n"))
                Button("Remove from the Inbox") { model.resolve(id) }
                    .buttonStyle(.sylvia(.primary))
            } else if item.state == .needsReview, let reason = item.reason {
                BodyText(reason)
                Button("Attach as an edition") { model.resolve(id) }
                    .buttonStyle(.sylvia(.primary))
                Button("Keep separate") { model.resolve(id) }
                    .buttonStyle(.sylvia(.secondary))
            } else if let reason = item.reason {
                BodyText(reason)
                BodyText(Fixtures.ExampleCopy.verifyingNothingToDo, role: .callout, muted: true)
            }
        }
    }
}
