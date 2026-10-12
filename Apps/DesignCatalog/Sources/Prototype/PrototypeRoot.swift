import SwiftUI
import SylviaDesign

/// The interaction prototype: onboarding, then the three areas (Section 4.1) with the tab bar on
/// iPhone and the sidebar on iPad in regular width, the mini-player above the tab bar, and the
/// reader and player as full-screen covers.
struct PrototypeRoot: View {
    @State private var model: PrototypeModel
    let onLeave: (() -> Void)?

    init(start: PrototypeScreen, writeSeconds: Double?, onLeave: (() -> Void)?) {
        let model = PrototypeModel(writeSeconds: writeSeconds)
        model.onLeave = onLeave
        model.open(start)
        _model = State(initialValue: model)
        self.onLeave = onLeave
    }

    var body: some View {
        @Bindable var model = model
        Group {
            if model.showsOnboarding {
                OnboardingScreen()
            } else {
                SylviaAreaNavigation(selection: $model.area, inboxNeedsAttention: model.inboxNeedsAttention) {
                    areaContent
                }
                .background(ColorToken.ground.color.ignoresSafeArea())
            }
        }
        .environment(model)
        .fullScreenCover(isPresented: $model.readerOpen) {
            ReaderFlow().environment(model)
        }
        .fullScreenCover(isPresented: $model.playerOpen) {
            PlayerFlow().environment(model)
        }
    }

    @ViewBuilder private var areaContent: some View {
        @Bindable var model = model
        switch model.area {
        case .library:
            NavigationStack(path: $model.libraryPath) {
                LibraryScreen().miniPlayer().destinations(withMiniPlayer: true)
            }
        case .thoughts:
            NavigationStack(path: $model.thoughtsPath) {
                ThoughtsScreen().miniPlayer().destinations(withMiniPlayer: true)
            }
        case .inbox:
            NavigationStack(path: $model.inboxPath) {
                InboxScreen().miniPlayer().destinations(withMiniPlayer: true)
            }
        }
    }
}

extension View {
    /// Routes for the area stacks (with the mini-player on every pushed screen) and for the
    /// full-screen reader and player (without it).
    func destinations(withMiniPlayer: Bool = false) -> some View {
        navigationDestination(for: PrototypeModel.Route.self) { route in
            Group {
                switch route {
                case .work(let id): WorkDetailScreen(id: id)
                case .inboxItem(let id): InboxDetailScreen(id: id)
                case .storage(let id): StorageScreen(id: id)
                case .settings: SettingsScreen()
                case .ask: AskScreen()
                case .audioCapture: AudioCaptureScreen()
                }
            }
            .miniPlayer(withMiniPlayer)
        }
    }

    /// The mini-player floats 12 pt above the tab bar while audio is active (Section 4.1, 4.4.7).
    /// It is a bottom safe-area inset of each screen inside the navigation stack, so the end of
    /// every list can scroll clear of it; while scrolling, content passes under it as under any
    /// floating object. (Set on the navigation stack itself, the inset did not reach the screens'
    /// scroll views: at AX5 on the iPhone SE the end of the Thoughts list stayed under it.)
    func miniPlayer(_ isShown: Bool = true) -> some View {
        modifier(MiniPlayerInset(isShown: isShown))
    }
}

private struct MiniPlayerInset: ViewModifier {
    let isShown: Bool
    @Environment(PrototypeModel.self) private var model

    @ViewBuilder func body(content: Content) -> some View {
        if isShown { inset(content) } else { content }
    }

    private func inset(_ content: Content) -> some View {
        content.safeAreaInset(edge: .bottom, spacing: 0) {
            MiniPlayer(title: "Middlemarch", author: "George Eliot",
                       caption: Microcopy.joined(["Part 14", rateText(model.playbackRate)]),
                       secondsRemaining: 20 * 3600 + 58 * 60, isPlaying: model.isPlaying,
                       onOpen: { model.playerOpen = true },
                       onCapture: {
                           model.playerOpen = true
                           model.captureMoment()
                       },
                       onPlayPause: { model.isPlaying.toggle() })
                // The UI tests read its frame to require that a key action is not under it.
                .accessibilityIdentifier("miniPlayer")
                .screenGutter()
                .padding(.bottom, MiniPlayer.gapAboveTabBar)
                .padding(.top, Spacing.xs)
        }
    }
}

/// "1.25×"
func rateText(_ rate: Double) -> String {
    rate.formatted(.number.precision(.fractionLength(0...2))) + "×"
}
