import SwiftUI

/// The mini-player (Section 4.1, 4.4.7): floats 12 pt above the tab bar while audio is active;
/// surface, radius 14, the one shadow; cover, title, caption, the capture control (bracket glyph,
/// "Capture the last 30 seconds") and play/pause. At accessibility text sizes the controls move
/// below the title so nothing is cut off.
public struct MiniPlayer: View {
    let title: String
    let author: String?
    let caption: String
    let secondsRemaining: Int?
    let isPlaying: Bool
    let onOpen: () -> Void
    let onCapture: () -> Void
    let onPlayPause: () -> Void
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    /// `caption` is the position line ("Part 14 · 1.25×"); time remaining is appended in Monospace.
    public init(title: String, author: String?, caption: String, secondsRemaining: Int?, isPlaying: Bool,
                onOpen: @escaping () -> Void, onCapture: @escaping () -> Void,
                onPlayPause: @escaping () -> Void) {
        self.title = title
        self.author = author
        self.caption = caption
        self.secondsRemaining = secondsRemaining
        self.isPlaying = isPlaying
        self.onOpen = onOpen
        self.onCapture = onCapture
        self.onPlayPause = onPlayPause
    }

    /// The gap to leave between the mini-player and the tab bar.
    public static let gapAboveTabBar = ComponentMetrics.miniPlayerGap

    public var body: some View {
        let layout = dynamicTypeSize.isAccessibilitySize
            ? AnyLayout(VStackLayout(alignment: .leading, spacing: Spacing.xs))
            : AnyLayout(HStackLayout(alignment: .center, spacing: Spacing.s))
        layout {
            Button(action: onOpen) {
                // At accessibility sizes the cover sits above the title so the text has the full
                // width; every text wraps rather than truncating (T51).
                let info = dynamicTypeSize.isAccessibilitySize
                    ? AnyLayout(VStackLayout(alignment: .leading, spacing: Spacing.xs))
                    : AnyLayout(HStackLayout(alignment: .center, spacing: Spacing.s))
                info {
                    TypographicCover(title: title, author: author, shape: .square, width: ComponentMetrics.miniPlayerCover)
                        .accessibilityHidden(true)
                    VStack(alignment: .leading, spacing: 0) {
                        Text(title)
                            .sylviaFont(.body, weight: ComponentMetrics.quietLabelWeight)
                            .foregroundStyle(ColorToken.ink.color)
                            .fixedSize(horizontal: false, vertical: true)
                        captionText
                    }
                    if !dynamicTypeSize.isAccessibilitySize { Spacer(minLength: 0) }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityElement(children: .combine)
            .accessibilityHint(Text(LabelKey.controlOpenPlayerHint.localized))
            HStack(spacing: Spacing.xxs) {
                SylviaIconButton(symbol: .capture, label: LabelKey.controlCaptureRecent.localized, action: onCapture)
                    .sylviaAuditRegion("mini.capture")
                SylviaIconButton(systemImage: (isPlaying ? ControlSymbol.pause : ControlSymbol.play).systemName,
                                 label: (isPlaying ? LabelKey.controlPause : LabelKey.controlPlay).localized,
                                 action: onPlayPause)
            }
        }
        .padding(.horizontal, Spacing.s)
        .padding(.vertical, Spacing.xs)
        .sylviaFill(.surface, .card)
        .sylviaElevation()
        .accessibilityElement(children: .contain)
        .sylviaAuditRegion("mini")
    }

    private var captionText: some View {
        ViewThatFits(in: .horizontal) {
            HStack(spacing: 0) { captionParts(separated: true) }
            VStack(alignment: .leading, spacing: 0) { captionParts(separated: false) }
        }
        .foregroundStyle(ColorToken.muted.color)
    }

    @ViewBuilder private func captionParts(separated: Bool) -> some View {
        Text(caption).sylviaFont(.caption)
            .fixedSize(horizontal: separated, vertical: true)
        if let secondsRemaining {
            Text((separated ? Microcopy.separator : "") + Durations.left(seconds: secondsRemaining))
                .sylviaFont(.caption, monospaced: true)
                .fixedSize(horizontal: separated, vertical: true)
        }
    }
}
