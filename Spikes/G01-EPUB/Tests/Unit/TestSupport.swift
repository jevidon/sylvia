@testable import EPUBHarness
import Foundation
import G01EPUBCore
import UIKit
import XCTest

struct TestFailure: Error, CustomStringConvertible { let description: String }

/// Hosts reader sessions in a real window of the test host app so WebKit lays them out.
@MainActor enum TestHost {
    static var windows: [UIWindow] = []

    static var scene: UIWindowScene {
        UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }.first!
    }

    static func show(_ controller: UIViewController) -> UIWindow {
        let window = UIWindow(windowScene: scene)
        window.frame = scene.effectiveGeometry.coordinateSpace.bounds
        window.rootViewController = controller
        window.makeKeyAndVisible()
        windows.append(window)
        return window
    }

    static func tearDown() {
        for w in windows {
            w.rootViewController = nil
            w.isHidden = true
        }
        windows.removeAll()
    }

    static func fixtureURL(_ name: String) throws -> URL {
        guard let url = Fixtures.url(name) else { throw TestFailure(description: "fixture \(name) not in bundle") }
        return url
    }

    /// Opens `fixture` through the adapter and shows it in a ReaderScreen; waits for the first location.
    static func open(_ fixture: String, settings: ReaderSettings = .init(), options: EPUBOpenOptions = .sylvia,
                     safety: ReadiumReaderSession.Safety = .sylvia, initial: ReaderLocator? = nil,
                     url: URL? = nil) async throws -> ReaderScreen {
        let fileURL = try url ?? fixtureURL(fixture)
        let opened: OpenedEPUB
        switch await EPUBOpener.open(fileURL: fileURL, options: options) {
        case let .success(o): opened = o
        case let .failure(e): throw TestFailure(description: "open \(fixture): \(e)")
        }
        let session = try await ReadiumReaderSession.make(opened: opened, initialLocator: initial, settings: settings,
                                                          safety: safety, editingActions: ReaderScreen.editingActions)
        // The store is keyed by fixture name; tests start from an empty store.
        try? FileManager.default.removeItem(at: HighlightStore.url(for: fixture))
        let screen = ReaderScreen(session: session, fixture: fixture)
        _ = show(screen)
        guard await session.waitUntilLocated() else { throw TestFailure(description: "\(fixture): no location after 20 s") }
        await session.settleInitialLocation(initial)
        // Let the first spread finish loading its scripts and decorations.
        try await Task.sleep(for: .milliseconds(500))
        return screen
    }

    static func png(_ image: UIImage?) -> Data? { image?.pngData() }
}

/// Parses "rgb(241, 228, 200)" into components.
func rgb(_ css: String?) -> [Int]? {
    guard let css, let open = css.firstIndex(of: "("), let close = css.firstIndex(of: ")") else { return nil }
    return css[css.index(after: open) ..< close].split(separator: ",").compactMap { Int($0.trimmingCharacters(in: .whitespaces).split(separator: ".").first ?? "") }
}
