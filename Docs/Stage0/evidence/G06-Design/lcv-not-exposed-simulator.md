# Large content viewer: not observable from the accessibility elements

Environment: simulator Sylvia-M0-g06-design, iPhone 17 (iPhone18,3), iOS 26.5, 7 October 2026.
Command: `xcodebuild test-without-building -scheme SylviaDesign-Package -only-testing:SylviaDesignSnapshotTests/AccessibilityTreeTests ...`
(an earlier revision of `AccessibilityTreeTests` that also expected each bar item's accessibility element to
report `showsLargeContentViewer` through `UILargeContentViewerItem`).

Result: every such expectation failed, for tab bar items, sidebar rows, navigation bar, reader chrome and the
mini-player capture control, although each applies `.accessibilityShowsLargeContentViewer`. SwiftUI does not
surface the large content viewer through the UIKit accessibility elements in the test process, so this
cannot be verified automatically here. The check is step 12 of the device checklist. Failure lines:

```
✘ Test "Sidebar rows: buttons, Thoughts selected, Inbox attention" recorded an issue at AccessibilityTreeTests.swift:65:9: Expectation failed: elements.allSatisfy { $0.showsLargeContentViewer }
✘ Test "Navigation bar and reader chrome: labelled icon buttons with the large content viewer" recorded an issue at AccessibilityTreeTests.swift:74:13: Expectation failed: item?.showsLargeContentViewer == true
✘ Test "Navigation bar and reader chrome: labelled icon buttons with the large content viewer" recorded an issue at AccessibilityTreeTests.swift:74:13: Expectation failed: item?.showsLargeContentViewer == true
✘ Test "Navigation bar and reader chrome: labelled icon buttons with the large content viewer" recorded an issue at AccessibilityTreeTests.swift:74:13: Expectation failed: item?.showsLargeContentViewer == true
✘ Test "Navigation bar and reader chrome: labelled icon buttons with the large content viewer" recorded an issue at AccessibilityTreeTests.swift:82:13: Expectation failed: item?.showsLargeContentViewer == true
✘ Test "Navigation bar and reader chrome: labelled icon buttons with the large content viewer" recorded an issue at AccessibilityTreeTests.swift:82:13: Expectation failed: item?.showsLargeContentViewer == true
✘ Test "Navigation bar and reader chrome: labelled icon buttons with the large content viewer" recorded an issue at AccessibilityTreeTests.swift:82:13: Expectation failed: item?.showsLargeContentViewer == true
✘ Test "Navigation bar and reader chrome: labelled icon buttons with the large content viewer" recorded an issue at AccessibilityTreeTests.swift:82:13: Expectation failed: item?.showsLargeContentViewer == true
✘ Test "Tab bar items: buttons with labels, one selected, Inbox attention as a value, large content viewer" recorded an issue at AccessibilityTreeTests.swift:43:9: Expectation failed: items.allSatisfy { $0.showsLargeContentViewer }
✘ Test "Tab bar items: buttons with labels, one selected, Inbox attention as a value, large content viewer" recorded an issue at AccessibilityTreeTests.swift:50:9: Expectation failed: items.map(\.largeContentTitle) == items.map { Optional($0.label) }
✘ Test "Mini-player: capture control labelled 'Capture the last 30 seconds', play/pause labelled" recorded an issue at AccessibilityTreeTests.swift:93:9: Expectation failed: capture?.showsLargeContentViewer == true
```
