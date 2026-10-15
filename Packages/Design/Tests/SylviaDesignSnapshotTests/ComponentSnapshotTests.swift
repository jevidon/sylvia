#if os(iOS)
import SnapshotTesting
import SwiftUI
import Testing
import UIKit
@testable import SylviaDesign
import SylviaDesignGallery

/// T51/T53 snapshot matrix (plan 4.4.9, 20.1; ADR-0013 Section 9): every Section 4.4.7 component in
/// light, dark, light and dark with Increase Contrast, at the default text size and the largest
/// accessibility size (AX5), each with its grayscale rendering, plus Bold Text in light at the
/// default size. References are recorded on the iPhone 17 / iOS 26.5 simulator at 2x.
///
/// Record mode comes from SNAPSHOT_TESTING_RECORD (set TEST_RUNNER_SNAPSHOT_TESTING_RECORD for
/// xcodebuild); Scripts/ci.d/20-design.sh sets `never`, so a missing reference fails.
@Suite("Component snapshots (T51, T53)")
@MainActor
struct ComponentSnapshotTests {
    @Test("Recorded on the reference simulator")
    func recordingDevice() {
        #expect(RecordingDevice.isRecordingDevice,
                "references were recorded on \(RecordingDevice.modelIdentifier), iOS \(RecordingDevice.runtimePrefix); running on \(RecordingDevice.current)")
    }

    @Test("The sample list names every sample")
    func sampleNames() {
        #expect(Gallery.samples.map(\.name) == Gallery.names)
        #expect(Set(Gallery.names).count == Gallery.names.count)
        // The shared gallery frames samples for the reference device.
        #expect(GalleryLayout.phoneWidth == RecordingDevice.width)
    }

    @Test("Snapshots in four appearances, two text sizes, grayscale and Bold Text", arguments: Gallery.names)
    func snapshots(_ name: String) {
        guard RecordingDevice.isRecordingDevice else {
            Issue.record("snapshots compare only on \(RecordingDevice.modelIdentifier), iOS \(RecordingDevice.runtimePrefix)")
            return
        }
        let sample = Gallery.sample(name)
        for variant in Variant.matrix + [Variant.bold] {
            let rendered = Renderer.render(sample.content, variant: variant, width: sample.width, height: sample.height,
                                           sizeClass: sample.sizeClass)
            assertSnapshot(of: rendered.image, as: .color(scale: variant.scale), named: variant.name, testName: name)
            if !variant.boldText {
                assertSnapshot(of: Grayscale.image(rendered.image), as: .grayscale(scale: variant.scale),
                               named: variant.name + "-gray", testName: name)
            }
        }
    }
}
#endif
