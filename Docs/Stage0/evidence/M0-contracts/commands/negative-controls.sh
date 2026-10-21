#!/usr/bin/env bash
# Shows that Scripts/check-spike-anchors.py fails when spike output, a fixture, a schema, a related contract or the
# design package's kind mapping breaks a contract rule (ADR-0016). Each control copies the inputs the checker reads into
# a scratch root, makes one change, runs the checker against that root and expects a failure whose error line contains
# the given text (the rule, field or record). The repository itself is never modified. Output:
# Docs/Stage0/evidence/M0-contracts/negative-controls.log.
#
#   Docs/Stage0/evidence/M0-contracts/commands/negative-controls.sh
set -euo pipefail
source "$(cd "$(dirname "$0")/../../../../../Scripts/lib" && pwd)/env.sh"

scratch="$SYLVIA_ROOT/.build/scratch/m0-contracts/controls"
log="$SYLVIA_ROOT/Docs/Stage0/evidence/M0-contracts/negative-controls.log"
inputs=(
  Contracts/schemas Contracts/openapi Contracts/design Contracts/fixtures/anchor.v1 Contracts/fixtures/capture-envelope.v1
  Docs/Stage0/evidence/G01-EPUB/anchor-samples.json Docs/Stage0/evidence/G01-EPUB/selection-samples.json
  Docs/Stage0/evidence/G01-PDF/anchor-samples.json Docs/Stage0/evidence/M0-contracts/g04-capture-records
  Docs/Stage0/evidence/G01-PDF/anchor-composed-samples.json
  Spikes/G05-Recovery/Tests/SylviaRecoveryTests/Fixtures/library-v1.sqlite
)

# Taken before this run writes its own log (inside clean-run.sh: the count before the clean run began).
if [[ -n "${SYLVIA_CLEAN_RUN_UNCOMMITTED:-}" ]]; then
  uncommitted="$SYLVIA_CLEAN_RUN_UNCOMMITTED before the clean run (clean-run.sh)"
else
  uncommitted="$(git -C "$SYLVIA_ROOT" status --porcelain | wc -l | tr -d ' ') before this run"
fi
exec > >(tee "$log") 2>&1
echo "command: Docs/Stage0/evidence/M0-contracts/commands/negative-controls.sh"
echo "commit: $(git -C "$SYLVIA_ROOT" rev-parse HEAD) (uncommitted files: $uncommitted)"
echo "host: $(sw_vers -productName) $(sw_vers -productVersion) ($(sw_vers -buildVersion)); python: $("$SYLVIA_TOOLS_VENV/bin/python" --version)"

fresh_root() {
  rm -rf "$scratch"
  for p in "${inputs[@]}"; do
    mkdir -p "$scratch/$(dirname "$p")"
    cp -R "$SYLVIA_ROOT/$p" "$scratch/$p"
  done
}

detected=0
failed=0
# control <name> <expected text in an error line of the checker output> <python statements editing files under ROOT>
control() {
  local name="$1" expect="$2" edit="$3" out
  fresh_root
  sylvia_python -I -c "import json, pathlib, sqlite3
ROOT = pathlib.Path('$scratch')
def edit(path, fn):
    p = ROOT / path; d = json.loads(p.read_text(encoding='utf-8')); fn(d); p.write_text(json.dumps(d, ensure_ascii=False), encoding='utf-8')
def g04(key, fn):
    for f in sorted((ROOT / 'Docs/Stage0/evidence/M0-contracts/g04-capture-records/records').glob('*.json')):
        d = json.loads(f.read_text(encoding='utf-8'))
        if d['idempotencyKey'] == key:
            fn(d); f.write_text(json.dumps(d), encoding='utf-8')
def recovery(*statements):
    db = sqlite3.connect(ROOT / 'Spikes/G05-Recovery/Tests/SylviaRecoveryTests/Fixtures/library-v1.sqlite')
    db.execute('PRAGMA ignore_check_constraints = ON')
    for s in statements: db.execute(s)
    db.commit(); db.close()
$edit"
  if out="$(sylvia_python -I "$SYLVIA_ROOT/Scripts/check-spike-anchors.py" --root "$scratch" 2>&1)"; then
    echo "CONTROL NOT DETECTED: $name (checker passed)"; failed=$((failed + 1)); return 0
  fi
  if ! grep '^error:' <<<"$out" | grep -qF -- "$expect"; then
    echo "CONTROL FAILED FOR ANOTHER REASON: $name"; grep '^error:' <<<"$out" | head -5; tail -5 <<<"$out"
    failed=$((failed + 1)); return 0
  fi
  detected=$((detected + 1))
  echo "detected: $name"
  grep '^error:' <<<"$out" | grep -F -- "$expect" | head -2 | sed 's/^/    /'
}

fresh_root
sylvia_python -I "$SYLVIA_ROOT/Scripts/check-spike-anchors.py" --root "$scratch" | tail -1 | sed 's/^/baseline (unchanged copy): /'

# --- Other contracts
control "design package export still mapping the draft's kind 'quote' to the Quote marker" "design package maps kinds" \
  "edit('Contracts/design/marginalia.v1.json', lambda d: d['capture_kind_mapping']['kinds'].update({'quote': d['capture_kind_mapping']['kinds'].pop('text_quote')}))"

control "context-pack contract gains a provider kind the saved-answer endpoint lacks" "generated_answer.endpoint.provider_kind" \
  "edit('Contracts/schemas/context-pack.v1.schema.json', lambda d: d['properties']['endpoint']['properties']['provider_kind']['enum'].append('google_genai'))"

# --- Patterns (review finding L2-R2-01)
control "anchor.v1 secret-name pattern back in its inline (?i) form" "not ECMA-262 with the u flag" \
  "edit('Contracts/schemas/anchor.v1.schema.json', lambda d: d['\$defs']['not_secret_name']['not'].update(pattern='(?i)^(api[_-]?key|apikey|key|secret|client[_-]?secret|password|passwd|token|access[_-]?token|auth[_-]?token|bearer|authorization|x[_-]api[_-]key|credential|credentials)\$'))"

control "anchor.v1 secret-name pattern losing one name the context-pack pattern has" "is not the context-pack secret-name pattern" \
  "edit('Contracts/schemas/anchor.v1.schema.json', lambda d: d['\$defs']['not_secret_name']['not'].update(pattern=d['\$defs']['not_secret_name']['not']['pattern'].replace('|[Bb][Ee][Aa][Rr][Ee][Rr]', '')))"

control "another owner's contract gains an inline (?i) pattern" "backup-manifest.v1.schema.json" \
  "def f(d):
    def walk(n):
        if isinstance(n, dict):
            if isinstance(n.get('pattern'), str):
                n['pattern'] = '(?i)' + n['pattern']; return True
            return any(walk(v) for v in n.values())
        return isinstance(n, list) and any(walk(v) for v in n)
    walk(d)
edit('Contracts/schemas/backup-manifest.v1.schema.json', f)"

control "context-pack secret-name pattern made portable while still recorded as not portable" "recorded as not portable but now compiles" \
  "anchor = json.loads((ROOT / 'Contracts/schemas/anchor.v1.schema.json').read_text(encoding='utf-8'))
edit('Contracts/schemas/context-pack.v1.schema.json', lambda d: d['\$defs']['notSecretName']['not'].update(pattern=anchor['\$defs']['not_secret_name']['not']['pattern']))"

# --- Schemas weakened: each listed invalid fixture now fails differently (review finding R1-01)
control "the reviewer's deletion: generated_answer and note may carry quoted_text, a text_quote need not" "generated-answer-with-quoted-text.json: schema errors [none]" \
  "def f(d):
    for rule in d['allOf']:
        if rule.get('title') in ('generated_answer', 'note'):
            rule['then']['not']['anyOf'] = [b for b in rule['then']['not']['anyOf'] if b != {'required': ['quoted_text']}]
        if rule.get('title') == 'text_quote':
            rule['then']['required'].remove('quoted_text')
edit('Contracts/schemas/capture-envelope.v1.schema.json', f)"

control "capture schema without the typed-quotation rule (review finding R1-02)" "quote-typed-at-an-epub-anchor.json: schema errors [none]" \
  "edit('Contracts/schemas/capture-envelope.v1.schema.json', lambda d: d['allOf'].remove(next(r for r in d['allOf'] if r.get('title') == 'typed-quote-has-no-reader-anchor')))"

control "anchor schema without the asset digest on PDF anchors (review finding R1-07)" "pdf-missing-asset-sha256.json: schema errors [none]" \
  "edit('Contracts/schemas/anchor.v1.schema.json', lambda d: d['\$defs']['pdf']['required'].remove('asset_sha256'))"

control "capture schema whose transcript-origin rule covers only machine transcripts (review finding R2-01)" "audio-corrected-transcript-without-transcript.json: schema errors [none]" \
  "def f(d):
    rule = next(r for r in d['allOf'] if r.get('title') == 'transcript-origin')
    rule['if']['properties']['quoted_text_origin']['enum'] = ['machine_transcript']
edit('Contracts/schemas/capture-envelope.v1.schema.json', f)"

control "anchor schema whose millisecond definition allows fractions (review finding R2-01)" "audio-fractional-start-milliseconds.json: schema errors [none]" \
  "edit('Contracts/schemas/anchor.v1.schema.json', lambda d: d['\$defs']['int64_non_negative'].pop('type'))"

# --- Fixtures edited
control "valid quote fixture whose origin becomes user_entered at its EPUB anchor (review finding R1-02)" "typed-quote-has-no-reader-anchor" \
  "edit('Contracts/fixtures/capture-envelope.v1/valid/quote-epub.json', lambda d: d.update(quoted_text_origin='user_entered'))"

control "valid fixture edited so the quote no longer equals its anchor" "C2" \
  "edit('Contracts/fixtures/capture-envelope.v1/valid/word-epub.json', lambda d: d.update(quoted_text='beneficence '))"

control "valid quotation beside a later writer's anchor whose text no longer equals its EPUB anchor (review finding R2-03)" "unknown-kind-anchor-beside-an-epub-selection.json: C2" \
  "edit('Contracts/fixtures/capture-envelope.v1/valid/unknown-kind-anchor-beside-an-epub-selection.json', lambda d: d.update(quoted_text='Words that appear nowhere in the anchored passage.'))"

control "valid fixture of a v1 writer using an unknown kind" "writer profile" \
  "edit('Contracts/fixtures/capture-envelope.v1/valid/note-edition-unknown.json', lambda d: d.update(kind='journal'))"

control "invalid fixture with a second change" "is not its base with the listed operations" \
  "edit('Contracts/fixtures/anchor.v1/invalid/epub-position-zero.json', lambda d: d.update(prefix=''))"

control "semantic-invalid fixture whose listed change breaks a second rule" "expected exactly one violation of C6" \
  "folder = ROOT / 'Contracts/fixtures/capture-envelope.v1'
ops = json.loads((folder / 'mutations.json').read_text(encoding='utf-8'))
doc = json.loads((folder / 'valid/quote-epub.json').read_text(encoding='utf-8'))
note = dict(doc['notes'][0], current_revision=1)
note['revisions'] = [dict(note['revisions'][0], body='First thought.\ud800'), note['revisions'][1]]
for e in ops:
    if e['fixture'] == 'semantic-invalid/c6-current-revision-not-latest.json':
        e['ops'] = [{'op': 'replace', 'path': '/notes/0', 'value': note}]
doc['notes'][0] = note
(folder / 'mutations.json').write_text(json.dumps(ops), encoding='utf-8')
(folder / 'semantic-invalid/c6-current-revision-not-latest.json').write_text(json.dumps(doc), encoding='utf-8')"

# --- G0.4 records
control "G0.4 cross-file record whose second range does not start at 0" "A6" \
  "def f(d):
    d['ranges'][1]['startMs'] = 500; d['excerpt']['saved']['_0']['requestedRanges'][1]['startMs'] = 500
g04('m0-contracts-cross-file', f)"

control "G0.4 record whose excerpt names a different asset than its range" "C4" \
  "g04('m0-contracts-single', lambda d: d['excerpt']['saved']['_0']['actualRanges'][0].update(assetID='00000000-0000-4000-8000-000000000402'))"

control "G0.4 record whose excerpt has an empty actual range" "C4" \
  "g04('m0-contracts-single', lambda d: d['excerpt']['saved']['_0']['actualRanges'][0].update(endMs=d['excerpt']['saved']['_0']['actualRanges'][0]['startMs']))"

control "G0.4 record whose excerpt claims audio from elsewhere in the file (review finding R1-10)" "does not overlap" \
  "def f(d):
    d['excerpt']['saved']['_0']['actualRanges'][0].update(startMs=0, endMs=30000)
g04('m0-contracts-single', f)"

control "G0.4 record whose excerpt overlaps the requested range by 1 ms (review finding R2-02)" "more than 500 ms" \
  "def f(d):
    d['excerpt']['saved']['_0']['actualRanges'][0].update(startMs=89999, endMs=119999)
g04('m0-contracts-single', f)"

control "G0.4 failed record whose reason holds a UNC path (review finding R2-07)" "reason" \
  "g04('m0-contracts-failed', lambda d: d['excerpt']['failed'].update(reason='cannot open \\\\\\\\nas\\\\audiobooks\\\\Part 3.mp3'))"

control "G0.4 record saved without a read-back duration (outputDurationMs nil)" "duration_ms" \
  "g04('m0-contracts-single', lambda d: d['excerpt']['saved']['_0'].pop('outputDurationMs'))"

control "G0.4 record that read back 1 ms for 30 s of ranges (review finding R1-10)" "C9" \
  "g04('m0-contracts-single', lambda d: d['excerpt']['saved']['_0'].update(outputDurationMs=1))"

control "G0.4 preserved record whose store made one durable write (review finding R1-10)" "C8" \
  "edit('Docs/Stage0/evidence/M0-contracts/g04-capture-records/context.json', lambda d: d['durable_writes'].update({k: 1 for k in d['durable_writes']}))"

control "G0.4 record whose failure reason holds a file path" "reason" \
  "g04('m0-contracts-failed', lambda d: d['excerpt']['failed'].update(reason='decodeFailed(\"/private/var/mobile/Part 3.mp3\")'))"

control "G0.4 record with a capture kind v1 does not have" "writer profile" \
  "g04('m0-contracts-pending', lambda d: d.update(kind='clip'))"

control "G0.4 record with an origin G0.4 does not write" "cannot be adapted" \
  "g04('m0-contracts-pending', lambda d: d.update(origin='harness'))"

# --- G0.1 samples
control "G0.1 EPUB sample whose quoted text differs from its anchor" "C2" \
  "edit('Docs/Stage0/evidence/G01-EPUB/anchor-samples.json', lambda d: d['capture_samples'][0].update(quoted_text=d['capture_samples'][0]['quoted_text'] + ' '))"

control "G0.1 EPUB two-resource quotation whose second anchor lost its segment" "C3" \
  "edit('Docs/Stage0/evidence/G01-EPUB/anchor-samples.json', lambda d: d['capture_samples'][5]['anchors'][1].pop('segment'))"

control "G0.1 EPUB anchor whose offsets cover one more scalar than its text" "A2" \
  "edit('Docs/Stage0/evidence/G01-EPUB/anchor-samples.json', lambda d: d['capture_samples'][3]['anchors'][0]['text_offsets'].update(end=d['capture_samples'][3]['anchors'][0]['text_offsets']['end'] + 1))"

control "G0.1 EPUB anchor with UTF-16 offsets" "text_offsets/unit" \
  "edit('Docs/Stage0/evidence/G01-EPUB/anchor-samples.json', lambda d: d['capture_samples'][4]['anchors'][0]['text_offsets'].update(unit='utf16'))"

control "G0.1 PDF anchor whose range no longer covers its text" "A2" \
  "edit('Docs/Stage0/evidence/G01-PDF/anchor-samples.json', lambda d: d['samples'][0]['anchor']['segments'][0]['text_range'].update(end=190))"

control "G0.1 PDF two-page selection whose exact text joins the pages with a space" "A3" \
  "edit('Docs/Stage0/evidence/G01-PDF/anchor-samples.json', lambda d: d['samples'][8]['anchor'].update(exact_text=' '.join(s['text'] for s in d['samples'][8]['anchor']['segments'])))"

# The composed selections the G0.1 PDF spike stores (anchor-composed-samples.json, read by the checker since the M0 final
# fix; an input of these controls since its second review round, contracts R2-02), against each branch of rule A3.
control "G0.1 PDF composed selection whose exact text joins its two pieces with a space" "anchor-composed-samples.json two pieces on one page, two lines apart: A3" \
  "edit('Docs/Stage0/evidence/G01-PDF/anchor-composed-samples.json', lambda d: d['samples'][0]['anchor'].update(exact_text=' '.join(s['text'] for s in d['samples'][0]['anchor']['segments'])))"

control "G0.1 PDF composed selection across a page change whose exact text drops that page's U+000A" "exact_text has no U+000A between two segments on different pages" \
  "edit('Docs/Stage0/evidence/G01-PDF/anchor-composed-samples.json', lambda d: d['samples'][6]['anchor'].update(exact_text=d['samples'][6]['anchor']['exact_text'].replace('\\nBody', 'Body')))"

control "G0.1 PDF anchor with a 45-degree rotation" "page_rotation" \
  "edit('Docs/Stage0/evidence/G01-PDF/anchor-samples.json', lambda d: d['samples'][3]['anchor']['segments'][0].update(page_rotation=45))"

control "G0.1 PDF line rectangle reaching past the page box, x + w = 1.4 (review finding R1-04)" "A7" \
  "edit('Docs/Stage0/evidence/G01-PDF/anchor-samples.json', lambda d: d['samples'][0]['anchor']['segments'][0]['line_rects'].__setitem__(0, [0.9, 0.5, 0.5, 0.01]))"

# --- G0.5 recovery library
control "G0.5 recovery note capture given quoted text" "golden-physical-note: unrecorded difference: not at /" \
  "recovery(\"UPDATE capture SET quoted_text = 'x' WHERE kind = 'note'\")"

control "G0.5 recovery capture of a kind the envelope does not know" "has no envelope kind" \
  "recovery(\"UPDATE capture SET kind = 'clip' WHERE kind = 'word'\")"

control "G0.5 recovery EPUB quotation whose capture lost its edition (an unrecorded difference)" "golden-epub-quote: unrecorded difference: required 'edition_id'" \
  "recovery(\"UPDATE capture SET edition_id = NULL WHERE idempotency_key = 'golden-epub-quote'\")"

control "G0.5 recovery PDF range corrected to 60 scalars: a recorded deviation no longer observed" "recorded deviation pdf-range-length is no longer observed" \
  "recovery(\"UPDATE capture_anchor SET locator_json = json_set(locator_json, '\$.text_range[1]', 940) WHERE kind = 'pdf'\")"

control "G0.5 recovery EPUB text digest that is not the quotation's" "exact_text_sha256 is not the SHA-256" \
  "recovery(\"UPDATE capture_anchor SET locator_json = json_set(locator_json, '\$.exact_text_sha256', '0000000000000000000000000000000000000000000000000000000000000000') WHERE kind = 'epub' AND locator_json LIKE '%exact_text_sha256%'\")"

control "G0.5 recovery conversation note moved onto a capture: a recorded deviation no longer observed (review finding R2-04)" "recorded deviation note-on-conversation is no longer observed" \
  "recovery(\"UPDATE note SET conversation_id = NULL, capture_id = (SELECT id FROM capture WHERE idempotency_key = 'golden-epub-quote') WHERE conversation_id IS NOT NULL\")"

control "G0.5 recovery library gaining a transcript table: a recorded deviation no longer observed (review finding R2-04)" "recorded deviation audio-no-transcript is no longer observed" \
  "recovery('CREATE TABLE capture_transcript (capture_id TEXT NOT NULL, raw_text TEXT NOT NULL)')"

# The work-level note is chosen by query (a note on a whole work: no capture and no conversation; the earliest), not by
# a fixed ID: the library was regenerated at M0 assembly, its notes got new IDs, and this control, which named the old
# one, changed nothing from then until the M0 final review's second round found it (contracts R2-02).
work_note="$(sqlite3 -readonly "$SYLVIA_ROOT/Spikes/G05-Recovery/Tests/SylviaRecoveryTests/Fixtures/library-v1.sqlite" \
  "SELECT id FROM note WHERE capture_id IS NULL AND conversation_id IS NULL ORDER BY created_at_ms, id LIMIT 1")"
[[ "$work_note" =~ ^[0-9a-f-]{36}$ ]] || { echo "PROBLEM: no work-level note in the G0.5 recovery library"; exit 1; }
echo "work-level note for the next control: ${work_note:0:8} (the earliest note with no capture and no conversation)"
control "G0.5 recovery work-level note whose revisions skip a number (the mapped note capture is checked)" "work note ${work_note:0:8}: unrecorded difference: C6" \
  "recovery(\"UPDATE note_revision SET revision = 2 WHERE note_id = '$work_note'\")"

rm -rf "$scratch"
echo "controls detected for the expected reason: $detected; not detected or failed for another reason: $failed"
exit $(( failed != 0 ))
