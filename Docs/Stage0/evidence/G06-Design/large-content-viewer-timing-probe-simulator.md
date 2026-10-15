# Large content viewer lift activation: timing probe (review round 3, R3-02)

Environment: simulator `Sylvia-M0-minors-g06-design` (iPhone 17, iPhone18,3, iOS 26.5), host macOS 26.6.2, Apple M5 Max, Xcode 27.0 (27A266a). Run 2026-10-13 between 09:15 and 10:02 NZDT in the worktree of branch `m0-int-minors-g06-design`. Load: `uptime` load averages between 24 and 197 (1-minute) during the runs; up to 13 other agents shared the Mac. Timings are indicative only. The catalog plays no audio.

**Scratch build, not the committed code.** To see the order of events inside the app, a script (run from `.build/scratch`; the same script is committed as [`commands/lift_probe_instrument.py`](commands/lift_probe_instrument.py), which also lists the commands) added `Logger.notice` probes (subsystem `com.jevidon.sylvia.probe`) to `LiftActivationGate`: touch down, touch lift, the Button's own action (ran or dropped), lift activation scheduled, lift activation settled (ran or skipped). The press durations of `AreaNavigationTests.testLargeContentViewerActivatesControlsOnce` were also changed in the scratch build. The catalog was built with `xcodebuild build-for-testing` and the one test run with `xcodebuild test-without-building -only-testing:DesignCatalogUITests/AreaNavigationTests/testLargeContentViewerActivatesControlsOnce`; the probe lines were read with `xcrun simctl spawn <udid> log show --predicate 'subsystem == "com.jevidon.sylvia.probe"'`. Both changes were then reverted (`git checkout`); the committed test presses for 0.15, 0.2, 0.35 and 3 s (`large-content-viewer-activation-simulator.md`). The probe lines of the four runs are kept in [`large-content-viewer-timing-probe/`](large-content-viewer-timing-probe/) (run 3 trimmed to its own two presses), and the tables below were made from them with [`commands/lift_probe_table.py`](commands/lift_probe_table.py).

"Measured" is the time from the probe's touch down to its touch lift. Launch 1 is at AX5 (the viewer is enabled), launch 2 at the default size (Large; the viewer is off, so no lift activation is ever scheduled).

## Finding: presses between about 0.15 and 0.25 s activated nothing

The round 2 lift recognizer began only after 0.25 s, on the assumption that the viewer's own delay is longer. Run with that value (commit `2288dee` plus the probes, presses requested 0.12, 0.15, 0.18, 0.2, 0.22 and 0.24 s; the test stops at its first failure):

| Launch | Press | Requested | Measured (down to lift) | Button action | Lift activation | Activations |
| --- | --- | --- | --- | --- | --- | --- |
| 1 | 1 | 0.12 s | 0.130 s | ran, 1 ms after the lift | not scheduled | 1 |
| 1 | 2 | 0.15 s | 0.163 s | none | not scheduled | 0 |

The viewer took the 0.163 s press over (the Button ran no action), and the recognizer had not begun, so nothing ran: `AX5: a 0.15 s press did not toggle to Pause exactly once`. An earlier probe run with the same value showed every press from 0.258 s up taken over and lift-activated. The lift recognizer now begins after 0.05 s (`LargeContentViewerLift.minimumPress`), and the committed test presses for 0.15 and 0.2 s at both sizes.

## With the recognizer beginning at 0.05 s

Commit `a339495` plus the probes; presses requested 0.1, 0.12, 0.15, 0.2, 0.35 and 3 s twice, then a 3 s press followed at once by a tap:

| Launch | Press | Requested | Measured (down to lift) | Button action | Lift activation | Activations |
| --- | --- | --- | --- | --- | --- | --- |
| 1 | 1 | 0.1 s | 0.112 s | ran, 1 ms after the lift | skipped, 186 ms after the lift | 1 |
| 1 | 2 | 0.12 s | 0.141 s | ran, 1 ms after the lift | skipped, 165 ms after the lift | 1 |
| 1 | 3 | 0.15 s | 0.161 s | none | ran, 155 ms after the lift | 1 |
| 1 | 4 | 0.2 s | 0.226 s | none | ran, 151 ms after the lift | 1 |
| 1 | 5 | 0.35 s | 0.356 s | none | ran, 152 ms after the lift | 1 |
| 1 | 6 | 3.0 s | 2.999 s | none | ran, 153 ms after the lift | 1 |
| 1 | 7 | 0.1 s | 0.122 s | ran, 0 ms after the lift | skipped, 165 ms after the lift | 1 |
| 1 | 8 | 0.12 s | 0.141 s | ran, 0 ms after the lift | skipped, 164 ms after the lift | 1 |
| 1 | 9 | 0.15 s | 0.148 s | ran, 1 ms after the lift | skipped, 165 ms after the lift | 1 |
| 1 | 10 | 0.2 s | 0.228 s | none | ran, 151 ms after the lift | 1 |
| 1 | 11 | 0.35 s | 0.354 s | none | ran, 151 ms after the lift | 1 |
| 1 | 12 | 3.0 s | 3.010 s | none | ran, 157 ms after the lift | 1 |
| 1 | 13 | 3.0 s | 3.010 s | none | ran, 157 ms after the lift | 1 |
| 1 | 14 | tap (XCUITest tap()) | 0.070 s | ran, 1 ms after the lift | skipped, 168 ms after the lift | 1 |
| 2 | 1 | 0.1 s | 0.118 s | ran, 0 ms after the lift | not scheduled | 1 |
| 2 | 2 | 0.12 s | 0.138 s | ran, 0 ms after the lift | not scheduled | 1 |
| 2 | 3 | 0.15 s | 0.149 s | ran, 1 ms after the lift | not scheduled | 1 |
| 2 | 4 | 0.2 s | 0.230 s | ran, 1 ms after the lift | not scheduled | 1 |
| 2 | 5 | 0.35 s | 0.362 s | ran, 1 ms after the lift | not scheduled | 1 |
| 2 | 6 | 3.0 s | 3.014 s | ran, 0 ms after the lift | not scheduled | 1 |
| 2 | 7 | 0.1 s | 0.131 s | ran, 0 ms after the lift | not scheduled | 1 |
| 2 | 8 | 0.12 s | 0.138 s | ran, 1 ms after the lift | not scheduled | 1 |
| 2 | 9 | 0.15 s | 0.150 s | ran, 0 ms after the lift | not scheduled | 1 |
| 2 | 10 | 0.2 s | 0.228 s | ran, 0 ms after the lift | not scheduled | 1 |
| 2 | 11 | 0.35 s | 0.356 s | ran, 0 ms after the lift | not scheduled | 1 |
| 2 | 12 | 3.0 s | 3.007 s | ran, 0 ms after the lift | not scheduled | 1 |
| 2 | 13 | 3.0 s | 3.012 s | ran, 0 ms after the lift | not scheduled | 1 |
| 2 | 14 | tap (XCUITest tap()) | 0.066 s | ran, 1 ms after the lift | not scheduled | 1 |

Every press activated exactly once. What the probe shows:

- **The viewer's delay at AX5 is about 0.15 s.** It let presses of up to 0.149 s through as taps and took over every press from 0.161 s up (also 0.258 to 3.01 s in the earlier runs). The recognizer now begins well before that.
- **Both paths, normal order.** Presses that began the recognizer and still ended as taps (0.07 to 0.149 s at AX5) got the Button's own action, and their lift activation was skipped 164 to 186 ms after the lift. Taken-over presses got the lift activation 151 to 157 ms after the lift and no Button action.
- **The Button's action follows the lift.** In all 20 presses of the table that produced a Button action, and in the 17 that did in the three earlier probe runs, the probe logged the touch lift first and the Button action 0 to 1 ms after it (at AX5 also after the lift activation was scheduled). This is the order the gate relies on to take a Button action for the latest press whose touch lifted (ADR-0013 Section 10).
- **Not produced:** a Button action arriving after the lift activation (a main thread busy for more than the 150 ms settle delay). Even at load averages near 200 the action came within 1 ms of the lift. The gate's handling of that order is proven by `ComponentLogicTests.liftActivationEitherOrder` and `liftActivationLimits`.
