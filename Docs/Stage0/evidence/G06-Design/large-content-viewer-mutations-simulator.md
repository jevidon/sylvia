# Large content viewer lift activation: mutation checks (review round 3, R3-02)

Environment: host macOS 26.6.2, Apple M5 Max, Xcode 27.0 (27A266a); simulator `Sylvia-M0-minors-g06-design` (iPhone 17, iPhone18,3, iOS 26.5). Run 2026-10-13 between 10:02 and 10:06 NZDT in the worktree of branch `m0-int-minors-g06-design`, on commit `a339495`. Load: `uptime` load averages 54 to 116 (1-minute); up to 13 other agents shared the Mac. The catalog plays no audio.

Purpose: show that the tests fail when a part of the round 3 lift activation is taken away, so they test it and not only the Button's own action.

Method, for each mutation: one edit to `Packages/Design/Sources/SylviaDesign/Components/LargeContentViewer.swift` in the working tree only. Mutation 1 runs the gate's unit tests on the host (`xcodebuild test -scheme SylviaDesign-Package -destination platform=macOS -only-testing:SylviaDesignTests/ComponentLogicTests`). Mutations 2 and 3 rebuild the catalog (`xcodebuild build-for-testing`, scheme DesignCatalog, generic iOS Simulator) and run `xcodebuild test-without-building -only-testing:DesignCatalogUITests/AreaNavigationTests/testLargeContentViewerActivatesControlsOnce` on the simulator. Each edit was reverted with `git checkout` before the next. The unmutated test then passed in a scratch run (the committed run is `large-content-viewer-activation-simulator.md`, `tests-ui-iphone-simulator.log`). Output below is the test lines, with the worktree path removed from file names.

## Mutation 1: a Button action is taken for the latest touch down (as in the first round 3 attempt)

`let owner = liftedPress` in `LiftActivationGate.run(_:)` replaced by `let owner = press`. Expected: when a new touch has begun but not lifted, the late action of a lift-activated press is taken for the new touch and runs too (case 5 of the test), and a press's own action that arrives after the next touch began no longer stops that press's lift activation (case 6).

Observed: `liftActivationEitherOrder` fails at case 5 and every count after it; the other 28 tests of the suite pass.

```
✘ Test "Large content viewer lift: one activation per press in either order, also when the Button's action arrives late (R3-02)" recorded an issue at ComponentLogicTests.swift:469:9: Expectation failed: runs == 5
✘ Test "Large content viewer lift: one activation per press in either order, also when the Button's action arrives late (R3-02)" recorded an issue at ComponentLogicTests.swift:472:9: Expectation failed: runs == 6
✘ Test "Large content viewer lift: one activation per press in either order, also when the Button's action arrives late (R3-02)" recorded an issue at ComponentLogicTests.swift:482:9: Expectation failed: runs == 7
✘ Test "Large content viewer lift: one activation per press in either order, also when the Button's action arrives late (R3-02)" recorded an issue at ComponentLogicTests.swift:491:9: Expectation failed: runs == 9
✘ Test run with 29 tests in 1 suite failed after 0.175 seconds with 4 issues.
```

The UI test cannot tell this mutation apart: it needs a main thread too busy to deliver the Button's action within the settle delay, which the simulator did not produce (`large-content-viewer-timing-probe-simulator.md`).

## Mutation 2: the lift recognizer begins after 0.25 s (the round 2 value)

`LargeContentViewerLift.minimumPress` set back to 0.25. Expected: a press the viewer takes over before 0.25 s activates nothing.

Observed: the test fails on its first press, 0.15 s at AX5.

```
Test Case '-[DesignCatalogUITests.AreaNavigationTests testLargeContentViewerActivatesControlsOnce]' started.
Apps/DesignCatalog/UITests/AreaNavigationTests.swift:175: error: -[DesignCatalogUITests.AreaNavigationTests testLargeContentViewerActivatesControlsOnce] : XCTAssertTrue failed - AX5: a 0.15 s press did not toggle to Play exactly once
Test Case '-[DesignCatalogUITests.AreaNavigationTests testLargeContentViewerActivatesControlsOnce]' failed (13.853 seconds).
```

## Mutation 3: the touch lift is not reported

`onTouchUp?()` removed from `LiftPressRecognizer.touchesEnded`, so the gate never learns that a press lifted. Expected: every lift activation is scheduled for the same press, so after the first one no other runs.

Observed: the first press (0.15 s at AX5) toggles through the lift activation; the test fails on the second.

```
Test Case '-[DesignCatalogUITests.AreaNavigationTests testLargeContentViewerActivatesControlsOnce]' started.
Apps/DesignCatalog/UITests/AreaNavigationTests.swift:175: error: -[DesignCatalogUITests.AreaNavigationTests testLargeContentViewerActivatesControlsOnce] : XCTAssertTrue failed - AX5: a 0.2 s press did not toggle to Pause exactly once
Test Case '-[DesignCatalogUITests.AreaNavigationTests testLargeContentViewerActivatesControlsOnce]' failed (18.729 seconds).
```

The round 2 check that removing the lift activation altogether fails the test is `large-content-viewer-lift-mutation-simulator.md` (run then with presses of 0.35 and 3 s).
