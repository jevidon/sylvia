#!/usr/bin/env bash
# G0.3 archive-library evaluation (host, macOS). Compares upstream ZIPFoundation 0.9.20 with Readium's fork
# 3.0.1 on a ZIP64 archive above 4 GiB: write, cross-read, Python zipfile and Info-ZIP cross-checks, and
# truncated copies. Also records whether both packages can share one SwiftPM graph with Readium 3.11.0.
#
#   Spikes/G03-Intake/ZipEval/run-eval.sh [log-file]
#
# Archives go to a directory of this run's own under $SYLVIA_FIXTURE_CACHE/generated/g03-intake/ (about 15 GiB while
# running; removed on exit). Default log: Docs/Stage0/evidence/G03-Intake/zip-eval.log
set -uo pipefail
source "$(cd "$(dirname "$0")/../../../Scripts/lib" && pwd)/env.sh"
here="$SYLVIA_ROOT/Spikes/G03-Intake/ZipEval"
log="${1:-$SYLVIA_ROOT/Docs/Stage0/evidence/G03-Intake/zip-eval.log}"
mkdir -p "$SYLVIA_FIXTURE_CACHE/generated/g03-intake"
work="$(mktemp -d "$SYLVIA_FIXTURE_CACHE/generated/g03-intake/zipeval.XXXXXX")"
trap 'rm -rf "$work"' EXIT
big=$((4 * 1024 * 1024 * 1024 + 512 * 1024 * 1024 + 12345))   # 4.5 GiB + 12345 bytes, deliberately unaligned
limit=120                                                        # seconds allowed for opening a truncated copy
mkdir -p "$(dirname "$log")"
exec > >(tee "$log") 2>&1

# Runs a command for at most $1 seconds; on expiry it is SIGKILLed and the status is 142. (An earlier version used
# perl's alarm before exec; on 2026-10-06 an upstream open ran 984 s under it without being stopped, so the limit is
# now enforced from the shell.)
with_limit() {
  local limit="$1"; shift
  "$@" &
  local pid=$! ticks=0
  while kill -0 "$pid" 2>/dev/null; do
    if (( ticks >= limit * 10 )); then
      kill -9 "$pid" 2>/dev/null; wait "$pid" 2>/dev/null
      return 142
    fi
    sleep 0.1; ticks=$((ticks + 1))
  done
  wait "$pid"
}
timed() { /usr/bin/time -l "$@" 2>&1 | grep -E '^\[|FAILED|ACCEPTED|maximum resident set size|peak memory footprint|real' ; }

echo "# G0.3 ZIP library evaluation"
echo "date: $(date -u +%Y-%m-%dT%H:%M:%SZ)"
echo "environment: host, $(sw_vers -productName) $(sw_vers -productVersion) ($(sw_vers -buildVersion)), $(sysctl -n machdep.cpu.brand_string), $(xcodebuild -version | tr '\n' ' ')"
echo "big entry: $big bytes (stored), plus text/small.txt (deflated)"
echo

echo "## 1. Can both packages share one SwiftPM graph with readium/swift-toolkit 3.11.0?"
(cd "$here/IdentityProbe" && rm -rf .build Package.resolved && swift package resolve 2>&1 | grep -E 'error|Computed|resolved' ) || true
echo

echo "## 2. Build"
for p in Upstream Readium; do
  (cd "$here/$p" && swift build --force-resolved-versions -c release 2>&1 | tail -1) || { echo "build $p failed"; exit 1; }
done
up="$here/Upstream/.build/release/zipeval-upstream"
rd="$here/Readium/.build/release/zipeval-readium"
echo

status=0
echo "## 3. Write a ZIP64 archive with each library"
rm -f "$work"/*.zip "$work"/*.truncated
timed "$up" write "$work/upstream.zip" "$big" || status=1
timed "$rd" write "$work/readium.zip" "$big" || status=1
ls -l "$work"/*.zip
echo

echo "## 4. Read every archive with every reader (streamed through SHA-256, CRC32 checked)"
for a in upstream readium; do
  echo "-- archive written by $a"
  timed "$up" read "$work/$a.zip" || status=1
  timed "$rd" read "$work/$a.zip" || status=1
  /usr/bin/python3 - "$work/$a.zip" <<'PY' || status=1
import hashlib, struct, sys, zipfile
path = sys.argv[1]
with zipfile.ZipFile(path) as z:
    for info in z.infolist():
        h = hashlib.sha256()
        with z.open(info) as f:
            while True:
                b = f.read(1 << 20)
                if not b: break
                h.update(b)
        # ZIP64 extended-information extra field (header id 0x0001) present in the central directory?
        extra, zip64 = info.extra, False
        i = 0
        while i + 4 <= len(extra):
            hid, size = struct.unpack('<HH', extra[i:i+4]); zip64 |= hid == 1; i += 4 + size
        print(f"[python zipfile] entry path={info.filename} method={info.compress_type} file_size={info.file_size} zip64_extra={zip64} create_system={info.create_system} mode={oct(info.external_attr >> 16)} sha256={h.hexdigest()}")
print("[python zipfile] read ok")
PY
  echo "[Info-ZIP unzip -tq] $(unzip -tq "$work/$a.zip" 2>&1 | tail -1)"
done
echo

echo "## 5. Truncated copies of the 4.5 GiB archive (clone, then cut); each open gets ${limit}s"
# Truncates a clone of $1 to each following size and opens it with each library (and Python) under the limit.
truncation_cases() {
  local src="$1"; shift
  local size; size=$(stat -f %z "$src")
  for newsize in "$@"; do
    t="$work/cut.truncated"
    rm -f "$t"; cp -c "$src" "$t"
    /usr/bin/python3 -c "import os,sys; os.truncate(sys.argv[1], int(sys.argv[2]))" "$t" "$newsize"
    echo "-- $(basename "$src") truncated to $newsize of $size bytes"
    # Where a backwards byte-by-byte scan for the end-record signature (PK\x05\x06) first succeeds.
    /usr/bin/python3 - "$t" <<'PY'
import mmap, sys
with open(sys.argv[1], 'rb') as f, mmap.mmap(f.fileno(), 0, access=mmap.ACCESS_READ) as m:
    at = m.rfind(b'PK\x05\x06')
    print(f"[signature scan] last end-record signature in the truncated file: {'none' if at < 0 else f'offset {at} ({len(m) - at} bytes before the end)'}")
PY
    for r in "$up" "$rd"; do
      out="$(with_limit "$limit" "$r" open "$t" 2>&1)"; rc=$?
      if (( rc == 142 )); then echo "[$(basename "$r")] did not finish within ${limit}s (SIGKILLed by the watchdog)"; else echo "$out"; fi
      [[ "$out" == *ACCEPTED* ]] && echo "  !! truncated copy was ACCEPTED by $(basename "$r")"
    done
    out="$(with_limit "$limit" /usr/bin/python3 -c "import zipfile,sys; zipfile.ZipFile(sys.argv[1]).testzip(); print('[python zipfile] ACCEPTED')" "$t" 2>&1 | tail -1)"; echo "${out:-[python zipfile] no output}"
  done
}
src="$work/readium.zip"
size=$(stat -f %z "$src")
truncation_cases "$src" $((size - 1)) $((size - 22)) $((size - 98)) $((size / 2)) 4096
echo

echo "## 6. The same cuts on a small archive (64 MiB stored entry), where a full backward scan is fast"
small=$((64 * 1024 * 1024 + 12345))
"$rd" write "$work/small.zip" "$small" | grep -E 'write ok|FAILED' || status=1
ssize=$(stat -f %z "$work/small.zip")
truncation_cases "$work/small.zip" $((ssize - 1)) $((ssize - 22)) $((ssize - 98)) $((ssize / 2)) 4096
rm -f "$work"/*.zip "$work"/*.truncated
echo
echo "eval finished, status=$status"
exit $status
