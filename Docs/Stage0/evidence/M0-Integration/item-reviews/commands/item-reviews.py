#!/usr/bin/env python3
"""The thirteen M0 items' review records, handed over on 24 October 2026: render and check them.

The records are the structured results that the workflow agents of the M0 items (integration log section 7.1) returned:
each item's author, its reviews (review-N; review-Nb is a second review of the same commit through another lens) and
its fixes (fix-N, after review N). They were extracted from the orchestrating session's workflow journals into one JSON
file per item and SUMMARY.json, and are committed unchanged in ../extracted/ (each named <file>.json.txt: see the
README for why). This script reads only those files, the repository's git objects and the documents it names; it
writes only the Markdown files of ../ (render) and its own standard output.

  python3 -I Docs/Stage0/evidence/M0-Integration/item-reviews/commands/item-reviews.py render
      writes ../<item>.md for each of the thirteen items from ../extracted/<item>.json.txt
  python3 -I .../item-reviews.py render --check
      renders in memory and compares with the committed ../<item>.md (exit 1 on any difference)
  python3 -I .../item-reviews.py check [--extraction DIR]
      the checks of the README: the files, SUMMARY.json, labels and timeline, every commit, the merge of each item,
      what the integration log and the reports say happened, the outcome of every finding, the Markdown, the pointers;
      with --extraction, also compares each committed file byte for byte with DIR/<file>.json (exit 1 on any problem)

No network, no simulator, no device; git is only read.
"""
import argparse
import hashlib
import json
import os
import re
import subprocess
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
FOLDER = os.path.dirname(HERE)
ROOT = os.path.abspath(os.path.join(FOLDER, "..", "..", "..", "..", ".."))
EXTRACTED = os.path.join(FOLDER, "extracted")
FOLDER_REL = "Docs/Stage0/evidence/M0-Integration/item-reviews"

# SHA-256 of each file as extracted (computed on the extraction's own files on 24 October 2026, before they were
# copied here; `check --extraction DIR` compares the bytes themselves again).
EXTRACTED_SHA256 = {
    "SUMMARY.json": "263c6aa5852e563c6f60d78f879a5e062888da5dd5e5cfcb2a5258148aed29a2",
    "amendments.json": "5fe1568bae95cca10765ebc31e26bf7ca3d0c1a432a27f82056bb88d3276ff0a",
    "contracts.json": "cb1773d2a21c96f48e8d5a95f94a82cd6a873dd0bbedb14214c1a971018b7c3a",
    "deps.json": "474a341b6c759adabd6eb58d9a52911dc988c89d6c3fc54ff916c30a918d73f0",
    "minors-g01-epub.json": "6ca04f0e73eaf9f7869477261ab958aa699ec8810bae67ed35ae7e2cf5d91371",
    "minors-g01-pdf.json": "538928a3122c92c6d7e8c95a178430699003360610afc626b9a0103196d17cdb",
    "minors-g02-transfer.json": "e5285ee87cab9a6b3c379236473ce64497c594eacaef3d7010e83a73bef58ee4",
    "minors-g03-intake.json": "c64d3f4c5198f7c755e755d54f9eec0a25b1590835a7d5fca180de9a348d93e2",
    "minors-g04-audio.json": "18875feef4fd00bbd9d73ceab3ee2cd06216d3dc04ca7775c63391d4467fdae3",
    "minors-g05-ai.json": "66be74695e9686c60cabad478e850c3fab9b19837efa89b76cb596be6227b31d",
    "minors-g05-recovery.json": "cdbb66f87047b697854303feb37344260a7b97755a91f46f5375a53867c6bcf5",
    "minors-g06-design.json": "5f452e918011d533195a014995e09c5cf9a6ee28387c24a37287a439804797cb",
    "runbook.json": "cc2e3d7fd84adde85bcbf7c320bf3d1625c82e3b749323347003200b3f18c1ba",
    "threat.json": "607827b588470f7f531c8d6bb855be535e8c40bae2609dc061e6142e6765ac2c",
}

# The thirteen items in the order integration log 7.1 merged them: name, branch, what the item made, where its
# record's pointer goes (the gate report, or the record the item made; ADR-0014 is another workstream's file, so the
# deps item's pointer is requested of its owner, not written here).
ITEMS = [
    ("contracts", "m0-int-contracts", "the capture-envelope and anchor contracts (`M0-contracts.md`, ADR-0016)",
     ["Docs/Stage0/M0-contracts.md", "Docs/ADRs/0016-capture-envelope-and-anchors.md"]),
    ("deps", "m0-int-deps", "the dependency lock and license inventory (ADR-0014)", []),
    ("threat", "m0-int-threat", "the threat model and the hard-rule audit (ADR-0015)",
     ["Docs/ADRs/0015-threat-model.md"]),
    ("minors-g06-design", "m0-int-minors-g06-design", "the remaining review findings of G0.6 (`G06-Design.md`)",
     ["Docs/Stage0/G06-Design.md"]),
    ("minors-g05-recovery", "m0-int-minors-g05-recovery",
     "the remaining review findings of G0.5 recovery (`G05-Recovery.md`)", ["Docs/Stage0/G05-Recovery.md"]),
    ("minors-g01-epub", "m0-int-minors-g01-epub", "the remaining review findings of G0.1 EPUB (`G01-EPUB.md`)",
     ["Docs/Stage0/G01-EPUB.md"]),
    ("minors-g01-pdf", "m0-int-minors-g01-pdf", "the remaining review findings of G0.1 PDF (`G01-PDF.md`)",
     ["Docs/Stage0/G01-PDF.md"]),
    ("minors-g03-intake", "m0-int-minors-g03-intake", "the remaining review findings of G0.3 (`G03-Intake.md`)",
     ["Docs/Stage0/G03-Intake.md"]),
    ("minors-g02-transfer", "m0-int-minors-g02-transfer", "the remaining review findings of G0.2 (`G02-Transfer.md`)",
     ["Docs/Stage0/G02-Transfer.md"]),
    ("minors-g05-ai", "m0-int-minors-g05-ai", "the remaining review findings of G0.5 AI (`G05-AI.md`)",
     ["Docs/Stage0/G05-AI.md"]),
    ("runbook", "m0-int-runbook", "the device and human-review runbook (`M0-device-runbook.md`)",
     ["Docs/Stage0/M0-device-runbook.md"]),
    ("amendments", "m0-int-amendments", "the plan amendments of draft 0.5 (`M0-plan-amendments.md`)",
     ["Docs/Stage0/M0-plan-amendments.md"]),
    ("minors-g04-audio", "m0-int-minors-g04-audio", "the remaining review findings of G0.4 (`G04-Audio.md`)",
     ["Docs/Stage0/G04-Audio.md"]),
]
NAMES = [i[0] for i in ITEMS]

# The workflow runs, in the order the records place them (each item's rounds run forward through them); `check`
# verifies that every item's records agree with this one order.
RUN_ORDER = ["wf_5ce13c9e-6bf", "wf_5552ba19-d21", "wf_744b95c1-309", "wf_3f1b0c6a-cad", "wf_9ea3b4d5-f4f",
             "wf_eaa493fa-c4f"]
# The runs the gate summary (Section 1, item 4) named, from a listing of the journals' folder, read-only.
GATE_SUMMARY_RUNS = ["wf_5552ba19-d21", "wf_744b95c1-309", "wf_3f1b0c6a-cad", "wf_9ea3b4d5-f4f", "wf_eaa493fa-c4f",
                     "wf_84f4e4ba-f4a"]

# Notes this hand-over adds to an item's Markdown (facts read in the records, the repository or the task).
NOTES = {
    "deps": [
        "The final round's R4-01 and R4-02 are the two serious findings the gate summary tracks (`M0-gate.md` "
        "Section 6.1; integration log 7.1). A parallel agent's task of 24 October 2026 is to close them, on a branch "
        "of its own; its outcome is not part of this record.",
        "The final round's minor findings R4-03 to R4-07 are not in ADR-0014, which names R4-01 and R4-02 only "
        "(searched by ID on this branch).",
    ],
    "contracts": [
        "fix-2 recorded that the list of review-2b's findings handed to it ended partway through L2-R2-01, so it saw "
        "the later L2-R2 findings only where the gate gaps named them (L2-R2-05); `M0-contracts.md`'s Review line "
        "says the same. fix-1 and the round-2 and round-3 reviews also recorded texts they did not receive in full "
        "(fix-1 reconstructed R1-10 from its title; review-2 and review-3 inferred several earlier findings from the "
        "fixer's cross-references).",
        "review-1b's and review-3b's IDs overlap (L2-01 to L2-09 in both, different findings): the tables above give "
        "each with its round.",
    ],
    "amendments": [
        "fix-1 recorded that the list of review-1b's findings handed to it was cut off partway through L2-01, and "
        "left L2-06 and L2-07 unaddressed, their texts not being in its task; fix-2 names none of review-2b's L2-12 to "
        "L2-17, and the round-3 reviews inferred several earlier findings from commits.",
        "review-2b's and review-3b's IDs overlap (L2-12 to L2-17 in both, different findings): the tables above give "
        "each with its round.",
    ],
    "runbook": [
        "review-2 names neither R1-07 nor R1-08 among the earlier findings it checked, and review-3 neither R2-10 nor "
        "R2-11; fix-1 and fix-2 recorded each as fixed.",
    ],
    "minors-g05-recovery": [
        "The final review (review-2) says the author result supplied with it was the round-3 result for `ce535e0`, "
        "not fix-1's, and that it reviewed the branch head, `cd3e42b`, which adds the round-4 fixes `a377b17` and "
        "`cd3e42b` (integration log section 2, row 2).",
        "The finding IDs continue the gate's own review rounds: review-1 is the gate's round 4 (R4-01 to R4-05), "
        "review-2 its round 5 (R5-01, R5-02).",
    ],
    "minors-g05-ai": [
        "The finding IDs continue the gate's own review rounds: review-1 is `G05-AI.md`'s Review round 7 (R7-01 to "
        "R7-04, recorded there), review-2 its round 8 (R8-01 to R8-04), which the report does not record.",
        "R8-04 says that the cleanup command `G05-AI.md` gives for the leftover temporary directories (Review round 6, "
        "last paragraph; the gate summary's Section 5.2 gives the same directories to the owner) would also delete "
        "G0.5 recovery's live test root `g05-tests`, and that 1,659 of the 1,664 directories match `g05-<UUID>`. "
        "The command is still there on this branch.",
    ],
    "minors-g01-pdf": [
        "The finding IDs continue the gate's own review rounds: review-1 is the gate's round 3 (R3-01 to R3-06), "
        "review-2 its round 4 (R4-01 to R4-07), review-3 its round 5 (R5-01 to R5-03); integration log section 2, "
        "row 4, names rounds 3 and 4.",
    ],
    "minors-g03-intake": [
        "The finding IDs continue the gate's own review rounds: review-1 is the gate's round 3 (R3-01 to R3-05), "
        "review-2 its round 4 (R4-01 to R4-06), review-3 its round 5 (R5-01 to R5-05), which `G03-Intake.md` does "
        "not record.",
    ],
    "minors-g01-epub": ["The finding IDs continue the gate's own review rounds: review-1 is its round 4."],
    "minors-g02-transfer": ["The finding IDs continue the gate's own review rounds: review-1 is its round 4."],
    "minors-g04-audio": ["The finding IDs continue the gate's own review rounds: review-1 is its round 7."],
    "minors-g06-design": ["The finding IDs continue the gate's own review rounds: review-1 is its round 4."],
    "threat": ["The two lenses of its one round reviewed the same commit; review-1b's IDs are L2-01 to L2-03."],
}

LABEL = re.compile(r"(?P<item>[a-z0-9-]+):(?:(?P<author>author)|review-(?P<review>\d+)(?P<lens>b?)|fix-(?P<fix>\d+))")
HEX = re.compile(r"[0-9a-f]{7,40}")
SERIOUS = {"blocker", "major", "serious", "critical"}


def read_records(name):
    with open(os.path.join(EXTRACTED, name + ".json.txt"), "rb") as fh:
        return json.loads(fh.read().decode("utf-8"))


def git(*args, check=True):
    done = subprocess.run(["git", "-C", ROOT] + list(args), capture_output=True, text=True)
    if check and done.returncode != 0:
        raise RuntimeError(f"git {' '.join(args)}: {done.stderr.strip()}")
    return done


def resolve(commitish):
    """The full SHA of the commit a string starts with, or None when it is not a commit of this repository."""
    m = HEX.match(commitish or "")
    if not m:
        return None
    done = git("rev-parse", "--verify", "--quiet", m.group(0) + "^{commit}", check=False)
    if done.returncode != 0:
        return None
    full = done.stdout.strip()
    return full if git("cat-file", "-e", full, check=False).returncode == 0 else None


def is_ancestor(a, b):
    return git("merge-base", "--is-ancestor", a, b, check=False).returncode == 0


def parse_label(label):
    m = LABEL.fullmatch(label)
    if not m:
        return None
    if m.group("author"):
        return {"kind": "author", "round": 0, "lens": ""}
    if m.group("review"):
        return {"kind": "review", "round": int(m.group("review")), "lens": m.group("lens")}
    return {"kind": "fix", "round": int(m.group("fix")), "lens": ""}


def ordered(records):
    """The records in the order they were made: author, then each round's reviews (by run and seq), then its fix."""
    def key(r):
        p = parse_label(r["label"])
        phase = {"author": 0, "review": 1, "fix": 2}[p["kind"]]
        return (p["round"], phase, RUN_ORDER.index(r["run"]) if r["run"] in RUN_ORDER else 99, r["seq"])
    return sorted(records, key=key)


def short_label(r):
    return r["label"].split(":", 1)[1]


def commit_of(r):
    res = r["result"]
    return res.get("commit_reviewed") if parse_label(r["label"])["kind"] == "review" else res.get("commit")


def id_pattern(fid):
    return re.compile(r"(?<![A-Za-z0-9-])" + re.escape(fid) + r"(?![0-9])")


def cell(text):
    """A record's text for one line of Markdown: whitespace collapsed, a table's | escaped, and outside code spans the
    characters Markdown would read as HTML or emphasis (<, >, *) escaped, so that it shows as the record has it."""
    parts = " ".join(str(text).split()).split("`")
    if len(parts) % 2 == 0:  # an odd number of backticks: the last one opens no code span, so it is escaped
        last = parts.pop()
        parts[-1] = parts[-1] + "\x00" + last
    for i in range(0, len(parts), 2):  # even parts lie outside code spans
        parts[i] = parts[i].replace("<", "&lt;").replace(">", "&gt;").replace("*", "\\*")
    return "`".join(parts).replace("\x00", "\\`").replace("|", "\\|")


class Item:
    """One item's records, ordered, with every finding's outcome as the later records give it."""

    def __init__(self, name):
        self.name = name
        self.branch, self.made, self.pointers = next((b, m, p) for n, b, m, p in ITEMS if n == name)
        self.records = ordered(read_records(name))
        self.reviews = [r for r in self.records if parse_label(r["label"])["kind"] == "review"]
        self.fixes = [r for r in self.records if parse_label(r["label"])["kind"] == "fix"]
        self.final_round = max(parse_label(r["label"])["round"] for r in self.reviews)
        self.finals = [r for r in self.reviews if parse_label(r["label"])["round"] == self.final_round]
        self.outcomes = {}  # (label, finding id) -> (state, trail)
        self.carried = {}  # (label, finding id) -> [(label, finding id)] it was carried to
        # Later rounds first, so that a finding carried forward can take the state of the finding that carries it.
        for review in sorted(self.reviews, key=lambda r: -parse_label(r["label"])["round"]):
            k = parse_label(review["label"])["round"]
            for f in review["result"].get("findings", []):
                self.outcomes[(review["label"], f["id"])] = self._outcome(k, f["id"], review["label"])

    def _outcome(self, k, fid, label):
        if k == self.final_round:
            return "open", ["raised by the final round"]
        pat = id_pattern(fid)
        trail, fixed, not_fixed, by_round, carried = [], False, False, {}, []
        for r in self.records:
            p = parse_label(r["label"])
            if p["kind"] == "fix" and p["round"] >= k:
                if any(pat.search(e.get("id", "")) for e in r["result"].get("fixed", [])):
                    trail.append(f"fixed ({short_label(r)})")
                    fixed = True
                if any(pat.search(e.get("id", "")) for e in r["result"].get("not_fixed", [])):
                    trail.append(f"not fixed ({short_label(r)})")
                    not_fixed = True
            elif p["kind"] == "review" and p["round"] > k:
                same_round = [(x["label"], f["id"]) for x in self.reviews if parse_label(x["label"])["round"] == p["round"]
                              for f in x["result"].get("findings", [])]
                for prev in r["result"].get("previous_findings_status", []):
                    if pat.search(prev.get("id", "")):
                        resolved = prev.get("resolved") is True
                        # A review that finds an earlier finding unresolved often raises the remainder as one of its
                        # own findings and names it in its note ("tracked as R2-04"): the earlier finding is carried.
                        to = [] if resolved else [t for t in same_round if id_pattern(t[1]).search(prev.get("note", ""))]
                        trail.append(f"{'resolved' if resolved else 'unresolved'} ({short_label(r)})"
                                     + (f", carried as {', '.join(t[1] for t in to)}" if to else ""))
                        by_round.setdefault(p["round"], []).append((resolved, to))
        if by_round:
            # The last round that names it decides; it counts as resolved only if every lens of that round that
            # names it says so, and as carried if each lens that does not names the finding that carries it.
            j = max(by_round)
            if all(resolved for resolved, _ in by_round[j]):
                return "resolved", trail
            if j == self.final_round:
                return "open", trail
            if all(resolved or to for resolved, to in by_round[j]):
                targets = [t for _, to in by_round[j] for t in to]
                self.carried[(label, fid)] = targets
                still = [t for t in targets if self.outcomes[t][0] in OPEN_STATES]
                return ("carried-open" if still else "carried-resolved"), trail
            return "unresolved-later", trail
        if fixed and not not_fixed:
            return "fixed-unconfirmed", trail
        if not_fixed:
            return "not-fixed", trail
        return "no-outcome", []

    def open_at_merge(self):
        """The findings open when the item was merged: those the final round raised; earlier ones the records leave
        unresolved (a later round marks them unresolved, or a fix did not fix them and no later review names them);
        earlier ones no later record names at all; and the final round's not-resolved entries for findings or gaps
        that are not this item's own. Earlier findings fixed by the fixer's account alone are returned apart."""
        raised = [(r, f) for r in self.finals for f in r["result"].get("findings", [])]
        earlier, unconfirmed = [], []
        for review in self.reviews:
            if review in self.finals:
                continue
            for f in review["result"].get("findings", []):
                state, trail = self.outcomes[(review["label"], f["id"])]
                if state in OPEN_STATES:
                    earlier.append((review, f, state, trail))
                elif state == "fixed-unconfirmed":
                    unconfirmed.append((review, f, state, trail))
        self.unconfirmed = unconfirmed
        prev_open = []  # unresolved entries of the final round that are not this item's own findings
        own = {f["id"] for r in self.reviews for f in r["result"].get("findings", [])}
        for r in self.finals:
            for p in r["result"].get("previous_findings_status", []):
                if p.get("resolved") is not True and not any(id_pattern(i).search(p.get("id", "")) for i in own):
                    prev_open.append((r, p))
        return raised, earlier, prev_open


def severity_counts(findings):
    counts = {}
    for f in findings:
        counts[f.get("severity", "?")] = counts.get(f.get("severity", "?"), 0) + 1
    order = ["blocker", "major", "minor"]
    keys = sorted(counts, key=lambda s: (order.index(s) if s in order else 9, s))
    return ", ".join(f"{counts[s]} {s}" for s in keys)


STATE_WORDS = {
    "resolved": "resolved",
    "open": "open at the merge",
    "unresolved-later": "marked unresolved by a later round, and named by no round after it",
    "carried-resolved": "carried into a later finding, which was resolved",
    "carried-open": "carried into a later finding, which stayed open",
    "fixed-unconfirmed": "fixed, by its fixer's account; no later review names it",
    "not-fixed": "not fixed, and no later review names it",
    "no-outcome": "no later record names it",
}
OPEN_STATES = ("open", "not-fixed", "no-outcome", "unresolved-later", "carried-open")


def render(name):
    it = Item(name)
    first = it.records[0]
    out = []
    w = out.append
    w(f"# M0 item `{name}`: its review record")
    w("")
    w(f"Every author, review and fix round of the M0 item `{name}`, {it.made}, on branch `{it.branch}`, in the order "
      f"they were made, as the orchestrating session's workflow journals hold them: each round's verdict, its findings "
      f"(ID, severity, title) and its commit, then the final verdict and the findings that stayed open. Generated by "
      f"`commands/item-reviews.py render` from [`extracted/{name}.json.txt`](extracted/{name}.json.txt), which holds "
      f"each result in full (every finding's location and detail, every fix's account, every review's re-run, claims "
      f"verified and gate gaps, and the author's criteria and open questions). These are agent reviews, not a person's; "
      f"human sign-off pending. Where the records came from and how they were checked: [`README.md`](README.md).")
    w("")
    final_commit = resolve(commit_of(it.finals[0])) or commit_of(it.finals[0])
    verdicts = "; ".join(f"{short_label(r)}: {r['result'].get('verdict')}" for r in it.finals)
    runs = []
    for r in it.records:
        if r["run"] not in runs:
            runs.append(r["run"])
    w(f"- **Final verdict:** {verdicts} (round {it.final_round}, at `{final_commit}`).")
    w(f"- **Records:** {len(it.records)}: {', '.join(short_label(r) for r in it.records)}.")
    w(f"- **Workflow runs:** {', '.join(f'`{x}`' for x in runs)}.")
    row = integration_rows()[1].get(name, {})
    w(f"- **Merged:** squash-merged into `m0-integrate` at M0 assembly as `{row.get('squash')}`, with `{it.branch}` "
      f"at `{str(row.get('final'))[:8]}` as its final reviewed commit and the verdict {row.get('verdict')} "
      f"(integration log section 7.1, row {row.get('order')}).")
    w("")
    w("## The rounds, in order")
    w("")
    w("| # | Record | Run (seq) | Commit | Verdict | Findings, or what the fix recorded |")
    w("| --- | --- | --- | --- | --- | --- |")
    for n, r in enumerate(it.records, 1):
        p = parse_label(r["label"])
        commit = resolve(commit_of(r))
        shown = f"`{commit[:8]}`" if commit else f"`{cell(commit_of(r))}` (not resolved)"
        res = r["result"]
        if p["kind"] == "review":
            fs = res.get("findings", [])
            what = f"{len(fs)}: {severity_counts(fs)}" if fs else "none"
            verdict = res.get("verdict")
        elif p["kind"] == "fix":
            what = f"fixed {len(res.get('fixed', []))}, not fixed {len(res.get('not_fixed', []))}"
            verdict = "-"
        else:
            what = f"{len(res.get('criteria', []))} criteria, {len(res.get('open_questions', []))} open questions"
            verdict = "-"
        w(f"| {n} | {short_label(r)} | `{r['run']}` ({r['seq']}) | {shown} | {verdict} | {what} |")
    w("")
    w(f"The author's result names branch `{first['result'].get('branch')}`. A commit shows its first eight characters; "
      f"the checks resolve each one in this repository (`README.md`).")
    w("")
    w("## Each round")
    for r in it.records:
        p = parse_label(r["label"])
        res = r["result"]
        commit = resolve(commit_of(r))
        at = f"`{commit[:8]}`" if commit else f"`{cell(commit_of(r))}`"
        w("")
        if p["kind"] == "author":
            w(f"### author, at {at}")
            w("")
            statuses = {}
            for c in res.get("criteria", []):
                statuses[c.get("status")] = statuses.get(c.get("status"), 0) + 1
            w(f"Branch `{res.get('branch')}`. {len(res.get('criteria', []))} criteria ("
              + ", ".join(f"{v} {k}" for k, v in sorted(statuses.items())) + f"); "
              f"{len(res.get('plan_findings', []))} plan findings; {len(res.get('open_questions', []))} open questions; "
              f"{len(res.get('shared_changes_requested', []))} shared changes requested.")
        elif p["kind"] == "fix":
            w(f"### {short_label(r)}, at {at}")
            w("")
            fixed = [e.get("id", "") for e in res.get("fixed", [])]
            not_fixed = [e.get("id", "") for e in res.get("not_fixed", [])]
            w("- **Fixed, as the fixer recorded:** " + ("; ".join(cell(i) for i in fixed) if fixed else "none") + ".")
            w("- **Not fixed, as the fixer recorded:** " + ("; ".join(cell(i) for i in not_fixed) if not_fixed
                                                             else "none") + ".")
        else:
            lens = " (the second lens)" if p["lens"] == "b" else ""
            w(f"### {short_label(r)}{lens}: {res.get('verdict')}, at {at}")
            w("")
            fs = res.get("findings", [])
            if fs:
                w("| ID | Severity | Title | What became of it |")
                w("| --- | --- | --- | --- |")
                for f in fs:
                    state, trail = it.outcomes[(r["label"], f["id"])]
                    if state == "open" and trail == ["raised by the final round"]:
                        became = "open at the merge (raised by the final round)"
                    else:
                        became = STATE_WORDS[state] + (" (" + "; ".join(trail) + ")" if trail else "")
                    w(f"| {cell(f['id'])} | {cell(f.get('severity'))} | {cell(f.get('title'))} | {became} |")
            else:
                w("No findings.")
            prev = res.get("previous_findings_status", [])
            if prev:
                ok = [p2.get("id", "") for p2 in prev if p2.get("resolved") is True]
                ko = [p2.get("id", "") for p2 in prev if p2.get("resolved") is not True]
                w("")
                w(f"Earlier findings and gaps it checked: {len(ok)} resolved"
                  + (f" ({'; '.join(cell(i) for i in ok)})" if ok else "")
                  + f"; {len(ko)} not resolved" + (f" ({'; '.join(cell(i) for i in ko)})" if ko else "") + ".")
    raised, earlier, prev_open = it.open_at_merge()
    w("")
    w("## Final verdict, and what stayed open")
    w("")
    w(f"Final round {it.final_round}: " + "; ".join(
        f"{short_label(r)}, {r['result'].get('verdict')}, at `{(resolve(commit_of(r)) or '')[:8]}`" for r in it.finals)
      + ". Open when the item was merged, by these records:")
    w("")
    if raised:
        w(f"- **Raised by the final round** ({len(raised)}: {severity_counts([f for _, f in raised])}): "
          + "; ".join(f"{cell(f['id'])} ({short_label(r)}, {cell(f.get('severity'))})" for r, f in raised) + ".")
    else:
        w("- **Raised by the final round:** none.")
    left = [x for x in earlier if x[2] != "no-outcome"]
    unnamed = [x for x in earlier if x[2] == "no-outcome"]
    if left:
        w(f"- **Earlier findings the records leave unresolved** ({len(left)}: "
          f"{severity_counts([f for _, f, _, _ in left])}): "
          + "; ".join(f"{cell(f['id'])} ({short_label(r)}, {cell(f.get('severity'))}; {STATE_WORDS[s]})"
                      for r, f, s, _ in left) + ".")
    else:
        w("- **Earlier findings the records leave unresolved:** none.")
    if unnamed:
        w(f"- **Earlier findings no later record names** ({len(unnamed)}: "
          f"{severity_counts([f for _, f, _, _ in unnamed])}; no fix lists them, and no later review's check of "
          f"earlier findings names them, so these records give no outcome for them): "
          + "; ".join(f"{cell(f['id'])} ({short_label(r)}, {cell(f.get('severity'))})" for r, f, _, _ in unnamed)
          + ".")
    else:
        w("- **Earlier findings no later record names:** none.")
    if it.unconfirmed:
        w(f"- **Not counted as open: earlier findings fixed by their fixer's account, which no later review names** "
          f"({len(it.unconfirmed)}): "
          + "; ".join(f"{cell(f['id'])} ({short_label(r)}, {cell(f.get('severity'))})"
                      for r, f, _, _ in it.unconfirmed) + ".")
    if prev_open:
        w(f"- **Earlier items the final round still marks not resolved** ({len(prev_open)}; findings of the gate's own "
          f"earlier rounds or gate gaps, not raised in this item's records): "
          + "; ".join(f"{cell(p2.get('id', ''))} ({short_label(r)})" for r, p2 in prev_open) + ".")
    else:
        w("- **Earlier items the final round still marks not resolved:** none.")
    w("")
    w("Whether later work (the M0 assembly, the M0 final fix or the rounds since) answered any of these was not "
      "checked for this record.")
    if NOTES.get(name):
        w("")
        w("## Notes of this hand-over")
        w("")
        for note in NOTES[name]:
            w(f"- {note}")
    return "\n".join(out) + "\n"


# --- checks -------------------------------------------------------------------------------------------------------

problems = []


def report(ok, message):
    print(("ok      " if ok else "PROBLEM ") + message)
    if not ok:
        problems.append(message)


def integration_rows():
    log = open(os.path.join(ROOT, "Docs/Stage0/integration-log.md"), encoding="utf-8").read()
    section = log.split("### 7.1 Item merges", 1)[1].split("\n### 7.2", 1)[0]
    rows = {}
    for line in section.splitlines():
        cells = [c.strip() for c in line.strip().strip("|").split("|")]
        if len(cells) == 8 and cells[0].isdigit():
            name = cells[1].split(":", 1)[0]
            rows[name] = {"order": int(cells[0]), "branch": cells[2].strip("`"), "final": cells[3].strip("`"),
                          "verdict": cells[4].strip("*"), "serious": cells[5], "paths": int(cells[6]),
                          "squash": cells[7].strip("`")}
    return log, rows


# What integration log section 2 says happened on each minors branch: a fragment of its row (it must still be in the
# log), the commits it names and what each must be in the records, and the rounds whose finding IDs it names.
SECTION2 = {
    "minors-g06-design": ("fixed with finding 18 on `m0-int-minors-g06-design` at `9812542` (clean run from `d3b4bb2`)",
                          [("9812542", "author"), ("d3b4bb2", "on-branch")], {}, ["R3-01", "R3-02", "18"]),
    "minors-g05-recovery": ("fixed on `m0-int-minors-g05-recovery` (`ce535e0`, with the round-4 fixes `a377b17` and "
                            "`cd3e42b`)",
                            [("ce535e0", "author"), ("a377b17", "between:author:fix-1"), ("cd3e42b", "fix-1")],
                            {"review-1": "R4-"}, ["R3-01", "R3-02", "R3-03", "R3-04", "R3-05"]),
    "minors-g01-epub": ("R3-01 closed on `m0-int-minors-g01-epub` (`d317054`; R3-02 resolved at integration, below)",
                        [("d317054", "author"), ("7f3b072", "on-branch")], {}, ["R3-01", "R3-02"]),
    "minors-g01-pdf": ("closed on `m0-int-minors-g01-pdf` (`7884a59`), with the later rounds' R3-01 to R3-06 "
                       "(`11736d1`) and R4-01 to R4-07, accepted by that branch's final agent review at `a44b746`",
                       [("7884a59", "author"), ("11736d1", "fix-1"), ("a44b746", "final")],
                       {"review-1": "R3-01..R3-06", "review-2": "R4-01..R4-07"}, ["R2-01", "R2-02", "R2-03"]),
    "minors-g03-intake": ("closed on `m0-int-minors-g03-intake` (head `4b8c634` for them, clean CI run at `c0affa9`), "
                          "with the later rounds through round 4 (final `77ceaf3`)",
                          [("4b8c634", "author"), ("c0affa9", "on-branch"), ("77ceaf3", "final")],
                          {"review-1": "R3-", "review-2": "R4-"},
                          ["R2-01", "R2-02", "R2-03", "R2-04", "R2-05", "R2-06"]),
    "minors-g02-transfer": ("fixed or handed to device and human steps on `m0-int-minors-g02-transfer` (`c83a3b9`)",
                            [("c83a3b9", "author"), ("c83a3b9", "final")], {},
                            ["R3-01", "R3-02", "R3-03", "R3-04", "R3-05", "R3-06"]),
    "minors-g05-ai": ("That branch's review round 7 then found R7-01 (blocker), R7-02 (major), R7-03 and R7-04 (minor): "
                      "R7-01 to R7-03 fixed on that branch, which ends at `4090d59`",
                      [("f838379", "author"), ("4090d59", "fix-1"), ("b7fadb1", "on-branch")],
                      {"review-1": "R7-01:blocker,R7-02:major,R7-03:minor,R7-04:minor"},
                      ["R6-01", "R6-02", "R6-03", "R6-04"]),
    "minors-g04-audio": ("closed on `m0-int-minors-g04-audio` (`d0c6120`) with a final clean run",
                         [("d0c6120", "author"), ("d0c6120", "final")], {},
                         ["R6-01", "R6-02", "R6-03", "R6-04", "R6-05", "R6-06"]),
}

# What a gate report says of the item's rounds, read again in the records.
REPORT_STATEMENTS = [
    ("minors-g03-intake", "Docs/Stage0/G03-Intake.md",
     "Round 3 found one major and four minor findings, R3-01 to R3-05", "review-1", {"major": 1, "minor": 4}),
    ("minors-g03-intake", "Docs/Stage0/G03-Intake.md",
     "Round 4 found one blocker and five minor findings, R4-01 to R4-06", "review-2", {"blocker": 1, "minor": 5}),
    ("minors-g05-ai", "Docs/Stage0/G05-AI.md", "The seventh review found 4 issues (1 blocker, 1 major, 2 minor)",
     "review-1", {"blocker": 1, "major": 1, "minor": 2}),
]


def check(extraction):
    print(f"command: python3 -I {FOLDER_REL}/commands/item-reviews.py check"
          + (f" --extraction {extraction}" if extraction else ""))
    print(f"commit: {git('rev-parse', 'HEAD').stdout.strip()}; uncommitted paths: "
          f"{len(git('status', '--porcelain').stdout.splitlines())}")
    print()
    print("== 1. The files")
    files = sorted(n for n in os.listdir(EXTRACTED) if n.endswith(".json.txt"))
    report(files == sorted(n + ".txt" for n in EXTRACTED_SHA256),
           f"extracted/ holds exactly the {len(EXTRACTED_SHA256)} files of the extraction, each named <file>.json.txt: "
           f"{len(files)} found")
    for name in sorted(EXTRACTED_SHA256):
        path = os.path.join(EXTRACTED, name + ".txt")
        data = open(path, "rb").read() if os.path.exists(path) else b""
        digest = hashlib.sha256(data).hexdigest()
        report(digest == EXTRACTED_SHA256[name], f"extracted/{name}.txt: {len(data)} bytes, SHA-256 {digest[:16]}... "
               f"{'equal to' if digest == EXTRACTED_SHA256[name] else 'NOT equal to'} the extracted file's")
        try:
            json.loads(data.decode("utf-8"))
            parsed = True
        except ValueError:
            parsed = False
        report(parsed, f"extracted/{name}.txt parses as JSON (UTF-8)")
        if extraction:
            original = os.path.join(extraction, name)
            same = os.path.exists(original) and open(original, "rb").read() == data
            report(same, f"extracted/{name}.txt is byte for byte {original}")
    readme_path = os.path.join(FOLDER, "README.md")
    readme = open(readme_path, encoding="utf-8").read() if os.path.exists(readme_path) else ""
    report(all(digest in readme for digest in EXTRACTED_SHA256.values()),
           "README.md lists the SHA-256 of each of the fourteen files")
    summary = json.loads(open(os.path.join(EXTRACTED, "SUMMARY.json.txt"), "rb").read().decode("utf-8"))
    report(sorted(summary) == sorted(NAMES), f"SUMMARY.json names the thirteen items of integration log 7.1: "
           f"{', '.join(summary)}")

    print()
    print("== 2. SUMMARY.json against the item files")
    items = {n: Item(n) for n in NAMES}
    for n in NAMES:
        it, s = items[n], summary.get(n, {})
        runs = sorted({r["run"] for r in it.records})
        last = max(it.finals, key=lambda r: (RUN_ORDER.index(r["run"]), r["seq"]))
        report(s.get("records") == len(it.records) and s.get("reviews") == len(it.reviews)
               and sorted(s.get("runs", [])) == runs,
               f"{n}: {len(it.records)} records, {len(it.reviews)} review{'s' if len(it.reviews) != 1 else ''}, "
               f"runs {', '.join(runs)}, as SUMMARY.json says")
        report(s.get("final_review") == last["label"] and s.get("final_verdict") == last["result"].get("verdict")
               and HEX.match(s.get("final_commit", "")).group(0) == HEX.match(commit_of(last)).group(0),
               f"{n}: SUMMARY.json's final review {s.get('final_review')} ({s.get('final_verdict')}) is the last "
               f"record of the final round, round {it.final_round}"
               + (f" (its lenses: {', '.join(short_label(r) for r in it.finals)})" if len(it.finals) > 1 else ""))

    print()
    print("== 3. Labels and the timeline")
    for n in NAMES:
        it = items[n]
        parsed = [parse_label(r["label"]) for r in it.records]
        report(all(p is not None for p in parsed) and all(r["label"].startswith(n + ":") for r in it.records),
               f"{n}: every label is <item>:author, review-N, review-Nb or fix-N, for this item")
        authors = [r for r in it.records if parse_label(r["label"])["kind"] == "author"]
        rounds = sorted({parse_label(r["label"])["round"] for r in it.reviews})
        fixes = sorted(parse_label(r["label"])["round"] for r in it.fixes)
        report(len(authors) == 1 and rounds == list(range(1, it.final_round + 1))
               and fixes == list(range(1, it.final_round)),
               f"{n}: one author, "
               + (f"review rounds 1-{it.final_round}, a fix after each round but the last (fixes: "
                  f"{', '.join(f'fix-{x}' for x in fixes)})" if it.final_round > 1 else "one review round, no fix"))
        position = [(RUN_ORDER.index(r["run"]) if r["run"] in RUN_ORDER else 99, r["seq"]) for r in it.records]
        report(all(r["run"] in RUN_ORDER for r in it.records) and position == sorted(position),
               f"{n}: the records' runs and seqs run forward in the order of the rounds: "
               + " -> ".join(f"{short_label(r)} {r['run']}#{r['seq']}" for r in it.records))
    used = sorted({r["run"] for it in items.values() for r in it.records}, key=RUN_ORDER.index)
    print(f"        the runs the records come from, in order: {', '.join(used)}")
    print(f"        named by the gate summary (Section 1, item 4) and holding no extracted record: "
          f"{', '.join(x for x in GATE_SUMMARY_RUNS if x not in used) or 'none'}")
    print(f"        holding records and not named by the gate summary: "
          f"{', '.join(x for x in used if x not in GATE_SUMMARY_RUNS) or 'none'} ("
          + "; ".join(f"{x}: " + ", ".join(r["label"] for it in items.values() for r in it.records if r["run"] == x)
                      for x in used if x not in GATE_SUMMARY_RUNS) + ")")

    print()
    print("== 4. Every commit: it is a commit of this repository, on the item's branch, and the rounds chain")
    for n in NAMES:
        it = items[n]
        head = git("rev-parse", "--verify", "--quiet", f"refs/heads/{it.branch}", check=False).stdout.strip()
        report(bool(head), f"{n}: branch {it.branch} exists, at {head[:12]}")
        reviewed_by_round = {}
        previous = None
        for r in it.records:
            p = parse_label(r["label"])
            given = commit_of(r) or ""
            full = resolve(given)
            note = "" if HEX.fullmatch(given) else f" (given as {given[:60]!r}{'...' if len(given) > 60 else ''})"
            ok = full is not None and is_ancestor(full, head)
            date = git("show", "-s", "--format=%cI", full).stdout.strip() if full else "-"
            report(ok, f"{n} {short_label(r)}: {(full or given)[:12]} is a commit of this repository (git cat-file -e), "
                       f"on {it.branch} (committed {date}){note}")
            if p["kind"] == "review":
                expected = previous
                report(full is not None and full == expected,
                       f"{n} {short_label(r)}: reviewed {str(full)[:12]}, the commit of "
                       f"{'the author' if p['round'] == 1 else 'fix-' + str(p['round'] - 1)} ({str(expected)[:12]})")
                reviewed_by_round.setdefault(p["round"], set()).add(full)
            else:
                if p["kind"] == "fix":
                    before = next(iter(reviewed_by_round.get(p["round"], {None})))
                    report(full is not None and before is not None and full != before and is_ancestor(before, full),
                           f"{n} {short_label(r)}: {str(full)[:12]} comes after the commit review {p['round']} read "
                           f"({str(before)[:12]})")
                previous = full
        lens_commits = reviewed_by_round.get(it.final_round, set())
        report(len(lens_commits) == 1, f"{n}: every lens of the final round reviewed the same commit")

    print()
    print("== 5. The merge: the final round reviewed the commit integration log 7.1 merged")
    log, rows = integration_rows()
    report(sorted(rows) == sorted(NAMES), f"integration log 7.1 lists the thirteen items: {len(rows)} rows")
    for n in NAMES:
        it, row = items[n], rows.get(n)
        if not row:
            continue
        final = resolve(commit_of(it.finals[0]))
        head = git("rev-parse", f"refs/heads/{it.branch}").stdout.strip()
        verdicts = {r["result"].get("verdict") for r in it.finals}
        report(row["branch"] == it.branch and final == row["final"] and head == row["final"],
               f"{n}: 7.1's final commit {row['final'][:12]} = the commit the final round reviewed = the head of "
               f"{it.branch}")
        report(verdicts == {row["verdict"]}, f"{n}: 7.1's verdict {row['verdict']!r} = the final round's "
               f"{', '.join(sorted(v for v in verdicts if v))}")
        squash = resolve(row["squash"])
        message = git("show", "-s", "--format=%B", squash).stdout if squash else ""
        report(squash is not None and it.branch in message and row["final"] in message,
               f"{n}: the squash commit {row['squash']} names {it.branch} and {row['final'][:12]} in its message")
        parent = git("rev-parse", f"{squash}^").stdout.strip()
        base = git("merge-base", it.branch, parent).stdout.strip()
        paths = [p for p in git("diff", "--name-only", "--no-renames", base, it.branch).stdout.splitlines() if p]
        differ = []
        for path in paths:
            a = git("ls-tree", it.branch, "--", path).stdout.split()
            b = git("ls-tree", squash, "--", path).stdout.split()
            if a[:1] + a[2:3] != b[:1] + b[2:3]:
                differ.append(path)
        expected = ["Docs/ADRs/0014-dependency-lock-and-license-inventory.md"] if n == "deps" else []
        report(len(paths) == row["paths"] and differ == expected,
               f"{n}: the {len(paths)} paths the branch changes are identical in mode and blob in the squash commit"
               + (f", except {', '.join(differ)}" if differ else "") + f" (7.1: {row['paths']} paths"
               + ("; its one conflict, in wording only, as 7.1 records" if n == "deps" else "") + ")")
        report(is_ancestor(squash, "HEAD"), f"{n}: the squash commit is in this branch's history")
        serious = [f["id"] for r in it.finals for f in r["result"].get("findings", [])
                   if f.get("severity") in SERIOUS]
        wanted = [] if row["serious"] == "none" else re.findall(r"R\d-\d\d", row["serious"])
        report(serious == wanted, f"{n}: 7.1's open serious findings ({row['serious']}) = the final round's blocker "
               f"and major findings ({', '.join(serious) or 'none'})")

    print()
    print("== 6. What the integration log, the gate summary and the reports say happened")
    for n, (fragment, commits, ids, closed) in SECTION2.items():
        it = items[n]
        report(fragment in log, f"{n}: integration log section 2 says: {fragment[:110]}...")
        head = git("rev-parse", f"refs/heads/{it.branch}").stdout.strip()
        by_label = {short_label(r): resolve(commit_of(r)) for r in it.records}
        final = resolve(commit_of(it.finals[0]))
        for short, role in commits:
            full = resolve(short)
            if role == "on-branch":
                ok = full is not None and is_ancestor(full, head)
                what = f"on {it.branch}"
            elif role == "final":
                ok = full == final
                what = "the commit the final round reviewed"
            elif role.startswith("between:"):
                _, lo, hi = role.split(":")
                ok = full is not None and is_ancestor(by_label[lo], full) and is_ancestor(full, by_label[hi])
                what = f"between the {lo}'s commit and {hi}'s"
            else:
                ok = full == by_label.get(role)
                what = f"the {role}'s commit"
            report(ok, f"{n}: {short} is {what}")
        for label, spec in ids.items():
            fs = next(r for r in it.records if short_label(r) == label)["result"].get("findings", [])
            got = [f["id"] for f in fs]
            if ".." in spec:
                lo, hi = spec.split("..")
                prefix = lo[:-2]
                want = [f"{prefix}{i:02d}" for i in range(int(lo[-2:]), int(hi[-2:]) + 1)]
                ok = got == want
            elif ":" in spec:
                want = [x.split(":")[0] for x in spec.split(",")]
                sev = [x.split(":")[1] for x in spec.split(",")]
                ok = got == want and [f.get("severity") for f in fs] == sev
            else:
                ok = bool(got) and all(g.startswith(spec) for g in got)
            report(ok, f"{n}: {label}'s findings are {spec} as the log says ({', '.join(got)})")
        author = next(r for r in it.records if short_label(r) == "author")["result"]
        text = " ".join(c.get("criterion", "") for c in author.get("criteria", []))
        missing = [c for c in closed if not (re.search(r"\bR\d-\d\d\b", c) and id_pattern(c).search(text)
                                             or c.isdigit() and re.search(r"[Ff]inding " + c + r"\b", text))]
        report(not missing, f"{n}: the author's criteria name the gate findings the log says the branch closed "
               f"({', '.join(closed)})" + (f"; missing {missing}" if missing else ""))
    ai_fix = next(r for r in items["minors-g05-ai"].records if short_label(r) == "fix-1")["result"]
    ai_fixed = " ".join(e.get("id", "") for e in ai_fix.get("fixed", []))
    ai_not = " ".join(e.get("id", "") for e in ai_fix.get("not_fixed", []))
    report(all(id_pattern(i).search(ai_fixed) for i in ("R7-01", "R7-02", "R7-03"))
           and id_pattern("R7-04").search(ai_not) and not id_pattern("R7-04").search(ai_fixed),
           "minors-g05-ai: fix-1 records R7-01 to R7-03 fixed and R7-04 not fixed, as the log says")
    deps3 = next(r for r in items["deps"].records if short_label(r) == "review-3")["result"]
    report("review R3-05 of the deps item" in log and any(f["id"] == "R3-05" for f in deps3["findings"]),
           "deps: integration log 7.2 cites review R3-05 of the deps item, and deps review-3 has R3-05")
    report("Merged at M0 assembly with its final review's verdict \"reject\" and two serious findings open" in log,
           "deps: integration log section 6 says it was merged with its final verdict reject and two serious findings "
           "open (part 5 reads them in the final round)")
    gate = open(os.path.join(ROOT, "Docs/Stage0/M0-gate.md"), encoding="utf-8").read()
    twelve = [n for n in NAMES if n != "deps"]
    accept = all({r["result"].get("verdict") for r in items[n].finals} == {"accept-with-minor"} for n in twelve)
    report("each returned accept-with-minor (deps: reject" in gate and accept
           and {r["result"].get("verdict") for r in items["deps"].finals} == {"reject"},
           "the gate summary (Section 6.2, last row): each final review returned accept-with-minor, deps reject")
    serious12 = [(n, f["id"]) for n in twelve for r in items[n].finals for f in r["result"].get("findings", [])
                 if f.get("severity") in SERIOUS]
    report("the other twelve M0 items each ended accept-with-minor with no open serious finding" in gate
           and not serious12, "the gate summary (Section 6.1): the twelve other items' final rounds raised no "
           "serious finding" + (f"; found {serious12}" if serious12 else ""))
    for n, path, fragment, label, counts in REPORT_STATEMENTS:
        text = open(os.path.join(ROOT, path), encoding="utf-8").read()
        fs = next(r for r in items[n].records if short_label(r) == label)["result"].get("findings", [])
        got = {}
        for f in fs:
            got[f.get("severity")] = got.get(f.get("severity"), 0) + 1
        report(fragment in text and got == counts, f"{n}: {os.path.basename(path)} says {fragment!r}; {label} has "
               f"{severity_counts(fs)}")

    print()
    print("== 7. What stayed open at the merge, by the records (as each item's Markdown gives it)")
    total = {"raised": 0, "earlier": 0, "prev": 0}
    for n in NAMES:
        raised, earlier, prev_open = items[n].open_at_merge()
        total["raised"] += len(raised)
        total["earlier"] += len(earlier)
        total["prev"] += len(prev_open)
        kinds = {}
        for _, _, s, _ in earlier:
            kinds[s] = kinds.get(s, 0) + 1
        sev = [f.get("severity") for _, f, _, _ in earlier]
        print(f"        {n}: final round {items[n].final_round} ({', '.join(short_label(r) for r in items[n].finals)}): "
              f"{len(raised)} raised ({severity_counts([f for _, f in raised]) or 'none'}); "
              f"{len(earlier)} earlier with no recorded resolution"
              + (f" ({', '.join(f'{v} {k}' for k, v in sorted(kinds.items()))}; "
                 f"{severity_counts([{'severity': s} for s in sev])})" if earlier else "")
              + f"; {len(prev_open)} earlier items the final round marks not resolved")
        serious_earlier = [f"{f['id']} ({short_label(r)}, {f.get('severity')}, {STATE_WORDS[s]})"
                           for r, f, s, _ in earlier if f.get("severity") in SERIOUS]
        if serious_earlier:
            print(f"note    {n}: earlier blocker or major findings these records leave without a resolution, by ID: "
                  + "; ".join(serious_earlier))
    print("-- the final rounds' finding IDs in each item's report or record (the deps item's: ADR-0014), outside this "
          "hand-over's pointer lines; each hit with its context, for a reader to judge which review's finding it cites")
    for n, branch, made, targets in ITEMS:
        ids = sorted({f["id"] for r in items[n].finals for f in r["result"].get("findings", [])})
        hits = 0
        for doc in targets or ["Docs/ADRs/0014-dependency-lock-and-license-inventory.md"]:
            for number, line in enumerate(open(os.path.join(ROOT, doc), encoding="utf-8").read().split("\n"), 1):
                if "item-reviews/" in line:
                    continue
                for fid in ids:
                    for m in id_pattern(fid).finditer(line):
                        hits += 1
                        context = line[max(0, m.start() - 80):m.end() + 40].replace("`", "'")
                        print(f"        {n}: {fid} at {doc}:{number}: ...{context}...")
        if not hits:
            print(f"        {n}: none of {', '.join(ids)}")
    findings = sum(len(r["result"].get("findings", [])) for it in items.values() for r in it.reviews)
    print(f"        in all: {sum(len(it.records) for it in items.values())} records, "
          f"{sum(len(it.reviews) for it in items.values())} reviews, {findings} findings; open at the merge: "
          f"{total['raised']} raised by the final rounds, {total['earlier']} earlier findings with no recorded "
          f"resolution, {total['prev']} earlier items the final rounds mark not resolved")

    adr14 = open(os.path.join(ROOT, "Docs/ADRs/0014-dependency-lock-and-license-inventory.md"),
                 encoding="utf-8").read()
    named = [i for i in ("R4-03", "R4-04", "R4-05", "R4-06", "R4-07") if id_pattern(i).search(adr14)]
    print(f"note    deps: of the final round's minor findings R4-03 to R4-07, ADR-0014 names "
          f"{', '.join(named) or 'none'} (searched by ID)")
    ai = open(os.path.join(ROOT, "Docs/Stage0/G05-AI.md"), encoding="utf-8").read()
    command = "find \"$TMPDIR\" -maxdepth 1 -name 'g05-*' -type d -exec rm -rf {} +"
    print(f"note    minors-g05-ai: the cleanup command R8-04 names is {'still' if command in ai else 'no longer'} in "
          f"G05-AI.md")
    support = open(os.path.join(ROOT, "Spikes/G05-Recovery/Tests/SylviaRecoveryTests/Support.swift"),
                   encoding="utf-8").read()
    print(f"note    minors-g05-ai: G0.5 recovery's tests {'still' if 'temporaryDirectory' in support and '\"g05-tests/' in support else 'no longer'} "
          f"make their scratch directories under g05-tests/ in the temporary folder (Spikes/G05-Recovery/Tests/"
          f"SylviaRecoveryTests/Support.swift)")

    print()
    print("== 8. The Markdown records")
    for n in NAMES:
        path = os.path.join(FOLDER, n + ".md")
        same = os.path.exists(path) and open(path, encoding="utf-8").read() == render(n)
        report(same, f"{n}.md is what `render` writes from extracted/{n}.json.txt")

    print()
    print("== 9. The pointers")
    for n, branch, made, targets in ITEMS:
        for target in targets:
            text = open(os.path.join(ROOT, target), encoding="utf-8").read()
            link = (f"../Stage0/evidence/M0-Integration/item-reviews/{n}.md" if target.startswith("Docs/ADRs/")
                    else f"evidence/M0-Integration/item-reviews/{n}.md")
            lines = [line for line in text.splitlines() if f"]({link})" in line]
            report(len(lines) == 1, f"{n}: {target} has one line linking to {link}")
        if not targets:
            adr = open(os.path.join(ROOT, "Docs/ADRs/0014-dependency-lock-and-license-inventory.md"),
                       encoding="utf-8").read()
            present = "item-reviews/deps.md" in adr
            print(f"note    {n}: ADR-0014 belongs to another workstream; the pointer is requested of its owner "
                  f"({'present' if present else 'not present'} on this branch)")
    print()
    print(f"result: {'pass' if not problems else 'FAIL'} ({len(problems)} problem(s))")
    return 1 if problems else 0


def main():
    parser = argparse.ArgumentParser(description=__doc__.split("\n")[0])
    sub = parser.add_subparsers(dest="command", required=True)
    r = sub.add_parser("render")
    r.add_argument("--check", action="store_true")
    c = sub.add_parser("check")
    c.add_argument("--extraction")
    args = parser.parse_args()
    if args.command == "render":
        differ = []
        for n in NAMES:
            text = render(n)
            path = os.path.join(FOLDER, n + ".md")
            if args.check:
                current = open(path, encoding="utf-8").read() if os.path.exists(path) else None
                print(f"{'ok      ' if current == text else 'PROBLEM '}{n}.md "
                      f"{'is' if current == text else 'is NOT'} what render writes ({len(text)} characters)")
                if current != text:
                    differ.append(n)
            else:
                with open(path, "w", encoding="utf-8") as fh:
                    fh.write(text)
                print(f"wrote {FOLDER_REL}/{n}.md ({len(text)} characters)")
        if args.check:
            print(f"result: {'pass' if not differ else 'FAIL'} ({len(differ)} differing)")
        return 1 if differ else 0
    return check(args.extraction)


if __name__ == "__main__":
    sys.exit(main())
