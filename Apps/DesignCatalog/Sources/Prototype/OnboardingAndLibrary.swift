import SwiftUI
import SylviaDesign

/// Onboarding (Section 4.2): "Import a book", "Connect a Mac" and "Add a record", a bundled sample
/// for trying capture offline, and the note that AI is optional. No API keys, no permissions.
struct OnboardingScreen: View {
    @Environment(PrototypeModel.self) private var model

    var body: some View {
        AuditedScreen("onboarding") {
            ScrollView {
                VStack(alignment: .leading, spacing: Spacing.m) {
                    FittingText("Sylvia", role: .display)
                        .foregroundStyle(ColorToken.ink.color)
                        .accessibilityAddTraits(.isHeader)
                        .padding(.top, Spacing.xxl)
                    BodyText("Your library of thought.", role: .heading, muted: true)
                    BodyText("Read and listen. Keep the passages and your thinking about them. Find them again long after the file is gone.")
                        .padding(.bottom, Spacing.s)
                    ActionCard(symbol: .importFile, title: "Import a book",
                               detail: "EPUB, PDF or audiobook from Files, AirDrop or a link.") { finish(.inbox) }
                    ActionCard(symbol: .connectMac, title: "Connect a Mac",
                               detail: "Pair once. Pull books over your network or a cable.") { finish(.inbox) }
                    ActionCard(symbol: .edit, title: "Add a record",
                               detail: "A book on paper, or one you read elsewhere. Keep its history here.") {
                        finish(.library)
                        model.libraryPath = [.work(.meditations)]
                    }
                    Button {
                        model.showsOnboarding = false
                        model.readerOpen = true
                    } label: {
                        Label { Text("Try capture with a short sample book") } icon: {
                            Image(systemName: ControlSymbol.disclosure.systemName)
                        }
                        .labelStyle(TrailingIconLabelStyle())
                    }
                    .buttonStyle(.sylvia(.quiet))
                    BodyText("Licensed and bundled. Works in airplane mode.", role: .caption, muted: true)
                    SylviaRule()
                    BodyText("AI is optional. Nothing here needs an account, a server or a model. Your library stays on this phone until you make a backup.",
                             role: .caption, muted: true)
                }
                .screenGutter()
                .padding(.bottom, Spacing.xl)
            }
            .background(ColorToken.ground.color.ignoresSafeArea())
            .statusBarGround()
        }
    }

    private func finish(_ area: SylviaArea) {
        model.area = area
        model.showsOnboarding = false
    }
}

/// Puts the icon after the title (disclosure chevrons on quiet buttons).
struct TrailingIconLabelStyle: LabelStyle {
    func makeBody(configuration: Configuration) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: Spacing.xs) {
            configuration.title
            configuration.icon.accessibilityHidden(true)
        }
    }
}

/// Library (Section 4.1): status filters, the work being read and listened to, recent works with
/// their availability; works without a file use the record-only badge, never a broken state.
struct LibraryScreen: View {
    @Environment(PrototypeModel.self) private var model
    @State private var filter: LibraryFilter = .all

    var body: some View {
        AuditedScreen("library") {
            ScrollView {
                VStack(alignment: .leading, spacing: Spacing.m) {
                    AreaTitle(LabelKey.areaLibrary.localized, trailing: [
                        // Search lives in Thoughts in this prototype (catalog and knowledge search).
                        .search { model.area = .thoughts },
                        SylviaBarItem(systemImage: ControlSymbol.importFile.systemName, label: "Import") {
                            model.area = .inbox
                        },
                        .settings { model.libraryPath.append(.settings) },
                    ])
                    FilterChips([
                        FilterChip(LibraryFilter.all, label: "All"),
                        FilterChip(.reading, label: "Reading"),
                        FilterChip(.listening, label: "Listening"),
                        FilterChip(.onDevice, label: Status.onThisDevice.text()),
                    ], selection: $filter)
                    if let middlemarch = model.work(.middlemarch), !model.deletedWorks.contains(.middlemarch),
                       middlemarch.filters.contains(filter) {
                        SectionLabel("Continue")
                        ContinueCard(work: middlemarch)
                    }
                    SectionLabel("Recent")
                    VStack(spacing: 0) {
                        ForEach(model.visibleWorks.filter { $0.id != .middlemarch && $0.filters.contains(filter) }) { work in
                            WorkRow(work: work) { model.libraryPath.append(.work(work.id)) }
                            SylviaRule()
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
}

/// The "Continue" card: cover, title, progress in the book and the recording, Listen and Read.
private struct ContinueCard: View {
    let work: Work
    @Environment(PrototypeModel.self) private var model

    var body: some View {
        SylviaCard {
            VStack(alignment: .leading, spacing: Spacing.s) {
                Button { model.libraryPath.append(.work(work.id)) } label: {
                    // At accessibility sizes the cover sits above the text, which then has the
                    // card's full width (the row was wider than the screen at AX5).
                    AdaptiveRow {
                        TypographicCover(title: work.title, author: work.author, shape: .list,
                                         width: ComponentMetrics.listCover)
                        VStack(alignment: .leading, spacing: Spacing.xxs) {
                            FittingText(work.title, role: .title).foregroundStyle(ColorToken.ink.color)
                            BodyText(Microcopy.joined([work.author, "2nd read"]), role: .callout, muted: true)
                            AvailabilityBadge(work.availability)
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                    }
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                ProgressRule(fraction: 0.38, position: .chapter(20, of: 86))
                ProgressRule(fraction: 0.4, position: .part(14, of: 35), secondsRemaining: 20 * 3600 + 58 * 60)
                ViewThatFits(in: .horizontal) {
                    HStack(spacing: Spacing.s) { buttons }
                    VStack(spacing: Spacing.s) { buttons }
                }
            }
        }
    }

    @ViewBuilder private var buttons: some View {
        Button { model.playerOpen = true } label: {
            Label { Text("Listen") } icon: { Image(systemName: ControlSymbol.play.systemName) }
        }
        .buttonStyle(.sylvia(.primary))
        Button("Read") { model.readerOpen = true }
            .buttonStyle(.sylvia(.secondary))
    }
}

/// A Library row: cover, title, author, what is here, and a disclosure.
struct WorkRow: View {
    let work: Work
    let action: () -> Void
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    var body: some View {
        Button(action: action) {
            AdaptiveRow {
                TypographicCover(title: work.title, author: work.author, shape: .list, width: ComponentMetrics.listCover)
                VStack(alignment: .leading, spacing: Spacing.xxs) {
                    FittingText(work.title, role: .heading).foregroundStyle(ColorToken.ink.color)
                    BodyText(work.author, role: .callout, muted: true)
                    if let rating = work.rating {
                        RatingView(rating)
                    }
                    if let line = work.readingLine {
                        BodyText(line, role: .caption, muted: true)
                    }
                    AvailabilityBadge(work.availability)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                if !dynamicTypeSize.isAccessibilitySize {
                    Image(systemName: ControlSymbol.disclosure.systemName)
                        .sylviaFont(.body)
                        .foregroundStyle(ColorToken.muted.color)
                        .accessibilityHidden(true)
                }
            }
            .padding(.vertical, Spacing.s)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(.isButton)
    }
}

/// Work detail (Section 4.1, 12): editions and where each file is, rating, history. A record with
/// no file never looks broken: "Record only"; a file elsewhere: "Not on this device · from Studio".
struct WorkDetailScreen: View {
    let id: WorkID
    @Environment(PrototypeModel.self) private var model

    var body: some View {
        @Bindable var model = model
        if let index = model.works.firstIndex(where: { $0.id == id }) {
            let work = model.works[index]
            SubPage("work.\(id.rawValue)", title: nil, backTitle: LabelKey.areaLibrary.localized) {
                AdaptiveRow(spacing: Spacing.m) {
                    TypographicCover(title: work.title, author: work.author, shape: .list, width: ComponentMetrics.detailCover)
                    VStack(alignment: .leading, spacing: Spacing.xs) {
                        FittingText(work.title, role: .title).foregroundStyle(ColorToken.ink.color)
                            .accessibilityAddTraits(.isHeader)
                        BodyText(work.author, role: .body, muted: true)
                        BodyText(work.meta, role: .caption, muted: true)
                        AvailabilityBadge(work.availability)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
                RatingView(value: $model.works[index].rating)
                primaryActions(work)
                SectionLabel("Editions")
                SylviaCard(padded: false) {
                    if work.editions.isEmpty {
                        BodyText("No file. The record keeps your history, rating and thoughts.", role: .callout, muted: true)
                            .padding(ComponentMetrics.cardPadding)
                    }
                    ForEach(Array(work.editions.enumerated()), id: \.element.id) { offset, edition in
                        if offset > 0 { SylviaRule() }
                        EditionRow(edition: edition, work: work)
                    }
                }
                if work.availability == .onThisDevice {
                    SylviaCard(padded: false) {
                        CardRow("Storage", caption: "Downloads, excerpt audio and retained text") {
                            model.libraryPath.append(.storage(work.id))
                        }
                    }
                }
                SectionLabel("History")
                SylviaCard {
                    VStack(alignment: .leading, spacing: Spacing.s) {
                        ForEach(work.history) { entry in
                            ViewThatFits(in: .horizontal) {
                                HStack(alignment: .firstTextBaseline, spacing: Spacing.s) { historyParts(entry) }
                                VStack(alignment: .leading, spacing: Spacing.xxs) { historyParts(entry) }
                            }
                            .accessibilityElement(children: .combine)
                        }
                    }
                }
            }
        }
    }

    @ViewBuilder private func historyParts(_ entry: HistoryEntry) -> some View {
        Text(entry.date).sylviaFont(.caption, monospaced: true).foregroundStyle(ColorToken.muted.color)
            .fixedSize()
        Text(entry.text).sylviaFont(.body).foregroundStyle(ColorToken.ink.color)
            .fixedSize(horizontal: false, vertical: true)
    }

    @ViewBuilder private func primaryActions(_ work: Work) -> some View {
        switch work.availability {
        case .onThisDevice:
            ViewThatFits(in: .horizontal) {
                HStack(spacing: Spacing.s) { onDeviceButtons(work) }
                VStack(spacing: Spacing.s) { onDeviceButtons(work) }
            }
        case .notOnThisDevice(let source):
            Button("Download from \(source)") {
                model.area = .inbox
                model.libraryPath.removeAll()
            }
            .buttonStyle(.sylvia(.primary))
        case .recordOnly:
            Button("Add a file") {
                model.area = .inbox
                model.libraryPath.removeAll()
            }
            .buttonStyle(.sylvia(.primary))
        }
    }

    @ViewBuilder private func onDeviceButtons(_ work: Work) -> some View {
        if work.id == .middlemarch {
            Button { model.playerOpen = true } label: {
                Label { Text("Continue") } icon: { Image(systemName: ControlSymbol.play.systemName) }
            }
            .buttonStyle(.sylvia(.primary))
            Button("Read") { model.readerOpen = true }
                .buttonStyle(.sylvia(.secondary))
        } else {
            Button("Read") { model.readerOpen = true }
                .buttonStyle(.sylvia(.primary))
        }
    }
}

private struct EditionRow: View {
    let edition: Edition
    let work: Work
    @Environment(PrototypeModel.self) private var model

    var body: some View {
        VStack(alignment: .leading, spacing: Spacing.xs) {
            BodyText(Microcopy.joined([edition.kind.label, edition.source]), role: .body)
            BodyText(Microcopy.joined([edition.size, edition.position ?? ""]), role: .caption, muted: true)
            AvailabilityBadge(edition.availability)
            if edition.availability == .onThisDevice {
                Button(Status.removeDownload.text()) {
                    model.libraryPath.append(.storage(work.id))
                    model.impactReport = edition.kind == .audiobook ? .audiobook : .epub
                }
                .buttonStyle(.sylvia(.quiet))
            }
        }
        .padding(ComponentMetrics.cardPadding)
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}
