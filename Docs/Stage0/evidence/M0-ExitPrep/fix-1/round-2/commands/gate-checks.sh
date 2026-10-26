#!/bin/bash
# Checks behind the fix of the second review of the M0 exit preparation (26 October 2026; integration log section 32) on
# branch m0-exit-prep: the review read the branch at 83030fba, the last commit of the fix of the first review (section
# 31), and the workflow relayed four findings, all on the thirteen M0 items' review records and their account: EV-01
# (major: the deps item's record said that ADR-0014 names none of R4-03 to R4-07, which it gives since the Zip guard's
# fix), EV-02 (the reason given for the 25 findings no later record names), EV-03 (the README's pointer to the check
# log's part for R8-04) and EV-04 (the records' commits kept only on the local m0-int-* branches). The successor of
# Docs/Stage0/evidence/M0-ExitPrep/fix-1/commands/gate-checks.sh, the same parts with these differences: part 1h reads
# the first fix's changes as it recorded them, from 609ed492 to 83030fba; the new part 1i reads this fix's, from
# 83030fba to HEAD, and 1j where the records' commits are kept; and part 4 expects the first fix's recheck to report
# exactly its group R, on the State line's clause, which now names the fix of the second review, and runs this fix's
# recheck and its reading of the findings' citations, each with its control, and two controls of the review records'
# check as this fix changed it. Run on the commit that adds this fix's other logs, with no uncommitted file:
#   Docs/Stage0/evidence/M0-ExitPrep/fix-1/round-2/commands/gate-checks.sh <log> [<extraction dir of the review records>]
# 1. What changed: (a) 5aec2518 is the CLAUDE.md correction on top of main at 96bdc7e9 (pull request #6), CLAUDE.md
#    alone, one line, unchanged since, and not on main; (b) the two branches, each made from 5aec2518, change disjoint
#    files, the zip guard's outside Docs/ exactly Scripts/check-dependency-lock.py and Scripts/ci.d/12-dependency-lock.sh,
#    the review records' nothing outside Docs/, and each merge commit's tree is the one git merge-tree computes from its
#    parents (no conflict resolved by hand); 83ed5ff3's parent is the second merge; (c) from the merges to 609ed492, the
#    assembly's own changes: nothing outside Docs/, the license inventory and its draft unchanged, the plan changed in
#    exactly three lines, each a dated note on R4-01 and R4-02, the two branches' commands, logs and records unchanged
#    but for two READMEs (the zip guard's evidence and the review records), which carry dated notes, and the gate
#    summary's checker changed in row 76's entry alone; (d) 9cdb0a02, the commit of the run of G0.5 recovery's whole
#    drop-in with the screen unlocked, an ancestor of HEAD, and since it, outside Docs/, exactly CLAUDE.md and the zip
#    guard's two scripts, none of which the drop-in builds, copies or runs (no change under Spikes/G05-Recovery,
#    Scripts/lib, Contracts or Scripts/ci.d/71-g05-recovery.sh, and none of those names the dependency check), so the
#    run stands for the drop-in's code; (e) the folders the rule for repeating a session names, changed since 4c73da57:
#    the code folders only in the lock harness, the G0.5 recovery drop-in and the zip guard's two scripts, the
#    checklists in all eight, none since 9cdb0a02; (f) the committed Xcode 27.0 logs of resolve-locks.sh and linkage.sh
#    unchanged, and the offline run under Xcode 27.1 present, unchanged since the zip guard's branch; (g) read-only, the
#    local main against the origin/main it last fetched, and m0-decisions (no fetch); (h) the first fix, from 609ed492
#    to 83030fba, its last commit, as it recorded itself: the guard's commit ad709059, whose parent is 609ed492, changes
#    exactly Scripts/check-dependency-lock.py; outside Docs/ exactly that file; the license inventory and its draft, the
#    plan, the amendments, CLAUDE.md and README.md unchanged; the assembly's, the zip guard's and the review records'
#    evidence unchanged but for two READMEs' dated notes; the gate summary's checker changed in row 76's entry alone;
#    and every new file in its own evidence folder; (i) this fix, from 83030fba to HEAD: nothing outside Docs/; the
#    license inventory and its draft, the plan, the amendments, CLAUDE.md, README.md, the device checklists, the gate
#    summary's checker, Scripts/, the zip guard's and the dependency lock's evidence, the first fix's commands and logs,
#    the assembly's commands and logs, the hand-over's checks' logs and the extracted records unchanged; in the
#    hand-over's folder exactly its README, deps.md and item-reviews.py; three evidence READMEs (the first fix's, the
#    assembly's and the hand-over's checks') each its text at 83030fba once its dated notes of 26 October 2026 naming
#    83030fba are taken out; and every new file in this fix's evidence folder; (j) read-only, where the 28 commits the
#    review records cite are kept (branch-reach.py beside this file, as in run-checks.sh: each on its item's m0-int-*
#    branch and on no other ref).
# 2. The Git LFS state of the tree and of the repository configuration (read-only), and the LFS files of HEAD against
#    those of 4c73da57: none added.
# 3. M0-gate.md: every cited path exists and every Section 2 status agrees with the records it cites
#    (Docs/Stage0/evidence/M0-Integration/commands/gate-refresh-check.py, row 76 passed-host, which reads ADR-0014's
#    status on it and the first fix's log of 12-dependency-lock); then, on copies with three planted wrong statuses, that
#    the checker reports exactly the rows resting on them (22, 42, 66, 71, 78, 92); the copies hold the logs that row 76
#    reads.
# 4. The documents' own consistency checks: the follow-up's fix's amendments checker (0 failures; its mutations and
#    controls run in its runner, whose log is check-amendments.log beside this folder); the assembly's runbook content
#    check and the step coverage; the runbook's correction-text check on 4c73da57, 5aec2518 and HEAD (from 4c73da57
#    exactly the nine texts of the corrections the decisions round applied, from 5aec2518 nothing); the earlier rounds'
#    rechecks, each as it reported on the first fix: the follow-up's fix's recheck exactly FID4-02, FID4-04 and
#    FID4-06, the second fix's exactly HON4-06, the third fix's exactly OWN4-01 and OWN4-07, the fix of the run's
#    record's recheck exactly UNL-02 and the review status on the same texts, the State line's word count aside; the
#    others as before, with their controls; the review records' own checks (item-reviews.py check and render --check,
#    audit-probe.sh), and two controls of the check as this fix changed it, each on a copy of the tree (git archive of
#    HEAD under .build/scratch, the check's git calls reading this repository): with the three facts its part 7 now
#    checks planted false (ADR-0014's R4-03 to R4-07 renamed, R8-04's command and G0.5 recovery's g05-tests/ root
#    changed), it must report exactly those three; and with one item's branch name made absent in the copy's script, it
#    must report only that item's problems and end with its result line, no error; the assembly's two:
#    recheck-exit-prep.py on HEAD, which must report exactly its group R6, on exactly the State line's clause the first
#    fix reworded, and as its control on the tree of 6ce2c119, where every group must be reported, and
#    check-xcode-reading.py on HEAD, and as its control on the tree of 6ce2c119, where exactly its part 4 must fail; the
#    first fix's recheck-fix-1.py on HEAD, which must report exactly its group R, on exactly the State line's clause
#    this fix rewords, and as its control on the tree of 609ed492, where every group must be reported; and this fix's
#    recheck-ev.py on HEAD, and as its control on the tree of 83030fba, where every group must be reported, and its
#    finding-lines.py at 83030fba, and as its control at HEAD, where the texts this fix dates or corrects must fail.
# 5. The drop-ins that read documents: Scripts/ci.sh contracts dependency-lock hard-rules (00-git-lfs runs first).
# 6. A read-only count of the leftover g05-* directories in the user's temporary folder, names only, one level deep,
#    g05-tests among them (G0.5 AI review R7-04, R8-04), as the earlier rounds' part 6.
# No simulator is created or used, nothing plays audio, nothing is fetched or pushed, no ref is written, and nothing is
# written outside .build/ and the log. Exit status 1 if any part fails.
set -u
root="$(cd "$(dirname "$0")/../../../../../../.." && pwd)"  # seven folders up: commands, round-2, fix-1, M0-ExitPrep, evidence, Stage0, Docs
log="$1"
extraction="${2:-}"
cd "$root" || exit 1
source Scripts/lib/env.sh
status=0
commands="Docs/Stage0/evidence/M0-Integration/commands"
evidence="Docs/Stage0/evidence/M0-Integration"
decisions="Docs/Stage0/evidence/M0-Decisions"
record="$decisions/unlocked-record"
fix="$record/round-2"
second="$record/round-3"
here="Docs/Stage0/evidence/M0-ExitPrep/assembly"
fixev="Docs/Stage0/evidence/M0-ExitPrep/fix-1"
ev2="Docs/Stage0/evidence/M0-ExitPrep/fix-1/round-2"
zipev="Docs/Stage0/evidence/M0-ExitPrep/zipguard"
revev="Docs/Stage0/evidence/M0-ExitPrep/reviews"
items="Docs/Stage0/evidence/M0-Integration/item-reviews"
base=4c73da5754f5cbddabde88e11d222a231a29f8ca      # main after pull request #5
run=9cdb0a02f43fd058cb6221aa2bdf2b2e4e0fa28e       # the run of G0.5 recovery's whole drop-in with the screen unlocked
fixstart=26530d4933c070c2c154a9116ef6f7fdd0415363  # the fix of the run's record, where its second fix starts
pr6=96bdc7e996f99fcd2571ea983cc32a04076a5a07       # pull request #6, main
correction=5aec2518c90427a283d9c8195e11bb9ab23e5d12
zip=84deea0c4871a1923f77970eaca4f3bf6553c09b
rev=2c5b2fcc6b406e21e3ec40708acdf2d9b8a636dd
merge1=7e2cd62eda61a573fe6eeea7a164a8200e215093
merge2=6ce2c1196aa436b7f456b7c019dc6bc1a3e0d603
wip=83ed5ff355e52fc56fb489bd31d166972e95d525
asm=609ed49250da6a44984359bddc8219cdc6ad7c13       # the assembly's last commit, which the first review read
guardfix=ad7090591f559cf3ce2e79f1768a49768aa4584e  # the first fix's change to the guard
fix1end=83030fba191735fa237c2cec014e590ee73a645c   # the first fix's last commit, which the second review read
guard_scripts="$(printf '%s\n' Scripts/check-dependency-lock.py Scripts/ci.d/12-dependency-lock.sh)"
s=.build/scratch/fix-1-round-2-gate
mkdir -p .build/scratch
rm -rf "$s"; mkdir -p "$s"
uncommitted="$(git status --porcelain | wc -l | tr -d ' ')"
{
  echo "commit: $(git rev-parse HEAD) ($(git rev-parse --abbrev-ref HEAD)); uncommitted files before this run: $uncommitted"
  echo "host: macOS $(sw_vers -productVersion) ($(sw_vers -buildVersion)); $(xcodebuild -version | tr '\n' ' ')"
  echo "start: $(date -u +%Y-%m-%dT%H:%M:%SZ); load: $(uptime)"
  echo "extraction dir of the review records: ${extraction:-(none given: item-reviews.py check runs without --extraction)}"
  echo
  echo "== 1. What changed"
} > "$log" 2>&1
yn() { if "$@"; then echo yes; else echo NO; fi; }

# 1a. The CLAUDE.md correction.
c_parent="$(git rev-parse "$correction^")"
c_files="$(git diff --name-only "$pr6" "$correction")"
c_numstat="$(git diff --numstat "$pr6" "$correction" | tr '\t' ' ')"
claude_since="$(git diff --name-only "$correction" HEAD -- CLAUDE.md)"
para="$(grep -E '^Current milestone:' CLAUDE.md)"
c_ok=1
[[ "$c_parent" == "$pr6" && "$c_files" == "CLAUDE.md" && "$c_numstat" == "1 1 CLAUDE.md" && -z "$claude_since" ]] || c_ok=0
[[ "$para" == *'All M0 work is on `main`.'* && "$para" == *'Never build on `m0-integrate` or `m0-decisions`'* && "$para" != *'are combined on `m0-integrate`'* ]] || c_ok=0
git merge-base --is-ancestor "$correction" HEAD || c_ok=0
on_main=no; git merge-base --is-ancestor "$correction" main && on_main=yes
[[ "$(git rev-parse main)" == "$pr6" && "$on_main" == no ]] || c_ok=0
{
  echo "-- 1a. the CLAUDE.md correction ${correction:0:8}: its parent ${c_parent:0:8} (pull request #6, ${pr6:0:8}): $( [[ "$c_parent" == "$pr6" ]] && echo yes || echo NO); files: $(printf '%s' "$c_files" | tr '\n' ' '); numstat: $c_numstat; CLAUDE.md since it: $( [[ -z "$claude_since" ]] && echo unchanged || echo "PROBLEM, changed")"
  echo "   the milestone paragraph names main as the home of the M0 work: $( [[ "$para" == *'All M0 work is on `main`.'* ]] && echo yes || echo NO); says never to build on m0-integrate or m0-decisions: $( [[ "$para" == *'Never build on `m0-integrate` or `m0-decisions`'* ]] && echo yes || echo NO); no longer says the work is combined on m0-integrate: $( [[ "$para" != *'are combined on `m0-integrate`'* ]] && echo yes || echo NO)"
  echo "   ${correction:0:8} is an ancestor of HEAD: $(yn git merge-base --is-ancestor "$correction" HEAD); the local main is $(git rev-parse main) and holds it: $on_main (the records say the correction is not yet on main)"
  if (( c_ok )); then echo "   as the records state it"; else echo "   PROBLEM: not as the records state it"; fi
} >> "$log"
(( c_ok )) || status=1

# 1b. The two branches and their merges.
git diff --name-only "$correction" "$zip" | sort > "$s/zip-files.txt"
git diff --name-only "$correction" "$rev" | sort > "$s/rev-files.txt"
overlap="$(comm -12 "$s/zip-files.txt" "$s/rev-files.txt")"
zip_out="$(grep -v '^Docs/' "$s/zip-files.txt" || true)"
rev_out="$(grep -v '^Docs/' "$s/rev-files.txt" || true)"
p1="$(git rev-list --parents -n 1 "$merge1" | cut -d' ' -f2-)"
p2="$(git rev-list --parents -n 1 "$merge2" | cut -d' ' -f2-)"
t1="$(git merge-tree --write-tree "$correction" "$zip" 2>/dev/null | head -n 1)"
t2="$(git merge-tree --write-tree "$merge1" "$rev" 2>/dev/null | head -n 1)"
b_ok=1
[[ "$(git merge-base "$correction" "$zip")" == "$correction" && "$(git merge-base "$correction" "$rev")" == "$correction" ]] || b_ok=0
[[ -z "$overlap" && "$zip_out" == "$guard_scripts" && -z "$rev_out" ]] || b_ok=0
[[ "$p1" == "$correction $zip" && "$p2" == "$merge1 $rev" ]] || b_ok=0
[[ "$t1" == "$(git rev-parse "$merge1^{tree}")" && "$t2" == "$(git rev-parse "$merge2^{tree}")" ]] || b_ok=0
[[ "$(git rev-parse "$wip^")" == "$merge2" ]] || b_ok=0
git merge-base --is-ancestor "$wip" HEAD || b_ok=0
{
  echo "-- 1b. the branches: m0-exit-zipguard is $(git rev-parse --verify --quiet m0-exit-zipguard || echo '(no such ref)') (merged: ${zip:0:8}), m0-exit-reviews is $(git rev-parse --verify --quiet m0-exit-reviews || echo '(no such ref)') (merged: ${rev:0:8}); each made from ${correction:0:8}: $( [[ "$(git merge-base "$correction" "$zip")" == "$correction" && "$(git merge-base "$correction" "$rev")" == "$correction" ]] && echo yes || echo NO)"
  echo "   files changed since ${correction:0:8}: the zip guard's $(grep -c . "$s/zip-files.txt"), the review records' $(grep -c . "$s/rev-files.txt"), in both: $( [[ -z "$overlap" ]] && echo none || echo "PROBLEM: $overlap")"
  echo "   outside Docs/: the zip guard's: $(printf '%s' "$zip_out" | tr '\n' ' ') $( [[ "$zip_out" == "$guard_scripts" ]] && echo '(exactly its two scripts)' || echo '(PROBLEM: not exactly its two scripts)'); the review records': $( [[ -z "$rev_out" ]] && echo none || echo "PROBLEM: $rev_out")"
  echo "   ${merge1:0:8}'s parents: $(echo "$p1" | sed -E 's/([0-9a-f]{8})[0-9a-f]*/\1/g'); its tree is git merge-tree's of them: $( [[ "$t1" == "$(git rev-parse "$merge1^{tree}")" ]] && echo yes || echo NO)"
  echo "   ${merge2:0:8}'s parents: $(echo "$p2" | sed -E 's/([0-9a-f]{8})[0-9a-f]*/\1/g'); its tree is git merge-tree's of them: $( [[ "$t2" == "$(git rev-parse "$merge2^{tree}")" ]] && echo yes || echo NO)"
  echo "   ${wip:0:8} (the first agent's uncommitted changes, committed by the orchestrating session) has the parent ${merge2:0:8}: $( [[ "$(git rev-parse "$wip^")" == "$merge2" ]] && echo yes || echo NO); HEAD descends from it: $(yn git merge-base --is-ancestor "$wip" HEAD)"
  if (( b_ok )); then echo "   merged with no conflict, the branches' files disjoint"; else echo "   PROBLEM: not as the records state it"; fi
} >> "$log"
(( b_ok )) || status=1

# 1c. The assembly's own changes since the merges, as at its last commit, which the first review read (the first fix's:
# 1h; this fix's: 1i).
changed="$(git diff --name-only "$merge2" "$asm")"
stray="$(printf '%s\n' "$changed" | grep -v -E '^Docs/' | grep . || true)"
licenses="$(git diff --name-only "$merge2" "$asm" -- Docs/Licenses/inventory.json Docs/Licenses/acknowledgements-draft.md)"
plan_stat="$(git diff --numstat "$merge2" "$asm" -- Docs/Sylvia_v1_iOS_Implementation_Plan.md | cut -f1,2 | tr '\t' ' ')"
plan_added="$(git diff -U0 "$merge2" "$asm" -- Docs/Sylvia_v1_iOS_Implementation_Plan.md | grep -E '^\+[^+]' || true)"
plan_noted="$(printf '%s\n' "$plan_added" | grep -c -F "*(24 October 2026: closed by an agent's change, reviewed next: ADR-0014 status.)*")"
branch_ev="$(git diff --name-only "$merge2" "$asm" -- "$zipev" "$revev" "$items" Docs/Stage0/evidence/M0-dependencies/xcode-27.1 Scripts/check-dependency-lock.py Scripts/ci.d/12-dependency-lock.sh)"
branch_ev_other="$(printf '%s\n' "$branch_ev" | grep -v -E "^($zipev|$items)/README\.md$" | grep . || true)"
checker_diff="$(git diff -U0 "$merge2" "$asm" -- "$commands/gate-refresh-check.py" | grep -E '^[-+][^-+]' || true)"
checker_other="$(printf '%s\n' "$checker_diff" | grep -v -E '^[-+] *(#|76: \("|\+ file_has\("Docs/Stage0/evidence/M0-ExitPrep/zipguard/ci-2/12-dependency-lock\.log",|"dependency lock check: 0 failure\(s\)"\)|"self-test: 278 mutations"\)\),)' | grep . || true)"
cc_ok=1
[[ -z "$stray" && -z "$licenses" && "$plan_stat" == "3 3" && "$plan_noted" == 3 && -z "$branch_ev_other" && -z "$checker_other" ]] || cc_ok=0
{
  echo "-- 1c. from ${merge2:0:8}, the second merge, to ${asm:0:8}, the assembly's last commit: $(printf '%s\n' "$changed" | grep -c .) files, $(printf '%s\n' "$changed" | grep -c '^Docs/') of them under Docs/; $(printf '%s\n' "$changed" | grep -c "^$here/") in the assembly's evidence"
  echo "   the documents changed, outside the assembly's evidence:"
  printf '%s\n' "$changed" | grep -v "^$here/" | sed 's/^/   /'
  echo "   outside Docs/: $( [[ -z "$stray" ]] && echo "nothing (README.md and CLAUDE.md included)" || echo "PROBLEM: $stray")"
  echo "   the license inventory and its acknowledgements draft: $( [[ -z "$licenses" ]] && echo unchanged || echo "PROBLEM, changed: $licenses")"
  echo "   the plan: lines added and removed $plan_stat (3 3 expected), the added lines each holding the dated note on R4-01 and R4-02: $plan_noted of 3"
  echo "   the two branches' evidence, records and scripts from the merge to ${asm:0:8} (zipguard/, reviews/, item-reviews/, xcode-27.1/, the guard's two scripts): $(printf '%s' "$branch_ev" | tr '\n' ' ') $( [[ -z "$branch_ev_other" ]] && echo '(only the zip guard evidence README and the review records README, which carry dated notes)' || echo "(PROBLEM, also: $branch_ev_other)")"
  echo "   the gate summary's checker ($commands/gate-refresh-check.py): $( [[ -z "$checker_other" ]] && echo "changed in row 76's entry and its comment alone" || echo "PROBLEM, also: $checker_other")"
  if (( cc_ok )); then echo "   as the assembly's records state it"; fi
} >> "$log"
(( cc_ok )) || status=1

# 1h, 1i and 1j come after 1g: the first fix's changes from 609ed492 to 83030fba, this fix's since 83030fba, and where
# the review records' commits are kept.

# 1d. The run of G0.5 recovery's whole drop-in on 9cdb0a02, against what changed since.
ancestor=no; git merge-base --is-ancestor "$run" HEAD && ancestor=yes
outside_since_run="$(git diff --name-only "$run" HEAD -- . ':(exclude)Docs')"
code_since_run="$(git diff --name-only "$run" HEAD -- Spikes Scripts Contracts Fixtures Apps Packages .github)"
dropin_since_run="$(git diff --name-only "$run" HEAD -- Spikes/G05-Recovery Scripts/lib Contracts Scripts/ci.d/71-g05-recovery.sh Scripts/ci.sh)"
dropin_names="$(git grep -l -E 'check-dependency-lock|12-dependency-lock' -- Spikes/G05-Recovery Scripts/lib Contracts Scripts/ci.d/71-g05-recovery.sh || true)"
d_ok=1
[[ "$ancestor" == yes && "$outside_since_run" == "$(printf '%s\n' CLAUDE.md Scripts/check-dependency-lock.py Scripts/ci.d/12-dependency-lock.sh)" && "$code_since_run" == "$guard_scripts" && -z "$dropin_since_run" && -z "$dropin_names" ]] || d_ok=0
{
  echo "-- 1d. ${run:0:8}, the commit the whole G0.5 recovery drop-in ran on with the screen unlocked, is an ancestor of HEAD: $ancestor"
  echo "   changed since it outside Docs/: $(printf '%s' "$outside_since_run" | tr '\n' ' ') (CLAUDE.md and the zip guard's two scripts expected)"
  echo "   of them code, scripts, contracts, fixtures or the workflow: $(printf '%s' "$code_since_run" | tr '\n' ' ')"
  echo "   what the drop-in builds, copies or runs (Spikes/G05-Recovery, Scripts/lib, Contracts, Scripts/ci.d/71-g05-recovery.sh, Scripts/ci.sh) changed since it: $( [[ -z "$dropin_since_run" ]] && echo none || echo "PROBLEM: $dropin_since_run")"
  echo "   files there that name the dependency check: $( [[ -z "$dropin_names" ]] && echo "none, so the drop-in does not run the zip guard's scripts" || echo "PROBLEM: $dropin_names")"
  if (( d_ok )); then echo "   so the run stands for the drop-in's code, as the records state it (runbook 0.8 needs nothing from the owner)"; else echo "   PROBLEM: not as the records state it"; fi
} >> "$log"
(( d_ok )) || status=1

# 1e. The folders the rule for repeating a session names, since pull request #5.
rule_code="$(git diff --name-only "$base" HEAD -- Apps Packages Spikes Fixtures Scripts Contracts)"
rule_other="$(printf '%s\n' "$rule_code" | grep -v -E '^Spikes/G05-Recovery/LockHarness/|^Scripts/ci\.d/71-g05-recovery\.sh$|^Scripts/check-dependency-lock\.py$|^Scripts/ci\.d/12-dependency-lock\.sh$' | grep . || true)"
lists_changed="$(git diff --name-only "$base" HEAD -- Docs/Stage0/device-checklists)"
lists_all="$(git ls-files Docs/Stage0/device-checklists | grep -E '\.md$')"
lists_since_run="$(git diff --name-only "$run" HEAD -- Docs/Stage0/device-checklists)"
{
  echo "-- 1e. the folders the rule for repeating a session names (Apps Packages Spikes Fixtures Scripts Contracts Docs/Stage0/device-checklists), changed since ${base:0:8} (pull request #5)"
  echo "   the code folders: $(printf '%s\n' "$rule_code" | grep -c .) files"
  printf '%s\n' "$rule_code" | sed -E 's#^(Spikes/G05-Recovery/LockHarness)/.*#\1/...#' | sort | uniq -c | sed 's/^/   /'
  if [[ -z "$rule_other" ]]; then echo "   only the lock harness, the G0.5 recovery drop-in and the zip guard's two scripts, as M0-gate.md item 2 and its dated note say"; else echo "   PROBLEM: also $rule_other"; fi
  echo "   Docs/Stage0/device-checklists: $(printf '%s\n' "$lists_changed" | grep -c .) of the $(printf '%s\n' "$lists_all" | grep -c .) checklists changed; since ${run:0:8}: $( [[ -z "$lists_since_run" ]] && echo none || echo "PROBLEM: $lists_since_run")"
  if [[ "$lists_changed" == "$lists_all" ]]; then echo "   all eight, as M0-gate.md item 2 says"; else echo "   PROBLEM: not every checklist, as item 2 says"; fi
} >> "$log"
[[ -n "$rule_other" || "$lists_changed" != "$lists_all" || -n "$lists_since_run" ]] && status=1

# 1f. resolve-locks.sh and linkage.sh: the Xcode 27.0 logs and the offline run under Xcode 27.1.
dep_logs="$(git diff --name-only "$base" HEAD -- Docs/Stage0/evidence/M0-dependencies/linkage.log Docs/Stage0/evidence/M0-dependencies/resolve-locks.log)"
x271=Docs/Stage0/evidence/M0-dependencies/xcode-27.1
x271_line="$(grep -m 1 -o -E 'Xcode [0-9.]+ Build version [0-9A-Za-z]+' "$x271/run-2/linkage.log" 2>/dev/null)"
x271_since="$(git diff --name-only "$zip" HEAD -- "$x271")"
f_ok=1
[[ -z "$dep_logs" && -e "$x271/README.md" && "$x271_line" == "Xcode 27.1 Build version 27A9275" && -z "$x271_since" ]] || f_ok=0
{
  echo "-- 1f. the committed logs of resolve-locks.sh and linkage.sh since ${base:0:8}: $( [[ -z "$dep_logs" ]] && echo unchanged || echo "PROBLEM, changed: $dep_logs"); linkage.log's Xcode line: $(grep -m 1 -o -E 'Xcode [0-9.]+ Build version [0-9A-Za-z]+' Docs/Stage0/evidence/M0-dependencies/linkage.log)"
  echo "   the run under Xcode 27.1 ($x271/): $( [[ -e "$x271/README.md" ]] && echo present || echo "PROBLEM, absent"); run-2/linkage.log's Xcode line: ${x271_line:-none}; changed since ${zip:0:8}: $( [[ -z "$x271_since" ]] && echo no || echo "PROBLEM: $x271_since")"
  if (( f_ok )); then echo "   as the records state it: made offline, by an agent, recorded (ADR-0014 section 4)"; fi
} >> "$log"
(( f_ok )) || status=1

# 1g. Remote-tracking refs, read-only.
{
  echo "-- 1g. the repository's refs, read-only (nothing is fetched):"
  echo "   main: $(git rev-parse main); origin/main: $(git rev-parse origin/main); commits on origin/main that main lacks: $(git rev-list --count main..origin/main); on main that origin/main lacks: $(git rev-list --count origin/main..main)"
  echo "   m0-decisions: $(git rev-parse m0-decisions); origin/m0-decisions: $(git rev-parse origin/m0-decisions); its tree is main's: $( [[ "$(git rev-parse 'm0-decisions^{tree}')" == "$(git rev-parse 'main^{tree}')" ]] && echo yes || echo no)"
  echo "   Spikes/G05-Recovery/LockHarness/project.yml at main: $(git cat-file -e main:Spikes/G05-Recovery/LockHarness/project.yml 2>/dev/null && echo present || echo absent); at HEAD: $(git cat-file -e HEAD:Spikes/G05-Recovery/LockHarness/project.yml 2>/dev/null && echo present || echo absent)"
} >> "$log"

# 1h. The first fix, from the assembly's last commit, which the first review read, to its own last commit, 83030fba,
# which the second review read: as the first fix's own gate checks read it from 609ed492 to their HEAD.
fix_changed="$(git diff --name-only "$asm" "$fix1end")"
fix_outside="$(printf '%s\n' "$fix_changed" | grep -v -E '^Docs/' | grep . || true)"
guard_parent="$(git rev-parse "$guardfix^")"
guard_files="$(git diff --name-only "$asm" "$guardfix")"
fix_kept="$(git diff --name-only "$asm" "$fix1end" -- Docs/Licenses Docs/Sylvia_v1_iOS_Implementation_Plan.md Docs/Stage0/M0-plan-amendments.md CLAUDE.md README.md Scripts/ci.d Scripts/lib "$here" "$zipev" "$revev" "$items" Docs/Stage0/evidence/M0-dependencies | grep -v -x -F -e "$here/README.md" -e "$zipev/README.md" || true)"
fix_readmes="$(git diff --name-only "$asm" "$fix1end" -- "$here/README.md" "$zipev/README.md")"
# Each README at 83030fba, with its dated notes of 26 October 2026 that name 609ed492 removed, must be its text at
# 609ed492.
fix_readme_other=""
for f in "$here/README.md" "$zipev/README.md"; do
  git show "$asm:$f" > "$s/readme-before.md"
  git show "$fix1end:$f" > "$s/readme-at-end.md"
  sed -E 's/ \*\(Dated note, 26 October 2026: [^*]*`609ed492`[^*]*\)\*//g' "$s/readme-at-end.md" > "$s/readme-after.md"
  cmp -s "$s/readme-before.md" "$s/readme-after.md" || fix_readme_other="$fix_readme_other $f"
  grep -q -F '*(Dated note, 26 October 2026: ' "$s/readme-at-end.md" || fix_readme_other="$fix_readme_other $f(no note)"
done
fix_added="$(git diff --name-only --diff-filter=A "$asm" "$fix1end")"
fix_added_other="$(printf '%s\n' "$fix_added" | grep -v -E "^$fixev/" | grep . || true)"
fix_checker="$(git diff -U0 "$asm" "$fix1end" -- "$commands/gate-refresh-check.py" | grep -E '^[-+][^-+]' || true)"
fix_checker_other="$(printf '%s\n' "$fix_checker" | grep -v -E '^\+ *(#.*|\+ adr_says\(14, "a local package inside the product roots must be one git tracks there"\)|\+ file_has\("Docs/Stage0/evidence/M0-ExitPrep/fix-1/12-dependency-lock\.log",|"dependency lock check: 0 failure\(s\)"\)|"self-test: 283 mutations"\))$' | grep . || true)"
h_ok=1
git merge-base --is-ancestor "$asm" "$fix1end" || h_ok=0
git merge-base --is-ancestor "$guardfix" "$fix1end" || h_ok=0
git merge-base --is-ancestor "$fix1end" HEAD || h_ok=0
[[ "$guard_parent" == "$asm" && "$guard_files" == "Scripts/check-dependency-lock.py" ]] || h_ok=0
[[ "$fix_outside" == "Scripts/check-dependency-lock.py" && -z "$fix_kept" && -z "$fix_added_other" && -n "$fix_checker" && -z "$fix_checker_other" && -z "$fix_readme_other" ]] || h_ok=0
{
  echo "-- 1h. the first fix, from ${asm:0:8} (the assembly's last commit, which the first review read) to ${fix1end:0:8} (its last commit, which the second review read; an ancestor of HEAD: $(yn git merge-base --is-ancestor "$fix1end" HEAD)): $(printf '%s\n' "$fix_changed" | grep -c .) files, $(printf '%s\n' "$fix_added" | grep -c .) of them new"
  echo "   ${guardfix:0:8}, the guard's change, an ancestor of ${fix1end:0:8}: $(yn git merge-base --is-ancestor "$guardfix" "$fix1end"); its parent ${guard_parent:0:8} ($( [[ "$guard_parent" == "$asm" ]] && echo "the assembly's last commit, as stated" || echo PROBLEM)); it changes: $(printf '%s' "$guard_files" | tr '\n' ' ')"
  echo "   the files changed, outside the first fix's evidence:"
  printf '%s\n' "$fix_changed" | grep -v "^$fixev/" | sed 's/^/   /'
  echo "   outside Docs/: $(printf '%s' "$fix_outside" | tr '\n' ' ') $( [[ "$fix_outside" == "Scripts/check-dependency-lock.py" ]] && echo '(exactly the guard)' || echo '(PROBLEM: not exactly the guard)')"
  echo "   unchanged from ${asm:0:8} to ${fix1end:0:8} (the license inventory, its texts and draft; the plan; the amendments; CLAUDE.md; README.md; the drop-ins and Scripts/lib; the assembly's, the zip guard's, the review records' and the dependency lock's evidence, but for two READMEs): $( [[ -z "$fix_kept" ]] && echo yes || echo "PROBLEM, changed: $fix_kept")"
  echo "   the two READMEs, the assembly's and the zip guard's: $(printf '%s' "$fix_readmes" | tr '\n' ' ') $( [[ -z "$fix_readme_other" ]] && echo '(each, at 83030fba, its text at 609ed492 once its dated note of 26 October 2026, which names 609ed492, is taken out)' || echo "(PROBLEM:$fix_readme_other)")"
  echo "   new files outside $fixev/: $( [[ -z "$fix_added_other" ]] && echo none || echo "PROBLEM: $fix_added_other")"
  echo "   the gate summary's checker ($commands/gate-refresh-check.py): $( [[ -n "$fix_checker" && -z "$fix_checker_other" ]] && echo "changed in row 76's entry alone, every line added: its comment, ADR-0014's status on the first fix and its log of 12-dependency-lock" || echo "PROBLEM: ${fix_checker_other:-not changed}")"
  if (( h_ok )); then echo "   as the first fix's records state it"; else echo "   PROBLEM: not as the first fix's records state it"; fi
} >> "$log"
(( h_ok )) || status=1

# 1i. This fix, from 83030fba, the first fix's last commit, which the second review read, to HEAD.
i_changed="$(git diff --name-only "$fix1end" HEAD)"
i_outside="$(printf '%s\n' "$i_changed" | grep -v -E '^Docs/' | grep . || true)"
i_kept="$(git diff --name-only "$fix1end" HEAD -- Docs/Licenses Docs/Sylvia_v1_iOS_Implementation_Plan.md Docs/Stage0/M0-plan-amendments.md CLAUDE.md README.md Scripts Docs/Stage0/device-checklists "$commands/gate-refresh-check.py" "$zipev" Docs/Stage0/evidence/M0-dependencies "$items/extracted" "$fixev" "$here" "$revev" | grep -v -x -F -e "$fixev/README.md" -e "$here/README.md" -e "$revev/README.md" | grep -v -E "^$ev2/" || true)"
i_items="$(git diff --name-only "$fix1end" HEAD -- "$items" | sort | tr '\n' ' ' | sed 's/ $//')"
i_items_expected="$(printf '%s\n' "$items/README.md" "$items/commands/item-reviews.py" "$items/deps.md" | sort | tr '\n' ' ' | sed 's/ $//')"
# Each of the three READMEs, with its dated notes of 26 October 2026 that name 83030fba removed, must be its text at
# 83030fba.
i_readme_other=""
for f in "$fixev/README.md" "$here/README.md" "$revev/README.md"; do
  git show "$fix1end:$f" > "$s/readme-before.md"
  sed -E 's/ \*\(Dated note, 26 October 2026: [^*]*`83030fba`[^*]*\)\*//g' "$f" > "$s/readme-after.md"
  cmp -s "$s/readme-before.md" "$s/readme-after.md" || i_readme_other="$i_readme_other $f"
  grep -q -F '`83030fba`' "$f" || i_readme_other="$i_readme_other $f(no note)"
done
i_added="$(git diff --name-only --diff-filter=A "$fix1end" HEAD)"
i_added_other="$(printf '%s\n' "$i_added" | grep -v -E "^$ev2/" | grep . || true)"
i_deleted="$(git diff --name-only --diff-filter=D "$fix1end" HEAD)"
i_ok=1
git merge-base --is-ancestor "$fix1end" HEAD || i_ok=0
[[ -z "$i_outside" && -z "$i_kept" && "$i_items" == "$i_items_expected" && -z "$i_readme_other" && -z "$i_added_other" && -z "$i_deleted" ]] || i_ok=0
{
  echo "-- 1i. this fix, from ${fix1end:0:8} (the first fix's last commit, which the second review read) to HEAD: $(printf '%s\n' "$i_changed" | grep -c .) files, $(printf '%s\n' "$i_added" | grep -c .) of them new, $(printf '%s\n' "$i_deleted" | grep -c .) deleted"
  echo "   the files changed, outside this fix's evidence:"
  printf '%s\n' "$i_changed" | grep -v "^$ev2/" | sed 's/^/   /'
  echo "   outside Docs/: $( [[ -z "$i_outside" ]] && echo "nothing (README.md, CLAUDE.md and Scripts/ included)" || echo "PROBLEM: $i_outside")"
  echo "   unchanged since ${fix1end:0:8} (the license inventory, its texts and draft; the plan; the amendments; CLAUDE.md; README.md; Scripts/; the device checklists; the gate summary's checker; the zip guard's and the dependency lock's evidence; the extracted records; the first fix's, the assembly's and the hand-over's checks' commands and logs): $( [[ -z "$i_kept" ]] && echo yes || echo "PROBLEM, changed: $i_kept")"
  echo "   in the hand-over's folder ($items/): $i_items $( [[ "$i_items" == "$i_items_expected" ]] && echo '(exactly its README, deps.md and item-reviews.py)' || echo '(PROBLEM: not exactly its README, deps.md and item-reviews.py)')"
  echo "   the three evidence READMEs, the first fix's, the assembly's and the hand-over's checks': $( [[ -z "$i_readme_other" ]] && echo 'each its text at 83030fba once its dated notes of 26 October 2026, which name 83030fba, are taken out' || echo "PROBLEM:$i_readme_other")"
  echo "   new files outside $ev2/: $( [[ -z "$i_added_other" ]] && echo none || echo "PROBLEM: $i_added_other"); deleted files: $( [[ -z "$i_deleted" ]] && echo none || echo "PROBLEM: $i_deleted")"
  if (( i_ok )); then echo "   as this fix's records state it"; else echo "   PROBLEM: not as this fix's records state it"; fi
} >> "$log"
(( i_ok )) || status=1

# 1j. Where the 28 commits the review records cite are kept (read-only).
reach_status=0
python3 -I "$ev2/commands/branch-reach.py" > "$s/reach.out" 2>&1 || reach_status=$?
{
  echo "-- 1j. where the review records' commits are kept ($ev2/commands/branch-reach.py), read-only: each on its item's m0-int-* branch and on no other ref, an ancestor of none of the branches the work went on to"
  grep -E '^(records read|remote-tracking refs|of them an m0-int|tags|local m0-int|PROBLEM|[0-9]+ distinct commits|result)' "$s/reach.out" | cut -c1-300 | sed 's/^/   /'
  echo "exit: $reach_status"
} >> "$log"
(( reach_status != 0 )) && status=1

{
  echo
  echo "== 2. Git LFS state"
  echo ".gitattributes patterns (non-comment lines):"
  grep -v -E '^\s*(#|$)' .gitattributes
  echo "git config --show-origin --get-regexp 'filter\\.lfs|lfs\\.':"
  git config --show-origin --get-regexp 'filter\.lfs|lfs\.' || echo "(no match)"
  git lfs version
  echo "files tracked by LFS (git lfs ls-files): $(git lfs ls-files | wc -l | tr -d ' '); of them still pointer files in the working tree: $(git lfs ls-files | awk '$2 == "-"' | wc -l | tr -d ' ')"
} >> "$log" 2>&1
git lfs ls-files -l "$base" | sort > "$s/lfs-base.txt"
git lfs ls-files -l HEAD | sort > "$s/lfs-head.txt"
if cmp -s "$s/lfs-base.txt" "$s/lfs-head.txt"; then
  echo "LFS files (object and path, git lfs ls-files -l) at HEAD and at $base: identical, $(wc -l < "$s/lfs-head.txt" | tr -d ' ') each: no LFS object added since pull request #5" >> "$log"
else
  echo "LFS files at HEAD and at $base differ:" >> "$log"
  diff "$s/lfs-base.txt" "$s/lfs-head.txt" | head -n 20 >> "$log"
  status=1
fi

{
  echo
  echo "== 3. M0-gate.md: paths, and statuses against the records they cite"
} >> "$log"
python3 -I "$commands/gate-refresh-check.py" "$root" >> "$log" 2>&1 || status=1
neg="$s/negative"
mkdir -p "$neg/$evidence/final-fix/ci-logs" "$neg/$evidence/final-fix-2/ci-logs" "$neg/$evidence/repin-27.1/round-2" "$neg/Docs/ADRs" "$neg/Docs/Stage0" "$neg/$zipev/ci-2"
cp Docs/Stage0/*.md "$neg/Docs/Stage0/"
cp Docs/ADRs/*.md "$neg/Docs/ADRs/"
cp "$evidence/ci-full-clean-run-assembled.log" "$evidence/ci-documents-final.log" "$evidence/ci-full-clean-run-final.log" "$neg/$evidence/"
cp "$evidence/final-fix/ci-full-clean-run-final.log" "$neg/$evidence/final-fix/"
for round in final-fix final-fix-2; do
  cp "$evidence/$round/ci-logs/10-contracts.log" "$evidence/$round/ci-logs/12-dependency-lock.log" "$neg/$evidence/$round/ci-logs/"
done
cp "$evidence/repin-27.1/12-dependency-lock.log" "$evidence/repin-27.1/12-dependency-lock-before.log" "$neg/$evidence/repin-27.1/"
cp "$evidence/repin-27.1/round-2/12-dependency-lock.log" "$neg/$evidence/repin-27.1/round-2/"
cp "$zipev/ci-2/12-dependency-lock.log" "$neg/$zipev/ci-2/"
mkdir -p "$neg/$fixev"
cp "$fixev/12-dependency-lock.log" "$neg/$fixev/"
sed -i '' -E '/^\| 22 \| /s/\| failed \|/| passed-simulator |/' "$neg/Docs/Stage0/M0-gate.md"
sed -i '' -E '/^\| 33 \| /s/budget failed for/budget missed for/' "$neg/Docs/Stage0/G04-Audio.md"
sed -i '' -E 's/^- \*\*Status:\*\* Proposed\. Security review/- **Status:** Accepted. Security review/' "$neg/Docs/ADRs/0015-threat-model.md"
neg_status=0
python3 -I "$commands/gate-refresh-check.py" "$neg" > "$s/negative.out" 2>&1 || neg_status=$?
disagree="$(grep -E -- '-> DISAGREES$' "$s/negative.out" | sed -E 's/^row ([0-9]+):.*/\1/' | sort -n -u | tr '\n' ' ' | sed 's/ $//')"
{
  echo
  echo "-- 3b. Negative control on copies with three planted wrong statuses (the copies hold the zip guard's log and the first fix's, which row 76 reads): checker exit $neg_status; rows reported as disagreeing: $disagree"
} >> "$log"
if [[ "$neg_status" == 1 && "$disagree" == "22 42 66 71 78 92" ]]; then
  echo "   as required (22, 42, 66, 71, 78, 92)" >> "$log"
else
  echo "   NOT as required (22, 42, 66, 71, 78, 92)" >> "$log"; status=1
fi

{
  echo
  echo "== 4. The documents' own consistency checks"
  echo "-- the follow-up's fix's amendments checker, unchanged ($decisions/followup/round-2/commands/check-amendments.py; its mutations and controls on this round's last documents commit: $here/check-amendments.log)"
} >> "$log"
amend_status=0
python3 -I "$decisions/followup/round-2/commands/check-amendments.py" > "$s/amend.out" 2>&1 || amend_status=$?
{
  grep -E '^FAIL |^summary:|Section 3\.2' "$s/amend.out"
  echo "exit: $amend_status"
  echo "-- the runbook's content check ($decisions/assembly/commands/runbook-content-check.py, unchanged; its controls and limits: $here/runbook-content-check.log)"
} >> "$log"
(( amend_status != 0 )) && status=1
content_status=0
python3 -I "$decisions/assembly/commands/runbook-content-check.py" "$root" > "$s/content.out" 2>&1 || content_status=$?
{
  grep -E '\.md: [0-9]+ steps|NOT_CARRIED:|in its gate.s checklist|source fragments|RUNBOOK_OWN:|^result:' "$s/content.out"
  echo "exit: $content_status"
  echo "-- the runbook's step coverage (final-fix/commands/runbook-coverage.py)"
} >> "$log"
(( content_status != 0 )) && status=1
cov_status=0
python3 -I "$evidence/final-fix/commands/runbook-coverage.py" "$root" > "$s/coverage.out" 2>&1 || cov_status=$?
{
  tail -n 3 "$s/coverage.out"
  echo "exit: $cov_status"
  echo "-- the runbook's correction-text check on $base, on $correction and on HEAD (Docs/Stage0/evidence/M0-runbook/commands/check-correction-texts.py, as committed at HEAD)"
} >> "$log"
(( cov_status != 0 )) && status=1
trees="$root/$s/trees"
mkdir -p "$trees/base" "$trees/start" "$trees/head" "$trees/fixstart" "$trees/merged" "$trees/asm" "$trees/fix1end"
git archive "$base" | tar -x -C "$trees/base"
git archive "$correction" | tar -x -C "$trees/start"
git archive HEAD | tar -x -C "$trees/head"
git archive "$fixstart" | tar -x -C "$trees/fixstart"
git archive "$merge2" | tar -x -C "$trees/merged"
git archive "$asm" | tar -x -C "$trees/asm"
git archive "$fix1end" | tar -x -C "$trees/fix1end"
cp Docs/Stage0/evidence/M0-runbook/commands/check-correction-texts.py "$trees/check.py"
for side in base start head; do
  (cd "$trees/$side" && python3 -I "$trees/check.py" > "$trees/$side.out" 2>&1); echo "$?" > "$trees/$side.status"
done
{
  echo "   $base: exit $(cat "$trees/base.status"); $(tail -n 1 "$trees/base.out")"
  echo "   $correction: exit $(cat "$trees/start.status"); $(tail -n 1 "$trees/start.out")"
  echo "   HEAD: exit $(cat "$trees/head.status"); $(tail -n 1 "$trees/head.out")"
  echo "   the lines that differ from $base to HEAD (the first line, a timestamp, left out):"
  diff <(tail -n +2 "$trees/base.out") <(tail -n +2 "$trees/head.out") | grep -E '^[<>] ' | sed 's/^/   /'
} >> "$log"
changed_cct="$(diff <(tail -n +2 "$trees/base.out") <(tail -n +2 "$trees/head.out") | grep -E '^> C[0-9]+ ' | sed -E 's/^> (C[0-9]+) +([A-Z]+|ok) +x([0-9]+) ([^:]+):.*/\1 \2 \3 \4/' | sort)"
expected="$(printf '%s\n' \
  "C28 MISSING 0 Docs/Stage0/device-checklists/G06-Design.md" \
  "C47 MISSING 0 Docs/Stage0/G02-Transfer.md" \
  "C49 MISSING 0 Docs/ADRs/0011-ai-providers-context-and-privacy.md" \
  "C49 MISSING 0 Docs/ADRs/0011-ai-providers-context-and-privacy.md" \
  "C49 MISSING 0 Docs/Stage0/G05-AI.md" \
  "C50 MISSING 0 Docs/ADRs/0013-design-language.md" \
  "C56 MISSING 0 Docs/ADRs/0010-intake-handoff-and-wired-bundles.md" \
  "C56 MISSING 0 Docs/Stage0/G03-Intake.md" \
  "C56 MISSING 0 Docs/Stage0/device-checklists/G03-Intake.md" | sort)"
start_diff="$(diff <(tail -n +2 "$trees/start.out") <(tail -n +2 "$trees/head.out") | grep -E '^[<>] ' || true)"
if [[ "$changed_cct" == "$expected" && "$(cat "$trees/base.status")" == 1 && "$(cat "$trees/head.status")" == 1 ]] \
   && [[ "$(diff <(tail -n +2 "$trees/base.out") <(tail -n +2 "$trees/head.out") | grep -c -E '^< ')" == 10 ]] \
   && [[ -z "$start_diff" ]]; then
  echo "   as required: from $base to HEAD the nine texts of the corrections the decisions round applied (C28, C47's report row, C49 three times, C50, C56 three times), found before and missing after, and the summary line, nothing else; from $correction to HEAD no line differs" >> "$log"
else
  echo "   NOT as required: expected exactly the nine applied corrections' texts to change from $base, and nothing from $correction:" >> "$log"
  printf '%s\n' "$start_diff" | sed 's/^/   /' >> "$log"
  status=1
fi

# The earlier rounds' rechecks.
recheck_status=0
python3 -I "$decisions/followup/commands/recheck-review2.py" "$root" > "$s/recheck2.out" 2>&1 || recheck_status=$?
{
  echo "-- the follow-up's recheck of the second review's twelve answered findings and HON-11 ($decisions/followup/commands/recheck-review2.py), on HEAD: it must still pass"
  sed 's/^/   /' "$s/recheck2.out"
  echo "exit: $recheck_status"
} >> "$log"
(( recheck_status != 0 )) && status=1
column="the ADR index lacks: | ADR | Title | Status (23 October 2026) | Owner during Stage 0 |"
recheck4_status=0
python3 -I "$decisions/followup/round-2/commands/recheck-review4.py" "$root" > "$s/recheck4.out" 2>&1 || recheck4_status=$?
fid_problems="$(grep '^PROBLEM ' "$s/recheck4.out" | sed -E 's/^PROBLEM +(FID4-[0-9]+):.*/\1/' | tr '\n' ' ' | sed 's/ $//')"
fid_details="$(grep '^PROBLEM ' "$s/recheck4.out" | sed -E 's/^PROBLEM +(FID4-[0-9]+):[^(]*\((.*)\)$/\1: \2/')"
fid_expected="FID4-02: ADR-0002's Branches lacks: reaches \`main\` before the M0 exit only through \`m0-decisions\`
FID4-04: $column
FID4-06: M0-gate.md item 4 lacks: under D-6, ADR-0014 is approved once Session 10's review of it is recorded, with your security sign-off; the runbook's exit review lacks: so ADR-0014's approval, once Session 10's review of it and your security sign-off are recorded (D-6)"
{
  echo "-- the follow-up's fix's recheck of FID4-01 to FID4-08 ($decisions/followup/round-2/commands/recheck-review4.py), on HEAD: it must report FID4-02 and FID4-06 on exactly the anchors the follow-up's second fix reworded, as before, and FID4-04 on exactly the ADR index's column, which this round dates 24 October 2026 (until then 23 October 2026, the text it requires); the rest still answered"
  sed 's/^/   /' "$s/recheck4.out"
  echo "exit: $recheck4_status; reported: $fid_problems"
} >> "$log"
if [[ "$recheck4_status" == 1 && "$fid_problems" == "FID4-02 FID4-04 FID4-06" && "$fid_details" == "$fid_expected" ]]; then
  echo "   as required: exactly FID4-02, FID4-04 and FID4-06, on exactly those anchors" >> "$log"
else
  echo "   NOT as required: exactly FID4-02 and FID4-06 on their anchors, and FID4-04 on the ADR index's column" >> "$log"; status=1
fi
hon_status=0
python3 -I "$decisions/followup/round-3/commands/recheck-hon4.py" "$root" > "$s/hon.out" 2>&1 || hon_status=$?
hon_problems="$(grep '^PROBLEM ' "$s/hon.out" | sed -E 's/^PROBLEM +(HON4-[0-9]+):.*/\1/' | tr '\n' ' ' | sed 's/ $//')"
hon_details="$(grep '^PROBLEM ' "$s/hon.out" | sed -E 's/^PROBLEM +(HON4-[0-9]+):[^(]*\((.*)\)$/\1: \2/')"
{
  echo "-- the second fix's recheck of HON4-01 to HON4-06 ($decisions/followup/round-3/commands/recheck-hon4.py), on HEAD: it must report exactly HON4-06, on exactly the ADR index's column, which this round dates 24 October 2026; the rest still answered"
  sed 's/^/   /' "$s/hon.out"
  echo "exit: $hon_status; reported: $hon_problems"
} >> "$log"
if [[ "$hon_status" == 1 && "$hon_problems" == "HON4-06" && "$hon_details" == "HON4-06: $column" ]]; then
  echo "   as required: exactly HON4-06, on exactly that column" >> "$log"
else
  echo "   NOT as required: exactly HON4-06, on the ADR index's column alone" >> "$log"; status=1
fi
own4_status=0
python3 -I "$decisions/followup/round-4/commands/recheck-own4.py" "$root" > "$s/own4.out" 2>&1 || own4_status=$?
own4_problems="$(grep '^PROBLEM ' "$s/own4.out" | sed -E 's/^PROBLEM +(OWN4-[0-9]+):.*/\1/' | tr '\n' ' ' | sed 's/ $//')"
own4_details="$(grep '^PROBLEM ' "$s/own4.out" | sed -E 's/.* \(([^()]*)\)$/\1/')"
own4_expected="the runbook's run 12 lacks: about 6-6.5 days of your time
a run under Xcode 27.1 is now recorded: the records that call it pending need updating"
{
  echo "-- the third fix's recheck of OWN4-01 to OWN4-09 ($decisions/followup/round-4/commands/recheck-own4.py), on HEAD: it must report OWN4-01 on run 12's old estimate, as before, and OWN4-07, by design, on the run under Xcode 27.1 that is now recorded; the rest still answered (OWN4-09: every step of item 1 within its 400 words)"
  sed 's/^/   /' "$s/own4.out"
  echo "exit: $own4_status; reported: $own4_problems"
} >> "$log"
if [[ "$own4_status" == 1 && "$own4_problems" == "OWN4-01 OWN4-07" && "$own4_details" == "$own4_expected" ]]; then
  echo "   as required: exactly OWN4-01 and OWN4-07, on exactly those texts" >> "$log"
else
  echo "   NOT as required: exactly OWN4-01 on run 12's old estimate and OWN4-07 on the recorded run" >> "$log"; status=1
fi
for check in "round-4/commands/moved-notes.py:the third fix's moved history notes" "round-5/commands/recheck-own5.py:the fourth fix's recheck of OWN5-01 to OWN5-06 and of the owner's answers (the State line within its 200 words among its texts)" "round-5/commands/moved-notes.py:the fourth fix's moved texts"; do
  path="$decisions/followup/${check%%:*}"
  what="${check#*:}"
  c_status=0
  python3 -I "$path" "$root" > "$s/c.out" 2>&1 || c_status=$?
  {
    echo "-- $what ($path), on HEAD: it must still pass"
    if [[ "$path" == *recheck-own5.py ]]; then sed 's/^/   /' "$s/c.out"; else tail -n 1 "$s/c.out" | sed 's/^/   /'; fi
    echo "exit: $c_status"
  } >> "$log"
  (( c_status != 0 )) && status=1
done
oldrun_status=0
python3 -I "$record/commands/check-run.py" "$root" > "$s/oldrun.out" 2>&1 || oldrun_status=$?
{
  echo "-- the record's check of the run's facts ($record/commands/check-run.py, as it ran), on the run's folder: it must still pass"
  tail -n 1 "$s/oldrun.out" | sed 's/^/   /'
  echo "exit: $oldrun_status"
} >> "$log"
(( oldrun_status != 0 )) && status=1
oldrec_status=0
python3 -I "$record/commands/recheck-unlocked.py" "$root" > "$s/oldrec.out" 2>&1 || oldrec_status=$?
oldrec_problems="$(grep '^PROBLEM ' "$s/oldrec.out" | sed -E 's/^PROBLEM +//')"
oldrec_expected="the ADR index, ADR-0015 (lacks: records the whole drop-in's run with the screen unlocked on \`9cdb0a02\`, which passed (not reviewed))
the Stage 0 README (lacks: and with the run of G0.5 recovery's whole drop-in with the screen unlocked, section 25))
the integration log, section 25 and 24.5's note (lacks: *(Dated note, 23 October 2026: a waiter of the orchestrating session ran it after this fix, on \`9cdb0a02\`, the fix's last commit, with the screen unlocked, and it passed: section 25.)*)"
{
  echo "-- the record's recheck of the records ($record/commands/recheck-unlocked.py), on HEAD: it must report exactly the three texts it reported on the second fix, every other record as on the record"
  sed 's/^/   /' "$s/oldrec.out"
  echo "exit: $oldrec_status"
} >> "$log"
if [[ "$oldrec_status" == 1 && "$oldrec_problems" == "$oldrec_expected" ]]; then
  echo "   as required: exactly those three" >> "$log"
else
  echo "   NOT as required: exactly the ADR index's entry, the Stage 0 README's line and 24.5's note" >> "$log"; status=1
fi
run_status=0
python3 -I "$fix/commands/check-run.py" "$root" > "$s/run.out" 2>&1 || run_status=$?
run_control=0
python3 -I "$fix/commands/check-run.py" "$root" "$decisions/assembly/dropin-clean" > "$s/run-control.out" 2>&1 || run_control=$?
{
  echo "-- the fix's check of the run's facts ($fix/commands/check-run.py), on the run's folder: it must still pass"
  tail -n 1 "$s/run.out" | sed 's/^/   /'
  echo "exit: $run_status"
  echo "-- its control, on the assembly's run of the same wrapper with the screen locked ($decisions/assembly/dropin-clean): it must fail"
  grep -E '^PROBLEM|^result' "$s/run-control.out" | cut -c1-200 | sed 's/^/   /'
  echo "exit: $run_control"
} >> "$log"
(( run_status != 0 )) && status=1
if [[ "$run_control" == 1 ]] && grep -q '^PROBLEM the screen unlocked at the start (ioreg)' "$s/run-control.out" \
   && grep -q "^PROBLEM the guard's line: row 10 evidence present" "$s/run-control.out"; then
  echo "   as required: the control fails, naming the locked screen and the missing row-10 line" >> "$log"
else
  echo "   NOT as required: the control must fail on the locked screen and the missing row-10 line" >> "$log"; status=1
fi
unl_status=0
python3 -I "$fix/commands/recheck-unl.py" "$root" > "$s/unl.out" 2>&1 || unl_status=$?
words() { sed -E 's/\(([0-9]+) words\)/(N words)/g'; }
unl_problems="$(grep '^PROBLEM ' "$s/unl.out" | sed -E 's/^PROBLEM +//' | words)"
unl_count="$(grep -o -E 'the State line \([0-9]+ words\)' "$s/unl.out" | head -n 1)"
unl_expected="$(printf '%s\n' "UNL-02: the State line (200 words) names the record of the drop-in run and its fix and the last two fixes as unreviewed; the Stage 0 README gives the review of the record and its fix; 25.2's row has its note (the State line lacks: the follow-up and its four fixes, the record of item 4's drop-in run and its fix, and this summary's own updates; the State line lacks: and the last two fixes, the follow-up's fourth and that record's, have not been reviewed; the Stage 0 README lacks: and a sixth agent review, of that record, raised five findings, one of them major, which a fix of the record answered the same day (section 26); that fix has not been reviewed either.; the Stage 0 README lacks: by the fix of the review of that run's record, section 26))" "review: the record read by an agent review, at 91c3b46a, and its fix not reviewed, in the gate summary, the runbook, the integration log, the record's README and the ADR index (the runbook's Who wrote it lacks: the follow-up's fourth fix of 23 October 2026, and the fix of the review of the drop-in's record, have not been reviewed)" | words)"
{
  echo "-- the fix's recheck of UNL-01 to UNL-05 and of the record's review status ($fix/commands/recheck-unl.py), on HEAD: it must report exactly UNL-02 and the review status, on exactly the texts it reported on the second fix (the State line's word count aside: $unl_count, which this round's notes changed), UNL-01, UNL-03, UNL-04 and UNL-05 still answered"
  sed 's/^/   /' "$s/unl.out"
  echo "exit: $unl_status"
} >> "$log"
if [[ "$unl_status" == 1 && "$unl_problems" == "$unl_expected" ]]; then
  echo "   as required: exactly those two, on exactly those texts" >> "$log"
else
  echo "   NOT as required: exactly UNL-02 and the review status, on the State line, the Stage 0 README and the runbook's Who wrote it" >> "$log"; status=1
fi
oldlines_status=0
python3 -I "$fix/commands/finding-lines.py" "$root" > "$s/oldlines.out" 2>&1 || oldlines_status=$?
{
  echo "-- the fix's check of its review's cited lines ($fix/commands/finding-lines.py), at 91c3b46a: it must still hold"
  tail -n 1 "$s/oldlines.out" | sed 's/^/   /'
  echo "exit: $oldlines_status"
} >> "$log"
(( oldlines_status != 0 )) && status=1
unl2_status=0
python3 -I "$second/commands/recheck-unl2.py" "$root" > "$s/unl2.out" 2>&1 || unl2_status=$?
unl2_control=0
python3 -I "$second/commands/recheck-unl2.py" "$trees/fixstart" > "$s/unl2-control.out" 2>&1 || unl2_control=$?
reported="$(grep -c -E '^PROBLEM +(UNL2-0[1-3]|review):' "$s/unl2-control.out")"
bare="$(grep -o 'no dated note naming `9cdb0a02` after: [^:]*:[0-9]*' "$s/unl2-control.out" | sed -E 's/^no dated note naming `9cdb0a02` after: //' | sort)"
unlisted="$(grep -o 'with a word of status, not read: [^:]*:[0-9]*' "$s/unl2-control.out" | sed -E 's/^with a word of status, not read: //' | sort)"
owner="$(grep -o 'does not say what remains: [^:]*:[0-9]*' "$s/unl2-control.out" | sed -E 's/^does not say what remains: //' | sort)"
rows_expected="$(printf '%s\n' "Docs/Stage0/integration-log.md:1003" "Docs/Stage0/integration-log.md:979" | sort)"
owner_expected="$(printf '%s\n' "Docs/Stage0/evidence/M0-Decisions/followup/round-5/README.md:18" "Docs/Stage0/integration-log.md:1389" | sort)"
{
  echo "-- the second fix's recheck of UNL2-01 to UNL2-03 and of the fix's review status ($second/commands/recheck-unl2.py), on HEAD, every Markdown file under Docs/ swept, this round's among them"
  sed 's/^/   /' "$s/unl2.out"
  echo "exit: $unl2_status"
  echo "-- its control on the tree of $fixstart: all three findings and the review status must be reported, exactly the two rows by both sweeps and exactly the two notes"
  echo "   sweep 1, texts with no note there: $(printf '%s' "$bare" | tr '\n' ' ')"
  echo "   sweep 2, sentences not listed there: $(printf '%s' "$unlisted" | tr '\n' ' ')"
  echo "   notes with no clause on what remains for the owner there: $(printf '%s' "$owner" | tr '\n' ' ')"
  echo "exit: $unl2_control; reported: $reported of 4"
} >> "$log"
(( unl2_status != 0 )) && status=1
if [[ "$unl2_control" == 1 && "$reported" == 4 && "$bare" == "$rows_expected" && "$unlisted" == "$rows_expected" && "$owner" == "$owner_expected" ]]; then
  echo "   as required: all four reported; exactly the two rows by both sweeps, and exactly the two notes" >> "$log"
else
  echo "   NOT as required: all four reported, exactly the two rows by both sweeps and exactly the two notes" >> "$log"; status=1
fi
lines_status=0
python3 -I "$second/commands/finding-lines.py" "$root" > "$s/lines.out" 2>&1 || lines_status=$?
lines_control=0
python3 -I "$second/commands/finding-lines.py" "$root" 91c3b46a1e034563ca9a6df9a77d5c736d202303 > "$s/lines-control.out" 2>&1 || lines_control=$?
{
  echo "-- the second fix's check of its review's cited lines and claims ($second/commands/finding-lines.py), at $fixstart"
  tail -n 1 "$s/lines.out" | sed 's/^/   /'
  echo "exit: $lines_status"
  echo "-- its control at 91c3b46a, the record's last commit, before the fix: it must fail"
  tail -n 1 "$s/lines-control.out" | sed 's/^/   /'
  echo "exit: $lines_control"
} >> "$log"
(( lines_status != 0 )) && status=1
if [[ "$lines_control" == 1 ]]; then
  echo "   as required: the control fails" >> "$log"
else
  echo "   NOT as required: the control must fail" >> "$log"; status=1
fi

# The review records' own checks.
ir_status=0
if [[ -n "$extraction" ]]; then
  python3 -I "$items/commands/item-reviews.py" check --extraction "$extraction" > "$s/ir.out" 2>&1 || ir_status=$?
else
  python3 -I "$items/commands/item-reviews.py" check > "$s/ir.out" 2>&1 || ir_status=$?
fi
render_status=0
python3 -I "$items/commands/item-reviews.py" render --check > "$s/render.out" 2>&1 || render_status=$?
probe_status=0
"$items/commands/audit-probe.sh" > "$s/probe.out" 2>&1 || probe_status=$?
{
  echo "-- the review records' check ($items/commands/item-reviews.py check${extraction:+ --extraction <dir>}), on HEAD: it must pass, the gate summary's Section 6.2 last row and ADR-0014's pointer line among the texts it reads"
  grep -E '^(PROBLEM|note|result)' "$s/ir.out" | cut -c1-240 | sed 's/^/   /'
  echo "exit: $ir_status"
  echo "-- the records' render check ($items/commands/item-reviews.py render --check): the thirteen Markdown records are what render writes"
  tail -n 1 "$s/render.out" | sed 's/^/   /'
  echo "exit: $render_status"
  echo "-- the hard-rule audit probe ($items/commands/audit-probe.sh): the copies named .json fail, the names committed pass"
  grep -E '^audit exit|^result' "$s/probe.out" | sed 's/^/   /'
  echo "exit: $probe_status"
} >> "$log"
(( ir_status != 0 || render_status != 0 || probe_status != 0 )) && status=1
# Two controls of the check as this fix changed it, each on a copy of HEAD's tree under .build/scratch: the copy's
# script reads the copy's files, and its git calls read this repository, whose worktree holds the copy.
plant="$root/$s/plant-facts"
mkdir -p "$plant"
git archive HEAD | tar -x -C "$plant"
adr_before="$(grep -c -E 'R4-0[3-7]' "$plant/Docs/ADRs/0014-dependency-lock-and-license-inventory.md")"
sed -i '' -E 's/R4-0([3-7])/R4-9\1/g' "$plant/Docs/ADRs/0014-dependency-lock-and-license-inventory.md"
sed -i '' -e 's/-type d -exec rm -rf {} +/-type d -print/' "$plant/Docs/Stage0/G05-AI.md"
sed -i '' -e 's#"g05-tests/#"g05-scratch/#' "$plant/Spikes/G05-Recovery/Tests/SylviaRecoveryTests/Support.swift"
planted="ADR-0014 lines naming R4-03 to R4-07: $adr_before before, $(grep -c -E 'R4-0[3-7]' "$plant/Docs/ADRs/0014-dependency-lock-and-license-inventory.md") after; R8-04's command in G05-AI.md: $(grep -c -F -e "-type d -exec rm -rf {} +" "$plant/Docs/Stage0/G05-AI.md") after; g05-tests/ in Support.swift: $(grep -c -F '"g05-tests/' "$plant/Spikes/G05-Recovery/Tests/SylviaRecoveryTests/Support.swift") after"
pa_status=0
(cd "$plant" && python3 -I "$items/commands/item-reviews.py" check) > "$s/plant-facts.out" 2>&1 || pa_status=$?
pa_lines="$(grep -E '^PROBLEM ' "$s/plant-facts.out" | cut -c1-90)"
pa_expected="$(printf '%s\n' "PROBLEM deps: the record's note on ADR-0014 holds: before 6cd842d3, the Zip guard's fix, A" "PROBLEM minors-g05-ai: the cleanup command R8-04 names is no longer in G05-AI.md; the reco" "PROBLEM minors-g05-ai: G0.5 recovery's tests no longer make their scratch directories unde")"  # each line's first 90 characters
{
  echo "-- control 1 of the check as this fix changed it: on a copy of HEAD's tree with the three facts its part 7 now checks planted false ($planted), it must report exactly those three"
  grep -E '^(PROBLEM|result|Traceback)' "$s/plant-facts.out" | cut -c1-260 | sed 's/^/   /'
  echo "exit: $pa_status"
} >> "$log"
if [[ "$pa_status" == 1 && "$pa_lines" == "$pa_expected" ]] && grep -q -x 'result: FAIL (3 problem(s))' "$s/plant-facts.out"; then
  echo "   as required: exactly the three planted, and nothing else" >> "$log"
else
  echo "   NOT as required: exactly the deps note, R8-04's command and the g05-tests/ root" >> "$log"; status=1
fi
plantb="$root/$s/plant-branch"
mkdir -p "$plantb"
git archive HEAD | tar -x -C "$plantb"
sed -i '' -e 's/"m0-int-minors-g04-audio"/"m0-int-minors-g04-audio-absent"/' "$plantb/$items/commands/item-reviews.py"
pb_status=0
(cd "$plantb" && python3 -I "$items/commands/item-reviews.py" check) > "$s/plant-branch.out" 2>&1 || pb_status=$?
pb_count="$(grep -c -E '^PROBLEM ' "$s/plant-branch.out")"
pb_other="$(grep -E '^PROBLEM ' "$s/plant-branch.out" | grep -v -c 'minors-g04-audio')"
pb_trace="$(grep -c -E '^Traceback|^[A-Za-z]+Error:' "$s/plant-branch.out")"
{
  echo "-- control 2: on a copy whose script names an absent branch for minors-g04-audio (m0-int-minors-g04-audio-absent; renamed in the copy's script: $(grep -c -F '"m0-int-minors-g04-audio-absent"' "$plantb/$items/commands/item-reviews.py")), it must report that item's branch, records, merge and Markdown record, and nothing else, and end with its result line, with no error"
  grep -E '^(PROBLEM|result|Traceback)' "$s/plant-branch.out" | cut -c1-240 | sed 's/^/   /'
  echo "exit: $pb_status; problems: $pb_count, of them not about minors-g04-audio: $pb_other; errors: $pb_trace"
} >> "$log"
if [[ "$pb_status" == 1 && "$pb_count" == 8 && "$pb_other" == 0 && "$pb_trace" == 0 ]] && grep -q -x 'result: FAIL (8 problem(s))' "$s/plant-branch.out"; then
  echo "   as required: the item's eight problems (part 4: the branch and its two records; part 5: the head, the squash message and the paths; part 6: the branch; part 8: the record), no error" >> "$log"
else
  echo "   NOT as required: that item's problems alone, and no error" >> "$log"; status=1
fi
rm -rf "$plant" "$plantb"

# The assembly's checks, then the first fix's, then this fix's.
xr_status=0
python3 -I "$here/commands/recheck-exit-prep.py" "$root" > "$s/xr.out" 2>&1 || xr_status=$?
xr_control=0
python3 -I "$here/commands/recheck-exit-prep.py" "$trees/merged" > "$s/xr-control.out" 2>&1 || xr_control=$?
xr_groups="$(grep -c -E '^(ok|PROBLEM) ' "$s/xr-control.out")"
xr_reported="$(grep -c -E '^PROBLEM ' "$s/xr-control.out")"
xr_problems="$(grep -E '^PROBLEM ' "$s/xr.out" | sed -E 's/^PROBLEM +([A-Z0-9]+):.*/\1/' | tr '\n' ' ' | sed 's/ $//')"
xr_r6="(1 of 6 not as stated; first: Docs/Stage0/M0-gate.md lacks: nor has the M0 exit preparation of 24 October 2026 (Sections 6.2 and 8).)"
{
  echo "-- the assembly's recheck of the requests and of what it recorded besides them ($here/commands/recheck-exit-prep.py), on HEAD: it must report exactly its group R6, by design, and there exactly the State line's clause that gave the exit preparation as not reviewed, which the first fix reworded, as on the first fix (the other five texts of R6 stand, each with its dated notes after it); every other group must pass"
  sed 's/^/   /' "$s/xr.out" | cut -c1-320
  echo "exit: $xr_status; reported: ${xr_problems:-none}"
} >> "$log"
if [[ "$xr_status" == 1 && "$xr_problems" == R6 ]] && grep -q -F "$xr_r6" "$s/xr.out"; then
  echo "   as required: exactly R6, on exactly the State line's clause" >> "$log"
else
  echo "   NOT as required: exactly R6, on the State line's clause alone" >> "$log"; status=1
fi
{
  echo "-- its control on the tree of ${merge2:0:8} (both branches merged, before the assembly's own changes): every group must be reported"
  grep -E '^(ok|PROBLEM|result)' "$s/xr-control.out" | cut -c1-200 | sed 's/^/   /'
  echo "exit: $xr_control; groups reported: $xr_reported of $xr_groups"
} >> "$log"
if [[ "$xr_control" == 1 && "$xr_groups" -gt 0 && "$xr_reported" == "$xr_groups" ]]; then
  echo "   as required: every group reported" >> "$log"
else
  echo "   NOT as required: every group reported" >> "$log"; status=1
fi
xc_status=0
python3 -I "$here/commands/check-xcode-reading.py" "$root" > "$s/xc.out" 2>&1 || xc_status=$?
xc_control=0
python3 -I "$here/commands/check-xcode-reading.py" "$trees/merged" > "$s/xc-control.out" 2>&1 || xc_control=$?
xc_parts="$(awk '/^== /{part=$2} /^PROBLEM /{print part}' "$s/xc-control.out" | sort -u | tr '\n' ' ' | sed 's/ $//')"
{
  echo "-- the assembly's reading of the relay of Apple's pages for Xcode 27.1 against the repository ($here/commands/check-xcode-reading.py), on HEAD: it must pass"
  sed 's/^/   /' "$s/xc.out" | cut -c1-220
  echo "exit: $xc_status"
  echo "-- its control on the tree of ${merge2:0:8}, before the relay was recorded: exactly its part 4, the records, must fail"
  grep -E '^PROBLEM|^result' "$s/xc-control.out" | cut -c1-200 | sed 's/^/   /'
  echo "exit: $xc_control; parts with a problem: $xc_parts"
} >> "$log"
(( xc_status != 0 )) && status=1
if [[ "$xc_control" == 1 && "$xc_parts" == "4." ]]; then
  echo "   as required: part 4 alone" >> "$log"
else
  echo "   NOT as required: part 4 alone" >> "$log"; status=1
fi
f1_status=0
python3 -I "$fixev/commands/recheck-fix-1.py" "$root" > "$s/f1.out" 2>&1 || f1_status=$?
f1_control=0
python3 -I "$fixev/commands/recheck-fix-1.py" "$trees/asm" > "$s/f1-control.out" 2>&1 || f1_control=$?
f1_groups="$(grep -c -E '^(ok|PROBLEM) ' "$s/f1-control.out")"
f1_reported="$(grep -c -E '^PROBLEM ' "$s/f1-control.out")"
f1_problems="$(grep -E '^PROBLEM ' "$s/f1.out" | sed -E 's/^PROBLEM +([A-Z0-9]+):.*/\1/' | tr '\n' ' ' | sed 's/ $//')"
f1_r="(1 of 16 not as stated; first: Docs/Stage0/M0-gate.md lacks: have not been reviewed, nor has the fix of the review of the M0 exit preparation (Sections)"  # the recheck prints a text's first 90 characters
{
  echo "-- the first fix's recheck of SEC-ZIPGUARD-01 and SEC-ZIPGUARD-02, of the first review's status and of the observation it records ($fixev/commands/recheck-fix-1.py), on HEAD: it must report exactly its group R, by design, and there exactly the State line's clause that gave the first fix as not reviewed, which this fix rewords now that the second review has read it (the other fifteen texts of R stand, each with its dated notes after it); every other group must pass"
  sed 's/^/   /' "$s/f1.out" | cut -c1-320
  echo "exit: $f1_status; reported: ${f1_problems:-none}"
} >> "$log"
if [[ "$f1_status" == 1 && "$f1_problems" == R ]] && grep -q -F "$f1_r" "$s/f1.out"; then
  echo "   as required: exactly R, on exactly the State line's clause" >> "$log"
else
  echo "   NOT as required: exactly R, on the State line's clause alone" >> "$log"; status=1
fi
{
  echo "-- its control on the tree of ${asm:0:8}, the commit the first review read: every group must be reported"
  grep -E '^(ok|PROBLEM|result)' "$s/f1-control.out" | cut -c1-200 | sed 's/^/   /'
  echo "exit: $f1_control; groups reported: $f1_reported of $f1_groups"
} >> "$log"
if [[ "$f1_control" == 1 && "$f1_groups" == 5 && "$f1_reported" == 5 ]]; then
  echo "   as required: all five groups reported" >> "$log"
else
  echo "   NOT as required: all five groups reported" >> "$log"; status=1
fi
ev_status=0
python3 -I "$ev2/commands/recheck-ev.py" "$root" > "$s/ev.out" 2>&1 || ev_status=$?
ev_control=0
python3 -I "$ev2/commands/recheck-ev.py" "$trees/fix1end" > "$s/ev-control.out" 2>&1 || ev_control=$?
ev_groups="$(grep -c -E '^(ok|PROBLEM) ' "$s/ev-control.out")"
ev_reported="$(grep -c -E '^PROBLEM ' "$s/ev-control.out")"
{
  echo "-- this fix's recheck of EV-01 to EV-04 and of the second review's status ($ev2/commands/recheck-ev.py), on HEAD: it must pass"
  sed 's/^/   /' "$s/ev.out" | cut -c1-260
  echo "exit: $ev_status"
  echo "-- its control on the tree of ${fix1end:0:8}, the commit the second review read: every group must be reported"
  grep -E '^(ok|PROBLEM|result)' "$s/ev-control.out" | cut -c1-200 | sed 's/^/   /'
  echo "exit: $ev_control; groups reported: $ev_reported of $ev_groups"
} >> "$log"
(( ev_status != 0 )) && status=1
if [[ "$ev_control" == 1 && "$ev_groups" == 5 && "$ev_reported" == 5 ]]; then
  echo "   as required: all five groups reported" >> "$log"
else
  echo "   NOT as required: all five groups reported" >> "$log"; status=1
fi
fl_status=0
python3 -I "$ev2/commands/finding-lines.py" > "$s/fl.out" 2>&1 || fl_status=$?
fl_control=0
python3 -I "$ev2/commands/finding-lines.py" HEAD > "$s/fl-control.out" 2>&1 || fl_control=$?
{
  echo "-- this fix's reading of the four findings' citations ($ev2/commands/finding-lines.py), at ${fix1end:0:8} (and, where the findings place them, ${asm:0:8}): every citation must hold"
  tail -n 1 "$s/fl.out" | sed 's/^/   /'
  echo "exit: $fl_status"
  echo "-- its control at HEAD, where the texts this fix dates or corrects are no longer as quoted: it must fail"
  grep -E '^PROBLEM' "$s/fl-control.out" | cut -c1-200 | sed 's/^/   /'
  tail -n 1 "$s/fl-control.out" | sed 's/^/   /'
  echo "exit: $fl_control"
} >> "$log"
(( fl_status != 0 )) && status=1
if [[ "$fl_control" == 1 ]]; then
  echo "   as required: the control fails" >> "$log"
else
  echo "   NOT as required: the control must fail" >> "$log"; status=1
fi
rm -rf "$trees"

{
  echo
  echo "== 5. Scripts/ci.sh contracts dependency-lock hard-rules (every drop-in must pass)"
} >> "$log"
ci_status=0
Scripts/ci.sh contracts dependency-lock hard-rules >> "$log" 2>&1 || ci_status=$?
{
  echo "ci.sh exit: $ci_status"
  echo "summary lines from the drop-ins' own logs (.build/ci-logs/):"
  for name in 00-git-lfs 10-contracts 11-capture-anchor-contracts 12-dependency-lock 13-hard-rules; do
    echo "-- $name (last 4 lines)"
    tail -n 4 ".build/ci-logs/$name.log"
  done
  echo "-- the audit's result line:"
  grep -E '^result:' .build/ci-logs/hard-rules/audit-repository.log || echo "(none)"
  echo "-- FAIL lines in 12-dependency-lock's log:"
  grep -E '^FAIL ' .build/ci-logs/12-dependency-lock.log || echo "(none)"
  echo "-- its self-test's count, its toolchain lines, and its count of the committed and registered locks:"
  grep -E -o 'self-test: [0-9]+ mutations[^;]*' .build/ci-logs/12-dependency-lock.log | head -n 1 || echo "(none)"
  grep -E '^ok    toolchain:' .build/ci-logs/12-dependency-lock.log || echo "(none)"
  grep -E '^ok    locks:' .build/ci-logs/12-dependency-lock.log || echo "(none)"
} >> "$log" 2>&1
(( ci_status != 0 )) && { echo "part 5: a drop-in failed (above)" >> "$log"; status=1; }
{
  echo
  echo "== 6. Leftover G0.5 temporary directories (read-only count, names only, one level; G05-AI R7-04, R8-04)"
  tmp="$(getconf DARWIN_USER_TEMP_DIR)"
  echo "g05-* directories in the user's temporary folder: $(find "$tmp" -maxdepth 1 -name 'g05-*' -type d 2>/dev/null | wc -l | tr -d ' ')"
  echo "of them g05-tests, G0.5 recovery's test root, which the cleanup command of G05-AI.md would delete too (R8-04): $(find "$tmp" -maxdepth 1 -name 'g05-tests' -type d 2>/dev/null | wc -l | tr -d ' '); g05-tests-*: $(find "$tmp" -maxdepth 1 -name 'g05-tests-*' -type d 2>/dev/null | wc -l | tr -d ' ')"
  echo
  echo "exit: $status"
  echo "end: $(date -u +%Y-%m-%dT%H:%M:%SZ); load: $(uptime)"
} >> "$log" 2>&1
rm -rf "$s"
exit $status
