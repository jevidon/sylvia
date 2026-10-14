# G0.6 design: progress

Branch `m0-g06-design`. Updated at each commit so a resuming agent can tell what is verified.

## Part 1 (SylviaDesign package core): complete

Report: `Docs/Stage0/G06-Design.md`. Decisions and final values: `Docs/ADRs/0013-design-language.md`
(Proposed). Device and human steps: `Docs/Stage0/device-checklists/G06-Design.md` (all pending).

Verified by `Scripts/ci.sh contracts design` from deleted build products (`ci-clean-run.log`):
host macOS 26.6.2 (57 token + 21 platform tests) and simulator iPhone 17 / iOS 26.5 (57 + 29),
export drift check, contract validation, fixture-reason check, Python and Swift contrast checks
(176/176), lint self-test and repository lint. No warnings in package code.

The earlier WIP commit (bbabe9d) held only a manifest and empty resource stubs; it was reviewed,
the target layout kept, and the stubs replaced by generated files.

## For part 2 (components and snapshot tests)

- Use `ColorToken.color`, `.sylviaFont(_:)`, `MarkerGlyph`, `CustomSymbol.image`, `Status.text()`,
  `ImportState.presentation(indexingContinues:)`. Never put muted text on a tint (fails contrast in
  Paper); captions inside tinted blocks use ink or the marker color.
- Complete ADR-0013 Section 9 step 2 (component grayscale snapshots) and record the procedure.
- `swift-snapshot-testing` 1.19.6 is the pinned snapshot dependency (ADR-0002).
- Extend `Scripts/ci.d/20-design.sh`; keep its checks (it fails on warnings, skips and zero tests).
- Token changes: edit `Packages/Design/Sources/SylviaDesignTokens`, then
  `swift run --package-path Packages/Design sylvia-design-export write <repo-root>`.

## Known problems

- None open in part 1. Findings that need decisions are listed in the report.
- The workflow scratchpad is shared between agents; use a private subdirectory.

## Part 2 (components and snapshot tests): complete

Report: `Docs/Stage0/G06-Design.md` (parts 1 and 2). ADR-0013 Sections 9 (grayscale method) and 10
(components). Device and human steps 12-21 added to `Docs/Stage0/device-checklists/G06-Design.md`.

Verified by `Scripts/ci.sh contracts 20-design` from deleted build products, DerivedData and package
checkouts (`ci-clean-run.log`): host 57 token + 44 platform/component-logic tests; simulator
(Sylvia-M0-g06-design, iPhone 17, iOS 26.5) 57 + 52, plus the snapshot target (374 references in
verify mode, T51/T53 proxies, accessibility tree), a negative check that changed references fail,
and the T51/T53/accessibility evidence tables. The snapshot suite also passed twice in a row in
verify mode right after recording (scratch logs). No warnings.

History: two earlier part-2 agents left unbuilt WIP (cb65d95, c64d625). The third agent built,
reviewed and tested it, fixed what was wrong (see report "Previous WIP reviewed"), re-recorded every
reference and completed the deliverables.

## For part 3 (design catalog app)

- Host the samples from `Packages/Design/Tests/SylviaDesignSnapshotTests/Gallery.swift` (move them
  into a shared place if the app needs them; keep the snapshot names stable).
- Device checklist steps 12-21 assume the catalog shows every component sample.
- `LayoutAudit` (environment `sylviaLayoutAudit`) can be installed by the catalog to show clipping.
- Re-record references only on Sylvia-M0-g06-design (iPhone 17, iOS 26.5) and review them.

## Known problems (after part 2)

- None open in parts 1-2. Decisions needed are in the report's findings and open questions.

## Part 3 (design catalog and interaction prototype): in progress

Started 2026-10-07 from c264a81 (part 2 complete). Plan, in order; each step is committed as "WIP:".

1. Package: move the component samples (`Gallery.swift`) into a library target `SylviaDesignGallery`
   so the snapshot tests and the catalog show the same samples (names unchanged); add the
   components the prototype needs (card, rule, section label, filter chips, Inbox row layout B,
   text field, status banner, action card) with gallery samples, record only the missing
   references, and add their control symbols and labels through the generator.
2. `Apps/DesignCatalog` (XcodeGen, `com.jevidon.sylvia.designcatalog`): catalog index, token,
   type, marker, symbol and component screens with switches for appearance, text size, Increase
   Contrast and Bold Text; then the interaction prototype screens.
3. XCUITest smoke tests (light, dark, AX5; screenshots to evidence), `Scripts/ci.d/21-design-catalog.sh`.
4. Report, ADR-0013 part 3 sections, device checklist, clean CI run.

Scratch files and logs: `.build/scratch/` in this worktree only. Simulators: `Sylvia-M0-g06-design`
(iPhone 17, iOS 26.5) and `Sylvia-M0-g06-design-iPad` (iPad (A16), iOS 26.5).

### Part 3 resume (fourth agent, 2026-10-07)

Re-read the WIP from 371a254, fc75445 and 40043a6 (unreviewed; treated as such). Kept the shared
`SylviaDesignGallery` target and the screen parts. Changes so far (unbuilt at this commit):

- Package: `ReadingParagraph` (highlight with underline, selection tint, margin dot, spoken
  "Highlighted"/"Saved thought here"), `PlayPauseButton`; two label keys and one control symbol
  (`thoughtsPane`); Inbox row action takes a `ControlSymbol`; gallery samples `readingParagraph`,
  `playPauseButton` (references not yet recorded: 31 samples x 17 = 527 expected). Export regenerated.
- App: Thoughts, Reader (+ iPad Thoughts pane, Look up sheet), Ask, Player, Audio capture detail,
  Storage with impact reports, Settings with prototype failure controls; lint findings fixed; launch
  argument `-SylviaPage` opens a catalog page.
- UITests: `PhonePrototypeTests` (28 screens x light/dark/AX5 with the layout audit, labels,
  1x screenshots), flow tests (attention dot, Saved only after write, failed save keeps text),
  `CatalogGalleryTests`, `PadLayoutTests` (iPad simulator only).

Next: generate and build the app, fix compile errors; record the two new samples' references;
update `20-design.sh` count (374 -> 527); write `21-design-catalog.sh`; run UI tests; docs.

### Part 3 resume (fifth agent, 2026-10-12)

The notes above stop at 8cbda19. Later WIP commits (87bb53c, 3b16128, 1e0dba5, 690801b) record:
the catalog builds; references for reading paragraph, play button and Inbox rows recorded;
`21-design-catalog.sh` written; a light pass of the iPhone screens passed once (not saved as
evidence); AX5 fixes (sidebar rows, library rows, wrapped filter chips) with re-recorded
references; ADR-0013 Section 11 and checklist steps 22-31 drafted. None of this was re-run from a
clean state. Treated as unreviewed: re-building, re-running 20-design and 21-design-catalog,
reviewing the prototype against the brief, then the report and the clean CI run.

First run of the inherited 21-design-catalog (scratch, simulator iPhone 17 / iOS 26.5): build
clean, no warnings; AX5 pass, flow tests and colors/index/text-field tests passed; light and dark
failed with "texts outside the screen" on library, reader, reader.selection and the capture sheet,
and the all-components page failed with one. Diagnosis (audit now names the failing texts):

- Phantom texts: `ViewThatFits` reports geometry for the candidates it does not show, at
  positions off screen. Fix: `LayoutAudit(countsOnlyAppearedTexts: true)` in the live catalog
  (texts between onAppear/onDisappear). Opt-in, because the snapshot renderer never runs onAppear
  (a first attempt applied it everywhere and 20-design's T51 audit then saw no texts: caught by
  its "no styled text was audited" check, reverted to opt-in).
- Real: the all-components page was 20 pt wider than the screen (screen gutter plus each
  sample's own gutter; the cover sample is 352 pt wide). Samples now render edge to edge, and the
  cover sample is two rows so it fits 375 pt (17 typographicCover references re-recorded on
  Sylvia-M0-g06-design and reviewed).
- Real, not caught by the audit: at AX5 "Middlemarch" in the Title role broke mid-word
  ("Middlemarc/h") on player and work detail. New package view `FittingText` steps Dynamic Type
  down (not below Large) until the widest word fits; used for area titles, sheet titles and the
  prototype's work titles. Unit test `ComponentLogicTests.fittingText`.
- Section name "To review" renamed to the vocabulary's "Needs review" (plan 4.4.6).
- Added: reachability check of each screen's key action (drag until hittable, second screenshot),
  an iPhone SE (3rd generation) run for the narrowest supported width.

Known problem for the report: at AX5 the mini-player covers about a third of the iPhone 17
screen (design finding, not changed).

Next: confirm run "b" (20-design and 21-design-catalog) passes; docs (report, ADR Section 11,
checklist); clean CI run from deleted build products; final commit.

### Part 3 resume (sixth agent, 2026-10-12)

Re-ran the inherited `21-design-catalog.sh` unchanged from HEAD 68a7c7f (scratch evidence dir,
simulators iPhone 17, iPhone SE (3rd generation) and iPad (A16), iOS 26.5): build clean, no
warnings, iPhone 10/10, SE 3/3, iPad 1/1 passed, 185 screenshots, every audit row 0/0. Not yet
saved as committed evidence. Review of the app found, to fix next:

- `closeReader` called `onLeave` even when the draft could not be dismissed (unsaved text lost).
- `reader.selection` screenshot does not show the selection or the menu (below the fold).
- Player speed/sleep/chapters buttons stack in three rows at the default size (board: one row).
- `capture.saved` label check "Saved " also matches the reader's "Saved thought here".
- "Audio excerpt saved" followed a sleep, not a write; the excerpt record must be written first.
- No automated test of `CaptureStore` itself (the "Saved means written" claim); add a unit target.

Then: 20-design re-run, docs (report part 3 rows, findings 11-15, placeholders), clean CI run.

Sixth agent, done since (each committed as WIP; build clean, lint 0):

- Fixed: reader leave guard; selection menu scrolled into view; player buttons (one row / two rows /
  full width); opaque status strip on area roots; excerpt record written before "Audio excerpt saved".
- `DesignCatalogTests` (8 unit tests, pass on Sylvia-M0-g06-design); mutation check saved as
  `catalog-save-ordering-mutation-simulator.log`.
- Reach check rewritten (whole frame above the mini-player, steering slow drags). It exposed a real
  defect: the mini-player inset on the NavigationStack did not reach the screens' scroll views (end
  of Thoughts hidden at AX5 on the SE). Fixed by insetting each screen (`miniplayer-inset-diagnosis-simulator.md`).
- 21-design-catalog: unit tests added, retry once only on the simulator's "Busy" launch refusal.
- Report part 3 rows, findings 11-15, other findings, open questions 9-11; ADR Section 11; checklist step 26.

Next: confirm the scratch run of 21-design-catalog (run2) passes; then `.build/scratch/clean-run.sh`
(clean `Scripts/ci.sh contracts design` into the committed evidence dir, about 1 h); fill the
report's {{CLEANRUN}} and {{REFSIZE}} placeholders from it; final commit.

Run2 of 21-design-catalog (scratch, before the selection-menu change) passed: unit 8/8, iPhone
10/10, SE 3/3, iPad 1/1, 187 screenshots, all audit rows 0/0. Selection menu fixed (one action per
row at AX5) and its 8 AX5 references re-recorded; snapshot suite passes in verify mode.
In progress: clean run `.build/scratch/clean-run.sh` (writes the committed evidence and
ci-clean-run.log). If interrupted, re-run it from the start.

## Part 3: complete (2026-10-12)

Clean run `Scripts/ci.sh contracts design` from deleted build products, DerivedData, package
checkouts and generated project passed (`ci-clean-run.log`, commit 376753f): 10-contracts,
20-design (527 references in verify mode), 21-design-catalog (8 unit, 10 + 3 + 1 UI tests,
187 screenshots). Report, ADR-0013 Section 11 and checklist steps 22-31 are final for part 3.
Every device and human step remains pending. Decisions needed: report Findings 11-15 and open
questions 9-11.

## Review round 1 fixes (2026-10-12)

All nine findings (R1-01 to R1-09) and the doable gate gaps are addressed; see the report's
"Review round 1" section. Snapshot references of `markerRows`, `captureCard-generated` and
`captureSheet-saveStates` were re-recorded on `Sylvia-M0-g06-design` (51 files) and reviewed;
the suite then passed in verify mode, and again in the clean run. New UI tests:
`AreaNavigationTests` (Command-1/2/3 on iPhone and iPad; large content viewer with host
screenshots from `lcv_helper` in 21-design-catalog.sh) and
`testSavedSheetDismissesWithTheSameDrag`. New unit tests: moment failure, failed disk write,
audio capture deep link. If interrupted before the final commit: re-run
`.build/scratch/clean-run.sh` style clean run (see the header of `ci-clean-run.log`).

Clean run after the fixes passed (`ci-clean-run.log`, commit c3f4d6d): 10-contracts, 20-design
(527 references in verify mode), 21-design-catalog (11 unit; 13 + 3 + 2 UI tests; 196 screenshots).
The first attempt failed on the new keyboard test (`ci-clean-run-attempt1-failed.log`); fixed.

## Review round 3 fixes on the integration branch (2026-10-13)

Branch `m0-int-minors-g06-design` from b354dc7. Simulators: `Sylvia-M0-minors-g06-design` (iPhone 17),
`-SE` and `-iPad` (iOS 26.5).

First attempt (WIP fd8dee8 to de06987, unreviewed): lint rules for R3-01 and a gate that took a Button
action for the latest touch down; its clean run stopped halfway and de06987 committed partial evidence.

Second agent (this state), each step committed as WIP:

- R3-01: reviewed the first attempt's rules, added the further spellings of the same classes
  (ListItemTint factories, semantic styles, `??`, `mix(with:)`, computed and conditional color
  lists, color dictionaries, `.init(.red)` shape styles, Canvas `.color(...)` shading),
  41 samples in `Styles.swift`, near-misses in `clean/`; `lint-r3-probe-host.log` (generator
  `commands/r3_lint_probe.py`) with the reviewer's probe, the samples, the documented gaps
  and a false-positive comparison over the package and spikes.
- R3-02: the gate takes a Button action for the latest press whose touch lifted (recognizer reports
  `touchesEnded`); unit tests `liftActivationEitherOrder`, `liftActivationLimits`.
- Finding 18: the viewer takes presses over after about 0.15 s; the lift recognizer began at 0.25 s,
  so 0.15-0.25 s presses did nothing. `minimumPress` is now 0.05 s; the UI test presses 0.15 and 0.2 s.
  Evidence: `large-content-viewer-timing-probe-simulator.md` (scratch instrumented build),
  `large-content-viewer-mutations-simulator.md`.
- Docs: report (Lint row, large content viewer row, Finding 18, Review round 3), ADR-0013 Sections 8,
  9, 10 and Evidence, checklist step 12.

Clean run after the round 3 fixes passed (`ci-clean-run.log`, commit d3b4bb2, started
2026-10-12T22:00:22Z): 10-contracts, 20-design (527 references in verify mode; host 59 + 51 tests,
simulator 59 + 60 + 28), 21-design-catalog (11 unit; 14 + 3 + 2 UI tests; 196 screenshots). A run
from 23dc5e1 was stopped by hand during 20-design to add lint rules. Report header, Review round 3,
Finding 18 and open question 14 are final for round 3. Device and human steps stay pending.
