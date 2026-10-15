import XCTest

/// The harness line `captures=<n> newest=<origin>` (accessibility identifier `g04-captures-summary`): the number of
/// capture records in the store and the origin of the newest one. Review R6-06: the UI tests counted the rows of the
/// Captures list, which SwiftUI renders lazily, so a third capture below the fold was not counted and the printed
/// counts contradicted the harness log; this line is the count of records, wherever the list is scrolled.
struct CaptureSummary: Equatable {
    var count: Int
    var newest: String

    @MainActor
    static func read(_ app: XCUIApplication, file: StaticString = #filePath, line: UInt = #line) -> CaptureSummary? {
        let element = app.staticTexts["g04-captures-summary"]
        guard element.waitForExistence(timeout: 10) else {
            XCTFail("the harness shows no capture summary", file: file, line: line)
            return nil
        }
        guard let summary = parse(element.label) else {
            XCTFail("unreadable capture summary: \(element.label)", file: file, line: line)
            return nil
        }
        return summary
    }

    static func parse(_ label: String) -> CaptureSummary? {
        var count: Int?
        var newest: String?
        for part in label.split(separator: " ") {
            if part.hasPrefix("captures=") { count = Int(part.dropFirst("captures=".count)) }
            if part.hasPrefix("newest=") { newest = String(part.dropFirst("newest=".count)) }
        }
        guard let count, let newest else { return nil }
        return CaptureSummary(count: count, newest: newest)
    }
}

/// The harness launch arguments of the UI tests: quiet (1 % volume) unless SYLVIA_AUDIBLE_PLAYBACK=1 (forwarded by the
/// CI script as TEST_RUNNER_SYLVIA_AUDIBLE_PLAYBACK; the argument overrides the persisted full-volume toggle), and
/// playing after the load when `autoPlay` is true.
func harnessLaunchArguments(autoPlay: Bool) -> [String] {
    let audible = ProcessInfo.processInfo.environment["SYLVIA_AUDIBLE_PLAYBACK"] == "1"
    return (autoPlay ? ["-g04AutoPlay", "YES"] : []) + ["-g04AudiblePlayback", audible ? "YES" : "NO"]
}

/// The current time as the harness log writes it (ISO 8601 UTC with milliseconds), to mark a press in the test output.
func logTimestamp() -> String {
    let f = ISO8601DateFormatter()
    f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
    return f.string(from: Date())
}
