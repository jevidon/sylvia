import Foundation

/// The generated files of the design package, keyed by path relative to the repository root.
/// `sylvia-design-export write` writes them; `check` compares them with the working tree.
public enum GeneratedFiles {
    public static let resourcesPath = "Packages/Design/Sources/SylviaDesign/Resources"
    public static let colorsCatalogPath = resourcesPath + "/Colors.xcassets"
    public static let symbolsCatalogPath = resourcesPath + "/Symbols.xcassets"
    public static let stringCatalogPath = resourcesPath + "/Vocabulary.xcstrings"
    /// Directories whose whole contents are generated (anything else inside them is stale).
    public static let generatedDirectories = [colorsCatalogPath, symbolsCatalogPath, ContractFixtures.directory]

    public static func all() -> [String: String] {
        var files: [String: String] = [TokenExport.relativePath: TokenExport.serialized()]
        files.merge(ColorCatalog.files(), uniquingKeysWith: { $1 })
        files.merge(SymbolCatalog.files(), uniquingKeysWith: { $1 })
        files[stringCatalogPath] = StringCatalog.serialized()
        files.merge(ContractFixtures.files(), uniquingKeysWith: { $1 })
        return files
    }
}

enum AssetCatalogInfo {
    static let catalogContents = JSONValue.object([
        ("info", .object([("author", .string("xcode")), ("version", .integer(1))])),
    ]).serialized(style: .xcode)
}

/// The color asset catalog: one color set per ``ColorToken`` with Any, Dark, Any + High Contrast
/// and Dark + High Contrast variants.
public enum ColorCatalog {
    public static func files() -> [String: String] {
        var files = [GeneratedFiles.colorsCatalogPath + "/Contents.json": AssetCatalogInfo.catalogContents]
        for token in ColorToken.allCases {
            files[GeneratedFiles.colorsCatalogPath + "/\(token.rawValue).colorset/Contents.json"] = colorSet(token)
        }
        return files
    }

    static func colorSet(_ token: ColorToken) -> String {
        func variant(_ appearance: Appearance) -> JSONValue {
            let c = token.value(in: appearance)
            var appearances: [JSONValue] = []
            if appearance.isDark {
                appearances.append(.object([("appearance", .string("luminosity")), ("value", .string("dark"))]))
            }
            if appearance.isIncreasedContrast {
                appearances.append(.object([("appearance", .string("contrast")), ("value", .string("high"))]))
            }
            var members: [(String, JSONValue)] = []
            if !appearances.isEmpty { members.append(("appearances", .array(appearances))) }
            members.append(("color", .object([
                ("color-space", .string("srgb")),
                ("components", .object([
                    ("alpha", .string(String(format: "%.3f", c.alpha))),
                    ("blue", .string(String(format: "0x%02X", c.blue))),
                    ("green", .string(String(format: "0x%02X", c.green))),
                    ("red", .string(String(format: "0x%02X", c.red))),
                ])),
            ])))
            members.append(("idiom", .string("universal")))
            return .object(members)
        }
        return JSONValue.object([
            ("colors", .array([variant(.light), variant(.dark), variant(.lightIncreasedContrast),
                               variant(.darkIncreasedContrast)])),
            ("info", .object([("author", .string("xcode")), ("version", .integer(1))])),
        ]).serialized(style: .xcode)
    }
}

/// The String Catalog: every vocabulary entry, label and format, English, manual extraction.
public enum StringCatalog {
    public static let tableName = "Vocabulary"

    public static func serialized() -> String {
        var strings: [String: JSONValue] = [:]
        for key in VocabularyKey.allCases {
            strings[key.rawValue] = entry(text: key.text, placeholders: key.placeholders, plural: key.plural,
                                          comment: key.comment)
        }
        for key in LabelKey.allCases {
            strings[key.rawValue] = entry(text: key.text, placeholders: [], plural: nil, comment: key.comment)
        }
        for key in FormatKey.allCases {
            strings[key.rawValue] = entry(text: key.text, placeholders: key.placeholders, plural: nil,
                                          comment: key.comment)
        }
        precondition(strings.count == VocabularyKey.allCases.count + LabelKey.allCases.count + FormatKey.allCases.count,
                     "duplicate String Catalog key")
        return JSONValue.object([
            ("sourceLanguage", .string("en")),
            ("strings", JSONValue.sortedObject(strings)),
            ("version", .string("1.0")),
        ]).serialized(style: .xcode)
    }

    static func unit(_ value: String) -> JSONValue {
        .object([("stringUnit", .object([("state", .string("translated")), ("value", .string(value))]))])
    }

    static func entry(text: String, placeholders: [Placeholder], plural: PluralForms?, comment: String) -> JSONValue {
        let format = Template.formatString(text, placeholders: placeholders, plural: plural)
        var english: [(String, JSONValue)] = [
            ("stringUnit", .object([("state", .string("translated")), ("value", .string(format))])),
        ]
        if let plural {
            let position = placeholders.firstIndex { $0.name == plural.placeholder }! + 1
            let spec = Template.specifier(placeholders[position - 1].kind)
            let one = plural.one.replacingOccurrences(of: "{\(plural.placeholder)}", with: "%arg")
            let other = plural.other.replacingOccurrences(of: "{\(plural.placeholder)}", with: "%arg")
            english.append(("substitutions", .object([(plural.placeholder, .object([
                ("argNum", .integer(position)),
                ("formatSpecifier", .string(spec)),
                ("variations", .object([("plural", .object([("one", unit(one)), ("other", unit(other))]))])),
            ]))])))
        }
        return .object([
            ("comment", .string(comment)),
            ("extractionState", .string("manual")),
            ("localizations", .object([("en", .object(english))])),
        ])
    }
}

/// Custom symbols as SF Symbols templates (template version 3.0) with Ultralight, Regular and
/// Black masters at the Small scale, from which the system interpolates every weight and scale.
/// Strokes from the boards are converted to filled outlines: each segment becomes a capsule
/// (round caps), so overlapping capsules form round joins. Every master has the same path
/// structure, which interpolation requires.
public enum SymbolCatalog {
    /// Template units are points at a 100 pt type size.
    static let unitsPerViewBoxUnit = 4.0
    /// Vertical centre of the glyph: half the SF Pro cap height at 100 pt (70.459), above the baseline.
    static let capHeight = 70.459
    static let sideBearing = 4.0
    static let columns: [(name: String, centre: Double)] = [("Ultralight", 560), ("Regular", 1450), ("Black", 2900)]
    static let baselines: [(scale: String, y: Double)] = [("S", 696), ("M", 1126), ("L", 1556)]

    public static func files() -> [String: String] {
        var files = [GeneratedFiles.symbolsCatalogPath + "/Contents.json": AssetCatalogInfo.catalogContents]
        for symbol in CustomSymbol.allCases {
            let dir = GeneratedFiles.symbolsCatalogPath + "/\(symbol.rawValue).symbolset"
            files[dir + "/Contents.json"] = JSONValue.object([
                ("info", .object([("author", .string("xcode")), ("version", .integer(1))])),
                ("symbols", .array([.object([("filename", .string("\(symbol.rawValue).svg")),
                                             ("idiom", .string("universal"))])])),
            ]).serialized(style: .xcode)
            files[dir + "/\(symbol.rawValue).svg"] = template(symbol)
        }
        return files
    }

    static func f(_ v: Double) -> String { String(format: "%.3f", v) }

    /// A capsule around segment p1-p2 with radius r, drawn clockwise on screen, as one closed path
    /// with a fixed command structure (M L C C L C C Z).
    static func capsule(_ x1: Double, _ y1: Double, _ x2: Double, _ y2: Double, _ r: Double) -> String {
        let k = 0.5522847498 * r
        let length = ((x2 - x1) * (x2 - x1) + (y2 - y1) * (y2 - y1)).squareRoot()
        let ux = (x2 - x1) / length, uy = (y2 - y1) / length
        let nx = -uy, ny = ux
        let a = (x1 + nx * r, y1 + ny * r), b = (x2 + nx * r, y2 + ny * r)
        let c = (x2 - nx * r, y2 - ny * r), d = (x1 - nx * r, y1 - ny * r)
        let tip2 = (x2 + ux * r, y2 + uy * r), tip1 = (x1 - ux * r, y1 - uy * r)
        func p(_ x: Double, _ y: Double) -> String { "\(f(x)) \(f(y))" }
        var s = "M\(p(a.0, a.1))L\(p(b.0, b.1))"
        s += "C\(p(b.0 + ux * k, b.1 + uy * k)) \(p(tip2.0 + nx * k, tip2.1 + ny * k)) \(p(tip2.0, tip2.1))"
        s += "C\(p(tip2.0 - nx * k, tip2.1 - ny * k)) \(p(c.0 + ux * k, c.1 + uy * k)) \(p(c.0, c.1))"
        s += "L\(p(d.0, d.1))"
        s += "C\(p(d.0 - ux * k, d.1 - uy * k)) \(p(tip1.0 - nx * k, tip1.1 - ny * k)) \(p(tip1.0, tip1.1))"
        s += "C\(p(tip1.0 + nx * k, tip1.1 + ny * k)) \(p(a.0 - ux * k, a.1 - uy * k)) \(p(a.0, a.1))Z"
        return s
    }

    /// Paths for one master with the glyph's left edge (including stroke) at x = 0, plus its width.
    static func master(_ symbol: CustomSymbol, strokeWidth: Double) -> (paths: [String], width: Double) {
        let points = symbol.polylines.flatMap { $0 }
        let minX = points.map(\.x).min()! * unitsPerViewBoxUnit - strokeWidth / 2
        let maxX = points.map(\.x).max()! * unitsPerViewBoxUnit + strokeWidth / 2
        var paths: [String] = []
        for line in symbol.polylines {
            for (start, end) in zip(line, line.dropFirst()) {
                let x1 = start.x * unitsPerViewBoxUnit - minX, x2 = end.x * unitsPerViewBoxUnit - minX
                let y1 = (start.y - 12) * unitsPerViewBoxUnit - capHeight / 2
                let y2 = (end.y - 12) * unitsPerViewBoxUnit - capHeight / 2
                paths.append(capsule(x1, y1, x2, y2, strokeWidth / 2))
            }
        }
        return (paths, maxX - minX)
    }

    static func template(_ symbol: CustomSymbol) -> String {
        let widths = symbol.masterStrokeWidths
        let strokes = [widths.ultralight, widths.regular, widths.black]
        var guides: [String] = []
        for (scale, y) in baselines {
            guides.append("  <line id=\"Baseline-\(scale)\" style=\"fill:none;stroke:#27AAE1;opacity:1;stroke-width:0.5;\" x1=\"263\" x2=\"3036\" y1=\"\(f(y))\" y2=\"\(f(y))\"/>")
            guides.append("  <line id=\"Capline-\(scale)\" style=\"fill:none;stroke:#27AAE1;opacity:1;stroke-width:0.5;\" x1=\"263\" x2=\"3036\" y1=\"\(f(y - capHeight))\" y2=\"\(f(y - capHeight))\"/>")
        }
        var groups: [String] = []
        for (column, stroke) in zip(columns, strokes) {
            let (paths, width) = master(symbol, strokeWidth: stroke)
            let left = column.centre - width / 2 - sideBearing
            let right = column.centre + width / 2 + sideBearing
            guides.append("  <line id=\"left-margin-\(column.name)-S\" style=\"fill:none;stroke:#00AEEF;stroke-width:0.5;opacity:1.0;\" x1=\"\(f(left))\" x2=\"\(f(left))\" y1=\"600\" y2=\"720\"/>")
            guides.append("  <line id=\"right-margin-\(column.name)-S\" style=\"fill:none;stroke:#00AEEF;stroke-width:0.5;opacity:1.0;\" x1=\"\(f(right))\" x2=\"\(f(right))\" y1=\"600\" y2=\"720\"/>")
            groups.append("  <g id=\"\(column.name)-S\" transform=\"matrix(1 0 0 1 \(f(left + sideBearing)) 696)\">")
            groups += paths.map { "   <path d=\"\($0)\"/>" }
            groups.append("  </g>")
        }
        let lines = [
            "<?xml version=\"1.0\" encoding=\"UTF-8\"?>",
            "<!DOCTYPE svg PUBLIC \"-//W3C//DTD SVG 1.1//EN\" \"http://www.w3.org/Graphics/SVG/1.1/DTD/svg11.dtd\">",
            "<!-- Generated by sylvia-design-export from Packages/Design/Sources/SylviaDesignTokens/Markers.swift. Do not edit. -->",
            "<!-- \(symbol.rawValue): geometry from \(symbol.boardSource). -->",
            "<svg version=\"1.1\" xmlns=\"http://www.w3.org/2000/svg\" xmlns:xlink=\"http://www.w3.org/1999/xlink\" width=\"3300\" height=\"2200\">",
            " <g id=\"Notes\">",
            "  <rect height=\"2200\" id=\"artboard\" style=\"fill:white;opacity:1\" width=\"3300\" x=\"0\" y=\"0\"/>",
            "  <text id=\"template-version\" style=\"stroke:none;fill:black;font-family:sans-serif;font-size:13;\" transform=\"matrix(1 0 0 1 3036 1933)\">Template v.3.0</text>",
            " </g>",
            " <g id=\"Guides\">",
        ] + guides + [
            " </g>",
            " <g id=\"Symbols\">",
        ] + groups + [
            " </g>",
            "</svg>",
        ]
        return lines.joined(separator: "\n") + "\n"
    }
}
