// swift-tools-version: 6.2
// Shared helpers for the G0.3 archive-library evaluation (deterministic data, memory probes).
import PackageDescription

let package = Package(
    name: "Common",
    platforms: [.iOS(.v26), .macOS(.v26)],
    products: [.library(name: "EvalCommon", targets: ["EvalCommon"])],
    targets: [
        .target(name: "EvalCommon", swiftSettings: [.swiftLanguageMode(.v6)]),
    ]
)
