# Large content viewer lift activation: mutation check

Environment: simulator `Sylvia-M0-g06-design` (iPhone 17, iPhone18,3, iOS 26.5), host macOS 26.6.2, Xcode 27.0 (27A266a). Run 2026-10-12 about 05:05Z, review round 2 (R2-02), in this worktree.

Mutation: the line `.sylviaLiftActivation(gate: gate, action: action)` was removed from `PlayPauseButton` (`Packages/Design/Sources/SylviaDesign/Components/ScreenParts.swift`) in the working tree only. The catalog was rebuilt with `xcodebuild build-for-testing` (scheme DesignCatalog, generic iOS Simulator), and `DesignCatalogUITests/AreaNavigationTests/testLargeContentViewerActivatesControlsOnce` was run with `xcodebuild test-without-building -only-testing:` on the simulator. The mutation was then reverted; the committed source has the line, and the unmutated test passes (`large-content-viewer-activation-simulator.md`, `tests-ui-iphone-simulator.log`).

Expected: the test fails, which shows that it exercises the lift activation and not only the Button's own action.

Observed: it fails on its first press, 0.35 s at AX5. At AX5 the large content viewer takes the touch over even in a 0.35 s press, so without the lift activation the press does nothing (as review round 1 found for the tab bar, where the Library stayed open). With the lift activation each press toggles the button exactly once.

Output (xcodebuild, trimmed to the test lines):

```
Test Case '-[DesignCatalogUITests.AreaNavigationTests testLargeContentViewerActivatesControlsOnce]' started.
Apps/DesignCatalog/UITests/AreaNavigationTests.swift:168: error: -[DesignCatalogUITests.AreaNavigationTests testLargeContentViewerActivatesControlsOnce] : XCTAssertTrue failed - AX5: a 0.35 s press did not toggle to Play exactly once
Test Case '-[DesignCatalogUITests.AreaNavigationTests testLargeContentViewerActivatesControlsOnce]' failed (13.646 seconds).
	 Executed 1 test, with 1 failure (0 unexpected) in 13.646 (13.647) seconds
```

The tab bar's lift activation has the same control from review round 1: before this change, `testLargeContentViewerOnTabBarItem` recorded that the Library stayed open after the lift (report Finding 17); the test now requires the Inbox to open.
