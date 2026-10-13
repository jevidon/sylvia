import AppIntents
import SwiftUI
import WidgetKit

/// G0.4 quick-capture prototype: a control for Control Center, the Lock Screen and the Action button that runs
/// `CaptureMomentIntent` (ADR-0007). Stage 0 harness only; never shipped.
@main
struct CaptureControlBundle: WidgetBundle {
    var body: some Widget {
        CaptureMomentControl()
    }
}

struct CaptureMomentControl: ControlWidget {
    static let kind = "com.jevidon.sylvia.spike.g04audio.capture"

    var body: some ControlWidgetConfiguration {
        StaticControlConfiguration(kind: Self.kind) {
            ControlWidgetButton(action: CaptureMomentIntent(surface: .control)) {
                Label("Capture", systemImage: "waveform.badge.plus")
            }
        }
        .displayName("Capture the last 30 seconds")
        .description("Saves the moment you just heard in the G0.4 harness.")
    }
}
