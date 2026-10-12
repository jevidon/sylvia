import Foundation
import Testing
@testable import SylviaDesign

/// Where tests write evidence (tables, PNGs). Set by Scripts/ci.d/20-design.sh through
/// `TEST_RUNNER_SYLVIA_EVIDENCE_DIR`; when absent, tests still assert but write nothing.
enum Evidence {
    static var directory: URL? {
        ProcessInfo.processInfo.environment["SYLVIA_EVIDENCE_DIR"].map { URL(fileURLWithPath: $0, isDirectory: true) }
    }

    static var environmentLabel: String {
        #if os(iOS)
        let device = ProcessInfo.processInfo.environment["SIMULATOR_MODEL_IDENTIFIER"] ?? "unknown device"
        let runtime = ProcessInfo.processInfo.environment["SIMULATOR_RUNTIME_VERSION"] ?? "unknown runtime"
        let name = ProcessInfo.processInfo.environment["SIMULATOR_DEVICE_NAME"] ?? "simulator"
        return "simulator: \(name) (\(device)), iOS \(runtime)"
        #else
        return "host: macOS \(ProcessInfo.processInfo.operatingSystemVersionString)"
        #endif
    }

    static var platformSuffix: String {
        #if os(iOS)
        "simulator"
        #else
        "host"
        #endif
    }

    static func write(_ name: String, _ data: Data) {
        guard let directory else { return }
        do {
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            try data.write(to: directory.appendingPathComponent(name))
        } catch {
            Issue.record("could not write evidence \(name): \(error)")
        }
    }

    static func write(_ name: String, text: String) { write(name, Data(text.utf8)) }
}
