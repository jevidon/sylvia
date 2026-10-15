#if os(iOS)
import SwiftUI
import Testing
import UIKit
@testable import SylviaDesign
import SylviaDesignGallery

/// The components' accessibility tree as UIKit exposes it from the SwiftUI hosting view (Section
/// 4.4.7, 4.4.8, 18.3): labels on every control and icon-only button, button and selected traits on
/// the tab bar, sidebar and reader chrome, and adjustable values on the rating and the audio range.
/// The large content viewer cannot be observed here: SwiftUI does not expose it through the
/// accessibility elements (measured: no element reports `showsLargeContentViewer`), so it is a
/// device checklist step.
@Suite("Accessibility tree")
@MainActor
struct AccessibilityTreeTests {
    static func tree(_ name: String, _ variant: Variant = Variant(.light, .standard)) -> [AXNode] {
        let sample = Gallery.sample(name)
        return Renderer.render(sample.content, variant: variant, width: sample.width, height: sample.height,
                               sizeClass: sample.sizeClass).elements
    }

    @Test("UI automation exposes the SwiftUI accessibility tree in the test process")
    func treeIsAvailable() {
        #expect(Renderer.accessibilityEnabled)
        #expect(!Self.tree("buttons").isEmpty)
    }

    @Test("Every element has a label; every button has a non-empty label", arguments: Gallery.names)
    func everyElementLabelled(_ name: String) {
        let elements = Self.tree(name)
        // Text fields are not exposed by this offscreen renderer (the capture sheet's note field is
        // absent from its tree too), so the text-field sample has no elements here. Its labels are
        // checked in a real window by the design catalog's UI tests (Apps/DesignCatalog/UITests).
        if name == "textField" {
            #expect(elements.isEmpty, "the renderer now exposes text fields; check their labels here: \(elements)")
            // Still reported, so the report (written once every sample has reported) is complete.
            AccessibilityReport.shared.add(name, elements)
            return
        }
        #expect(!elements.isEmpty, "\(name): no accessibility elements")
        for element in elements {
            #expect(!element.label.trimmingCharacters(in: .whitespaces).isEmpty, "\(name): unlabelled \(element)")
        }
        AccessibilityReport.shared.add(name, elements)
    }

    @Test("Tab bar items: buttons with labels, one selected, Inbox attention as a value")
    func tabBar() {
        let elements = Self.tree("tabBar")
        let areas = SylviaArea.allCases.map(\.label)
        let items = elements.filter { areas.contains($0.label) }
        #expect(items.count == 6, "\(elements)")
        #expect(items.allSatisfy { $0.isButton }, "\(items)")
        // First bar: Library selected, no attention. Second bar: Thoughts selected, Inbox needs attention.
        let first = Array(items.prefix(3)), second = Array(items.suffix(3))
        #expect(first.map(\.isSelected) == [true, false, false], "\(first)")
        #expect(second.map(\.isSelected) == [false, true, false], "\(second)")
        #expect(first[2].value.isEmpty, "\(first[2])")
        #expect(second[2].value == Status.needsAttention.text(), "\(second[2])")
    }

    @Test("Hardware keyboard: Command-1, -2, -3 select Library, Thoughts, Inbox")
    func keyboardShortcuts() {
        #expect(SylviaArea.allCases.map(\.keyboardShortcut.character) == ["1", "2", "3"])
    }

    @Test("Area navigation: a tab bar along the bottom in compact width, a sidebar on the leading edge in regular width")
    func areaNavigation() {
        let view = SylviaAreaNavigation(selection: .constant(.library), inboxNeedsAttention: false) {
            ColorToken.ground.color
        }
        for sizeClass in [UIUserInterfaceSizeClass.compact, .regular] {
            let width: CGFloat = sizeClass == .regular ? 1024 : RecordingDevice.width
            let r = Renderer.render(view, variant: Variant(.light, .standard), width: width, height: 700, sizeClass: sizeClass)
            let frames = SylviaArea.allCases.compactMap { r.audit.regions["area.\($0.rawValue)"] }
            guard frames.count == 3 else { Issue.record("\(sizeClass): \(r.audit.regions.keys.sorted())"); continue }
            if sizeClass == .compact {
                let rows = frames.map(\.midY)
                #expect(rows.max()! - rows.min()! < Spacing.xxs && frames[0].maxX <= frames[1].minX
                        && frames[1].maxX <= frames[2].minX, "one row, left to right: \(frames)")
                #expect(frames.allSatisfy { $0.maxY > 600 }, "tab bar at the bottom: \(frames)")
            } else {
                #expect(Set(frames.map(\.minX)).count == 1 && frames[0].maxY <= frames[1].minY
                        && frames[1].maxY <= frames[2].minY, "one column, top to bottom: \(frames)")
                #expect(frames.allSatisfy { $0.maxX <= ComponentMetrics.sidebarWidth }, "sidebar on the leading edge: \(frames)")
            }
            #expect(r.elements.filter { $0.isButton }.map(\.label) == SylviaArea.allCases.map(\.label), "\(r.elements)")
        }
    }

    @Test("Sidebar rows: buttons, Thoughts selected, Inbox attention")
    func sidebar() {
        let elements = Self.tree("sidebar")
        #expect(elements.map(\.label) == SylviaArea.allCases.map(\.label), "\(elements)")
        #expect(elements.allSatisfy { $0.isButton })
        #expect(elements.map(\.isSelected) == [false, true, false])
        #expect(elements.last?.value == Status.needsAttention.text())
    }

    @Test("Navigation bar and reader chrome: labelled icon buttons")
    func bars() {
        let nav = Self.tree("navigationBar")
        for label in [LabelKey.navSearch.localized, LabelKey.navSettings.localized, "Reader"] {
            let item = nav.first { $0.label == label }
            #expect(item?.isButton == true, "\(label): \(nav)")
        }
        #expect(nav.contains { $0.label == "Ask about this passage" && $0.traits.contains(.header) }, "\(nav)")

        let reader = Self.tree("readerChrome")
        for label in [LabelKey.navBack, .readerSettings, .readerBookmark, .readerSearch].map(\.localized) {
            let item = reader.first { $0.label == label }
            #expect(item?.isButton == true, "\(label): \(reader)")
        }
        #expect(reader.first { $0.label == LabelKey.readerBookmark.localized }?.isSelected == true)
        #expect(reader.contains { $0.label.contains("Chapter 20 of 86") && $0.value.contains("38%") }, "\(reader)")
    }

    @Test("Mini-player: capture control labelled 'Capture the last 30 seconds', play/pause labelled")
    func miniPlayer() {
        let elements = Self.tree("miniPlayer")
        let capture = elements.first { $0.label == LabelKey.controlCaptureRecent.localized }
        #expect(capture?.isButton == true, "\(elements)")
        #expect(elements.contains { $0.isButton && $0.label == LabelKey.controlPause.localized }, "\(elements)")
        #expect(elements.contains { $0.isButton && $0.label.contains("Middlemarch") && !$0.hint.isEmpty }, "\(elements)")
    }

    @Test("Rating: adjustable when editable, values in half stars, clearing is a separate button")
    func rating() {
        let elements = Self.tree("rating")
        let ratings = elements.filter { $0.label == LabelKey.ratingLabel.localized }
        #expect(ratings.map(\.value) == ["4.5 of 5 stars", "2 of 5 stars", LabelKey.ratingNone.localized, "3.5 of 5 stars"],
                "\(ratings)")
        #expect(ratings.map { $0.traits.contains(.adjustable) } == [false, false, false, true], "\(ratings)")
        #expect(elements.contains { $0.isButton && $0.label == LabelKey.ratingClear.localized })
    }

    @Test("Audio range: numeric start and end are adjustable, with labelled earlier/later buttons")
    func audioRange() {
        let elements = Self.tree("captureSheet.audio")
        let start = elements.first { $0.label == LabelKey.captureStart.localized }
        let end = elements.first { $0.label == LabelKey.captureEnd.localized }
        #expect(start?.value == "11:12.0" && start?.traits.contains(.adjustable) == true, "\(elements)")
        #expect(end?.value == "11:42.0" && end?.traits.contains(.adjustable) == true, "\(elements)")
        for key in [LabelKey.controlStartEarlier, .controlStartLater, .controlEndEarlier, .controlEndLater] {
            #expect(elements.contains { $0.isButton && $0.label == key.localized }, "\(key)")
        }
    }

    @Test("Capture sheet: Look up, Ask and the save-state button; Saving is not enabled")
    func captureSheet() {
        let elements = Self.tree("captureSheet.quote")
        for label in [LabelKey.actionLookUp, .actionAsk, .actionSave].map(\.localized) {
            #expect(elements.contains { $0.isButton && $0.label == label }, "\(label): \(elements)")
        }
        #expect(elements.contains { $0.label == LabelKey.captureSheetTitle.localized && $0.traits.contains(.header) })
        let states = Self.tree("captureSheet.saveStates").filter(\.isButton)
        #expect(states.map(\.label) == [LabelKey.actionSave.localized, Status.saving.text(),
                                        Status.savedAt(SampleText.savedTime).text(), Status.notSaved.text()], "\(states)")
        #expect(states.map { $0.traits.contains(.notEnabled) } == [false, true, false, false], "\(states)")
    }

    @Test("Generated answer: citation chips are spoken, unresolved ones as unresolved")
    func generatedAnswer() {
        let elements = Self.tree("captureCard.generated")
        #expect(elements.contains { $0.label.contains("Citation c1") && $0.label.contains("Unresolved citation c2") },
                "\(elements)")
    }

    @Test("Audio card: the play control is a labelled button; no transcript is said, not invented")
    func audioCard() {
        let elements = Self.tree("captureCard.audio")
        #expect(elements.contains { $0.isButton && $0.label == LabelKey.controlPlayExcerpt.localized })
        #expect(elements.contains { $0.isButton && $0.label == LabelKey.controlPauseExcerpt.localized })
        #expect(elements.contains { $0.label == LabelKey.audioNoTranscript.localized })
    }

    @Test("One primary button per screen: the capture sheet and the impact report have exactly one")
    func onePrimaryPerScreen() {
        for name in ["captureSheet.quote", "captureSheet.audio", "impactReport", "buttons"] {
            let box = PrimaryCount()
            let sample = Gallery.sample(name)
            _ = Renderer.render(sample.content.reportingPrimaryCount(into: box), variant: Variant(.light, .standard),
                                width: sample.width, height: sample.height, sizeClass: sample.sizeClass)
            #expect(box.value == 1, "\(name): \(box.value) primary buttons")
        }
    }
}

/// Collects every sample's accessibility tree and writes it once all have reported.
@MainActor
final class AccessibilityReport {
    static let shared = AccessibilityReport()
    private var trees: [String: [AXNode]] = [:]

    func add(_ name: String, _ elements: [AXNode]) {
        trees[name] = elements
        guard trees.count == Gallery.names.count else { return }
        var text = """
            # Accessibility tree of each component sample (\(Evidence.environmentLabel))

            Generated by `AccessibilityTreeTests.everyElementLabelled` (light, default text size). Each row is \
            an element as UIKit exposes it to VoiceOver from the SwiftUI hosting view. Traits: B button, S \
            selected, H header, A adjustable, D not enabled, I image. The large content viewer is not exposed \
            through these elements and is checked on a device.

            """
        for name in Gallery.names {
            text += "\n## \(name)\n\n"
            if trees[name]?.isEmpty ?? true {
                text += "No elements: this offscreen renderer does not expose text fields. The design catalog's UI "
                    + "test `CatalogGalleryTests.testTextFieldSampleLabels` checks their labels in a real window.\n"
                continue
            }
            text += "| Label | Value | Hint | Traits |\n| --- | --- | --- | --- |\n"
            for e in trees[name] ?? [] {
                var t = ""
                if e.traits.contains(.button) { t += "B" }
                if e.traits.contains(.selected) { t += "S" }
                if e.traits.contains(.header) { t += "H" }
                if e.traits.contains(.adjustable) { t += "A" }
                if e.traits.contains(.notEnabled) { t += "D" }
                if e.traits.contains(.image) { t += "I" }
                let clean = { (s: String) in s.replacingOccurrences(of: "|", with: "\\|").replacingOccurrences(of: "\n", with: " ") }
                text += "| \(clean(e.label)) | \(clean(e.value)) | \(clean(e.hint)) | \(t) |\n"
            }
        }
        Evidence.write("accessibility-tree-simulator.md", text: text)
    }
}
#endif
