// swift-tools-version: 6.2
// G0.2 transfer spike: the Mac source service (library and command-line host) and the host fault tests.
// macOS only. Dependencies are pinned exactly (ADR-0002, ADR-0009).
import PackageDescription

let strictSwift: [SwiftSetting] = [
    .swiftLanguageMode(.v6),
    .enableUpcomingFeature("ExistentialAny"),
]

let package = Package(
    name: "SylviaSourceService",
    platforms: [.macOS(.v26)],
    products: [
        .library(name: "SylviaSourceService", targets: ["SylviaSourceService"]),
        .executable(name: "sylvia-source", targets: ["sylvia-source"]),
        .executable(name: "sylvia-fetch", targets: ["sylvia-fetch"]),
        .executable(name: "sylvia-test-source", targets: ["sylvia-test-source"]),
    ],
    dependencies: [
        .package(path: "../TransferKit"),
        .package(url: "https://github.com/apple/swift-nio.git", exact: "2.103.0"),
        .package(url: "https://github.com/apple/swift-nio-ssl.git", exact: "2.37.5"),
        .package(url: "https://github.com/apple/swift-certificates.git", exact: "1.21.0"),
        .package(url: "https://github.com/apple/swift-crypto.git", exact: "5.0.0"),
        .package(url: "https://github.com/apple/swift-asn1.git", exact: "1.7.3"),
    ],
    targets: [
        .target(
            name: "SylviaSourceService",
            dependencies: [
                .product(name: "SylviaTransferCore", package: "TransferKit"),
                .product(name: "NIOCore", package: "swift-nio"),
                .product(name: "NIOPosix", package: "swift-nio"),
                .product(name: "NIOHTTP1", package: "swift-nio"),
                .product(name: "NIOSSL", package: "swift-nio-ssl"),
                .product(name: "X509", package: "swift-certificates"),
                .product(name: "Crypto", package: "swift-crypto"),
                .product(name: "SwiftASN1", package: "swift-asn1"),
            ],
            swiftSettings: strictSwift
        ),
        // The command-line source: options, terminal approval and commands, shared by both executables.
        .target(
            name: "SylviaSourceCLI",
            dependencies: ["SylviaSourceService", .product(name: "SylviaTransferCore", package: "TransferKit")],
            swiftSettings: strictSwift
        ),
        .executableTarget(
            name: "sylvia-source",
            dependencies: ["SylviaSourceCLI"],
            swiftSettings: strictSwift
        ),
        // G0.2 part 2: the same source with test-only fault injection, throttling, connection closing and
        // automatic approval, for simulator integration runs. Never the companion; sylvia-source has none of it.
        .executableTarget(
            name: "sylvia-test-source",
            dependencies: ["SylviaSourceCLI"],
            swiftSettings: strictSwift
        ),
        .executableTarget(
            name: "sylvia-fetch",
            dependencies: [
                .product(name: "SylviaTransferCore", package: "TransferKit"),
                .product(name: "SylviaTransferClient", package: "TransferKit"),
            ],
            swiftSettings: strictSwift
        ),
        .testTarget(
            name: "SylviaSourceServiceTests",
            dependencies: [
                "SylviaSourceService",
                .product(name: "SylviaTransferCore", package: "TransferKit"),
                .product(name: "SylviaTransferClient", package: "TransferKit"),
                .product(name: "SylviaBackgroundTransfer", package: "TransferKit"),
                .product(name: "NIOCore", package: "swift-nio"),
                .product(name: "NIOPosix", package: "swift-nio"),
                .product(name: "NIOSSL", package: "swift-nio-ssl"),
                .product(name: "X509", package: "swift-certificates"),
                .product(name: "Crypto", package: "swift-crypto"),
            ],
            swiftSettings: strictSwift
        ),
    ]
)
