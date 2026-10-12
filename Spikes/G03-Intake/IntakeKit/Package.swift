// swift-tools-version: 6.2
// G0.3 intake spike: share-extension handoff, .sylviapack v1 and container layout.
// Stage 0 evidence code. The module boundaries mirror plan Section 6.2 (SylviaImportHandoff, SylviaFiles)
// so the product can lift them, but nothing here ships as is.
import PackageDescription

let swift6: [SwiftSetting] = [.swiftLanguageMode(.v6)]

let package = Package(
    name: "IntakeKit",
    platforms: [.iOS(.v26), .macOS(.v26)],
    products: [
        .library(name: "SylviaIntakeCore", targets: ["SylviaIntakeCore"]),
        .library(name: "SylviaImportHandoff", targets: ["SylviaImportHandoff"]),
        .library(name: "SylviaPack", targets: ["SylviaPack"]),
        .library(name: "SylviaContainerLayout", targets: ["SylviaContainerLayout"]),
        .executable(name: "sylviapack-tool", targets: ["sylviapack-tool"]),
    ],
    dependencies: [
        // ADR-0010: the archive library is Readium's ZIPFoundation fork, already pinned by readium/swift-toolkit
        // 3.11.0. Upstream weichsel/ZIPFoundation cannot join the same SwiftPM graph (same package identity).
        .package(url: "https://github.com/readium/ZIPFoundation.git", exact: "3.0.1"),
    ],
    targets: [
        .target(name: "SylviaIntakeCore", swiftSettings: swift6),
        .target(name: "SylviaImportHandoff", dependencies: ["SylviaIntakeCore"], swiftSettings: swift6),
        .target(
            name: "SylviaPack",
            dependencies: ["SylviaIntakeCore", .product(name: "ReadiumZIPFoundation", package: "ZIPFoundation")],
            swiftSettings: swift6
        ),
        .target(
            name: "SylviaContainerLayout",
            dependencies: ["SylviaIntakeCore", "SylviaImportHandoff", "SylviaPack"],
            swiftSettings: swift6
        ),
        .executableTarget(
            name: "sylviapack-tool",
            dependencies: ["SylviaIntakeCore", "SylviaImportHandoff", "SylviaPack", "SylviaContainerLayout"],
            swiftSettings: swift6
        ),
        .testTarget(name: "SylviaImportHandoffTests", dependencies: ["SylviaImportHandoff"], swiftSettings: swift6),
        .testTarget(name: "SylviaPackTests", dependencies: ["SylviaPack"], swiftSettings: swift6),
        .testTarget(
            name: "SylviaContainerLayoutTests",
            dependencies: ["SylviaContainerLayout", "SylviaPack", "SylviaImportHandoff"],
            swiftSettings: swift6
        ),
    ]
)
