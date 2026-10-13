import AppIntents
import G04AudioKit
import SwiftUI

@main
struct HarnessApp: App {
    @Environment(\.scenePhase) private var scenePhase

    init() {
        // Installed at process launch, including a background launch to perform CaptureMomentIntent.
        QuickCaptureBridge.handler = { origin in HarnessModel.shared.quickCapture(origin: origin) }
        HarnessShortcuts.updateAppShortcutParameters()
    }

    var body: some Scene {
        WindowGroup {
            HarnessView(model: HarnessModel.shared)
                .task {
                    // Hosted unit tests build their own services; the demo edition stays unloaded.
                    guard ProcessInfo.processInfo.environment["XCTestConfigurationFilePath"] == nil else { return }
                    await HarnessModel.shared.start()
                }
        }
        .onChange(of: scenePhase) { _, phase in
            switch phase {
            case .background: HarnessModel.shared.playback.handleLifecycle(.didEnterBackground)
            case .inactive: HarnessModel.shared.playback.handleLifecycle(.willResignActive)
            default: break
            }
        }
    }
}

/// App Shortcuts: makes the capture intent available to Shortcuts, Siri, Spotlight and the Action button.
struct HarnessShortcuts: AppShortcutsProvider {
    static var appShortcuts: [AppShortcut] {
        AppShortcut(intent: CaptureMomentIntent(),
                    phrases: ["Capture the last 30 seconds in \(.applicationName)", "Capture a moment in \(.applicationName)"],
                    shortTitle: "Capture moment",
                    systemImageName: "waveform.badge.plus")
    }
}

/// Harness chrome (exempt from the design-literal rules, never shipped).
struct HarnessView: View {
    let model: HarnessModel
    @State private var startText = ""
    @State private var endText = ""
    @State private var selected: UUID?

    var body: some View {
        NavigationStack {
            List {
                Section("Player · \(model.editionTitle)") {
                    TimelineView(.periodic(from: .now, by: 0.5)) { _ in
                        VStack(alignment: .leading) {
                            Text("\(format(model.playback.currentGlobalMs)) / \(format(model.playback.timeline?.durationMs ?? 0))")
                                .monospacedDigit()
                            Text("status \(String(describing: model.playback.status)) · rate \(model.playback.rate, specifier: "%.2f")x")
                            Text("furthest \(format(model.playback.furthestGlobalMs)) · listened \(format(model.playback.listenedMs))")
                        }
                    }
                    HStack {
                        Button("-15") { Task { await model.playback.skip(bySeconds: -15) } }
                        // During a preview play/pause stops the preview (as the remote commands do; review R4-03).
                        Button(model.playback.mode == .preview ? "Stop preview" : model.playback.isPlayingOrStarting ? "Pause" : "Play") {
                            model.playback.togglePlayPause()
                            model.nowPlaying.update()
                        }
                        Button("+15") { Task { await model.playback.skip(bySeconds: 15) } }
                        Button("Prev ch") { Task { await model.playback.previousChapter() } }
                        Button("Next ch") { Task { await model.playback.nextChapter() } }
                    }.buttonStyle(.bordered)
                    Picker("Rate", selection: Binding(get: { model.playback.rate }, set: { model.playback.setRate($0); model.nowPlaying.update() })) {
                        ForEach([Float(0.5), 1, 1.5, 2, 3], id: \.self) { Text("\($0, specifier: "%.1f")x").tag($0) }
                    }.pickerStyle(.segmented)
                    // Each tap is its own capture (its own idempotency key; review R3-04).
                    Button("Capture the last 30 seconds") {
                        _ = model.quickCapture(origin: "player", idempotencyKey: QuickCaptureCoordinator.requestKey(origin: "player"))
                    }
                    Button("Bookmark") { Task { await model.bookmark() } }
                    // Quiet (1 % volume) by default so automated runs stay quiet; a person turns full volume on for
                    // listening checks.
                    Button(model.audiblePlayback ? "Quiet playback (now full volume)" : "Full volume (now quiet, 1 %)") {
                        model.setAudiblePlayback(!model.audiblePlayback)
                    }
                    Button(model.bookmarkCommandEnabled ? "Disable remote bookmark command" : "Enable remote bookmark command") { model.toggleBookmarkCommand() }
                    if let m = model.lastMessage { Text(m).font(.footnote) }
                }
                Section("Captures") {
                    ForEach(model.records) { r in
                        VStack(alignment: .leading) {
                            Text("\(r.kind.rawValue) · \(SpikePhrases.phrase(r.statusKey))")
                            Text(r.ranges.map { "\($0.assetID.uuidString.prefix(4)) \($0.startMs)-\($0.endMs) ms" }.joined(separator: ", "))
                                .font(.caption).monospacedDigit()
                            Text(r.origin).font(.caption2)
                            HStack {
                                if model.canRetry(r) { Button("Retry") { Task { await model.retry(r.id) } } }
                                if r.kind == .audio { Button("Preview") { Task { await model.preview(r) } } }
                                if r.kind == .audio { Button("Edit range") { selected = r.id } }
                            }.buttonStyle(.borderless)
                        }
                    }
                }
                if let id = selected {
                    Section("Range (global ms)") {
                        TextField("Start ms", text: $startText).keyboardType(.numberPad)
                        TextField("End ms", text: $endText).keyboardType(.numberPad)
                        Button("Apply") {
                            if let s = Int64(startText), let e = Int64(endText) {
                                Task { await model.setRange(id, startMs: s, endMs: e) }
                            }
                        }
                    }
                }
            }
            .navigationTitle("G0.4 audio harness")
        }
    }

    private func format(_ ms: Int64) -> String {
        let s = ms / 1000
        return String(format: "%d:%02d:%02d.%03d", s / 3600, (s / 60) % 60, s % 60, ms % 1000)
    }
}
