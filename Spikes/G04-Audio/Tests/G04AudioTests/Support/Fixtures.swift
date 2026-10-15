import Foundation
import Testing
@testable import G04AudioKit

/// Locates the G0.4 fixtures. Simulator runs read the host cache (`SYLVIA_FIXTURE_CACHE`, passed by the CI script
/// as `TEST_RUNNER_SYLVIA_FIXTURE_CACHE`, or the default cache under the simulator's host home). Device builds
/// carry them in the test bundle. A missing fixture is a test failure, never a skip.
enum Fixtures {
    struct Missing: Error, CustomStringConvertible {
        var path: String
        var description: String { "fixture missing: \(path) (run Scripts/fixtures/fetch.sh and Scripts/fixtures/generate-g04-audio-fixtures.sh)" }
    }

    static var cacheRoot: URL {
        let env = ProcessInfo.processInfo.environment
        if let c = env["SYLVIA_FIXTURE_CACHE"], !c.isEmpty { return URL(fileURLWithPath: c) }
        if let home = env["SIMULATOR_HOST_HOME"] {
            return URL(fileURLWithPath: home).appendingPathComponent("Library/Caches/SylviaFixtures")
        }
        return Bundle(for: BundleToken.self).bundleURL.appendingPathComponent("G04Fixtures")
    }

    static var generated: URL { cacheRoot.appendingPathComponent("generated/g04-audio") }

    static func url(_ relative: String) throws -> URL {
        let u = generated.appendingPathComponent(relative)
        guard FileManager.default.fileExists(atPath: u.path) else { throw Missing(path: u.path) }
        return u
    }

    static func librivoxM4B() throws -> URL {
        let u = cacheRoot.appendingPathComponent("downloads/MeditationsMarcusAurelius_librivox.m4b")
        guard FileManager.default.fileExists(atPath: u.path) else { throw Missing(path: u.path) }
        return u
    }

    nonisolated(unsafe) private static var masters: [String: MasterPCM] = [:]
    private static let lock = NSLock()

    static func master600() throws -> MasterPCM { try master("master-600s.wav") }
    static func masterLong() throws -> MasterPCM { try master("master-long.wav") }

    private static func master(_ name: String) throws -> MasterPCM {
        try lock.withLock {
            if let m = masters[name] { return m }
            let m = try MasterPCM(url: url(name))
            masters[name] = m
            return m
        }
    }

    /// The chapter table written by the generate script into the chaptered 600 s fixtures (milliseconds).
    static let chapters600: [ChapterInfo] = [
        ChapterInfo(title: "Opening", startMs: 0, endMs: 95_500),
        ChapterInfo(title: "Chapter Two", startMs: 95_500, endMs: 241_250),
        ChapterInfo(title: "Chapter Three", startMs: 241_250, endMs: 400_000),
        ChapterInfo(title: "Chapter Four", startMs: 400_000, endMs: 600_000),
    ]

    /// master-long.wav length in frames (generate script; checked by a test).
    static let longLoopFrames = 95_319_936
    static let longLoops = 17

    /// Multi-file book members: file name, slice start in master-long (s), duration (s), embedded track.
    static let multi: [(name: String, start: Double, duration: Double, track: Int)] = [
        ("Part 2.mp3", 0, 137.5, 1),
        ("Part 1.mp3", 137.5, 162.25, 2),
        ("Part 3.mp3", 299.75, 150, 3),
        ("Part 10.mp3", 449.75, 120.1, 4),
    ]
}

private final class BundleToken {}

/// Writes machine-readable results for the evidence folder and always prints them so they appear in the test log.
/// Where they are written:
/// - `G04_RESULTS_DIR` when set (the CI script passes an absolute path as `TEST_RUNNER_G04_RESULTS_DIR`). A relative
///   path would resolve against the test process's working directory, not the repository, so it is rejected.
/// - otherwise, on a physical device only, `Documents/G04Results/` in the test host's (the harness app's) container,
///   where the device checklist pulls them with `devicectl` (printed tables can interleave with console lines).
/// A table that cannot be written is a test failure, never silently dropped.
enum Results {
    static let lock = NSLock()

    static func write(_ name: String, _ lines: [String]) {
        let text = lines.joined(separator: "\n") + "\n"
        print("=== \(name) ===\n\(text)=== end \(name) ===")
        let dir: URL
        switch directory() {
        case .none: return
        case let .invalid(reason):
            Issue.record("result table \(name) not written: \(reason)")
            return
        case let .directory(url): dir = url
        }
        lock.withLock {
            let url = dir.appendingPathComponent(name)
            do {
                try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
                try text.write(to: url, atomically: true, encoding: .utf8)
            } catch {
                Issue.record("result table \(name) not written to \(url.path): \(error)")
            }
        }
    }

    enum Destination { case none, invalid(String), directory(URL) }

    static func directory() -> Destination {
        if let dir = ProcessInfo.processInfo.environment["G04_RESULTS_DIR"], !dir.isEmpty {
            guard dir.hasPrefix("/") else { return .invalid("G04_RESULTS_DIR must be an absolute path, got '\(dir)'") }
            return .directory(URL(fileURLWithPath: dir, isDirectory: true))
        }
        #if targetEnvironment(simulator)
        return .none
        #else
        guard let docs = try? FileManager.default.url(for: .documentDirectory, in: .userDomainMask, appropriateFor: nil, create: true) else {
            return .invalid("the test host has no Documents directory")
        }
        return .directory(docs.appendingPathComponent("G04Results", isDirectory: true))
        #endif
    }

    static func environmentLabel() -> String {
        let env = ProcessInfo.processInfo.environment
        #if targetEnvironment(simulator)
        let model = env["SIMULATOR_MODEL_IDENTIFIER"] ?? "unknown model"
        let runtime = env["SIMULATOR_RUNTIME_VERSION"] ?? "unknown runtime"
        let build = env["SIMULATOR_RUNTIME_BUILD_VERSION"] ?? ""
        return "simulator \(model), iOS \(runtime) (\(build)), \(buildConfiguration), \(TestAudio.label)"
        #else
        var info = utsname()
        uname(&info)
        let machine = withUnsafeBytes(of: &info.machine) { String(decoding: $0.prefix { $0 != 0 }, as: UTF8.self) }
        let os = ProcessInfo.processInfo.operatingSystemVersionString
        return "device \(machine), iOS \(os), \(buildConfiguration), \(TestAudio.label)"
        #endif
    }

    /// The 1-, 5- and 15-minute load averages of the machine running the test: on the simulator the host's (simulator
    /// processes run on the host's kernel), on a device the device's. Review R4-02: on the simulator, MP3 cold-resume
    /// times depend on the host's load (other jobs' simulators), so the budget and long-format tables record it.
    static func loadAverages() -> [Double] {
        var l = [Double](repeating: .nan, count: 3)
        return getloadavg(&l, 3) == 3 ? l : [.nan, .nan, .nan]
    }

    /// For the environment line of the timing tables: the load averages now and, when the CI drop-in passed it
    /// (`TEST_RUNNER_G04_BOOTED_SIMULATORS`), how many simulators were booted on the host when the test run started.
    static func loadLabel() -> String {
        let l = loadAverages()
        #if targetEnvironment(simulator)
        let whose = "host"
        #else
        let whose = "device"
        #endif
        var s = String(format: "%@ load averages %.2f %.2f %.2f (1, 5, 15 min)", whose, l[0], l[1], l[2])
        if let booted = ProcessInfo.processInfo.environment["G04_BOOTED_SIMULATORS"], !booted.isEmpty {
            s += ", \(booted) simulators booted on the host when the test run started"
        }
        return s
    }

    /// The 1-minute load average, for a per-trial column.
    static func load1m() -> String { String(format: "%.1f", loadAverages()[0]) }

    /// The configuration the tests were built with (plan 19.1 asks for release builds for device measurements; the
    /// scheme's test action builds Debug, so every table says which it was).
    static var buildConfiguration: String {
        #if DEBUG
        "Debug build"
        #else
        "Release build"
        #endif
    }

    static func percentile(_ xs: [Double], _ p: Double) -> Double {
        guard !xs.isEmpty else { return .nan }
        let s = xs.sorted()
        let rank = p / 100 * Double(s.count - 1)
        let lo = Int(rank.rounded(.down)), hi = Int(rank.rounded(.up))
        return s[lo] + (s[hi] - s[lo]) * (rank - Double(lo))
    }
}
