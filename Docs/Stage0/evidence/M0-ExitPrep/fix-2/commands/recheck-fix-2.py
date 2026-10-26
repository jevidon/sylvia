#!/usr/bin/env python3
"""Recheck of the fix of the fourth review of the M0 exit preparation (26 October 2026; integration log section 34): the
one finding the workflow relayed from that review, which read m0-exit-prep at fcbd6c89, SEC-ZIPGUARD-03, answered where
the fix says it is, with the routes of the same kind the fix found, and the review's status given wherever the records
gave the fix of the third review as not reviewed.

    python3 -I Docs/Stage0/evidence/M0-ExitPrep/fix-2/commands/recheck-fix-2.py <tree>

<tree> is a repository root or an extracted tree (git archive). One line per group:
  G  the guard: the rule for a version-specific manifest under the product roots, the letter-case rules, the module
     maps read by every name clang reads them by, the dump cache's key, the docstring, the self-test's eight mutations
     and two allowed changes, and its 123 failure branches; and the reproductions' log (every route as expected, and
     the tools' behaviour of its part 2);
  A  ADR-0014: rule 5 of section 1, section 3 (manifest-input, letter-case, the self-test's counts and the list of what
     the check cannot see), sections 5 and 6, the status line, Evidence, the consequence and the open item, the old
     counts gone;
  D  the records of the finding: the gate summary (row 76, item 4's bullet, Section 1's bullet on the preparation,
     Section 2.10, Section 6.1, items 105, 111, 113 and 22's counts, items 125 and 126, Section 8's bullet for this fix
     and its Branch note) and its checker's row 76; the ADR index; the Stage 0 README; integration log section 34 and
     the notes on the route in 31.5, 32.2, 32.5, 33.2 and 33.5; and the evidence READMEs that named the route as left
     open (the first fix's, the second's and the third's) or gave the earlier counts (the Zip guard's);
  R  the review's status: the State line (within 200 words), Section 6.2 (the third review's row, a row for the fourth
     before the hand-over's row, which stays the table's last, and the paragraph after the table), the notes after each
     text that gave the third fix as not reviewed (items 109, 118 and 124, Section 7's item 5, Section 8's bullet for
     the third fix and its Written by line; ADR-0014, the ADR index, the Stage 0 README, the runbook, integration log
     30.6, 31.5, 32 and 33, and the evidence READMEs of the assembly, the Zip guard's fix and the hand-over's two);
  C  the self-test's counts: every line of the records' Markdown files that gives the counts of the first fix (283
     mutations, 36 allowed changes, 120 failure branches) or earlier also gives this fix's (291), or is one of ACCOUNTS,
     the accounts of those runs as they ran, each with its reason; and each of ACCOUNTS must still be there.
Most checks are a text that must stand, an anchor with the start of the dated note that must follow it, or a text that
must be gone. On HEAD every group must pass; on the tree of fcbd6c89, the reviewed commit, which the gate checks beside
this file run as its control, every group must be reported. Standard library only; read-only; reads files only. Exits
1 if any group is not as stated.
"""
import ast
import re
import sys
from pathlib import Path

ROOT = Path(sys.argv[1])
CHECK = "Scripts/check-dependency-lock.py"
GATE = "Docs/Stage0/M0-gate.md"
LOG = "Docs/Stage0/integration-log.md"
README = "Docs/Stage0/README.md"
RUNBOOK = "Docs/Stage0/M0-device-runbook.md"
INDEX = "Docs/ADRs/README.md"
A14 = "Docs/ADRs/0014-dependency-lock-and-license-inventory.md"
CHECKER = "Docs/Stage0/evidence/M0-Integration/commands/gate-refresh-check.py"
ITEMS = "Docs/Stage0/evidence/M0-Integration/item-reviews"
IREADME = f"{ITEMS}/README.md"
EXIT = "Docs/Stage0/evidence/M0-ExitPrep"
ZIP = f"{EXIT}/zipguard/README.md"
FIX1 = f"{EXIT}/fix-1/README.md"
FIX2 = f"{EXIT}/fix-1/round-2/README.md"
FIX3 = f"{EXIT}/fix-1/round-3/README.md"
ASM = f"{EXIT}/assembly/README.md"
REVIEWS = f"{EXIT}/reviews/README.md"
REPRO = f"{EXIT}/fix-2/reproductions.log"
CACHE = {}


def read(rel):
    if rel not in CACHE:
        p = ROOT / rel
        CACHE[rel] = p.read_text(encoding="utf-8") if p.is_file() else ""
    return CACHE[rel]


problems = 0


def group(name, checks, what):
    """checks: (file, text) pairs that must stand; (file, anchor, note start) triples that must stand together;
    ('gone', file, text) triples that must not stand; and (label, bool) pairs."""
    global problems
    missing = []
    for c in checks:
        if c[0] == "gone":
            _, f, text = c
            if text in read(f):
                missing.append(f"{f} still has: {text[:90]}")
        elif isinstance(c[1], bool):
            if not c[1]:
                missing.append(c[0])
        elif len(c) == 2:
            f, text = c
            if text not in read(f):
                missing.append(f"{f} lacks: {text[:90]}")
        else:
            f, anchor, note = c
            if anchor + note not in read(f):
                missing.append(f"{f}: {('anchor missing: ' + anchor[:70]) if anchor not in read(f) else ('no note after: ' + anchor[-70:])}")
    if missing:
        problems += 1
        print(f"PROBLEM  {name}: {what} ({len(missing)} of {len(checks)} not as stated; first: {missing[0]})")
    else:
        print(f"ok       {name}: {what} ({len(checks)} texts)")


def fail_sites(source):
    try:
        tree = ast.parse(source)
    except SyntaxError:
        return -1
    return sum(1 for n in ast.walk(tree) if isinstance(n, ast.Call) and isinstance(n.func, ast.Attribute)
               and n.func.attr == "fail" and isinstance(n.func.value, ast.Name) and n.func.value.id == "self")


def section(text, start, end):
    i = text.find(start)
    if i < 0:
        return ""
    j = text.find(end, i + len(start))
    return text[i:j if j >= 0 else len(text)]


check = read(CHECK)
repro = read(REPRO)
verdicts = re.findall(r"^    (ok \(|UNEXPECTED)", repro, re.M)
routes = re.findall(r"^--- route \d+, ([a-z0-9-]+): ", repro, re.M)

# G: the guard.
group("G", [
    (CHECK, "VERSION_SPECIFIC_MANIFEST = re.compile(r'^package@.*\\.swift$', re.I | re.S)"),
    (CHECK, "MANIFEST_NAMES = ('Package.swift', 'project.yml')"),
    (CHECK, "MODULEMAP_NAMES = ('module.map', 'module_private.map')"),
    (CHECK, "    def check_names(self, files, product_roots, spike_roots):"),
    (CHECK, "        self.check_names(files, product_roots, spike_roots)\n"),
    (CHECK, "            if self.under_ci(f, roots) and not self.under(f, roots):\n"),
    (CHECK, "            elif self.under(f, product_roots) and VERSION_SPECIFIC_MANIFEST.match(name):\n"),
    (CHECK, "                 and is_modulemap_name(os.path.basename(f))]"),
    ("gone", CHECK, "and (f.endswith('.modulemap') or os.path.basename(f) == 'module.map')]"),
    (CHECK, "        key = (rel, hashlib.sha256(content).hexdigest()) + others\n"),
    (CHECK, "  letter-case        a tracked path whose name differs only in letter case from the one this check reads"),
    (CHECK, "Or a product package holds a version-specific manifest, a\n"),
    (CHECK, "(\"SEC-ZIPGUARD-03: a product package's version-specific manifest takes its target's path from the "
            "environment (the review's reproduction)\","),
    (CHECK, "('SEC-ZIPGUARD-03: a version-specific manifest named in another letter case, which SwiftPM takes too "
            "(package@Swift-6.swift)',"),
    (CHECK, "('a product root in another letter case (packages/), which the default macOS file system checks out into "
            "Packages/',"),
    (CHECK, "(\"a product package's manifest named package.swift, which SwiftPM opens as Package.swift\", 'letter-case',"),
    (CHECK, "('a product project named Project.yml, which XcodeGen opens as project.yml', 'letter-case',"),
    (CHECK, "(\"a spike package's manifest named PACKAGE.SWIFT, which the lock rules, reading every manifest, would "
            "not read\","),
    (CHECK, "('a module map named in another letter case (MODULE.MODULEMAP), which clang loads as module.modulemap, "
            "names a transitive public header',"),
    (CHECK, "('a private module map, which clang reads beside a module.map (module_private.map), names a transitive "
            "public header',"),
    (CHECK, "('a spike package keeps a version-specific manifest (spikes never ship), and product files whose names "
            "only begin like one (Package+Model.swift, PackageNotes.md, an image named Package@2x.png)',"),
    (CHECK, "('a product module map named in another letter case (Module.ModuleMap) that names its own header',"),
    (f"the check has 123 failure branches (it has {fail_sites(check)})", fail_sites(check) == 123),
    (f"the reproductions log has thirteen routes, each ok (it has {len(routes)}, {verdicts.count('ok (')} ok)",
     len(routes) == 13 and len(verdicts) == 13 and all(v == "ok (" for v in verdicts)),
    (REPRO, "  the unplanted copy, check before the fix: exit 0 -> dependency lock check: 0 failure(s), 0 warning(s)\n"),
    (REPRO, "  the unplanted copy, check after the fix: exit 0 -> dependency lock check: 0 failure(s), 0 warning(s)\n"),
    (REPRO, "it reports the test-only package in shipping code (1 test-in-product finding(s)), which it does not see "
            "without the variable"),
    (REPRO, "  6.4                                exit 0; files: Package.swift Package@swift-6.4.swift -> evaluates the "
            "one declaring Sources/Specific\n"),
    (REPRO, "  all-capitals                       exit 0; files: PACKAGE@SWIFT-6.4.SWIFT Package.swift -> evaluates the "
            "one declaring Sources/Specific\n"),
    (REPRO, "  7                                  exit 0; files: Package.swift Package@swift-7.swift -> evaluates the one "
            "declaring Sources/Regular\n"),
    (REPRO, "  lower-package.swift                exit 0; files: package.swift -> evaluates the one declaring "
            "Sources/Regular\n"),
    (REPRO, "  vsm-env, SYLVIA_EXTRA Sources/Elsewhere: exit 0; the SylviaDesign target: path Sources/Elsewhere,"),
    (REPRO, "  a package whose only manifest is package.swift: swift build exit 0; the tool prints: built from a "
            "manifest named package.swift\n"),
    (REPRO, "`xcodegen generate` run in it as sylvia_generate runs it: exit 0; it wrote: Probe.xcodeproj\n"),
    (REPRO, "the build phase the project gives it: Extra.SWIFT in Resources"),
    (REPRO, "  MODULE.MODULEMAP:                                  @import ProbeMod: exit 0 (read)\n"),
    (REPRO, "  module_private.map beside module.map:              @import OtherMod: exit 0 (read)\n"),
    (REPRO, "  swift build of the clone's Packages/P: exit 0; the tool prints: Shadow.swift, tracked as "
            "packages/P/Sources/P/Shadow.swift, was compiled\n"),
    (REPRO, "\nresult: every route as expected\n"),
], "the rules for version-specific manifests and names in another letter case, module maps by every name, the dump "
   "cache's key, eight mutations and two allowed changes, 123 failure branches, and the reproductions' thirteen routes "
   "and tools as expected")

# A: ADR-0014.
FIX = "*(Since 26 October 2026, the fourth review of the M0 exit preparation, SEC-ZIPGUARD-03"
group("A", [
    (A14, FIX + ", and the routes of the same kind found with its fix:)* a product package's only manifest is its "
                "`Package.swift`: no version-specific manifest is beside it"),
    (A14, "every name the check reads as it spells it is spelled so: no tracked path is under a product or spike root "
          "written in another case"),
    (A14, FIX + ":)* Or a product package holds a version-specific manifest, a file whose name begins with `Package@` "
                "and ends with `.swift`, in any letter case."),
    (A14, "  - *(Since 26 October 2026, found with the fix of SEC-ZIPGUARD-03: category `letter-case`.)* A tracked path "
          "whose first directory is a product or spike root in another letter case"),
    (A14, "- 291 mutated copies, each of which must be reported with its own category and message (283 until 26 "
          "October 2026, when the fix of the fourth review of the M0 exit preparation added eight"),
    (A14, "- 38 allowed changes (36 until 26 October 2026, when the fix of the fourth review of the M0 exit preparation "
          "added two"),
    (A14, "every one of the check's 123 failure branches (120 until the fix of the fourth review of the M0 exit "
          "preparation and 119 until the fix of the first, both on 26 October 2026,"),
    ("gone", A14, "- 283 mutated copies"), ("gone", A14, "- 36 allowed changes (35 until"),
    ("gone", A14, "every one of the check's 120 failure branches"),
    (A14, "- A file a tool reads under a name the check does not know."),
    (A14, "Until then this paragraph relied on a guard with those two routes around it.)*",
     " *(26 October 2026: that note did not hold for a version-specific manifest beside a product `Package.swift`"),
    (A14, "so a toolchain change that misses one of them fails.",
     " *(Since 26 October 2026, the fix of the fourth review of the M0 exit preparation, SEC-ZIPGUARD-03:)* a "
     "toolchain change also runs `Docs/Stage0/evidence/M0-ExitPrep/fix-2/commands/reproductions.sh` again"),
    (A14, "*(26 October 2026: a fourth agent review of the M0 exit preparation read the branch at `fcbd6c89`, and the "
          "workflow relayed one finding as the complete list, SEC-ZIPGUARD-03 (major)"),
    (A14, "**Amended on 26 October 2026 (25 October UTC) by an agent, at the fix of that review, on `m0-exit-prep`: a "
          "product package's only manifest is its `Package.swift`"),
    (A14, "- The fix of the fourth review of the M0 exit preparation (26 October 2026, SEC-ZIPGUARD-03), in "
          "`Docs/Stage0/evidence/M0-ExitPrep/fix-2/`"),
    (A14, "A product target that needs one of these is a reviewed change to the check, with a self-test case.",
     " *(Since 26 October 2026, SEC-ZIPGUARD-03:)* A product package has one manifest, its `Package.swift`"),
    (A14, "*(26 October 2026: its fourth review found another, a version-specific manifest beside a product "
          "`Package.swift`"),
], "rule 5, section 3 (manifest-input, letter-case, the counts, the limits), sections 5 and 6, the status line, "
   "Evidence, the consequence and the open item")

# D: the records of the finding.
gate = read(GATE)
row76 = next((line for line in gate.splitlines() if line.startswith("| 76 | ")), "")
group("D", [
    ("row 76 gives the route as answered, review pending, with what it said",
     "is answered by an agent's change since the fourth review named it (SEC-ZIPGUARD-03), review pending (Section "
     "6.3, items 113 and 125; until 26 October 2026 this clause said that the route is open and that no finding names "
     "it)" in row76),
    ("row 76 no longer gives the route as open", "one more route of R4-01's kind is open" not in row76),
    ("row 76 ends with this fix's note and its log of 12-dependency-lock",
     "the drop-in passes from a clean tree with a self-test of 291 mutations "
     "(`evidence/M0-ExitPrep/fix-2/12-dependency-lock.log`). The row stays failed until a review accepts the change: "
     "Section 6.3, item 125.)* | ADR-0014 status and section 3; integration log section 28 |" in row76),
    ("row 76 stays failed", row76.startswith("| 76 | Dependency lock: the CI guard that keeps marmelroy/Zip 2.1.2 "
                                             "(CVE-2023-39135) out of product code | failed |")),
    (GATE, "Until then this bullet's first note said done, with your sign-off as what remained: Section 6.3, item 119.)*",
     " *(26 October 2026: a fourth agent review read the branch at `fcbd6c89` and found one more route of the same "
     "kind"),
    (GATE, "the fix of that review answers the five, not reviewed: Section 6.3, items 119-124.)*",
     " *(26 October 2026: a fourth agent review read it at `fcbd6c89`, with the third fix, and raised one finding"),
    (GATE, "rule for local packages, every one passing (`evidence/M0-ExitPrep/fix-1/`).)*",
     " *(26 October 2026: and on the last documents commit of the fix of its fourth review"),
    (GATE, "both stay open here, and row 76 is failed again: Section 6.3, item 119.)*",
     " *(26 October 2026: a fourth agent review read the branch at `fcbd6c89` and found another route of the same "
     "kind"),
    (GATE, "(278 mutations; 283 since the fix of the exit preparation's review, item 111)",
     " *(26 October 2026: 291 since the fix of its fourth review, item 125)*"),
    (GATE, "(283 mutations; all 120 failure branches reached)",
     " *(26 October 2026: the counts of that fix; 291 mutations and all 123 branches since the fix of the fourth "
     "review"),
    (GATE, "and since the fix of that review they are 283 and 120, item 111)*",
     " *(26 October 2026: 291 and 123 since the fix of the fourth review of the M0 exit preparation, item 125)*"),
    (GATE, "none on that route, which stays with ADR-0014's owner and which row 76 now names: items 119-124.)*",
     " *(26 October 2026: a fourth read the branch at `fcbd6c89` and named that route, SEC-ZIPGUARD-03 (major)"),
    (GATE, "125. **A version-specific manifest, and names in another letter case** (SEC-ZIPGUARD-03, major)"),
    (GATE, "126. **Not reviewed**: this fix is agent-written; its checks, on its last commits, are in "
           "`evidence/M0-ExitPrep/fix-2/` (integration log section 34.4)."),
    (GATE, "- **The fix of the fourth review of the M0 exit preparation (26 October 2026; integration log section "
           "34).**"),
    (GATE, " *(26 October 2026: the fix of the fourth review of the M0 exit preparation, on `m0-exit-prep`, changed "
           "`Scripts/check-dependency-lock.py` outside `Docs/`, and nothing else;"),
    (CHECKER, '                   + adr_says(14, "a product package\'s only manifest is its `Package.swift`")\n'),
    (CHECKER, '"Docs/Stage0/evidence/M0-ExitPrep/fix-2/12-dependency-lock.log",\n'
              '                              "self-test: 291 mutations")'),
    (INDEX, "*(26 October 2026: a fourth read the branch at `fcbd6c89` and found that a version-specific manifest "
            "beside a product `Package.swift`"),
    (README, "*(26 October 2026: a fourth agent review read the branch at `fcbd6c89`, with the third fix, and raised one "
             "finding, major"),
    (LOG, "## 34. The fourth review of the M0 exit preparation, and its fix (26 October 2026)"),
    (LOG, "### 34.1 The finding, and what was done"), (LOG, "### 34.2 What this fix left as it was"),
    (LOG, "### 34.3 Commits"), (LOG, "### 34.4 Checks"), (LOG, "### 34.5 Not done here, and why"),
    (LOG, "as is the case today.", " *(Dated note, 26 October 2026: the fourth review of the M0 exit preparation named "
                                   "it, SEC-ZIPGUARD-03 (major)"),
    (LOG, "which the second review's findings, as relayed, do not mention and which stays with ADR-0014's owner.",
     " *(Dated note, 26 October 2026: named by the fourth review, SEC-ZIPGUARD-03, and answered by its fix, review "
     "pending: section 34.)*"),
    (LOG, "- **The route the first fix found and left open** (31.5), and the `--no-env` in `Scripts/lib/xcodegen.sh` "
          "(30.2): as they were.",
     " *(Dated note, 26 October 2026: the route since named by the fourth review"),
    (LOG, "which the third review's findings, as relayed, do not mention and which row 76 now names; and the `--no-env` "
          "in `Scripts/lib/xcodegen.sh` (30.2).",
     " *(Dated note, 26 October 2026: that route since named by the fourth review, SEC-ZIPGUARD-03"),
    (LOG, "and the thirteen `m0-int-*` branches (32.5): as they were.",
     " *(Dated note, 26 October 2026: the route since named by the fourth review"),
    (FIX1, "as is the case today.", " *(Dated note, 26 October 2026: the fourth review of the M0 exit preparation named "
                                    "it, SEC-ZIPGUARD-03 (major)"),
    (FIX2, "the second review's findings, as relayed, mention neither.",
     " *(Dated note, 26 October 2026: the route since named by the fourth review, SEC-ZIPGUARD-03"),
    (FIX3, "and the thirteen `m0-int-*` branches (32.5): as they were.",
     " *(Dated note, 26 October 2026: the route since named by the fourth review, SEC-ZIPGUARD-03"),
    (ZIP, "and found each route as committed.)*", " *(Dated note, 26 October 2026: a fourth agent review read the branch "
                                              "at `fcbd6c89` and found one more route of R4-01's kind"),
], "the gate summary (row 76, item 4, Section 1, Sections 2.10 and 6.1, the counts of items 105, 111 and 22, items "
   "113, 125 and 126, Section 8), its checker, the ADR index, the Stage 0 README, integration log section 34 and its "
   "notes on the route, and the evidence READMEs")

# R: the review's status.
state = next((line for line in gate.splitlines() if line.startswith("- **State:**")), "")
words = len(state.split())
s62 = section(gate, "### 6.2 Minor findings", "### 6.3 ")
rows = [line for line in s62.splitlines() if line.startswith("| ")]


def row_index(start):
    return next((i for i, r in enumerate(rows) if r.startswith(start)), -1)


first = row_index("| The review of the M0 exit preparation (26 October 2026, at `609ed492`")
second = row_index("| The second review of the M0 exit preparation (26 October 2026, at `83030fba`")
third = row_index("| The third review of the M0 exit preparation (26 October 2026, at `415ae25b`")
fourth = row_index("| The fourth review of the M0 exit preparation (26 October 2026, at `fcbd6c89`")
handover = row_index("| The thirteen M0 items' own final reviews |")
group("R", [
    (GATE, "have not been reviewed, nor has the fix of the fourth review of the M0 exit preparation (Sections 6.2 and "
           "8)."),
    ("gone", GATE, "nor has the fix of the third review of the M0 exit preparation (Sections 6.2 and 8)."),
    (f"the State line has {words} words (at most 200)", 0 < words <= 200),
    ("Section 6.2: the first review's row, the second's, the third's, the fourth's, then the hand-over's, the table's "
     "last", 0 <= first < second < third < fourth < handover == len(rows) - 1),
    (GATE, "that answer read by a fourth agent review the same day, at `fcbd6c89` (next row; until the fix of that "
           "review this cell said not reviewed) | integration log section 33 |"),
    (GATE, "with routes of the same kind it found in names written in another letter case (Section 6.3, items 125 and "
           "126); not reviewed | integration log section 34 |"),
    (GATE, "which the fix of that review answers (Section 6.3, items 119-124); that fix has not been reviewed.)*",
     " *(26 October 2026: a fourth agent review has read the branch since, at `fcbd6c89`"),
    (GATE, "*(Dated note, 26 October 2026: and a third time, with the second fix, at `415ae25b`: items 119-124.)*",
     " *(Dated note, 26 October 2026: and a fourth time, with the third fix, at `fcbd6c89`: items 125 and 126.)*"),
    (GATE, "which raised HON-EP-01 to HON-EP-05: items 119-124.)*",
     " *(Dated note, 26 October 2026: and by a fourth, at `fcbd6c89`, with the third fix: items 125 and 126.)*"),
    (GATE, "the evidence READMEs of the second fix, the first fix, the assembly, the Zip guard's fix and the hand-over's "
           "two.", " *(Dated note, 26 October 2026: read by a fourth agent review at `fcbd6c89`, which raised "
                   "SEC-ZIPGUARD-03: items 125 and 126.)*"),
    (GATE, "*(26 October 2026: and the fix of its third review, items 119-124)*",
     " *(26 October 2026: and the fix of its fourth review, items 125 and 126)*"),
    (GATE, "`evidence/M0-ExitPrep/fix-1/round-3/commands/gate-checks.sh`); not reviewed.",
     " *(26 October 2026: read by the fourth review of the M0 exit preparation, at `fcbd6c89`"),
    (GATE, "the fix of the third, section 33, has had none)*",
     " *(26 October 2026: a fourth read it at `fcbd6c89`, the third's fix with it; the fix of the fourth, section 34, "
     "has had none)*"),
    (RUNBOOK, "has not been reviewed: integration log section 33.)*",
     " *(26 October 2026: a fourth agent review read the branch at `fcbd6c89`;"),
    (LOG, "before any review had: sections 32 and 33.)*",
     " *(Dated note, 26 October 2026: a fourth read it at `fcbd6c89`"),
    (LOG, "the first fix's row 76 note among them: section 33.)*",
     " *(Dated note, 26 October 2026: and a fourth, at `fcbd6c89`"),
    (LOG, "at `415ae25b`: 32.5 and section 33.)*", " *(Dated note, 26 October 2026: and by a fourth, at `fcbd6c89`: "
                                                  "section 34.)*"),
    (LOG, "and raised HON-EP-01 to HON-EP-05 (section 33).)*", " *(Dated note, 26 October 2026: and a fourth, at "
                                                              "`fcbd6c89`, SEC-ZIPGUARD-03 (section 34).)*"),
    (LOG, "from `415ae25b`; agent-written, not reviewed, human sign-off pending.",
     " *(Dated note, 26 October 2026: read by a fourth agent review the same day, at `fcbd6c89`: 33.5 and section "
     "34.)*"),
    (LOG, "round 4's verdict on ADR-0014 stays on the record until a review accepts the change; human sign-off pending.",
     " *(Dated note, 26 October 2026: a fourth agent review read it the same day, at `fcbd6c89`, and raised "
     "SEC-ZIPGUARD-03 (section 34).)*"),
    (FIX3, "**It is agent-written and not reviewed.**", " *(Dated note, 26 October 2026: read since by a fourth agent "
                                                       "review of the M0 exit preparation, at `fcbd6c89`"),
    (FIX2, "(integration log section 33); the logs here are this fix's, as they ran.)*",
     " *(Dated note, 26 October 2026: and by a fourth, at `fcbd6c89`"),
    (FIX1, "(integration log section 33).)*", " *(Dated note, 26 October 2026: and by a fourth, at `fcbd6c89`"),
    (ASM, "(integration log section 33). The logs here are this assembly's, as they ran.)*",
     " *(Dated note, 26 October 2026: a fourth agent review read the branch at `fcbd6c89`;"),
    (REVIEWS, "is in `../fix-1/round-3/` (integration log section 33).)*",
     " *(Dated note, 26 October 2026: and by a fourth, at `fcbd6c89`"),
    (IREADME, "reworded by the fix of that review, not reviewed: integration log section 33.)*",
     " *(Dated note, 26 October 2026: and by a fourth, at `fcbd6c89`"),
], "the State line, Section 6.2, the notes after each text that gave the third fix as not reviewed, item 126, Section "
   "8's bullets and the evidence READMEs")

# C: the self-test's counts.
OLD = re.compile(r"283 mutat|283 and 120|36 allowed|120 failure|all 120|120 of (?:the )?120")
# The accounts of the first fix's runs as they ran, each with its reason; each must hold the count found.
ACCOUNTS = [
    (FIX1, "and one allowed change (a product package that depends on another by a path inside the roots, whose "
           "manifest git tracks): 283 mutations (278 before)", "the first fix's README, its account of its own change"),
    (FIX1, "the self-test with 283 mutations and the check of the repository", "the first fix's README, its log"),
    (LOG, "283 mutations, 36 allowed changes, all 120 failure branches reached.", "31.1, the first fix's account"),
    (LOG, "283 and 120 from this fix)", "31.1, the account of SEC-ZIPGUARD-02"),
    (LOG, "the self-test with 283 mutations, 36 allowed changes and all 120 failure branches reached;",
     "31.4, the first fix's checks as they ran"),
    (LOG, "its self-test with 283 mutations, ADR-0014 among the records it reads;",
     "32.4 and 33.4, the second and third fixes' checks as they ran"),
]
found, accounted, stray, used = 0, 0, [], set()
files = sorted((ROOT / "Docs").rglob("*.md")) + [ROOT / "README.md", ROOT / "CLAUDE.md"]
for f in files:
    if not f.is_file():
        continue
    rel = str(f.relative_to(ROOT))
    for n, line in enumerate(f.read_text(encoding="utf-8").split("\n"), 1):
        if not OLD.search(line):
            continue
        found += 1
        if "291" in line:
            continue
        hit = [i for i, (af, text, _) in enumerate(ACCOUNTS) if af == rel and text in line]
        if hit:
            accounted += 1
            used.update(hit)
        else:
            stray.append(f"{rel}:{n}: {OLD.search(line).group(0)}")
stale = [f"{ACCOUNTS[i][0]}: {ACCOUNTS[i][1][:70]}" for i in range(len(ACCOUNTS)) if i not in used]
group("C", [(f"every line giving the first fix's counts also gives 291, or is an account (not: {len(stray)}"
             + (f"; first: {stray[0]}" if stray else "") + ")", not stray),
            (f"every account still there ({len(stale)} not found" + (f"; first: {stale[0]}" if stale else "") + ")",
             not stale)],
      f"the counts over {len(files)} Markdown files: {found} lines give the first fix's counts or earlier ones, "
      f"{found - accounted - len(stray)} of them with 291 beside, {accounted} accounts of the runs as they ran")

print(f"result: {'pass' if problems == 0 else 'FAIL'} ({problems} of 5 groups not as stated)")
sys.exit(1 if problems else 0)
