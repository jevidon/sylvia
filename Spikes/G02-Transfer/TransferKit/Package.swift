// swift-tools-version: 6.2
// G0.2 transfer spike: the protocol core and client shared by the Mac source service tests and the iOS client.
// Platform-neutral: builds for iOS 26 and macOS 26 (ADR-0001). Dependencies are pinned exactly (ADR-0002, ADR-0009).
import PackageDescription

let strictSwift: [SwiftSetting] = [
    .swiftLanguageMode(.v6),
    .enableUpcomingFeature("ExistentialAny"),
]

let package = Package(
    name: "SylviaTransferKit",
    platforms: [.iOS(.v26), .macOS(.v26)],
    products: [
        .library(name: "SylviaTransferCore", targets: ["SylviaTransferCore"]),
        .library(name: "SylviaTransferClient", targets: ["SylviaTransferClient"]),
        .library(name: "SylviaBackgroundTransfer", targets: ["SylviaBackgroundTransfer"]),
    ],
    dependencies: [
        .package(url: "https://github.com/apple/swift-asn1.git", exact: "1.7.3"),
    ],
    targets: [
        .target(
            name: "SylviaTransferCore",
            dependencies: [.product(name: "SwiftASN1", package: "swift-asn1")],
            swiftSettings: strictSwift
        ),
        .target(
            name: "SylviaTransferClient",
            dependencies: ["SylviaTransferCore"],
            swiftSettings: strictSwift
        ),
        // G0.2 part 2: the iOS background-download client (jobs, reconciliation, pinned background session,
        // verified-only part journal, assembly and exactly-once import handoff).
        .target(
            name: "SylviaBackgroundTransfer",
            dependencies: ["SylviaTransferCore", "SylviaTransferClient"],
            swiftSettings: strictSwift
        ),
        .testTarget(
            name: "SylviaTransferCoreTests",
            dependencies: ["SylviaTransferCore"],
            resources: [.copy("Fixtures")],
            swiftSettings: strictSwift
        ),
        .testTarget(
            name: "SylviaTransferClientTests",
            dependencies: ["SylviaTransferClient", "SylviaTransferCore"],
            swiftSettings: strictSwift
        ),
        .testTarget(
            name: "SylviaBackgroundTransferTests",
            dependencies: ["SylviaBackgroundTransfer", "SylviaTransferClient", "SylviaTransferCore"],
            swiftSettings: strictSwift
        ),
    ]
)
