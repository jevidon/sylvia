import CoreText
import SwiftUI

/// The typographic cover (Section 4.4.2, 4.4.7): the Literata title on one of the five cover
/// fields, chosen by a stable FNV-1a hash of the title (never Swift's per-launch `hashValue`), with
/// the author in a small caption. 2:3 in lists, square in the player. Covers 56 pt wide or less use
/// the block radius and show the title's first letter. A long word shrinks the title (to 60% at
/// most) rather than break. The cover is an object: its type scales with
/// its width, not with Dynamic Type, and its accessibility label carries the title and author.
public struct TypographicCover: View {
    public enum Shape: Sendable, Hashable {
        /// 2:3 (lists, work detail).
        case list
        /// Square (player, mini-player).
        case square

        public var aspectRatio: Double {
            switch self {
            case .list: CoverLayout.listAspectRatio
            case .square: CoverLayout.playerAspectRatio
            }
        }
    }

    public let title: String
    public let author: String?
    public let shape: Shape
    public let width: CGFloat

    public init(title: String, author: String?, shape: Shape, width: CGFloat) {
        self.title = title
        self.author = author
        self.shape = shape
        self.width = width
    }

    /// The cover field token for this title.
    public var field: ColorToken { CoverFields.field(forTitle: title) }

    public var isThumbnail: Bool { width <= CoverLayout.thumbnailMaximumWidth }

    public var height: CGFloat { width / shape.aspectRatio }

    static func literata(size: Double, weight: Int) -> Font {
        let style = ResolvedTypeStyle(role: .title, face: .literata, pointSize: size,
                                      lineHeight: size * TypeRole.title.spec.lineHeightRatio, tracking: 0,
                                      weight: weight, opticalSize: LiterataFont.opticalSize(forPointSize: size),
                                      uppercase: false)
        return Font(style.ctFont())
    }

    /// The title size: the role's share of the cover width, reduced (down to
    /// ``CoverLayout/minimumTitleScaleFactor``) until the longest word fits on one line, so a title
    /// is never broken inside a word when it can be avoided.
    public static func titleSize(title: String, width: CGFloat) -> CGFloat {
        let nominal = width * CoverLayout.titleScale
        let minimum = nominal * CoverLayout.minimumTitleScaleFactor
        let available = width * (1 - 2 * CoverLayout.insetScale)
        let words = title.split(whereSeparator: { $0.isWhitespace }).map(String.init)
        var size = nominal
        // Literata's optical size changes with the point size, so width is not exactly linear in
        // size: re-measure after each step (converges in one or two).
        for _ in 0..<4 {
            let widest = words.map { wordWidth($0, size: size) }.max() ?? 0
            guard widest > available, size > minimum else { break }
            // One point of slack keeps layout rounding from re-breaking the word.
            size = max(size * (available - 1) / widest, minimum)
        }
        return size
    }

    static func wordWidth(_ word: String, size: CGFloat) -> CGFloat {
        let style = ResolvedTypeStyle(role: .title, face: .literata, pointSize: size,
                                      lineHeight: size * TypeRole.title.spec.lineHeightRatio, tracking: 0,
                                      weight: CoverLayout.titleWeight,
                                      opticalSize: LiterataFont.opticalSize(forPointSize: size), uppercase: false)
        let attributed = NSAttributedString(string: word, attributes: [
            NSAttributedString.Key(kCTFontAttributeName as String): style.ctFont(),
        ])
        let line = CTLineCreateWithAttributedString(attributed)
        return CTLineGetTypographicBounds(line, nil, nil, nil)
    }

    public var body: some View {
        let inset = width * CoverLayout.insetScale
        ZStack(alignment: .topLeading) {
            RoundedRectangle(cornerRadius: (isThumbnail ? Radius.block : Radius.card).value, style: .continuous)
                .fill(field.color)
            if isThumbnail {
                Text(String(title.prefix(1)))
                    .font(Self.literata(size: width * CoverLayout.initialScale, weight: CoverLayout.titleWeight))
                    .foregroundStyle(ColorToken.coverTitle.color)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                VStack(alignment: .leading, spacing: 0) {
                    Text(title)
                        .font(Self.literata(size: Self.titleSize(title: title, width: width), weight: CoverLayout.titleWeight))
                        .foregroundStyle(ColorToken.coverTitle.color)
                    Spacer(minLength: 0)
                    if let author {
                        Text(author)
                            .font(Self.literata(size: width * CoverLayout.authorScale, weight: CoverLayout.authorWeight))
                            .foregroundStyle(ColorToken.coverTitle.color)
                    }
                }
                .padding(inset)
            }
        }
        .frame(width: width, height: height)
        .dynamicTypeSize(.large)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text(Microcopy.joined([title, author ?? ""])))
        .accessibilityAddTraits(.isImage)
        .sylviaAuditRegion("cover")
    }
}
