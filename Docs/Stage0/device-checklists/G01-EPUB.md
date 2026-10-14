# G0.1 EPUB: physical-device and human checks

Everything here is **pending**. None of it has been run; nothing in it is inferred from the simulator results in `Docs/Stage0/G01-EPUB.md`.

- **Harness:** `Spikes/G01-EPUB` (app `EPUBHarness`, bundle id `com.jevidon.sylvia.spike.epub`, display name "Sylvia EPUB Spike"). Without launch arguments it lists every bundled fixture; tap one to open it.
- **Devices:** the iPhone 17 Pro (iPhone18,1, iOS 26.7) recorded in ADR-0001 for every step. Repeat steps 1, 6 and 11 on the iPhone 12-class baseline and an iPad once they are available (ADR-0001 open item).
- **Where to record:** create `Docs/Stage0/evidence/G01-EPUB/device/` and write one `step-NN.md` per step with: date, tester, device model and identifier, iOS version and build, harness commit (`git rev-parse HEAD`), build configuration, the result (**pass** or **fail**), what was seen, and screenshots or screen recordings (under 2 MB each; PNG or MP4). Then change the step's status in the table of `Docs/Stage0/G01-EPUB.md` from pending-device or pending-human to passed-device or failed, with the link.

## Install the harness on the device

From a clone of the branch, with the phone unlocked, paired and in Developer Mode:

```sh
source Scripts/lib/env.sh; source Scripts/lib/xcodegen.sh
sylvia_generate Spikes/G01-EPUB
xcrun devicectl list devices          # note the iPhone 17 Pro's identifier
DEVICE_ID=<identifier from the list>
# Release build of the app, for every step except 11:
xcodebuild build -project Spikes/G01-EPUB/G01EPUB.xcodeproj -scheme EPUBHarness -configuration Release \
  -destination "id=$DEVICE_ID" -derivedDataPath Spikes/G01-EPUB/.build/DerivedData-device \
  -disableAutomaticPackageResolution -allowProvisioningUpdates DEVELOPMENT_TEAM=A4KBDX665Z
xcrun devicectl device install app --device "$DEVICE_ID" \
  Spikes/G01-EPUB/.build/DerivedData-device/Build/Products/Release-iphoneos/EPUBHarness.app
```

Launch the app from the Home Screen (not from Xcode), so no debugger is attached. Step 11 needs a separate Debug build because the hosted tests use `@testable import`.

## Steps

1. **Finger selection and the selection menu.** Open `se-meditations.epub`, go forward to Book I (page 3 or 4). Long-press the word "governor" in "From my governor, to be neither of the green nor of the blue party", drag the end handle to "fights" at the end of that sentence. **Expected:** the edit menu shows Highlight, Note, Look Up and Ask (and may show system items such as Copy). Tap **Highlight**. The status line at the bottom reads "Saved"; the passage is drawn with a light ochre fill and a darker ochre underline on every line; the selection disappears. Tap **Saved** at the top: the row reads "Quote: From my governor, … gladiators' fights" with the exact text you selected, nothing cut off. Record a screenshot of the highlight and of the Saved row.

2. **Selection across an element boundary by finger.** In Book I, select from "From my mother," through "piety and beneficence" (the selection crosses the small superscript note number 3). Tap **Note**, type "test note", tap **Save**. **Expected:** the alert's message shows the selected text including the "3"; after saving, "Saved" appears and the Saved list shows "Quote: From my mother,3 piety and beneficence" and "Your note: test note". Record whether the handles could be placed on both sides of the superscript without jumping.

3. **Selection that reaches the end of a page (paginated).** In Book I, start a selection in the last line of a page and try to drag the end handle onto the next page. **Expected (to be recorded either way):** whether iOS lets the selection extend past the visible page. If it cannot, the selection stops at the page edge and the captured text equals what is shown selected (never silently shorter). Record the result as an observation; it decides whether long quotations need a "continue selection" affordance (report, finding F8).

4. **Look Up and Ask.** Select "beneficence" and tap **Look Up**. **Expected:** the system dictionary sheet appears. Select a sentence and tap **Ask**. **Expected:** an alert "Ask (not sent)" shows the selected passage; nothing is sent anywhere (the harness has no provider code).

5. **VoiceOver reaches the selection actions (plan 9.4).** Turn on VoiceOver (Settings > Accessibility > VoiceOver). Open `se-meditations.epub`, Book I. Using the rotor's Text Selection (or a double-tap-and-hold then drag), select "From my governor" and open the edit menu. **Expected:** VoiceOver can focus and activate Highlight, Note, Look Up and Ask, each announced by its title; after activating Highlight, VoiceOver announces or lets you reach "Saved" at the bottom. Record the exact gestures that worked and any action that could not be reached. If text selection with VoiceOver is not possible in the reader at all, record **fail** with what happened.

6. **VoiceOver reads saved notes.** With VoiceOver on, tap **Saved**. **Expected:** each row is announced as "Quote: <exact text>" followed by "Your note: <note>" when there is one; swiping moves through every row. Record a screen recording with VoiceOver captions or a written transcript of what was spoken.

7. **Footnote in place.** In Book I, tap the superscript "1" after "From my grandfather Verus". **Expected:** an alert titled "Note" shows "Annius Verius was his grandfather's name…"; tap Close; the page has not moved (the same lines are visible). Then tap **Back**: nothing changes (no link history). Record before/after screenshots.

8. **Rotation and relaunch.** After step 1, rotate the phone to landscape and back. **Expected:** the ochre highlight stays on exactly the same words in both orientations (it may move to another page; use the page-turn gesture to find it). Force-quit the harness from the app switcher, reopen it, open `se-meditations.epub` again and go to Book I. **Expected:** the highlight is drawn on the same words. (The harness reopens at the start of the book when launched from the fixture list; the saved locator restore is automated on the simulator only.)

9. **Reader settings by eye.** Use **A+** and **A−**, **Theme** and **Face**. **Expected:** size changes visibly in 2 pt steps between 14 and 28 pt; Theme switches between Paper (light ground, dark ink) and Night (dark ground, light ink) with the highlight fill and underline visible in both; Face cycles Literata → system serif (New York) → system sans (SF Pro) → the publisher's own font. Human judgment: Literata renders as Literata (compare with the specimen in `Docs/Design/`), with correct italics in Book I headings. Record screenshots of each face.

10. **Highlight without color (plan 4.4.8).** Settings > Accessibility > Display & Text Size > Color Filters > Grayscale on. Look at the highlight from step 1 in Paper and Night. **Expected (human judgment):** the underline still distinguishes the highlight from plain text in both themes. Record screenshots and the reviewer's name. Turn the filter off afterwards.

11. **Automated suite on the device.** Run the hosted tests on the phone (Debug build; this replaces the installed Release app, so do step 12 first):

    ```sh
    xcodebuild test -project Spikes/G01-EPUB/G01EPUB.xcodeproj -scheme EPUBHarness -configuration Debug \
      -destination "id=$DEVICE_ID" -derivedDataPath Spikes/G01-EPUB/.build/DerivedData-device-debug \
      -disableAutomaticPackageResolution -allowProvisioningUpdates DEVELOPMENT_TEAM=A4KBDX665Z \
      -only-testing:EPUBHarnessTests 2>&1 | tee device-tests.log
    ```

    **Expected:** "Executed 38 tests, with 0 failures". Copy the evidence the tests wrote inside the app with `xcrun devicectl device copy from --device "$DEVICE_ID" --domain-type appDataContainer --domain-identifier com.jevidon.sylvia.spike.epub --source Documents/evidence --destination Docs/Stage0/evidence/G01-EPUB/device/` and commit `device-tests.log` plus those files. The safety test's loopback recorder runs on the phone itself, so "loopback_request_count": 0 for the `sylvia` configuration in `safety.json` is the device result for publication scripts and remote resources. The UI tests (`EPUBHarnessUITests`) are not part of this step.

    **Sanitizer time near its caps on the phone (review R3-01).** Among the 38 tests, `SanitizerAtCapsTimingTests` sanitizes the three slowest documents the adapter still serves (just under its element and attribute caps) three times each and writes `sanitizer-at-caps-device.json` (copied with the evidence above): every run's seconds, the build configuration, the device and the phone's load average. **Expected:** every run of every document is served and under the 20 s budget (`max_seconds` < 20); the test fails otherwise. Record the nine times in `step-11.md` next to the Mac figures in the report (finding F5). Keep the phone idle and on power during the run, and note its temperature state if it felt warm. This is a Debug build, which is expected to be slower than the Release product (not measured), so a pass here should hold for Release too; if any run is over 20 s, record **fail** with the times, then measure once more and report both; a Release measurement and the product owner's decision on the caps or budget (report open question 8) follow from that, and the budget is never raised to make the test pass. Repeat this step on the iPhone 12-class baseline when it is available: that is the phone the 20 s budget must hold on.

12. **Open time on a real device (plan 19.2: p95 <= 2 s for a typical EPUB).** Use the Release build from the Home Screen (no debugger). For each of `se-meditations.epub`, `se-walden.epub`, `se-middlemarch.epub`, `pg-walden-epub2.epub` and `pg-walden-epub3.epub`, force-quit, relaunch, tap the fixture and time from the tap to the first readable page with a screen recording (count frames at 60 fps). Repeat 5 times per fixture. **Expected:** every run under 2 s. Record a table of the 25 times. Step 11's `compatibility-matrix.json` adds the in-process parse and first-location times measured on the same phone.

13. **Protected and hostile files show a clear message.** Open `g01-encrypted-chapter.epub`, `g01-lcp-like.epub`, `g01-adept-like.epub`, `g01-traversal.epub`, `g01-bomb.epub` and `g01-truncated.epub` from the list. **Expected:** each shows a "Cannot open" alert naming the reason (unsupported protection, or unsafe archive with the reason code, or truncated); the app does not crash or hang, and the list stays usable. Open `g01-font-obfuscated.epub`. **Expected:** it opens and shows two short chapters. Open `g01-csp-bypass.epub` and page through its three chapters. **Expected:** each shows its paragraph of text and nothing else happens (no alert, no navigation away). Open `g01-nesting-bypass.epub` and page to the end. **Expected:** chapter 2 shows "Before the comment." and "After the comment."; chapter 3 shows "This section cannot be shown: its markup is not XHTML that Sylvia can read safely."; the app does not crash or hang. Open `g01-form-navigation.epub` (review R2-01). In chapter 1, tap each of the four buttons below the paragraph with a finger ("Continue", "Continue to the record", "Continue to the picture", "Continue to the appendix"), waiting a few seconds after each. **Expected:** after every tap the same chapter 1 page stays on screen; no page reading "An archive entry the manifest does not declare.", "A declared XML resource outside the spine.", "A declared XHTML resource outside the spine." or "Markup declared as a PNG image." ever appears. Page to chapter 2. **Expected:** "This section cannot be shown: it contains scripts or interactive content." and no buttons. Record a screen recording of the taps. (The alert wording is harness text; product wording comes from the status vocabulary, plan 4.4.6.)
