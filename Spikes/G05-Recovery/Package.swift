// swift-tools-version: 6.2
// G0.5 recovery spike: persistence, durable saves, migrations, media removal, backup and restore.
// Stage 0 evidence code (ADR-0002 "Spikes/"); never shipped. See Docs/Stage0/G05-Recovery.md.
import PackageDescription

let strictSettings: [SwiftSetting] = [
    .swiftLanguageMode(.v6),
    .enableUpcomingFeature("ExistentialAny"),
]

let package = Package(
    name: "G05Recovery",
    platforms: [.iOS(.v26), .macOS(.v26)],
    products: [
        .library(name: "SylviaRecovery", targets: ["SylviaRecovery"]),
        .executable(name: "g05-recovery-tool", targets: ["g05-recovery-tool"]),
    ],
    dependencies: [
        // ADR-0002 pin; ADR-0003 records why GRDB.
        .package(url: "https://github.com/groue/GRDB.swift.git", exact: "7.11.1"),
    ],
    targets: [
        // C wrapper for sqlite3_db_config (variadic, so not callable from Swift), used to open
        // untrusted backup databases in SQLite's defensive mode. Links the system SQLite GRDB uses.
        .target(
            name: "SylviaSQLiteShim",
            linkerSettings: [.linkedLibrary("sqlite3")]
        ),
        .target(
            name: "SylviaRecovery",
            dependencies: ["SylviaSQLiteShim", .product(name: "GRDB", package: "GRDB.swift")],
            swiftSettings: strictSettings
        ),
        .executableTarget(
            name: "g05-recovery-tool",
            dependencies: ["SylviaRecovery", .product(name: "GRDB", package: "GRDB.swift")],
            swiftSettings: strictSettings
        ),
        .testTarget(
            name: "SylviaRecoveryTests",
            // The crash-drill test spawns the tool as its child process, so the tool must be built.
            dependencies: ["SylviaRecovery", "SylviaSQLiteShim", "g05-recovery-tool", .product(name: "GRDB", package: "GRDB.swift")],
            resources: [.copy("Fixtures")],
            swiftSettings: strictSettings
        ),
    ]
)
