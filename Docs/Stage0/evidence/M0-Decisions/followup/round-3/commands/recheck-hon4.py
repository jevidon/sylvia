#!/usr/bin/env python3
"""Checks the answers to the honesty findings of the review of the follow-up (the fourth agent review of the M0
decisions round; integration log section 22): the workflow relayed its honesty lens's six findings, HON4-01 to HON4-06,
to the follow-up's second fix of 23 October 2026, after the fidelity lens's eight (section 21). Each check reads the
texts its finding named and asserts what the second fix's answer (integration log 22.1) says is there now: the text the
finding faulted gone, or kept only inside a dated note that says what it was, and the answer's text present.

Two of the fidelity findings that the follow-up's fix answered are re-asserted here in this fix's wording, because this
fix rewrote texts their recheck (../../round-2/commands/recheck-review4.py) reads: FID4-02 (agent work goes into
m0-decisions, never straight into main), inside HON4-01's check, and FID4-06 (ADR-0014's approval is D-6's, the Zip
request the security reviewer's), inside HON4-02's. HON-11 is reported as it stands.

    python3 -I Docs/Stage0/evidence/M0-Decisions/followup/round-3/commands/recheck-hon4.py <repository root>

Run on the follow-up's own tree (git archive 19489f10, the commit the review read), it must report all six as not
answered, and on the follow-up's fix's tree (git archive 13d2b4c7, where this fix starts) all six too, since each
finding names a text that fix left: the gate checks of this round (gate-checks.sh beside this file) run both controls.
Read-only; standard library only; host only. Prints one line per finding and exits 1 if any of the six is not answered.
"""
import sys
from pathlib import Path

ROOT = Path(sys.argv[1])
problems = 0


def read(path):
    return (ROOT / path).read_text(encoding="utf-8")


def line_with(path, start):
    found = [line for line in read(path).splitlines() if line.startswith(start)]
    return found[0] if len(found) == 1 else ""


def report(finding, missing, what):
    global problems
    if missing:
        problems += 1
    print(f"{'answered' if not missing else 'PROBLEM '} {finding}: {what}" + (f" ({'; '.join(missing)})" if missing else ""))


def need(text, phrases, where):
    return [f"{where} lacks: {p}" for p in phrases if p not in text]


def gone(text, phrases, where):
    return [f"{where} still says: {p}" for p in phrases if p in text]


GATE = "Docs/Stage0/M0-gate.md"
RUNBOOK = "Docs/Stage0/M0-device-runbook.md"
PLAN = "Docs/Sylvia_v1_iOS_Implementation_Plan.md"
AMEND = "Docs/Stage0/M0-plan-amendments.md"
LOG = "Docs/Stage0/integration-log.md"
TPI = "Docs/Licenses/third-party-inventory.md"
A01 = "Docs/ADRs/0001-platform-baseline-and-toolchain.md"
A02 = "Docs/ADRs/0002-repository-build-and-ci.md"
A14 = "Docs/ADRs/0014-dependency-lock-and-license-inventory.md"
INDEX = "Docs/ADRs/README.md"
G06C = "Docs/Stage0/device-checklists/G06-Design.md"
SESSIONS = "Docs/Stage0/evidence/M0-runbook/sessions.md"

gate, runbook, plan, amend, log = read(GATE), read(RUNBOOK), read(PLAN), read(AMEND), read(LOG)
a02, a14 = read(A02), read(A14)

# HON4-01: H-1's exception covers pull requests #4 and #5 and the merge of m0-decisions, and no other merge; bringing
# agent work to main before the exit is a further merge the answer did not cover, for the owner to decide first, or the
# sessions build from m0-decisions until the exit. FID4-02's answer (agent work into m0-decisions) is kept.
m = gone(a02, ["The rule stays for every other milestone branch",
               "so that merge is made once the agent work the M0 exit waits for is in `m0-decisions`",
               "reaches `main` before the M0 exit only through `m0-decisions`"], "ADR-0002")
m += need(a02, ["before the M0 exit review the exception covers pull request #4, pull request #5 and this merge, and no "
                "other merge into `main`",
                "is merged into `m0-decisions`, never into `main` directly",
                "Bringing that work to `main` before the M0 exit is a further merge that the answer did not cover",
                "- Product owner: whether H-1's exception also covers bringing agent work started during the device "
                "sessions"], "ADR-0002")
m += gone(runbook, ["or by pull request for `main`), between sessions",
                    "or make the merge of `m0-decisions` into `main` only once the agent work the exit waits for is in "
                    "`m0-decisions`"], "the runbook")
m += need(runbook, ["Never merge it into `main`, or open a pull request of it into `main`, before the M0 exit",
                    "Bringing that work to `main` before the exit is a further merge that your answer did not cover",
                    "or build from `m0-decisions` until the exit",
                    "and no other merge: agent work goes into `m0-decisions`",
                    "and bringing it to `main` before the exit is a further merge your answer did not cover (0.3)"],
          "the runbook")
m += gone(gate, ["merge that branch into the branch you build from",
                 "or merge `m0-decisions` into `main` only once the agent work the exit waits for is in it"], "M0-gate.md")
m += need(gate, ["Never merge it, or a pull request of it, straight into `main` before the M0 exit",
                 "Bringing such work to `main` before the exit is a further merge your answer did not cover",
                 "the rule stays for every other merge",
                 "merge that branch into `m0-decisions`, never straight into `main` (item 1)",
                 "bringing it on to `main` before the exit is a further merge your answer did not cover (item 1)"],
          "M0-gate.md")
m += need(line_with(SESSIONS, "| 1 | Before the sessions"),
          ["and on to `main` before the exit only if you first say that H-1's exception covers that"], "the session log's row 1")
m += gone(read(INDEX), ["agent work reaches `main` before the exit only through that merge (since the follow-up's fix"],
          "the ADR index")
report("HON4-01", m, "ADR-0002 keeps the rule with only pull requests #4 and #5 and the merge of m0-decisions excepted, "
       "and asks the owner whether bringing agent work to main before the exit is covered; the runbook, the gate "
       "summary and the session log route that work through m0-decisions and call that a further merge")

# HON4-02: Session 10's review can approve ADR-0014 without waiting for the lawyer's review; whether it does is not
# settled. FID4-06's answer (the approval is D-6's; the Zip request goes with the security sign-off) is kept.
m = gone(gate, ["the exit review approves ADR-0014 with the lawyer's review",
                "ADR-0014 is approved once Session 10's review of it is recorded, with your security sign-off",
                "as items for the public-release gate",
                "or for the answers to the requests below, which stay open until before any public App Store release"],
         "M0-gate.md")
m += need(gate, ["Session 10's review can approve ADR-0014 without waiting for it",
                 "the fourth, to drop marmelroy/Zip, goes with your security sign-off in Session 10",
                 "Whether that review approves ADR-0014 is not settled",
                 "The fourth is not part of that answer"], "M0-gate.md item 4")
m += gone(runbook, ["so the exit review approves ADR-0014 with that review",
                    "so ADR-0014's approval, once Session 10's review of it and your security sign-off are recorded (D-6), "
                    "need not wait"], "the runbook")
m += need(runbook, ["so Session 10's review can approve ADR-0014 without waiting for that review",
                    "Whether it approves ADR-0014 is not settled"], "the runbook's exit review")
m += gone(a14, ["the exit review approves this record with that review open",
                "this record's approval, once Session 10's review of it and the security sign-off are recorded (D-6), "
                "need not wait for that review"], "ADR-0014")
m += need(a14, ["Session 10's review can approve this record without waiting for that review",
                "Whether it does is not settled"], "ADR-0014's open item")
m += need(line_with(LOG, "| OWN3-02:"), ["section 22, HON4-02"], "integration log 20.2's OWN3-02 row")
report("HON4-02", m, "the gate summary, the runbook and ADR-0014 say that Session 10's review can approve ADR-0014 "
       "without waiting for the lawyer's review, not that it does; item 4 sets the Zip request apart; the log's "
       "OWN3-02 row has its dated note")

# HON4-03: the iPad is checked before Session 0 (FID4-03), and its fitness is said to be unverified until then.
m = gone(read(A01), ["on iPadOS 26.x or 27.x as it has."], "ADR-0001")
m += need(read(A01), ["until then whether it can run the iPad's steps is not verified"], "ADR-0001's Test devices")
line_c = line_with(G06C, "- **C. An iPad**")
if not line_c.startswith("- **C. An iPad** (any model that runs iPadOS 26.x or 27.x)"):
    m.append("the G0.6 checklist's line C does not state the iPadOS as a requirement")
m += need(line_c, ["Until that check and the record of Session 0.4, whether it can run these steps is not verified."],
          "the G0.6 checklist's line C")
m += gone(plan, ["(23 October 2026; ADR-0001), so no device has to be acquired"], "the plan")
m += need(plan, ["no device has to be acquired if that iPad runs iPadOS 26 or later"], "plan 21.1")
m += need(runbook, ["**Before Session 0, check that it runs iPadOS 26**",
                    "so whether it can run Session 9 is not verified until you have checked it as below and Session 0.4 "
                    "has recorded it",
                    "and until that check and that record whether it can run Session 9 is not verified",
                    "For the iPad, that record is what shows whether it can run Session 9"], "the runbook")
m += need(gate, ["Check it as device A: it must run iPadOS 26",
                 "whether it can run Session 9 is not verified until you have checked it and Session 0.4 has recorded it"],
          "M0-gate.md item 1")
m += need(line_with(SESSIONS, "| 1 | Before the sessions"), ["(whether it can run Session 9 is not verified until then"],
          "the session log's row 1")
report("HON4-03", m, "ADR-0001, the G0.6 checklist, the runbook (1.1, run 1, 0.4), item 1 and the session log say that "
       "the iPad's fitness for Session 9 is unverified until it is checked and recorded; plan 21.1 makes 'no device to "
       "acquire' depend on that check")

# HON4-04: no item of the decision page is open, and the decisions still the owner's are listed.
m = gone(gate, ["It waits on no decision of yours"], "M0-gate.md")
m += need(gate, ["M0 cannot be approved yet. No item of the M0 decision page is open",
                 "**M0 cannot be approved yet. No item of the M0 decision page is open",
                 "Decisions are still yours beyond the page, among them, in Session 10",
                 "the G0.2 report's open questions 5-7",
                 "the review of the follow-up, its finding HON4-04, item 69"], "M0-gate.md Sections 1, 6.3 and 7")
report("HON4-04", m, "Sections 1 and 7 say that no item of the decision page is open, not that M0 waits on no "
       "decision; Section 1 lists the decisions still the owner's; item 41 has its dated note")

# HON4-05: PO-42 is the owner's for now, not decided; the advertising clauses are quoted, their reach left to the
# lawyer's review.
paraphrase = "bind only advertising material that mentions the companion's features"
m = gone(log, ["the owner decided all three that day"], "integration log 15.1")
m += need(log, ["and took PO-42 on for now, with PO-41, PO-43 and PO-44"], "integration log 15.1")
m += gone(amend, ["You decided them on 23 October 2026",
                  "stayed open until the product owner decided them on 23 October 2026"], "the amendments")
m += need(amend, ["On 23 October 2026 you decided the first two, set aside and recovered, and took PO-42 on for now"],
          "the amendments' header")
po42 = line_with(AMEND, "| PO-42 |")
m += gone(po42, ["the recommended default applies to your own and TestFlight builds"], "the amendments' PO-42 row")
m += need(po42, ["but not decided: your answer applies the recommended defaults to your own and TestFlight builds"],
          "the amendments' PO-42 row")
m += gone(gate, ["stayed open until you decided them", paraphrase], "M0-gate.md")
m += need(gate, ["its own question staying open for the lawyer's review",
                 "PO-42's own question, which no default answers, stays open for that review",
                 "**23 October 2026: yours for now**, with PO-41, PO-43 and PO-44, but not decided",
                 "All advertising materials mentioning features or use of this software"], "M0-gate.md")
m += gone(a14, [paraphrase], "ADR-0014")
m += need(a14, ["so the answer decides neither option",
                "All advertising materials mentioning features or use of this software"], "ADR-0014 item 2")
tpi = read(TPI)
m += gone(tpi, ["in advertising material that mentions the companion's features or use"], "the third-party inventory")
m += need(tpi, ["the advertising clauses had no recommended default, so their question stays open for that review"],
          "the third-party inventory")
report("HON4-05", m, "integration log 15.1, the amendments, the gate summary and ADR-0014 record PO-42 as the owner's "
       "for now, its question open; item 4, ADR-0014 and the third-party inventory quote the licenses' clause 3")

# HON4-06: the two READMEs say what was relayed and recorded; the ADR index's column is dated 23 October 2026.
readme = read("README.md")
stage0 = read("Docs/Stage0/README.md")
m = gone(readme, ["this merge before the M0 exit review, which approves nothing"], "README.md")
m += need(readme, ["M0 decisions of 22 October 2026 and of the owner's answers of 23 October 2026"], "README.md")
m += gone(stage0, ["of the second fix, raised six more, which a follow-up answered"], "the Stage 0 README")
m += need(stage0, ["raised six more in its owner-readability lens, the only findings of it that were relayed",
                   "and six in its honesty lens, which a second fix of the follow-up answered"], "the Stage 0 README")
m += need(read(INDEX), ["| ADR | Title | Status (23 October 2026) | Owner during Stage 0 |"], "the ADR index")
report("HON4-06", m, "the README names the answers of 23 October 2026 on m0-decisions; the Stage 0 README says which "
       "lenses' findings were relayed; the ADR index's column is dated 23 October 2026")

# HON-11: reported as it stands (left for the owner; no agent changes CLAUDE.md on a workflow's request).
stale = "are combined on `m0-integrate`" in read("CLAUDE.md")
print(f"{'open    ' if stale else 'changed '} HON-11: CLAUDE.md's milestone paragraph "
      + ("still says the M0 work is combined on `m0-integrate`: left for the product owner, in M0-gate.md Section 1, "
         "item 1" if stale else "no longer says the M0 work is combined on `m0-integrate`"))

print(f"result: {'pass' if problems == 0 else 'FAIL'} ({problems} of the six not answered)")
sys.exit(1 if problems else 0)
