// swift-tools-version: 6.2
// G0.3 archive-library evaluation: upstream weichsel/ZIPFoundation 0.9.20.
// Evidence code only; never shipped. Run through Spikes/G03-Intake/ZipEval/run-eval.sh.
import PackageDescription

let package = Package(
    name: "ZipEvalUpstream",
    platforms: [.iOS(.v26), .macOS(.v26)],
    dependencies: [
        .package(path: "../Common"),
        .package(url: "https://github.com/weichsel/ZIPFoundation.git", exact: "0.9.20"),
    ],
    targets: [
        .executableTarget(
            name: "zipeval-upstream",
            dependencies: [
                .product(name: "EvalCommon", package: "Common"),
                .product(name: "ZIPFoundation", package: "ZIPFoundation"),
            ],
            swiftSettings: [.swiftLanguageMode(.v6)]
        ),
    ]
)
