import SwiftUI
import SylviaDesign
import UIKit

/// Wraps a screen. With the layout audit switched on it installs a fresh `LayoutAudit` (the T51
/// proxy of ADR-0013 Section 9) and exposes the result as an accessibility element named
/// "Layout audit" whose value reads "0 truncated, 0 outside of 57 texts", so UI tests can require
/// that no styled text on the screen is truncated or pushed sideways past the screen's edges (a
/// row wider than the screen). Texts scrolled out vertically are not counted as outside. Only
/// texts that are on screen count (`countsOnlyAppearedTexts`): the candidates a `ViewThatFits`
/// measures but does not show report frames off the screen and are left out. A second element,
/// "layoutAuditDetail.<name>", names each failing text's role and frame for the tests' failure
/// messages. Both elements are 1 pt clear views; they draw nothing.
/// Every screen also gets an accessibility identifier "screen.<name>" for the tests.
struct AuditedScreen<Content: View>: View {
    let name: String
    let content: Content
    @Environment(DisplaySettings.self) private var display

    init(_ name: String, @ViewBuilder content: () -> Content) {
        self.name = name
        self.content = content()
    }

    var body: some View {
        if display.layoutAudit {
            AuditHost(name: name, content: content)
        } else {
            content.accessibilityIdentifier("screen.\(name)")
        }
    }
}

private struct AuditHost<Content: View>: View {
    let name: String
    let content: Content
    @State private var audit = LayoutAudit(countsOnlyAppearedTexts: true)
    @State private var report = "pending"
    @State private var detail = ""

    var body: some View {
        content
            .environment(\.sylviaLayoutAudit, audit)
            .accessibilityIdentifier("screen.\(name)")
            .overlay(alignment: .topLeading) {
                Color.clear
                    .frame(width: 1, height: 1)
                    .accessibilityElement()
                    .accessibilityLabel(Text(verbatim: "Layout audit"))
                    .accessibilityValue(Text(verbatim: report))
                    .accessibilityIdentifier("layoutAudit.\(name)")
            }
            .overlay(alignment: .topTrailing) {
                // Which texts failed, for the tests' failure messages: role and frame in the window.
                Color.clear
                    .frame(width: 1, height: 1)
                    .accessibilityElement()
                    .accessibilityLabel(Text(verbatim: "Layout audit detail"))
                    .accessibilityValue(Text(verbatim: detail))
                    .accessibilityIdentifier("layoutAuditDetail.\(name)")
            }
            .task {
                // Layout settles over a few frames; report repeatedly so the value is current.
                while !Task.isCancelled {
                    try? await Task.sleep(for: .milliseconds(300))
                    let texts = audit.texts
                    let truncated = texts.filter(\.isTruncated).count
                    let bounds = Self.windowBounds
                    let outside = texts.filter {
                        $0.frame.width > 0 && ($0.frame.minX < bounds.minX - 0.5 || $0.frame.maxX > bounds.maxX + 0.5)
                    }
                    report = "\(truncated) truncated, \(outside.count) outside of \(texts.count) texts"
                    detail = (texts.filter(\.isTruncated).map { "truncated " + Self.describe($0) }
                        + outside.map { "outside " + Self.describe($0) }).joined(separator: "; ")
                }
            }
    }

    /// "body at x 20 y 300 w 362 h 23 needs 23": the text's role, window frame and needed height.
    private static func describe(_ text: LayoutAudit.TextReport) -> String {
        let f = text.frame
        return "\(text.role) at x \(Int(f.minX)) y \(Int(f.minY)) w \(Int(f.width)) h \(Int(f.height)) needs \(Int(text.neededHeight))"
    }

    /// The key window's bounds: SwiftUI's global coordinates are the window's, so a text outside
    /// these horizontally is off the screen (a whole screen wider than the window is caught too).
    private static var windowBounds: CGRect {
        let windows = UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }.flatMap(\.windows)
        return (windows.first(where: \.isKeyWindow) ?? windows.first)?.bounds ?? .infinite
    }
}
