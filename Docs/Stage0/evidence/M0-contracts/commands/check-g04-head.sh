#!/usr/bin/env bash
# Shows that the G0.4 capture probe still runs against later m0-g04-audio commits and that what G0.4 writes there
# still fits the contracts (ADR-0016 open item; review finding R1-08). Output: Docs/Stage0/evidence/M0-contracts/
# g04-head-check.log. The committed records (g04-capture-records/, written at 943d5e7, from which the fixtures are
# built) are not replaced.
#
#   Docs/Stage0/evidence/M0-contracts/commands/check-g04-head.sh [g04-commit ...]
#
# Default commits: 943d5e7 (the committed records' commit, to show the current probe reproduces their format) and the
# current m0-g04-audio head. For each commit: run-g04-capture-probe.sh into a scratch directory; compare every record's
# structure (its JSON key paths, values ignored) with the committed record of the same idempotency key; then copy the
# checker's inputs into a scratch root with these records in place of the committed ones and run
# Scripts/check-spike-anchors.py there. Nothing is played: the probe only decodes and encodes.
set -euo pipefail
source "$(cd "$(dirname "$0")/../../../../../Scripts/lib" && pwd)/env.sh"

here="$SYLVIA_ROOT/Docs/Stage0/evidence/M0-contracts/commands"
scratch="$SYLVIA_ROOT/.build/scratch/m0-contracts/g04-head"
log="$SYLVIA_ROOT/Docs/Stage0/evidence/M0-contracts/g04-head-check.log"
committed="$SYLVIA_ROOT/Docs/Stage0/evidence/M0-contracts/g04-capture-records"
if [[ $# -gt 0 ]]; then commits=("$@"); else commits=(943d5e778de2b58f47343f0e146f9e3ed7baa70e m0-g04-audio); fi
inputs=(
  Contracts/schemas Contracts/design Contracts/fixtures/anchor.v1 Contracts/fixtures/capture-envelope.v1
  Docs/Stage0/evidence/G01-EPUB/anchor-samples.json Docs/Stage0/evidence/G01-EPUB/selection-samples.json
  Docs/Stage0/evidence/G01-PDF/anchor-samples.json
  Spikes/G05-Recovery/Tests/SylviaRecoveryTests/Fixtures/library-v1.sqlite
)

uncommitted="$(git -C "$SYLVIA_ROOT" status --porcelain | wc -l | tr -d ' ')"
exec > >(tee "$log") 2>&1
echo "command: Docs/Stage0/evidence/M0-contracts/commands/check-g04-head.sh $*"
echo "commit: $(git -C "$SYLVIA_ROOT" rev-parse HEAD) (branch $(git -C "$SYLVIA_ROOT" rev-parse --abbrev-ref HEAD); uncommitted files before the run: $uncommitted)"
echo "m0-g04-audio head: $(git -C "$SYLVIA_ROOT" rev-parse m0-g04-audio)"
echo "host: $(sw_vers -productName) $(sw_vers -productVersion) ($(sw_vers -buildVersion)); load: $(uptime)"
echo "audio: none played (the probe decodes and encodes only)"
rm -rf "$scratch"
mkdir -p "$scratch"

status=0
for spec in "${commits[@]}"; do
  sha="$(git -C "$SYLVIA_ROOT" rev-parse --verify "$spec^{commit}")"
  out="$scratch/${sha:0:12}"
  echo
  echo "==> G0.4 $spec = $sha"
  echo "    capture code changed since 943d5e7: $(git -C "$SYLVIA_ROOT" diff --name-only 943d5e778de2b58f47343f0e146f9e3ed7baa70e "$sha" -- Spikes/G04-Audio/Sources/G04AudioKit/Capture Spikes/G04-Audio/Sources/G04AudioKit/Excerpt Spikes/G04-Audio/Sources/G04AudioKit/Timeline Spikes/G04-Audio/Sources/G04AudioKit/Media | sed 's#Spikes/G04-Audio/Sources/G04AudioKit/##' | tr '\n' ' ')"
  if ! "$here/run-g04-capture-probe.sh" "$sha" "$out/probe" > /dev/null; then
    echo "    probe FAILED (log: ${out#$SYLVIA_ROOT/}/probe/g04-capture-probe-run.log)"; status=1; continue
  fi
  grep -E '^(per-file timing mode|compiled|records|kept)' "$out/probe/g04-capture-probe-run.log" | sed 's/^/    /'
  if ! sylvia_python -I - "$committed" "$out/probe" <<'PY'
import json, sys
from pathlib import Path

def paths(value, prefix=""):
    """JSON key paths; array items share one path, an enum case's payload key is kept (its state)."""
    if isinstance(value, dict):
        out = set()
        for k, v in value.items():
            out |= {f"{prefix}/{k}"} | paths(v, f"{prefix}/{k}")
        return out
    if isinstance(value, list):
        out = set()
        for v in value:
            out |= paths(v, f"{prefix}/[]")
        return out
    return set()

def load(d):
    return {json.loads(p.read_text())["idempotencyKey"]: json.loads(p.read_text()) for p in sorted(Path(d, "records").glob("*.json"))}

old, new = load(sys.argv[1]), load(sys.argv[2])
same = sorted(old) == sorted(new)
print(f"    records: {len(new)} ({', '.join(sorted(new))}); same idempotency keys as the committed records: {same}")
problems = 0 if same else 1
for key in sorted(set(old) & set(new)):
    a, b = paths(old[key]), paths(new[key])
    if a != b:
        problems += 1
        print(f"    FORMAT DIFFERS {key}: only committed {sorted(a - b)}, only new {sorted(b - a)}")
    else:
        print(f"    same format: {key} ({len(a)} key paths)")
for key in ("m0-contracts-single", "m0-contracts-cross-file"):
    e = new[key]["excerpt"].get("saved", {}).get("_0")
    if e:
        ranges = ", ".join(f"[{r['startMs']}, {r['endMs']})" for r in e["actualRanges"])
        print(f"    {key}: actual ranges {ranges}, {e['frameCount']} frames at {e['sampleRate']:g} Hz, "
              f"read back {e.get('outputDurationMs')} ms, {e['byteCount']} bytes")
ctx = json.loads(Path(sys.argv[2], "context.json").read_text())
for m in ctx["members"]:
    if "timing" in m:
        print(f"    member {m['file_name']}: timing {m['timing']} ({m['timing_reason']})")
sys.exit(1 if problems else 0)
PY
  then
    status=1
  fi
  root="$out/root"
  for p in "${inputs[@]}"; do
    mkdir -p "$root/$(dirname "$p")"
    cp -R "$SYLVIA_ROOT/$p" "$root/$p"
  done
  mkdir -p "$root/Docs/Stage0/evidence/M0-contracts/g04-capture-records"
  cp -R "$out/probe/records" "$out/probe/context.json" "$root/Docs/Stage0/evidence/M0-contracts/g04-capture-records/"
  if sylvia_python -I "$SYLVIA_ROOT/Scripts/check-spike-anchors.py" --root "$root" > "$out/checker.txt" 2>&1; then
    echo "    checker with these records: $(tail -1 "$out/checker.txt")"
  else
    echo "    checker with these records: FAIL"; grep -E '^error:' "$out/checker.txt" | sed 's/^/      /'; status=1
  fi
  grep -E '^  (ok|FAIL) +G0\.4|not a capture' "$out/checker.txt" | sed 's/^ */      /'
done
echo
echo "exit $status"
exit $status
