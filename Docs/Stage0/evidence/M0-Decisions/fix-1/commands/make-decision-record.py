"""Writes Docs/Stage0/evidence/M0-Decisions/fix-1/decision-page-record.json: the product owner's M0 decisions as the
workflow relayed them to the fix round of the decisions round's review (22 October 2026), verbatim, with a header that
says what the file is and where the page itself is. Run once: python3 -I make-decision-record.py <output>."""
import json
import sys

not_recommendation = [
    {"id": "PO-13", "group": "questions", "title": "When the phone reads the device inbox", "choice": "b",
     "is_recommendation": False,
     "chosen": "(b) also periodically in the background, which iOS runs only when it chooses, so it adds no promise of timely delivery",
     "note": ""},
    {"id": "PO-23", "group": "questions", "title": "The locked-device test T50", "choice": "b", "is_recommendation": False,
     "chosen": "(b) build the harness in Stage 0 now, before the device run", "note": ""},
    {"id": "PO-33", "group": "questions", "title": "The bundled onboarding sample", "choice": "change", "is_recommendation": False,
     "chosen": "change",
     "note": "All three (Middlemarch, Walden, Meditations), clearly marked as removable samples; pair Meditations with its LibriVox audio excerpt."},
    {"id": "PO-39", "group": "questions", "title": "Playback control defaults (draft 0.7)", "choice": "change",
     "is_recommendation": False, "chosen": "change",
     "note": "Accept mostly, but also consider other audiobook players have ways to rewind a bit further back to restart if you pick up after not listening for a while."},
    {"id": "D-1", "group": "runbook",
     "title": "(i) Which phone is device A, the oldest supported iPhone; (ii) whether the iPad's steps (runbook Session 9) are part of M0",
     "choice": "b", "is_recommendation": False,
     "chosen": "(b) an older phone iOS 26 supports (iPhone 11 family, iPhone SE (2nd generation)): plan 19.1 and ADR-0001 change, every budget measured on it is stricter, and the SE's 375 × 667 pt screen becomes the layout floor on a device. (ii)",
     "note": "I have access to an iPhone 11 and 11 pro."},
]

clarifications = {
    "D-1": "Part (i): option (b), the iPhone 11 family. The owner has an iPhone 11 and an iPhone 11 Pro; device A, the oldest supported iPhone, is the iPhone 11 Pro (A13, 375 x 812 pt, the narrower layout floor of the two), with the iPhone 11 available as a second A13 phone. The iPhone SE (2nd generation) 375 x 667 pt floor is not available as a device and stays a simulator check. Part (ii): option (c), keep the iPad steps (runbook Session 9) in M0. (The decision page offered one choice across both parts; the owner answered part (ii) separately on 22 October 2026.)",
    "PO-39": "Accept the recommended defaults (15 s back and 15 s forward; both sleep-timer kinds) except the rewind after a long pause: it is ON by default and graduated, as other audiobook players do (for example about 10 s after a pause of a few minutes, rising to about 60 s after a day; exact steps to be set in M4 within those bounds and stated in ADR-0006), shown with a brief notice that offers Undo, configurable and able to be turned off in Settings, and it never changes a saved bookmark, quote or capture anchor (plan 10.1). Owner's note: 'Accept mostly, but also consider other audiobook players have ways to rewind a bit further back to restart if you pick up after not listening for a while.'",
    "PO-33": "All three Standard Ebooks (CC0) samples ship in M2: Middlemarch, Walden and Meditations, each a short excerpt, clearly marked as samples and removable; Meditations is paired with its LibriVox (public domain) audio excerpt so onboarding can show listening and capture too; provenance in Fixtures/LICENSES.md.",
    "PO-23": "Option (b): build the background-audio harness for the locked-device test (T50, G0.5 recovery device step 3) now in Stage 0, before the device run, so the run is conclusive the first time. The app-level unavailable-before-first-unlock state stays in M1 with the app shell.",
    "PO-13": "Option (b): the phone reads the device inbox on launch, on returning to the foreground and when the Inbox is shown, and also periodically in the background when iOS runs the app (opportunistic; no promise of timely delivery; plan 15.1 still promises no real-time delivery).",
    "SIGNOFFS": "The project is a solo project. The product owner signs the plan 23.3 roles (security reviewer, QA, design, technical lead) personally, each recorded only after the device sessions have produced the evidence that role signs; until then each stays pending. Records stay honest that all reviews so far were done by agents, not independent people, and recommend an outside security review before any public release.",
}

choices = [
    ("PO-01", "a", True, ""), ("PO-02", "a", True, ""), ("PO-03", "a", True, ""), ("PO-04", "a", True, ""),
    ("PO-05", "a", True, ""), ("PO-06", "a", True, ""), ("PO-07", "a", True, ""), ("PO-08", "a", True, ""),
    ("PO-09", "recommended", True, ""), ("PO-10", "a", True, ""), ("PO-11", "a", True, ""),
    ("PO-12", "recommended", True, ""), ("PO-13", "b", False, ""), ("PO-14", "recommended", True, ""),
    ("PO-15", "a", True, ""), ("PO-16", "c", True, ""), ("PO-17", "a", True, ""), ("PO-18", "recommended", True, ""),
    ("PO-19", "a", True, ""), ("PO-20", "recommended", True, ""), ("PO-21", "a", True, ""), ("PO-22", "a", True, ""),
    ("PO-23", "b", False, ""), ("PO-24", "recommended", True, ""), ("PO-25", "a", True, ""), ("PO-26", "a", True, ""),
    ("PO-27", "a", True, ""), ("PO-28", "recommended", True, ""), ("PO-29", "a", True, ""), ("PO-30", "a", True, ""),
    ("PO-31", "a", True, ""), ("PO-32", "recommended", True, ""),
    ("PO-33", "change", False, "All three (Middlemarch, Walden, Meditations), clearly marked as removable samples; pair Meditations with its LibriVox audio excerpt."),
    ("PO-34", "b", True, ""),
    ("PO-35", "recommended", True, "Decided 20 Oct 2026 in chat: re-pin to Xcode 27.1 (27A9275), the version installed. Done in PR #5. Still to do: turn off App Store automatic updates for Xcode. Update from owner: auto updates is confirmed disabled."),
    ("PO-36", "a", True, ""), ("PO-37", "a", True, ""), ("PO-38", "a", True, ""),
    ("PO-39", "change", False, "Accept mostly, but also consider other audiobook players have ways to rewind a bit further back to restart if you pick up after not listening for a while."),
    ("PO-40", "a", True, ""), ("PO-41", "b", True, ""), ("PO-42", "recommended", True, ""), ("PO-43", "a", True, ""),
    ("PO-44", "recommended", True, ""),
    ("D-1", "b", False, "I have access to an iPhone 11 and 11 pro."),
    ("D-10", "recommended", True, ""), ("D-2", "a", True, ""),
    ("D-3", "recommended", True, "Decided with PO-35 (Xcode 27.1)."),
    ("D-4", "a", True, ""), ("D-5", "recommended", True, ""), ("D-6", "recommended", True, ""),
    ("D-7", "recommended", True, ""), ("D-8", "recommended", True, ""), ("D-9", "b", True, ""),
]
choices += [("D%02d" % n, "approve", True, "") for n in range(1, 18)]
choices += [("A%02d" % n, "approve", True, "") for n in range(1, 57)]
choices += [("H-1", "a", True, "")]

record = {
    "what": ("The product owner's decisions on the M0 decision page (approved 22 October 2026) and the clarifications the "
             "owner gave in conversation the same day, as the workflow relayed them, verbatim, to the fix round of the "
             "decisions round's review on 22 October 2026. Not the page itself: the page is outside this repository (a "
             "page the workflow built from Docs/Stage0/M0-gate.md, M0-plan-amendments.md and M0-device-runbook.md at "
             "40ba6bc; integration log section 15.1), and no other copy is committed. The decisions round's records "
             "(integration log sections 15-17) say its data was relayed to it the same way; the review of that round "
             "compared the five choices that differ from the recommendation, and the clarifications, with the data "
             "relayed to it, and they matched (its finding HON-9, which asked for this record). Each choice is the page's option letter, 'recommended', 'approve' or 'change'; 'rec' says "
             "whether it is the recommendation; the clarifications are authoritative where they add to the page."),
    "relayed_to": "the fix round of the review of the decisions round (branch m0-decisions, reviewed at 88d4e1c7), 22 October 2026",
    "count": len(choices),
    "not_recommendation": not_recommendation,
    "clarifications": clarifications,
    "choices": [{"id": i, "choice": c, "rec": r, "note": n} for i, c, r, n in choices],
}
assert len(choices) == 128, len(choices)
assert len({c[0] for c in choices}) == 128
assert sorted(c[0] for c in choices if not c[2]) == sorted(x["id"] for x in not_recommendation)
with open(sys.argv[1], "w", encoding="utf-8") as handle:
    json.dump(record, handle, ensure_ascii=False, indent=1)
    handle.write("\n")
print("wrote %d choices, %d not the recommendation" % (len(choices), len(not_recommendation)))
