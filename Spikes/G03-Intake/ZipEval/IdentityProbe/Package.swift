// swift-tools-version: 6.2
// Probe: can an app graph that already contains Readium 3.11.0 (which depends on readium/ZIPFoundation)
// also depend on upstream weichsel/ZIPFoundation 0.9.20? Both URLs end in "ZIPFoundation", so SwiftPM
// derives the same package identity ("zipfoundation") for both. run-eval.sh records the resolver's answer.
import PackageDescription

let package = Package(
    name: "IdentityProbe",
    platforms: [.iOS(.v26), .macOS(.v26)],
    dependencies: [
        .package(url: "https://github.com/readium/swift-toolkit.git", exact: "3.11.0"),
        .package(url: "https://github.com/weichsel/ZIPFoundation.git", exact: "0.9.20"),
    ],
    targets: [
        .target(
            name: "IdentityProbe",
            dependencies: [
                .product(name: "ReadiumShared", package: "swift-toolkit"),
                .product(name: "ZIPFoundation", package: "ZIPFoundation"),
            ]
        ),
    ]
)
