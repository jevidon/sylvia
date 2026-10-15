// swift-tools-version: 6.2
// G0.5 AI spike (plan Sections 13, 14, 21.1). Evidence code; never shipped (ADR-0002, ADR-0011).
import PackageDescription

let strict: [SwiftSetting] = [
    .swiftLanguageMode(.v6),
    .enableUpcomingFeature("ExistentialAny"),
]

let package = Package(
    name: "G05AI",
    platforms: [.iOS(.v26), .macOS(.v26)],
    products: [
        .library(name: "SylviaAI", targets: ["SylviaAI"]),
        .library(name: "SylviaContext", targets: ["SylviaContext"]),
        .library(name: "G05TestSupport", targets: ["G05TestSupport"]),
    ],
    dependencies: [
        // Pinned in ADR-0002; exact version only.
        .package(url: "https://github.com/groue/GRDB.swift.git", exact: "7.11.1"),
    ],
    targets: [
        // Providers, streaming, lifecycle, consent, network policy, credentials, grounding, transcription.
        // Foundation, Network and Security only, so it builds for iOS and macOS.
        .target(name: "SylviaAI", swiftSettings: strict),
        // Text extraction, chunking, FTS5 retrieval and ContextPack assembly.
        .target(
            name: "SylviaContext",
            dependencies: ["SylviaAI", .product(name: "GRDB", package: "GRDB.swift")],
            swiftSettings: strict
        ),
        // Test-only helpers: loopback fake HTTP server, bounded EPUB (ZIP) reader, fixture lookup.
        .target(name: "G05TestSupport", dependencies: ["SylviaAI"], swiftSettings: strict),
        .testTarget(
            name: "SylviaAITests",
            dependencies: ["SylviaAI", "G05TestSupport"],
            swiftSettings: strict
        ),
        .testTarget(
            name: "SylviaContextTests",
            dependencies: ["SylviaAI", "SylviaContext", "G05TestSupport"],
            resources: [.copy("EvaluationSet")],
            swiftSettings: strict
        ),
        // Live smoke tests against real endpoints (OpenAI, Anthropic, a user's OpenAI-compatible server or gateway,
        // a transcription endpoint). Each runs only with SYLVIA_LIVE_PROVIDER_TESTS=1 plus its own variables.
        .testTarget(
            name: "LiveProviderTests",
            dependencies: ["SylviaAI", "G05TestSupport"],
            swiftSettings: strict
        ),
    ]
)
