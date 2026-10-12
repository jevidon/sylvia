// swift-tools-version: 6.2
// SylviaDesign: the Marginalia design language (plan Section 4.4, ADR-0013).
//
// Targets
//   SylviaDesignTokens   Platform-neutral token definitions: colors (all four appearances),
//                        markers, type roles, shape/space/motion, status vocabulary,
//                        contrast math. Foundation only, so the exporter and host tests
//                        can use it without UIKit/AppKit.
//   SylviaDesign         The UI-facing package: asset catalog, custom symbols, Literata,
//                        String Catalog, typed SwiftUI/UIKit/AppKit API. Re-exports the tokens.
//   SylviaDesignGallery  The component samples (iOS): every component in the states the snapshot
//                        tests compare, shared by the snapshot tests and the design catalog app
//                        (Apps/DesignCatalog), so a device shows what the references show.
//   SylviaDesignExport   `sylvia-design-export`: writes Contracts/design/marginalia.v1.json,
//                        the color asset catalog and the vocabulary String Catalog from the
//                        token definitions, or checks that the committed files match.
//
// Test targets
//   SylviaDesignTokensTests     token definitions (host and simulator)
//   SylviaDesignTests           platform layer and component logic (host and simulator)
//   SylviaDesignSnapshotTests   component snapshots and the T51/T53 automated proxies; iOS only,
//                               recorded on the iPhone 17 / iOS 26.5 simulator (ADR-0013 §9)
//
// The only dependency is pointfreeco/swift-snapshot-testing at exactly 1.19.6 (ADR-0002), used by
// the snapshot test target alone; it never links into the library.
import PackageDescription

let package = Package(
    name: "SylviaDesign",
    defaultLocalization: "en",
    platforms: [.iOS(.v26), .macOS(.v26)],
    products: [
        .library(name: "SylviaDesign", targets: ["SylviaDesign"]),
        .library(name: "SylviaDesignGallery", targets: ["SylviaDesignGallery"]),
        .executable(name: "sylvia-design-export", targets: ["SylviaDesignExport"]),
    ],
    dependencies: [
        .package(url: "https://github.com/pointfreeco/swift-snapshot-testing", exact: "1.19.6"),
    ],
    targets: [
        .target(
            name: "SylviaDesignTokens",
            path: "Sources/SylviaDesignTokens"
        ),
        .target(
            name: "SylviaDesign",
            dependencies: ["SylviaDesignTokens"],
            path: "Sources/SylviaDesign",
            resources: [
                .copy("Resources/Fonts"),
                .process("Resources/Colors.xcassets"),
                .process("Resources/Symbols.xcassets"),
                .process("Resources/Vocabulary.xcstrings"),
            ]
        ),
        .target(
            name: "SylviaDesignGallery",
            dependencies: ["SylviaDesign"],
            path: "Sources/SylviaDesignGallery"
        ),
        .executableTarget(
            name: "SylviaDesignExport",
            dependencies: ["SylviaDesignTokens"],
            path: "Sources/SylviaDesignExport"
        ),
        .testTarget(
            name: "SylviaDesignTokensTests",
            dependencies: ["SylviaDesignTokens"],
            path: "Tests/SylviaDesignTokensTests"
        ),
        .testTarget(
            name: "SylviaDesignTests",
            dependencies: ["SylviaDesign"],
            path: "Tests/SylviaDesignTests"
        ),
        .testTarget(
            name: "SylviaDesignSnapshotTests",
            dependencies: [
                "SylviaDesign",
                "SylviaDesignGallery",
                .product(name: "SnapshotTesting", package: "swift-snapshot-testing"),
            ],
            path: "Tests/SylviaDesignSnapshotTests",
            exclude: ["__Snapshots__"]
        ),
    ],
    swiftLanguageModes: [.v6]
)
