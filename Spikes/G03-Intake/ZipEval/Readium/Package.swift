// swift-tools-version: 6.2
// G0.3 archive-library evaluation: Readium's fork readium/ZIPFoundation 3.0.1 (module ReadiumZIPFoundation),
// the version readium/swift-toolkit 3.11.0 resolves to. Evidence code only; never shipped.
import PackageDescription

let package = Package(
    name: "ZipEvalReadium",
    platforms: [.iOS(.v26), .macOS(.v26)],
    dependencies: [
        .package(path: "../Common"),
        .package(url: "https://github.com/readium/ZIPFoundation.git", exact: "3.0.1"),
    ],
    targets: [
        .executableTarget(
            name: "zipeval-readium",
            dependencies: [
                .product(name: "EvalCommon", package: "Common"),
                .product(name: "ReadiumZIPFoundation", package: "ZIPFoundation"),
            ],
            swiftSettings: [.swiftLanguageMode(.v6)]
        ),
    ]
)
