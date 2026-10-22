import SwiftUI

/// The harness's one screen: its state, Start, Stop, Check library, Export log, and the newest log lines first.
struct HarnessView: View {
    let controller: HarnessController

    var body: some View {
        NavigationStack {
            VStack(alignment: .leading, spacing: 12) {
                Text(controller.statusLine)
                    .font(.footnote)
                    .accessibilityIdentifier("harness.status")
                HStack(spacing: 16) {
                    Button("Start") { controller.start() }
                        .disabled(controller.runState == .running)
                        .accessibilityIdentifier("harness.start")
                    Button("Stop") { controller.stop() }
                        .disabled(controller.runState != .running)
                        .accessibilityIdentifier("harness.stop")
                    Button("Check library") { controller.verifyNow() }
                        .accessibilityIdentifier("harness.verify")
                    ShareLink(item: controller.logFileURL) {
                        Text("Export log")
                    }
                    .accessibilityIdentifier("harness.export")
                }
                .buttonStyle(.bordered)
                Text("Volume \(String(format: "%.2f", controller.configuration.volume)) (\(controller.configuration.volumeReason)); "
                     + "an attempt every \(Int(controller.configuration.interval)) s.")
                    .font(.caption)
                List(Array(controller.recentLines.reversed().enumerated()), id: \.offset) { _, line in
                    Text(line)
                        .font(.caption2.monospaced())
                        .textSelection(.enabled)
                }
                .listStyle(.plain)
            }
            .padding(.horizontal)
            .navigationTitle("G0.5 lock harness")
            .navigationBarTitleDisplayMode(.inline)
        }
    }
}
