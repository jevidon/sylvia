#!/usr/bin/env python3
"""m0-records-update (26 October 2026; integration log section 41): a copy of
Docs/Stage0/evidence/M0-Integration/commands/gate-refresh-check.py, as committed at c3adae68 and unchanged since, with
one difference: row 76 (below) expects passed-host, since the review of m0-exit-prep accepted the Zip guard's change at
c3adae68 (its security lens, third round, as relayed), and reads ADR-0014's status line and the drop-in's log on
m0-records-update for it. The old version, run on the same tree, reports exactly row 76, by design.

Checks behind the 19 October 2026 refresh of Docs/Stage0/M0-gate.md (run by gate-refresh-checks.sh), since the M0
final fix of the same day behind its update (run by final-fix/commands/gate-final-checks.sh), since the fix's second
round of 20 October 2026 behind that round's update (run by final-fix-2/commands/gate-final-checks.sh; rows 75 and 90
read that round's complete run, ci-full-clean-run-final.log, and the first round's, moved to final-fix/), and since the
toolchain re-pin round of 20 October 2026 behind its update (run by repin-27.1/commands/gate-repin-checks.sh): row 75
reads the dependency lock drop-in under the new pin, and rows 66, 78 and 82 ADR-0001's new status line; and since the
fix of that round's review, the same day, behind its update (run by repin-27.1/round-2/commands/gate-checks.sh): row
75 also reads the drop-in's run on that fix's last documents commit, whose toolchain line now quotes the whole build
line it compared. Run by an earlier round's script on a later commit, it checks the later documents against these
facts.

1. Every backticked path in the summary exists: paths are taken relative to Docs/Stage0/ first, then to the
   repository root. Bare names (no slash) are checked only when they end in .md. Tokens with spaces, wildcards,
   braces, angle brackets, '$', '=', '#' or ':' are not paths and are skipped, and so are slash-bearing names that
   are neither under a repository folder nor end in a file extension (a package such as readium/ZIPFoundation).
2. Section 2's numbered rows: each status is one of the six allowed values, the numbers run 1, 2, 3, ... without a
   gap, and the count of each status is printed.
3. Every row that cites a gate report (ROWS below) is compared with the status cell of each report row it cites.
   A report row is found by its first cell (equal to the key, or starting with it) in a table whose header has a
   Status column; it must be found exactly once. The report's status cell, stripped of bold markers, must begin with
   the summary row's status, or, for the two compound cells of G0.4 rows 21 and 33, contain it as a word.
4. Every ADR and deliverable row (FACTS below) is compared with the ADR status lines or CI log lines it rests on.
5. Rows 67-70 and 81 are judgements on the plan's text and on the other rows: listed as not checked mechanically.
   Every Section 2 row must be in exactly one of ROWS, FACTS and NOT_CHECKED.

Standard library only; reads files and writes nothing. Exit status 1 on any problem.
    python3 -I gate-refresh-check.py <repository root>
"""
import pathlib
import re
import sys

ROOT = pathlib.Path(sys.argv[1]).resolve()
STAGE0 = ROOT / "Docs/Stage0"
DOC = STAGE0 / "M0-gate.md"
ADRS = ROOT / "Docs/ADRs"
ALLOWED = {"passed-host", "passed-simulator", "failed", "partial", "pending-device", "pending-human"}
PREFIXES = ("evidence/", "device-checklists/", "Docs/", "Spikes/", "Contracts/", "Scripts/", "Packages/", "Apps/",
            "Fixtures/", ".github/")
EXTS = (".md", ".log", ".txt", ".json", ".tsv", ".png", ".sh", ".yml", ".yaml", ".py", ".resolved", ".swift",
        ".sqlite")

# Summary row -> the gate report rows it cites: (report, key, how the key matches the first cell, how the status
# must appear in the report's status cell, the status token; None means the summary row's own status).
ID, PREFIX, STARTS, CONTAINS = "id", "prefix", "starts", "contains"
def r(report, key, mode=ID, match=STARTS, token=None):
    return (report, key, mode, match, token)

E, P, T2, T3, A4, AI, RC, D6 = ("G01-EPUB.md", "G01-PDF.md", "G02-Transfer.md", "G03-Intake.md", "G04-Audio.md",
                                "G05-AI.md", "G05-Recovery.md", "G06-Design.md")
ROWS = {
    1: [r(E, "G1")], 2: [r(E, "G2")], 3: [r(E, "G3")], 4: [r(E, "G4")], 5: [r(E, "G5")], 6: [r(E, "G6")],
    7: [r(E, "G7")], 11: [r(E, "G8")], 12: [r(E, "G9")], 13: [r(E, "G10")],
    8: [r(P, "1")], 9: [r(P, "2")], 10: [r(P, "10c")],
    14: [r(T2, "User-mediated trust bootstrap from iOS", PREFIX)],
    15: [r(T2, "User-mediated trust bootstrap on a physical iPhone over Wi-Fi", PREFIX)],
    16: [r(T2, "Certificate pinning on iOS", PREFIX)],
    17: [r(T2, "Authorized ranged downloads with verified parts", PREFIX)],
    18: [r(T2, "Recovery after suspension or force-quit", PREFIX)],
    19: [r(T2, "Mac source mutation never yields a mixed-version file", PREFIX)],
    20: [r(T2, "Manual-address connectivity: IPv4 and IPv6 loopback", PREFIX)],
    21: [r(T2, "Plan 15.2 Stage 0 gate, local address forms", PREFIX)],
    22: [r(T2, "Plan 15.2 Stage 0 gate, Tailscale address forms", PREFIX),
         r(T2, "T43 Tailscale address and MagicDNS name on iOS without an ATS exception", PREFIX)],
    23: [r(T2, "Manual-address and Tailscale connectivity between a phone and the Mac", PREFIX)],
    24: [r(T2, "Security reviewer approves the pairing protocol", PREFIX)],
    25: [r(T2, "No trust-all path, no ATS exception in the harness, TLS 1.2 minimum", PREFIX)],
    26: [r(T3, "G1")], 27: [r(T3, "G2")], 28: [r(T3, "G6")], 29: [r(T3, "G3")], 30: [r(T3, "G4")],
    31: [r(T3, "G5")], 32: [r(T3, "G7")], 33: [r(T3, "G8")], 34: [r(T3, "T42")], 35: [r(T3, "G9")],
    36: [r(T3, "G10")],
    37: [r(A4, "1")], 38: [r(A4, "2")], 39: [r(A4, "3"), r(A4, "11")], 40: [r(A4, "12")],
    41: [r(A4, "21", ID, CONTAINS, "passed-simulator")],
    42: [r(A4, "21", ID, CONTAINS, "failed"), r(A4, "33", ID, CONTAINS, "failed")],
    43: [r(A4, "4")], 44: [r(A4, "5")], 45: [r(A4, "6")], 46: [r(A4, "7")], 47: [r(A4, "8")],
    48: [r(A4, "18")], 49: [r(A4, "19")], 50: [r(A4, "9")],
    51: [r(AI, "G1")], 52: [r(AI, "G2")], 53: [r(AI, "G3")], 54: [r(AI, "G4")], 58: [r(AI, "G6")],
    55: [r(RC, "1")], 56: [r(RC, "22")], 57: [r(RC, "2")], 59: [r(RC, "23")],
    60: [r(D6, "G0.6: SylviaDesign package at v0.1 from Section 4.4", PREFIX)],
    61: [r(D6, "G0.6: every token pair's contrast verified", PREFIX)],
    62: [r(D6, "G0.6: type roles under Dynamic Type", PREFIX)],
    63: [r(D6, "Scaling through UIFontMetrics as Section 4.4.3 specifies", PREFIX)],
    64: [r(D6, "G0.6: component set viewed on a device", PREFIX)],
    65: [r(D6, "G0.6: token values adjusted where devices disagree", PREFIX)],
    72: [r(D6, "CI drop-in `Scripts/ci.d/21-design-catalog.sh`", PREFIX)],
    73: [r(D6, "Prototype matches the boards where they agree with Section 4.4", PREFIX)],
    74: [r(D6, "G0.6 device review of the component set and the prototype", PREFIX)],
    79: [r(D6, "G0.6: SylviaDesign package at v0.1 from Section 4.4", PREFIX)],
    80: [r(D6, "Design review of the components and references", PREFIX)],
    91: [r(D6, "Token export with schema, fixtures", PREFIX)],
}

ADR_FILES = {n: next(ADRS.glob(f"{n:04d}-*.md")) for n in range(1, 17)}
def adr_status(n):
    for line in ADR_FILES[n].read_text(encoding="utf-8").splitlines():
        if line.startswith("- **Status:**"):
            return line[len("- **Status:**"):].strip()
    return ""
def adr_proposed(*numbers):
    return [(f"ADR-{n:04d} status begins 'Proposed'", lambda n=n: adr_status(n).startswith("Proposed")) for n in numbers]
def adr_says(n, *phrases):
    return [(f"ADR-{n:04d} status says '{p}'", lambda n=n, p=p: p in adr_status(n)) for p in phrases]
def log_has(name, text):
    path = STAGE0 / "evidence/M0-Integration" / name
    return [(f"{name} has '{text.replace(chr(10), ' / ')}'", lambda: text in path.read_text(encoding="utf-8"))]
def file_has(path, text):
    return [(f"{path} has '{text}'", lambda: text in (ROOT / path).read_text(encoding="utf-8"))]

ALL_ADRS_PENDING = (adr_says(1, "technical-lead confirmation pending the M0 gate") + adr_says(2, "pending")
                    + adr_proposed(*range(3, 17)))
FACTS = {
    66: ("pending-human", ALL_ADRS_PENDING),
    71: ("pending-human", adr_proposed(15) + adr_says(15, "human sign-off pending")),
    # Row 75 (final review R1-07): passed-host under Xcode 27.0 at efc9479; on the build Mac's Xcode 27.1 the drop-in
    # failed its toolchain check, and only that, in both complete runs of the M0 final fix (the first round's, final-fix/,
    # and the second round's, ci-full-clean-run-final.log and final-fix-2/), so the row was partial until PO-35 was
    # decided. Since the re-pin to 27.1 (20 October 2026) the drop-in passes, its toolchain check included, and the row
    # is passed-host again: repin-27.1/12-dependency-lock.log, with the run before the pins changed as its control. Since
    # the fix of that round's review (TC-02, TC-08) the check compares the whole build line and every record of the pin,
    # and passed on that fix's last documents commit: repin-27.1/round-2/12-dependency-lock.log.
    75: ("passed-host", log_has("ci-full-clean-run-assembled.log", "==> 12-dependency-lock\n    pass")
                    + log_has("ci-documents-final.log", "==> 12-dependency-lock\n    pass")
                    + log_has("final-fix/ci-full-clean-run-final.log", "==> 12-dependency-lock\n    FAIL")
                    + log_has("final-fix/ci-logs/12-dependency-lock.log",
                              "FAIL toolchain xcodebuild -version: expected 'Build version 27A266a', got 'Xcode 27.1'\n")
                    + log_has("final-fix/ci-logs/12-dependency-lock.log", "dependency lock check: 1 failure(s)")
                    + log_has("ci-full-clean-run-final.log", "==> 12-dependency-lock\n    FAIL")
                    + log_has("final-fix-2/ci-logs/12-dependency-lock.log",
                              "FAIL toolchain xcodebuild -version: expected 'Build version 27A266a', got 'Xcode 27.1'\n")
                    + log_has("final-fix-2/ci-logs/12-dependency-lock.log", "dependency lock check: 1 failure(s)")
                    + log_has("repin-27.1/12-dependency-lock-before.log",
                              "FAIL toolchain xcodebuild -version: expected 'Build version 27A266a', got 'Xcode 27.1'\n")
                    + log_has("repin-27.1/12-dependency-lock-before.log", "FAIL lines in its output: 1\n")
                    + log_has("repin-27.1/12-dependency-lock.log", "toolchain: xcodebuild -version -> Build version 27A9275")
                    + log_has("repin-27.1/12-dependency-lock.log", "dependency lock check: 0 failure(s)")
                    + log_has("repin-27.1/12-dependency-lock.log", "12-dependency-lock exit status: 0\n")
                    + log_has("repin-27.1/round-2/12-dependency-lock.log",
                              "toolchain: xcodebuild -version -> Build version 27A9275 (the pin, compared whole)")
                    + log_has("repin-27.1/round-2/12-dependency-lock.log",
                              "toolchain: the Xcode pin 27.1 (27A9275) as stated in .github/workflows/ci.yml, CLAUDE.md, "
                              "Docs/ADRs/0001-platform-baseline-and-toolchain.md")
                    + log_has("repin-27.1/round-2/12-dependency-lock.log", "dependency lock check: 0 failure(s)")
                    + log_has("repin-27.1/round-2/12-dependency-lock.log", "12-dependency-lock exit status: 0\n")),
    # Row 76: failed on round 4's verdict, reject, with R4-01 and R4-02 open. Before 24 October 2026 this entry read
    # ("failed", adr_says(14, "reject", "R4-01", "R4-02")). From the M0 exit preparation of 24 October 2026 until its
    # third review, 26 October 2026, it expected passed-host, as the agent that changed the guard (m0-exit-zipguard,
    # 6cd842d3) asked (integration log 30.2), on ADR-0014's status saying that R4-01 and R4-02 are closed in the guard:
    # ("passed-host", adr_says(14, "R4-01 and R4-02 are closed in the guard") with the four facts on the guard's logs
    # below, and from the fix of the first review (SEC-ZIPGUARD-01; integration log section 31) also the fact on its
    # rule for local packages, below). Since the third review (HON-EP-01; integration log section 33) it expects failed
    # again: closing R4-01 and R4-02 is an agent's change to the guard with an agent review that accepts it (M0-gate.md
    # Section 1, item 4), no review has accepted the change, as ADR-0014's status now says, and that status must no
    # longer say that they are closed in the guard. The guard's logs, which the row cites, are read as before: they show
    # that the change exists and passes, which is not what the row waits for. Since the fix of the fourth review
    # (SEC-ZIPGUARD-03; integration log section 34) it also reads ADR-0014's status on that fix and the fix's log of
    # 12-dependency-lock, which the row cites; the row stays failed, that fix awaiting a review like the change.
    # m0-records-update, 26 October 2026 (integration log section 41): R4-01 and R4-02 are closed, the change accepted by
    # an agent review (the review of m0-exit-prep at c3adae68, its security lens in its third round, as relayed), so the
    # row expects passed-host, on ADR-0014's status saying so, with the guard's logs as before and the drop-in's log on
    # this branch, which reads the owner's lock for Spikes/G05-Recovery/DeviceTests too. Until then: ("failed", ...), on
    # ADR-0014's status saying "No review has accepted that change" and not that R4-01 and R4-02 are closed in the guard.
    76: ("passed-host", adr_says(14, "R4-01 and R4-02 are closed in the guard",
                                 "its security lens, in its third round, accepted the change")
                   + adr_says(14, "a local package inside the product roots must be one git tracks there")
                   + adr_says(14, "a product package's only manifest is its `Package.swift`")
                   + file_has("Docs/Stage0/evidence/M0-RecordsUpdate/checks/12-dependency-lock.log",
                              "dependency lock check: 0 failure(s)")
                   + file_has("Docs/Stage0/evidence/M0-RecordsUpdate/checks/12-dependency-lock.log",
                              "self-test: 291 mutations")
                   + file_has("Docs/Stage0/evidence/M0-ExitPrep/fix-2/12-dependency-lock.log",
                              "dependency lock check: 0 failure(s)")
                   + file_has("Docs/Stage0/evidence/M0-ExitPrep/fix-2/12-dependency-lock.log",
                              "self-test: 291 mutations")
                   + file_has("Docs/Stage0/evidence/M0-ExitPrep/fix-1/12-dependency-lock.log",
                              "dependency lock check: 0 failure(s)")
                   + file_has("Docs/Stage0/evidence/M0-ExitPrep/fix-1/12-dependency-lock.log",
                              "self-test: 283 mutations")
                   + file_has("Docs/Stage0/evidence/M0-ExitPrep/zipguard/ci-2/12-dependency-lock.log",
                              "dependency lock check: 0 failure(s)")
                   + file_has("Docs/Stage0/evidence/M0-ExitPrep/zipguard/ci-2/12-dependency-lock.log",
                              "self-test: 278 mutations")),
    77: ("pending-human", file_has("Docs/ADRs/0014-dependency-lock-and-license-inventory.md",
                                   "### 7. Decisions that need a person (pending-human)")),
    78: ("pending-human", ALL_ADRS_PENDING),
    82: ("pending-human", adr_says(1, "Toolchain pin: Xcode 27.1 (27A9275), decided by the product owner on 20 October 2026")
                          + adr_says(1, "technical-lead confirmation pending the M0 gate")),
    83: ("pending-human", adr_proposed(3)),
    84: ("pending-human", adr_proposed(4, 5)),
    85: ("pending-human", adr_proposed(6)),
    86: ("pending-human", adr_proposed(8, 9)),
    87: ("pending-human", adr_proposed(11)),
    88: ("pending-human", adr_proposed(12)),
    89: ("pending-human", adr_proposed(13)),
    90: ("passed-host", log_has("ci-full-clean-run-assembled.log", "==> 10-contracts\n    pass")
                        + log_has("ci-full-clean-run-assembled.log", "==> 11-capture-anchor-contracts\n    pass")
                        + log_has("final-fix/ci-full-clean-run-final.log", "==> 10-contracts\n    pass")
                        + log_has("final-fix/ci-full-clean-run-final.log", "==> 11-capture-anchor-contracts\n    pass")
                        + log_has("final-fix/ci-logs/10-contracts.log", "schemas: 18  fixtures: 655")
                        + log_has("ci-full-clean-run-final.log", "==> 10-contracts\n    pass")
                        + log_has("ci-full-clean-run-final.log", "==> 11-capture-anchor-contracts\n    pass")
                        + log_has("final-fix-2/ci-logs/10-contracts.log", "schemas: 18  fixtures: 657")),
    92: ("pending-human", adr_says(2, "pending") + adr_proposed(7, 10, 14, 15, 16)),
}
NOT_CHECKED = {
    67: "the Section 23 decisions are signed by people; nothing to read",
    68: "a judgement for the exit review",
    69: "a judgement on the amendments' text against the four gates with failed rows",
    70: "summarises rows 1-65",
    81: "an exit demonstration by people",
}

problems = 0
def problem(message):
    global problems
    problems += 1
    print("PROBLEM: " + message)

text = DOC.read_text(encoding="utf-8")

# 1. Paths.
checked = 0
for token in sorted(set(re.findall(r"`([^`\n]+)`", text))):
    if any(c in token for c in " *{}<>$=#:"):
        continue
    if "/" not in token:
        if not token.endswith(".md"):
            continue
    elif not (token.endswith(EXTS) or token.startswith(PREFIXES)):
        continue
    checked += 1
    if not any(c.exists() for c in (STAGE0 / token, ROOT / token)):
        problem(f"missing path: {token}")
print(f"== paths: {checked} checked")

# 2. Section 2 rows.
def split_cells(line):
    return [c.strip() for c in re.split(r"(?<!\\)\|", line.strip().strip("|"))]

rows = {}
in_section_2 = False
for line in text.splitlines():
    if line.startswith("## "):
        in_section_2 = line.startswith("## 2.")
    if not in_section_2 or not line.startswith("| "):
        continue
    cells = split_cells(line)
    if not cells[0].isdigit():
        continue
    number = int(cells[0])
    if number in rows:
        problem(f"row {number} appears twice")
    rows[number] = cells
numbers = sorted(rows)
if numbers != list(range(1, len(numbers) + 1)):
    problem(f"row numbers are not 1..{len(numbers)} without gaps")
counts = {}
for n in numbers:
    status = rows[n][2]
    if status not in ALLOWED:
        problem(f"row {n}: status '{status}' is not an allowed value")
    counts[status] = counts.get(status, 0) + 1
covered = set(ROWS) | set(FACTS) | set(NOT_CHECKED)
for n in numbers:
    kinds = (n in ROWS) + (n in FACTS) + (n in NOT_CHECKED)
    if kinds != 1:
        problem(f"row {n} is in {kinds} of ROWS, FACTS and NOT_CHECKED (must be exactly one)")
for n in sorted(covered - set(numbers)):
    problem(f"the check names row {n}, which the summary does not have")

# 3. Gate report rows.
def status_tables(report):
    """Yield (status column index, cells) for every data row of every table whose header has a Status column."""
    lines = (STAGE0 / report).read_text(encoding="utf-8").splitlines()
    i = 0
    while i < len(lines):
        if lines[i].startswith("|") and i + 1 < len(lines) and re.match(r"^\|(\s*:?-{3,}:?\s*\|)+\s*$", lines[i + 1]):
            header = split_cells(lines[i])
            column = header.index("Status") if "Status" in header else None
            i += 2
            while i < len(lines) and lines[i].startswith("|"):
                if column is not None:
                    yield column, split_cells(lines[i])
                i += 1
        else:
            i += 1

print("== gate report rows")
gate_checked = 0
for n in sorted(ROWS):
    if n not in rows:
        continue
    own = rows[n][2]
    for report, key, mode, match, token in ROWS[n]:
        token = token or own
        found = [(col, cells) for col, cells in status_tables(report)
                 if (cells[0] == key if mode == ID else cells[0].startswith(key))]
        if len(found) != 1:
            problem(f"row {n}: {report} row '{key}' found {len(found)} times in tables with a Status column")
            continue
        col, cells = found[0]
        cell = cells[col].replace("**", "").strip()
        if match == STARTS:
            present = cell.startswith(token)
        else:
            present = re.search(r"(?<![\w-])" + re.escape(token) + r"(?![\w-])", cell) is not None
        agree = present and token == own
        gate_checked += 1
        shown = cell if len(cell) <= 70 else cell[:67] + "..."
        print(f"row {n}: {own} | {report} {key[:48]}: '{shown}' -> {'agrees' if agree else 'DISAGREES'}")
        if not agree:
            problem(f"row {n}: status {own} does not match {report} row '{key}' ({cell[:80]})")

# 4. ADR and deliverable rows.
print("== ADR and deliverable rows")
fact_checked = 0
for n in sorted(FACTS):
    if n not in rows:
        continue
    expected, checks = FACTS[n]
    own = rows[n][2]
    results = []
    for label, test in checks:
        try:
            ok = bool(test())
        except OSError as e:
            ok = False
            label += f" ({e})"
        results.append(ok)
        fact_checked += 1
        if not ok:
            problem(f"row {n}: {label}: not so")
    agree = own == expected and all(results)
    print(f"row {n}: {own} | expected {expected}; {sum(results)} of {len(results)} facts hold -> "
          f"{'agrees' if agree else 'DISAGREES'}")
    if own != expected:
        problem(f"row {n}: status {own}, but its record gives {expected}")

print("== rows not checked mechanically")
for n in sorted(NOT_CHECKED):
    if n in rows:
        print(f"row {n}: {rows[n][2]} | {NOT_CHECKED[n]}")

print(f"== summary: {len(numbers)} rows; " + ", ".join(f"{k} {counts[k]}" for k in sorted(counts))
      + f"; {gate_checked} report rows and {fact_checked} ADR and log facts compared; {problems} problem(s)")
sys.exit(1 if problems else 0)
