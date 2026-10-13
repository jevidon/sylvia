import AppIntents
import Foundation

// Compiled into both the harness app and the control extension (G0.4 quick-capture prototype, ADR-0007).
// The control extension needs the type to build its button; because the intent adopts AudioPlaybackIntent the
// system performs it in the app's process, where the app has installed `QuickCaptureBridge.handler`. If it ever
// runs anywhere else, the handler is absent and the intent fails without claiming a save.

/// What the app's capture path reports back to the intent.
public struct QuickCaptureReply: Sendable, Equatable {
    public var acknowledged: Bool
    public var message: String
    public init(acknowledged: Bool, message: String) {
        self.acknowledged = acknowledged
        self.message = message
    }
}

/// Process-local hook the app sets at launch. Absent in the extension process.
@MainActor
public enum QuickCaptureBridge {
    public static var handler: (@MainActor (_ origin: String) async -> QuickCaptureReply)?
    /// The process that last performed the intent (bundle identifier), for evidence.
    public static var lastPerformedIn: String?
}

public enum QuickCaptureIntentError: Error, CustomLocalizedStringResourceConvertible {
    case notInAppProcess(String)
    case notSaved(String)

    public var localizedStringResource: LocalizedStringResource {
        switch self {
        // A developer diagnostic, not product copy: it should never be reachable (the intent runs in the app).
        case let .notInAppProcess(p): "[quick_capture.not_in_app_process \(p)]"
        case let .notSaved(m): "\(m)"
        }
    }
}

/// Which kind of entry point created an intent instance (review R2-05). The control sets it; an intent performed
/// from the App Shortcut, Siri, Spotlight or the Shortcuts app has none. The Control Center, Lock Screen and
/// Action-button placements of the control run the same configured instance, so they cannot be told apart.
public enum CaptureSurface: String, AppEnum {
    case control

    public static let typeDisplayRepresentation: TypeDisplayRepresentation = "Capture surface"
    public static let caseDisplayRepresentations: [CaptureSurface: DisplayRepresentation] = [.control: "Control"]
}

/// "Capture the last 30 seconds" as an App Intent: usable from a Control Center / Lock Screen control, the
/// Action button, Shortcuts and Siri. It acknowledges only after the durable save returns (plan 10.2, T25).
public struct CaptureMomentIntent: AudioPlaybackIntent {
    public static let title: LocalizedStringResource = "Capture the last 30 seconds"
    public static let description = IntentDescription("Saves the moment you just heard, with the preceding 30 seconds of audio.")
    /// Runs while the device is locked; whether the save can complete then depends on file protection (ADR-0007).
    public static let authenticationPolicy: IntentAuthenticationPolicy = .alwaysAllowed
    public static let supportedModes: IntentModes = .background

    /// Set by the control; nil for every other entry point. Optional, so the system never asks for it.
    @Parameter(title: "Surface")
    public var surface: CaptureSurface?

    public init() {}

    public init(surface: CaptureSurface) {
        self.surface = surface
    }

    /// The capture's `origin`: the entry-point kind when known, and the process that performed the intent, for
    /// example `intent.control@com.jevidon.sylvia.spike.g04audio`, or `intent@...` without a surface.
    public static func origin(surface: CaptureSurface?, process: String) -> String {
        "intent\(surface.map { ".\($0.rawValue)" } ?? "")@\(process)"
    }

    @MainActor
    public func perform() async throws -> some IntentResult & ProvidesDialog {
        let process = Bundle.main.bundleIdentifier ?? "unknown"
        QuickCaptureBridge.lastPerformedIn = process
        guard let handler = QuickCaptureBridge.handler else { throw QuickCaptureIntentError.notInAppProcess(process) }
        let reply = await handler(Self.origin(surface: surface, process: process))
        guard reply.acknowledged else { throw QuickCaptureIntentError.notSaved(reply.message) }
        return .result(dialog: IntentDialog(stringLiteral: reply.message))
    }
}
