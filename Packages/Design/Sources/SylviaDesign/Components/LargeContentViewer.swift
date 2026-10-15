import SwiftUI
#if os(iOS)
import UIKit
import UIKit.UIGestureRecognizerSubclass
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
//   delays the Button's own touch) reports every touch down, every touch lift and where the
//   finger lifted at the end of a long press.
// - A control (``SylviaIconButton``, the navigation bar's back button, the reader's settings
//   button, ``PlayPauseButton``) activates when the finger lifts inside it; a bar (the tab bar and
//   the iPad sidebar) activates the item under the finger, so the finger can slide from item to
//   item as on a system tab bar.
// - It runs only while the system's large content viewer is enabled (an accessibility text size),
//   and never when the content under the finger scrolled during the press.
// - A press activates its control once, whichever path runs first (review round 3, R3-02). The
//   Button's own action still runs when the viewer did not take the press over (a press shorter
//   than the viewer's delay ends as a normal tap), and SwiftUI delivers it asynchronously, after
//   the touch lifts. The lift activation waits ``LargeContentViewerLift/settleDelay`` for it and
//   runs only if it has not run for this press; and if the Button's action arrives after the lift
//   activation ran (the main thread was too busy to deliver it within the delay),
//   ``LiftActivationGate/run(_:)`` drops it. So the settle delay only decides which path normally
//   wins; correctness does not depend on it.
//
// Which press a Button action belongs to: a Button runs its action when a touch lifts inside it,
// so an action that arrives belongs to the latest press whose touch has lifted (the recognizer
// reports every lift, also of taps too short to begin a long press), or to no touch at all (a
// hardware keyboard or VoiceOver). A later tap is therefore never taken for the late action of an
// earlier press, and a new touch that has begun but not lifted does not hide that late action.
// The limits (ADR-0013 Section 10): a touch-free activation of the same control or bar during the
// settle delay or within ``LargeContentViewerLift/lateActionWindow`` after a lift activation, with
// no other touch lifting in between, counts as that press's own action, so the two activate once;
// and if a whole later tap lifts before the late action of a lift-activated press arrives (or the
// late action comes after the window), that action runs too.

/// Decides, for each press, whether the Button's own action or the lift activation runs, so that
/// a press activates once (within the limits above). Every Button action of a control or bar with
/// the lift activation goes through ``run(_:)``.
@MainActor
final class LiftActivationGate {
    typealias Now = @MainActor () -> ContinuousClock.Instant

    private let now: Now
    /// Touches that began on the control or bar so far; the latest is the current press.
    private(set) var press = 0
    /// The latest press whose touch lifted. A Button action that arrives now belongs to it (or to
    /// no touch at all).
    private(set) var liftedPress = 0
    /// The latest press a Button action was taken for, and the latest press the lift activation
    /// ran for.
    private var buttonActionPress: Int?
    private var liftPress: Int?
    /// The lift activation whose press may still deliver a late Button action; the next Button
    /// action, whichever press it belongs to, clears it.
    private var awaitingLateAction: (press: Int, at: ContinuousClock.Instant)?

    init(now: @escaping Now = { ContinuousClock.now }) {
        self.now = now
    }

    /// A touch began on the control or bar (the lift recognizer's touch down): a new press.
    func touchBegan() {
        press += 1
    }

    /// The current press's touch lifted (the lift recognizer's touch up, reported before the
    /// recognizer ends).
    func touchLifted() {
        liftedPress = press
    }

    /// Whether a Button action was taken for the current press.
    var buttonActionRanDuringPress: Bool { buttonActionPress == press }

    /// Whether the lift activation ran for the current press.
    var liftActivatedDuringPress: Bool { liftPress == press }

    /// The Button's own action (wrap every Button action in it). It belongs to the latest press
    /// that lifted; it runs `action` unless the lift activation already ran for that press within
    /// ``LargeContentViewerLift/lateActionWindow``, in which case it is that press's late action
    /// and is dropped (once).
    func run(_ action: () -> Void) {
        let owner = liftedPress
        if let late = awaitingLateAction {
            awaitingLateAction = nil
            if late.press == owner, now() - late.at <= LargeContentViewerLift.lateActionWindow { return }
        }
        buttonActionPress = owner
        action()
    }

    /// The lift activation for press `lifted`, after the settle delay: runs `action` unless a
    /// Button action or a lift activation was already taken for that press.
    func liftSettled(press lifted: Int, _ action: () -> Void) {
        guard buttonActionPress != lifted, liftPress != lifted else { return }
        liftPress = lifted
        awaitingLateAction = (lifted, now())
        action()
    }

    /// Runs `action` for the press that just lifted after ``LargeContentViewerLift/settleDelay``,
    /// unless the Button's own action runs for that press first (``liftSettled(press:_:)``).
    func scheduleLiftActivation(_ action: @escaping () -> Void) {
        let lifted = liftedPress
        Task { @MainActor in
            try? await Task.sleep(for: LargeContentViewerLift.settleDelay)
            self.liftSettled(press: lifted, action)
        }
    }
}

enum LargeContentViewerLift {
    /// How long the finger must rest before the lift recognizer begins. It must be shorter than the
    /// viewer's own delay, or a press the viewer takes over before the recognizer begins activates
    /// nothing: on the iPhone 17 simulator (iOS 26.5, AX5) the viewer let presses of up to 0.149 s
    /// through as taps and took a 0.161 s press over, so the 0.25 s used until review round 3 lost
    /// every press between about 0.15 and 0.25 s (report Finding 18). A press that begins the
    /// recognizer and still ends as a normal tap gets both paths, and the gate keeps it to one
    /// activation.
    static let minimumPress: TimeInterval = 0.05
    /// How long the lift activation waits for the Button's own action before it runs (SwiftUI
    /// delivers Button actions asynchronously). It decides which path normally wins; the gate keeps
    /// the action to one run either way.
    static let settleDelay: Duration = .milliseconds(150)
    /// How long after a lift activation the same press's Button action is still taken as late and
    /// dropped. Both come from the same touch, so the late action is already on its way when the
    /// lift activation runs and follows it closely even under load; the window bounds how long a
    /// touch-free activation (keyboard, VoiceOver) right after a lift activation is merged with it.
    static let lateActionWindow: Duration = .seconds(1)
    /// How far the content under the finger may move during the press before it counts as a scroll.
    static let scrollTolerance: CGFloat = 1
}

#if os(iOS)
/// A long-press recognizer that also reports every touch down and every touch lift on its view,
/// including touches that end before the press is long enough to begin (normal taps): each touch
/// down starts a new press, and each lift tells which press a Button action that follows belongs to.
final class LiftPressRecognizer: UILongPressGestureRecognizer {
    var onTouchDown: (@MainActor () -> Void)?
    var onTouchUp: (@MainActor () -> Void)?

    override func touchesBegan(_ touches: Set<UITouch>, with event: UIEvent) {
        super.touchesBegan(touches, with: event)
        onTouchDown?()
    }

    override func touchesEnded(_ touches: Set<UITouch>, with event: UIEvent) {
        // Reported before the recognizer ends, so the lift activation is scheduled for this press.
        // A cancelled touch is not a lift: a Button runs no action for it.
        onTouchUp?()
        super.touchesEnded(touches, with: event)
    }
}

/// Reports every touch down and lift, and where a long press ended. `space` names the coordinate
/// space of the reported location (the view's own space when nil).
struct LiftRecognizer: UIGestureRecognizerRepresentable {
    let space: String?
    let onTouchDown: @MainActor () -> Void
    let onTouchUp: @MainActor () -> Void
    /// The lift location and whether the content under the finger moved (scrolled) during the press.
    let onLift: @MainActor (CGPoint, Bool) -> Void

    @MainActor
    final class Coordinator: NSObject, UIGestureRecognizerDelegate {
        var beganLocal: CGPoint = .zero
        var beganGlobal: CGPoint = .zero
        // The closures of the latest view update (set in makeCoordinator and on every update).
        var onTouchDown: @MainActor () -> Void
        var onTouchUp: @MainActor () -> Void
        var onLift: @MainActor (CGPoint, Bool) -> Void

        init(onTouchDown: @escaping @MainActor () -> Void, onTouchUp: @escaping @MainActor () -> Void,
             onLift: @escaping @MainActor (CGPoint, Bool) -> Void) {
            self.onTouchDown = onTouchDown
            self.onTouchUp = onTouchUp
            self.onLift = onLift
        }

        func gestureRecognizer(_ gestureRecognizer: UIGestureRecognizer,
                               shouldRecognizeSimultaneouslyWith other: UIGestureRecognizer) -> Bool {
            true
        }
    }

    func makeCoordinator(converter: CoordinateSpaceConverter) -> Coordinator {
        Coordinator(onTouchDown: onTouchDown, onTouchUp: onTouchUp, onLift: onLift)
    }

    func updateUIGestureRecognizer(_ recognizer: LiftPressRecognizer, context: Context) {
        context.coordinator.onTouchDown = onTouchDown
        context.coordinator.onTouchUp = onTouchUp
        context.coordinator.onLift = onLift
    }

    func makeUIGestureRecognizer(context: Context) -> LiftPressRecognizer {
        let recognizer = LiftPressRecognizer()
        recognizer.minimumPressDuration = LargeContentViewerLift.minimumPress
        recognizer.allowableMovement = .greatestFiniteMagnitude
        recognizer.cancelsTouchesInView = false
        recognizer.delaysTouchesBegan = false
        recognizer.delaysTouchesEnded = false
        recognizer.delegate = context.coordinator
        let coordinator = context.coordinator
        recognizer.onTouchDown = { coordinator.onTouchDown() }
        recognizer.onTouchUp = { coordinator.onTouchUp() }
        return recognizer
    }

    func handleUIGestureRecognizerAction(_ recognizer: LiftPressRecognizer, context: Context) {
        let local = space.map { context.converter.location(in: .named($0)) } ?? context.converter.localLocation
        let global = context.converter.location(in: .global)
        switch recognizer.state {
        case .began:
            context.coordinator.beganLocal = local
            context.coordinator.beganGlobal = global
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
    /// is in use, once per press together with the Button's own action (see `gate`).
    func sylviaLiftActivation(gate: LiftActivationGate, action: @escaping () -> Void) -> some View {
        modifier(LiftActivationModifier(gate: gate, action: action))
    }

    /// Activates the target under the finger when a long press over this bar ends while the
    /// large content viewer is in use: `target` returns the action of the item at a point in the
    /// coordinate space `space`, which this modifier defines on the view.
    func sylviaBarLiftActivation(space: String, gate: LiftActivationGate,
                                 target: @escaping @MainActor (CGPoint) -> (() -> Void)?) -> some View {
        #if os(iOS)
        gesture(LiftRecognizer(space: space, onTouchDown: { gate.touchBegan() }, onTouchUp: { gate.touchLifted() },
                               onLift: { point, moved in
            guard !moved, let action = target(point) else { return }
            gate.scheduleLiftActivation(action)
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
            .gesture(LiftRecognizer(space: nil, onTouchDown: { gate.touchBegan() }, onTouchUp: { gate.touchLifted() },
                                    onLift: { point, moved in
                guard !moved, CGRect(origin: .zero, size: size).contains(point) else { return }
                gate.scheduleLiftActivation(action)
            }))
        #else
        content
        #endif
    }
}
