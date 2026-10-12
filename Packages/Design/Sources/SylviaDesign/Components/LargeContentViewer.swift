import SwiftUI
#if os(iOS)
import UIKit
#endif

// The large content viewer's activation on lift (Section 4.4.7: Sylvia's bars give "full
// system-equivalent accessibility"; review round 2, R2-02).
//
// At accessibility text sizes a long press on a bar item shows the item enlarged in the large
// content viewer, and a system bar opens the item that is under the finger when it lifts. SwiftUI's
// `.accessibilityShowsLargeContentViewer` shows the viewer on a custom control but does not
// activate it on lift: the viewer's gesture cancels the Button's touch, so its action never runs
// (found on the iPhone 17 simulator, report Finding 17). Sylvia adds that activation:
//
// - A UIKit long-press recognizer that runs alongside every other gesture (it never cancels or
//   delays the Button's own touch) reports where the finger lifted.
// - A control (``SylviaIconButton``, the navigation bar's back button, the reader's settings
//   button, ``PlayPauseButton``) activates when the finger lifts inside it; a bar (the tab bar and
//   the iPad sidebar) activates the item under the finger, so the finger can slide from item to
//   item as on a system tab bar.
// - It runs only while the system's large content viewer is enabled (an accessibility text size),
//   never when the content under the finger scrolled during the press, and never when the Button's
//   own action already ran for this press (a press shorter than the viewer's delay ends as a
//   normal tap), so an action never runs twice.

/// Records whether a control's Button action ran during the current long press.
@MainActor
final class LiftActivationGate {
    private var press = 0
    private var buttonActionPress = -1

    /// A long press began (the lift recognizer's `.began`).
    func pressBegan() { press += 1 }

    /// The Button's own action ran (a normal tap or a press the viewer did not take over).
    func buttonActionRan() { buttonActionPress = press }

    /// Whether the Button's action ran since the current press began.
    var buttonActionRanDuringPress: Bool { buttonActionPress == press }

    /// Runs a Button's own action and records that it ran (wrap every Button action in it).
    func run(_ action: () -> Void) {
        buttonActionRan()
        action()
    }
}

enum LargeContentViewerLift {
    /// How long the finger must rest before the lift recognizer begins. Shorter than the viewer's
    /// own delay on purpose: a press between the two ends as a normal tap, which the gate detects.
    static let minimumPress: TimeInterval = 0.25
    /// How long the lift activation waits for the Button's own action before it decides that the
    /// viewer took the press over (SwiftUI delivers Button actions asynchronously).
    static let settleDelay: Duration = .milliseconds(150)
    /// How far the content under the finger may move during the press before it counts as a scroll.
    static let scrollTolerance: CGFloat = 1
}

#if os(iOS)
/// Reports where a long press ended. `space` names the coordinate space of the reported location
/// (the view's own space when nil).
struct LiftRecognizer: UIGestureRecognizerRepresentable {
    let space: String?
    let onBegan: @MainActor () -> Void
    /// The lift location and whether the content under the finger moved (scrolled) during the press.
    let onLift: @MainActor (CGPoint, Bool) -> Void

    @MainActor
    final class Coordinator: NSObject, UIGestureRecognizerDelegate {
        var beganLocal: CGPoint = .zero
        var beganGlobal: CGPoint = .zero
        // The closures of the latest view update (set in makeCoordinator and on every update).
        var onBegan: @MainActor () -> Void
        var onLift: @MainActor (CGPoint, Bool) -> Void

        init(onBegan: @escaping @MainActor () -> Void, onLift: @escaping @MainActor (CGPoint, Bool) -> Void) {
            self.onBegan = onBegan
            self.onLift = onLift
        }

        func gestureRecognizer(_ gestureRecognizer: UIGestureRecognizer,
                               shouldRecognizeSimultaneouslyWith other: UIGestureRecognizer) -> Bool {
            true
        }
    }

    func makeCoordinator(converter: CoordinateSpaceConverter) -> Coordinator {
        Coordinator(onBegan: onBegan, onLift: onLift)
    }

    func updateUIGestureRecognizer(_ recognizer: UILongPressGestureRecognizer, context: Context) {
        context.coordinator.onBegan = onBegan
        context.coordinator.onLift = onLift
    }

    func makeUIGestureRecognizer(context: Context) -> UILongPressGestureRecognizer {
        let recognizer = UILongPressGestureRecognizer()
        recognizer.minimumPressDuration = LargeContentViewerLift.minimumPress
        recognizer.allowableMovement = .greatestFiniteMagnitude
        recognizer.cancelsTouchesInView = false
        recognizer.delaysTouchesBegan = false
        recognizer.delaysTouchesEnded = false
        recognizer.delegate = context.coordinator
        return recognizer
    }

    func handleUIGestureRecognizerAction(_ recognizer: UILongPressGestureRecognizer, context: Context) {
        let local = space.map { context.converter.location(in: .named($0)) } ?? context.converter.localLocation
        let global = context.converter.location(in: .global)
        switch recognizer.state {
        case .began:
            context.coordinator.beganLocal = local
            context.coordinator.beganGlobal = global
            context.coordinator.onBegan()
        case .ended:
            guard Self.viewerEnabled(for: recognizer.view) else { return }
            // The finger's movement on screen minus its movement relative to the view: how far
            // the view itself moved under the finger (a scroll).
            let start = context.coordinator
            let dx = (global.x - start.beganGlobal.x) - (local.x - start.beganLocal.x)
            let dy = (global.y - start.beganGlobal.y) - (local.y - start.beganLocal.y)
            let moved = max(abs(dx), abs(dy)) > LargeContentViewerLift.scrollTolerance
            context.coordinator.onLift(local, moved)
        default:
            break
        }
    }

    /// The large content viewer is in use: the system enables it at accessibility text sizes.
    static func viewerEnabled(for view: UIView?) -> Bool {
        UILargeContentViewerInteraction.isEnabled
            || view?.traitCollection.preferredContentSizeCategory.isAccessibilityCategory == true
    }
}
#endif

extension View {
    /// Activates `action` when a long press ends inside this view while the large content viewer
    /// is in use and the Button's own action did not run for the press (see `gate`).
    func sylviaLiftActivation(gate: LiftActivationGate, action: @escaping () -> Void) -> some View {
        modifier(LiftActivationModifier(gate: gate, action: action))
    }

    /// Activates the target under the finger when a long press over this bar ends while the
    /// large content viewer is in use: `target` returns the action of the item at a point in the
    /// coordinate space `space`, which this modifier defines on the view.
    func sylviaBarLiftActivation(space: String, gate: LiftActivationGate,
                                 target: @escaping @MainActor (CGPoint) -> (() -> Void)?) -> some View {
        #if os(iOS)
        gesture(LiftRecognizer(space: space, onBegan: { gate.pressBegan() }, onLift: { point, moved in
            guard !moved, let action = target(point) else { return }
            Task { @MainActor in
                try? await Task.sleep(for: LargeContentViewerLift.settleDelay)
                if !gate.buttonActionRanDuringPress { action() }
            }
        }))
        .coordinateSpace(.named(space))
        #else
        coordinateSpace(.named(space))
        #endif
    }
}

private struct LiftActivationModifier: ViewModifier {
    let gate: LiftActivationGate
    let action: () -> Void
    @State private var size: CGSize = .zero

    func body(content: Content) -> some View {
        #if os(iOS)
        content
            .onGeometryChange(for: CGSize.self) { $0.size } action: { size = $0 }
            .gesture(LiftRecognizer(space: nil, onBegan: { gate.pressBegan() }, onLift: { point, moved in
                guard !moved, CGRect(origin: .zero, size: size).contains(point) else { return }
                Task { @MainActor in
                    try? await Task.sleep(for: LargeContentViewerLift.settleDelay)
                    if !gate.buttonActionRanDuringPress { action() }
                }
            }))
        #else
        content
        #endif
    }
}
