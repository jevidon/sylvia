"""Adds temporary os_log probes to the lift activation gate, for the timing probe of G0.6 review
round 3 (large-content-viewer-timing-probe-simulator.md). Never commit the instrumented source.

Each probe logs at notice level under subsystem com.jevidon.sylvia.probe, category lift, so the
simulator's log lists the order and time of every touch down, touch lift, Button action and lift
activation. Procedure used for the evidence (a scratch build on this task's iPhone 17 simulator):

  python3 Docs/Stage0/evidence/G06-Design/commands/lift_probe_instrument.py
  (optionally change the press durations of AreaNavigationTests.testLargeContentViewerActivatesControlsOnce)
  xcodebuild build-for-testing -project Apps/DesignCatalog/DesignCatalog.xcodeproj -scheme DesignCatalog \
      -destination "generic/platform=iOS Simulator" -derivedDataPath Apps/DesignCatalog/.build/DerivedData \
      -disableAutomaticPackageResolution
  xcodebuild test-without-building ... -destination "id=<udid>" \
      -only-testing:DesignCatalogUITests/AreaNavigationTests/testLargeContentViewerActivatesControlsOnce
  xcrun simctl spawn <udid> log show --last 10m --style compact \
      --predicate 'subsystem == "com.jevidon.sylvia.probe"' > probe.txt
  python3 Docs/Stage0/evidence/G06-Design/commands/lift_probe_table.py probe.txt "<requested durations>"
  git checkout -- Packages/Design/Sources/SylviaDesign/Components/LargeContentViewer.swift Apps/DesignCatalog/UITests

(The evidence was made with the same script under .build/scratch; this copy differs only in the
path depth.)
"""
from pathlib import Path

path = Path(__file__).resolve().parents[5] / "Packages/Design/Sources/SylviaDesign/Components/LargeContentViewer.swift"
src = path.read_text(encoding="utf-8")
probe = 'liftProbe.notice("%s")'
replacements = [
    ("import SwiftUI\n", "import SwiftUI\nimport os\nlet liftProbe = Logger(subsystem: \"com.jevidon.sylvia.probe\", category: \"lift\")\n"),
    ("    func touchBegan() {\n        press += 1\n",
     "    func touchBegan() {\n        press += 1\n        liftProbe.notice(\"probe touchBegan press=\\(self.press, privacy: .public)\")\n"),
    ("    func touchLifted() {\n        liftedPress = press\n",
     "    func touchLifted() {\n        liftedPress = press\n        liftProbe.notice(\"probe touchLifted lifted=\\(self.liftedPress, privacy: .public)\")\n"),
    ("        let owner = liftedPress\n        if let late = awaitingLateAction {\n            awaitingLateAction = nil\n            if late.press == owner, now() - late.at <= LargeContentViewerLift.lateActionWindow { return }\n        }\n",
     "        let owner = liftedPress\n        if let late = awaitingLateAction {\n            awaitingLateAction = nil\n            if late.press == owner, now() - late.at <= LargeContentViewerLift.lateActionWindow {\n                liftProbe.notice(\"probe buttonAction owner=\\(owner, privacy: .public) press=\\(self.press, privacy: .public) DROPPED\")\n                return\n            }\n        }\n        liftProbe.notice(\"probe buttonAction owner=\\(owner, privacy: .public) press=\\(self.press, privacy: .public) ran\")\n"),
    ("        guard buttonActionPress != lifted, liftPress != lifted else { return }\n",
     "        guard buttonActionPress != lifted, liftPress != lifted else {\n            liftProbe.notice(\"probe liftSettled press=\\(lifted, privacy: .public) skipped\")\n            return\n        }\n        liftProbe.notice(\"probe liftSettled press=\\(lifted, privacy: .public) ran\")\n"),
    ("        let lifted = liftedPress\n        Task { @MainActor in\n",
     "        let lifted = liftedPress\n        liftProbe.notice(\"probe liftScheduled press=\\(lifted, privacy: .public)\")\n        Task { @MainActor in\n"),
]
for old, new in replacements:
    assert src.count(old) == 1, f"not found exactly once: {old[:60]!r}"
    src = src.replace(old, new)
path.write_text(src, encoding="utf-8")
print("instrumented", path)
