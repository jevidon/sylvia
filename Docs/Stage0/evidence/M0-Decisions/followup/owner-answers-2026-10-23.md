# The product owner's answers of 23 October 2026, as relayed

The product owner's answers of 23 October 2026 to the points the M0 decisions of 22 October 2026 left open, as the workflow that ran the follow-up round relayed them, verbatim, to that round (integration log section 20). The owner gave them in conversation with the orchestrating session; that conversation is outside this repository, and no other copy is committed. The workflow called them authoritative and asked that each be recorded wherever the records listed it as open, waiting or to confirm. Each entry gives the answer as relayed, the open items it settles as the records had them at `a1ea66d2`, and where the follow-up recorded it. A decision is not a device result: nothing here changes a device or human step's status.

This record is Markdown, not JSON as the first fix's record of the decision page is (`../fix-1/decision-page-record.json`): answer 5 names an App Transport Security key, which the hard-rule audit (`Scripts/audit-hard-rules.sh`, rule `ats-exception`) rightly refuses in any configuration file, `.json` included, while a document may name it.

- **Relayed to:** the follow-up round of the M0 decisions round (branch `m0-decisions`, from `a1ea66d2`), 23 October 2026.

## 1. H-1: pull request #5 and the merge of `m0-decisions`

> H-1's one-off exception also covers pull request #5 and the merge of m0-decisions into main before the M0 exit. The branch rule stays; M0 stays formally pending until the device sessions and sign-offs.

- **Settles:** ADR-0002's open items (whether pull request #5 is covered by H-1's exception; whether a merge of `m0-decisions` into `main` before the M0 exit review would be); `M0-gate.md` Section 1, item 4 (Merges), and Section 6.3, item 1.
- **Recorded in:** ADR-0002 (status, date, Deciders, Branches, Open items); the ADR index; `M0-gate.md` (Sections 1, 2.9 row 92, 6.3 item 1, 7 and 8); the runbook (header, run 1, 0.3); its session log (row 1); the Stage 0 README; the repository README; the integration log (section 20, and dated notes in 17.5, 18.5 and 19.5).

## 2. PO-12's two open parts: the sources file and the import ledger

> PO-12's two open parts: set aside and recover. A damaged sources file is moved aside for the diagnostic export and every Mac is paired again; a damaged import ledger is moved aside and an item already imported may arrive again as a duplicate for review (plan 7.3, 8.1). Transfers keep working. (The job store's (a) stands.)

- **Settles:** plan 15.5 and Appendix D (the repair path for a damaged sources file or import ledger, the product owner's to decide); ADR-0009's open items; `G02-Transfer.md` open question 8; `M0-plan-amendments.md` PO-12; `M0-gate.md` Sections 1 (item 4), 4.1 and 5.4.
- **Recorded in:** the plan (15.5, Appendix D); ADR-0009; the ADR index; `G02-Transfer.md` (open question 8); `M0-plan-amendments.md` (header, Section 4); `M0-gate.md` (Sections 1, 4, 5.4 and 7); the integration log.

## 3. PO-41 to PO-44, the questions left for counsel

> PO-41 to PO-44 (the questions left for counsel): the owner handles them for now: the recommended defaults apply to the owner's own and TestFlight builds, with the notices the licenses require; a lawyer's review comes before any public App Store release. PO-42 (BoringSSL's advertising clauses) included.

- **Settles:** ADR-0014 section 7, items 1, 2, 3 and 8 (counsel's part); plan 23.1's D13 row (its pending text); `M0-plan-amendments.md` PO-41 to PO-44; `M0-gate.md` Sections 1 (item 4, Counsel), 3 (D13), 4.1, 4.2 and 7 (item 4).
- **Recorded in:** ADR-0014 (status, Deciders, sections 4 and 7, Open items); the ADR index; the plan (23.1 D13, Appendix D); `M0-plan-amendments.md` (header, Section 4); `M0-gate.md` (Sections 1, 2.8 row 77, 3, 4, 5.4 and 7); the integration log.
- **Not changed:** `Docs/Licenses/inventory.json` and the acknowledgements draft it generates keep their markings for counsel ("pending counsel", "Pending (not yet decided)"): the lawyer's review they wait for is still to come, before any public App Store release, and `12-dependency-lock` requires the draft to equal what the inventory generates.

## 4. The iPad for Session 9

> The owner has an iPad with a keyboard and a trackpad or mouse for Session 9 (model recorded at Session 0).

- **Settles:** `M0-gate.md` Section 1, item 1 (an iPad, if you do not have one); the runbook's 1.1 row C and run 1; ADR-0001's open item and Test devices; plan 19.1, 21.1 and the device-evidence risk row; the G0.6 checklist's device line C.
- **Recorded in:** `M0-gate.md` (Sections 1 and 4.3); the runbook (header, 1.1, run 1, 0.4, D-1); its session log (row 1); the G0.6 checklist (header, device line C); ADR-0001 (Test devices, Open items); the plan (19.1, 21.1, 23.2, Appendix D); `G01-EPUB.md` (open question 8); the integration log.
- **Still to record:** the iPad's model, identifier and iPadOS version and build, at the runbook's Session 0.4.

## 5. Three readings of the decisions of 22 October 2026

> Readings confirmed: D-6 (Stage 0 ADRs stay Proposed until Session 10's review of each), D-7 (draft 0.6's two merge wordings kept), D-9 (b) (the ATS key is NSAllowsLocalNetworking).

- **Settles:** `M0-gate.md` Section 1, item 4 (three readings to confirm), and Section 6.3, item 30 (if you meant D-6 to approve the ADRs now, say so); the integration log's 17.3, 17.5, 18.5 and 19.5 (readings for the owner to confirm).
- **Recorded in:** `M0-gate.md` (Sections 1, 4.3, 6.3 item 30); the runbook (D-6, D-7, D-9); the plan (Appendix D, the draft 0.6 entry); the integration log.
