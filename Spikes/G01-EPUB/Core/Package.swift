// swift-tools-version: 6.2
// G0.1 EPUB spike: platform-neutral pieces of the EPUB reader adapter (ADR-0004) that run on the host.
// Stage 0 evidence code; never shipped.
import PackageDescription

let package = Package(
    name: "G01EPUBCore",
    platforms: [.iOS(.v26), .macOS(.v26)],
    products: [
        .library(name: "G01EPUBCore", targets: ["G01EPUBCore"]),
    ],
    dependencies: [
        // The HTML5 parser Readium 3.11.0 itself uses (resolved at this version by the harness project's lock). The
        // sanitizer parses each served document with it to check the tree Readium's content iterator will build.
        .package(url: "https://github.com/scinfu/SwiftSoup.git", exact: "2.13.9"),
    ],
    targets: [
        .target(
            name: "G01EPUBCore",
            dependencies: [.product(name: "SwiftSoup", package: "SwiftSoup")],
            linkerSettings: [.linkedLibrary("sqlite3")]
        ),
        .testTarget(name: "G01EPUBCoreTests", dependencies: ["G01EPUBCore", .product(name: "SwiftSoup", package: "SwiftSoup")]),
    ],
    swiftLanguageModes: [.v6]
)
