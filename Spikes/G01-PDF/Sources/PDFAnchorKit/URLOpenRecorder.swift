import Foundation

/// Records every URL that reaches the harness from the system (scene `openURLContexts`). The harness registers the
/// canary scheme used by `actions.pdf`, so if PDFKit ever opens one of the fixture's URLs by itself, it lands here.
@MainActor
public final class URLOpenRecorder {
    public static let shared = URLOpenRecorder()

    public private(set) var received: [URL] = []

    public func record(_ url: URL) {
        received.append(url)
        NotificationCenter.default.post(name: URLOpenRecorder.didRecord, object: url)
    }

    public func reset() {
        received.removeAll()
    }

    public static let didRecord = Notification.Name("com.jevidon.sylvia.spike.pdf.URLOpenRecorder.didRecord")
}
