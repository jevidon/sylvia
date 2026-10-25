# G0.2 step 1 — passed-device

Run: 2026-10-25 17:12 UTC (26 October, Pacific/Auckland).
Tester: Codex executed the tests with Justin Evidon operating the physical phone.
Build commit: `96bdc7e996f99fcd2571ea983cc32a04076a5a07`.
Device: iPhone 17 Pro (iPhone18,1), iOS 27.0.1 (24A446).
Mac: macOS 26.6.2 (25G83), Xcode 27.1 (27A9275).
Configuration: Debug; connected by cable. Developer Mode verified enabled.
User confirmed automatic OS updates off and at least 15 GB free.

All three KeychainCredentialStoreTests passed: after-first-unlock/device-only storage, not synchronizable, replacement and deletion. xcodebuild exited 0 with TEST SUCCEEDED. This result does not verify other transfer steps or complete Session 0.

Log: [01-keychain-class.log](01-keychain-class.log).

Last 20 output lines:

```text
✔ Test storesTokenAfterFirstUnlockThisDeviceOnly() passed after 0.001 seconds.
◇ Test itemIsNotSynchronizable() started.
✔ Test itemIsNotSynchronizable() passed after 0.001 seconds.
◇ Test replaceAndDelete() started.
✔ Test replaceAndDelete() passed after 0.001 seconds.
✔ Suite "Transfer credential Keychain storage (14.2)" passed after 0.004 seconds.
✔ Test run with 3 tests in 1 suite passed after 0.005 seconds.
2026-10-26 06:12:02.530 xcodebuild[13884:54060000] [MT] IDESchemeActionSDKRecord: operatingSystemBuild = <DVTBuildVersion 24A94232>, error = invalidDigitCount(94232).
2026-10-26 06:12:02.530 xcodebuild[13884:54060000] [MT] IDESchemeActionSDKRecord: operatingSystemBuild = <DVTBuildVersion 24A94232>, error = invalidDigitCount(94232).
2026-10-26 06:12:02.531 xcodebuild[13884:54060000] [MT] IDESchemeActionSDKRecord: operatingSystemBuild = <DVTBuildVersion 24A94232>, error = invalidDigitCount(94232).
2026-10-26 06:12:02.799 xcodebuild[13884:54060000] [MT] IDETestOperationsObserverDebug: 4.924 elapsed -- Testing started completed.
2026-10-26 06:12:02.799 xcodebuild[13884:54060000] [MT] IDETestOperationsObserverDebug: 0.000 sec, +0.000 sec -- start
2026-10-26 06:12:02.799 xcodebuild[13884:54060000] [MT] IDETestOperationsObserverDebug: 4.924 sec, +4.924 sec -- end

Test session results, code coverage, and logs:
	/Users/jevidon/Git/sylvia-sessions/Spikes/G02-Transfer/iOS/.build/DerivedData/Logs/Test/Test-G02TransferHarness-2026.10.26_06-11-48-+1300.xcresult

** TEST SUCCEEDED **

Testing started
```
