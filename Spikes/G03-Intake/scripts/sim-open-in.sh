#!/usr/bin/env bash
# G0.3 open-in through the system's own document handling, on the simulator (T08; review R1-04, R1-07).
#
#   Spikes/G03-Intake/scripts/sim-open-in.sh <simulator-udid> <IntakeHarness.app> <log>
#
# `xcrun simctl openurl` asks the simulator's LaunchServices to open a host file URL. The system picks the app from
# its CFBundleDocumentTypes, copies the file into the app's Documents/Inbox (LSSupportsOpeningDocumentsInPlace = NO)
# and hands that copy to onOpenURL; the harness then runs DropAreaImporter.importOpenedFile. This drives that path
# with a valid .sylviapack (the app is the type's Owner), a truncated .sylviapack, an EPUB (Alternate handler) and
# the same EPUB again (a duplicate), and checks the journal and Documents after each. The harness logs where the opened file was (folder only) and the
# outcome (G03-OPENIN lines). Installs the app fresh and leaves it installed; the caller uninstalls it.
set -uo pipefail
source "$(cd "$(dirname "$0")/../../../Scripts/lib" && pwd)/env.sh"
udid="$1"; app_path="$2"; log="$3"
mkdir -p "$(dirname "$log")"
exec > >(tee "$log") 2>&1

kit="$SYLVIA_ROOT/Spikes/G03-Intake/IntakeKit"
bundle_id="com.jevidon.sylvia.spike.intake"
work="$(mktemp -d "${TMPDIR:-/tmp}/g03-open-in.XXXXXX")"
trap 'rm -rf "$work"' EXIT
failures=0
check() {  # check <description> <actual> <expected>
  if [[ "$2" == "$3" ]]; then echo "  ok: $1 ($2)"; else echo "  FAIL: $1: got '$2', expected '$3'"; failures=$((failures + 1)); fi
}

echo "# G0.3 open-in through the system (simctl openurl)"
echo "date: $(date -u +%Y-%m-%dT%H:%M:%SZ)"
echo "simulator: $udid ($(xcrun simctl list devices | grep "$udid" | sed 's/^ *//' | cut -c1-60))"
(cd "$kit" && swift build --force-resolved-versions --configuration release --product sylviapack-tool 2>&1 | tail -1)
tool="$kit/.build/release/sylviapack-tool"
mkdir -p "$work/src" "$work/open"
"$tool" gen-pack "$work/open/Small Book.sylviapack" "$work/src" 1000000 | head -1
head -c 100000 "$work/open/Small Book.sylviapack" > "$work/open/Cut Book.sylviapack"
cp "$SYLVIA_ROOT/Fixtures/epub/se-walden.epub" "$work/open/Walden Open In.epub"
cp "$SYLVIA_ROOT/Fixtures/epub/se-walden.epub" "$work/open/Walden Again.epub"

xcrun simctl uninstall "$udid" "$bundle_id" >/dev/null 2>&1 || true
xcrun simctl install "$udid" "$app_path" || { echo "install failed"; exit 1; }
xcrun simctl launch "$udid" "$bundle_id" >/dev/null || { echo "launch failed"; exit 1; }
sleep 3
data="$(xcrun simctl get_app_container "$udid" "$bundle_id" data)"
journal="$data/Library/Application Support/Sylvia/Staging/journal.json"
started="$(date -u '+%Y-%m-%d %H:%M:%S')"

# Prints "<open_in jobs> <states> <item counts>" from the journal.
jobs() {
  /usr/bin/python3 - "$journal" <<'PY'
import json, sys
try:
    d = json.load(open(sys.argv[1]))
except Exception:
    print("0 - -"); sys.exit()
jobs = d.get("jobs", d) if isinstance(d, dict) else d
jobs = list(jobs.values()) if isinstance(jobs, dict) else list(jobs)
jobs = [j for j in jobs if j.get("route") == "open_in"]   # the journal appends jobs in order
print(len(jobs), ",".join(j.get("state", "?") for j in jobs) or "-", ",".join(str(len(j.get("items", []))) for j in jobs) or "-")
PY
}
documents() { (cd "$data/Documents" 2>/dev/null && find . -mindepth 1 -type f | wc -l | tr -d ' '); }

open_file() {  # open_file <name>: opens it and waits for the harness to log the outcome
  local name="$1" url before
  url="file://$(/usr/bin/python3 -c 'import sys, urllib.parse; print(urllib.parse.quote(sys.argv[1]))' "$work/open/$name")"
  before="$(xcrun simctl spawn "$udid" log show --start "$started" --style compact --predicate 'eventMessage CONTAINS "G03-OPENIN"' 2>/dev/null | grep -c 'G03-OPENIN folder=')"
  echo; echo "## open $name"
  xcrun simctl openurl "$udid" "$url"; echo "  openurl exit status: $?"
  for _ in $(seq 1 30); do
    sleep 1
    now="$(xcrun simctl spawn "$udid" log show --start "$started" --style compact --predicate 'eventMessage CONTAINS "G03-OPENIN"' 2>/dev/null | grep 'G03-OPENIN folder=')"
    if (( $(grep -c 'G03-OPENIN folder=' <<<"$now") > before )); then break; fi
  done
  last="$(grep 'G03-OPENIN' <<<"$now" | tail -1 | sed 's/.*G03-OPENIN/G03-OPENIN/')"
  echo "  harness: ${last:-no G03-OPENIN line within 30 s}"
}

open_file "Small Book.sylviapack"
check "the system's copy was in Documents/Inbox" "$(sed -n 's/.*folder=\([^ ]*\/[^ ]*\) .*/\1/p' <<<"$last")" "Documents/Inbox"
check "Inbox copy removed after the import" "$(sed -n 's/.*inboxEntriesAfter=\([0-9-]*\).*/\1/p' <<<"$last")" "0"
read -r count states items <<<"$(jobs)"
check "bundle imported through the bundle importer (open_in jobs, states, items)" "$count $states $items" "1 staged 4"
check "files left in Documents" "$(documents)" "0"

open_file "Cut Book.sylviapack"
check "truncated bundle rejected" "$(grep -o 'outcome=Open-in not imported: bundle rejected: [a-z_]*' <<<"$last")" "outcome=Open-in not imported: bundle rejected: truncated_or_not_a_pack"
check "Inbox copy removed after the rejection" "$(sed -n 's/.*inboxEntriesAfter=\([0-9-]*\).*/\1/p' <<<"$last")" "0"
read -r count states items <<<"$(jobs)"
check "no job for the truncated bundle" "$count" "1"
check "files left in Documents" "$(documents)" "0"

open_file "Walden Open In.epub"
check "the system's copy was in Documents/Inbox" "$(sed -n 's/.*folder=\([^ ]*\/[^ ]*\) .*/\1/p' <<<"$last")" "Documents/Inbox"
read -r count states items <<<"$(jobs)"
check "EPUB imported through the single-file importer" "$count $states $items" "2 staged,staged 4,1"
check "files left in Documents" "$(documents)" "0"

# T08: the same bytes opened again (under another name) are a duplicate, as for every other route.
open_file "Walden Again.epub"
read -r count states items <<<"$(jobs)"
check "the same EPUB opened again is flagged for review, not staged twice" "$count $states" "3 staged,staged,needs_review"
check "files left in Documents" "$(documents)" "0"

echo
echo "failures=$failures"
exit $(( failures > 0 ))
