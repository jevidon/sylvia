#!/bin/bash
# M0 device fixes, fix-1, the security review of 26 October 2026 (finding S4): does the copy guard
# (ProtectedCopyTests.noCopyKeepsTheSourceClass) find the calls the review says it missed? Runs the guard alone in a
# scratch copy of the recovery spike (git archive of <base commit> into .build/scratch, never the working tree), into
# whose LockHarness three planted files are written first: a Swift file (a copyItem call after a string literal that
# holds "//", a linkItem call, a link(2) call), an Objective-C file (copyItemAtURL: and linkItemAtPath:) and a C file
# (a copyfile(3) call split across two lines). LockHarness is not part of the package, so the planted files are only
# read by the guard, never compiled. Six planted calls in all.
#   Docs/Stage0/evidence/M0-DeviceFixes/fix-1/security/commands/run-scratch-guard.sh <log name> <base commit> <guard> <expected>
#     <guard>: "base" (the guard as committed in <base commit>) or "working-tree" (the working tree's
#              Spikes/G05-Recovery/Tests/SylviaRecoveryTests/ProtectedCopyTests.swift, copied into the scratch copy)
#     <expected>: the expectation, written into the log before the run
# Log: Docs/Stage0/evidence/M0-DeviceFixes/fix-1/security/<log name>.log. Build Mac only; no simulator, no device.
set -u
root="$(cd "$(dirname "$0")/../../../../../../.." && pwd)"
cd "$root" || exit 1
name="$1"; base="$2"; guard="$3"; expected="$4"
out="$root/Docs/Stage0/evidence/M0-DeviceFixes/fix-1/security/$name.log"
source Scripts/lib/env.sh
source Docs/Stage0/evidence/M0-Decisions/harness/commands/lock-state.sh
short="$(git -C "$root" rev-parse --short=8 "$base")" || exit 1
scratch="$root/.build/scratch/security-fix/s4-guard-$short"
pkg="$scratch/Spikes/G05-Recovery"
test_file="Tests/SylviaRecoveryTests/ProtectedCopyTests.swift"
mkdir -p "$scratch"
# A fresh copy of the base commit's spike, keeping only the scratch copy's own .build from an earlier run.
find "$pkg" -mindepth 1 -maxdepth 1 ! -name .build -exec rm -rf {} + 2>/dev/null
git -C "$root" archive "$base" Spikes/G05-Recovery | tar -x -C "$scratch" || exit 1
case "$guard" in
  base) ;;
  working-tree) cp "$root/Spikes/G05-Recovery/$test_file" "$pkg/$test_file" || exit 1 ;;
  *) echo "guard must be base or working-tree" >&2; exit 2 ;;
esac

planted="$pkg/LockHarness/Core"
cat > "$planted/PlantedS4.swift" <<'EOF'
// Planted in a scratch copy by the security fix's guard check (review of 26 October 2026, finding S4); never in the
// repository's spike. Each function holds one call that keeps the source file's class.
import Foundation

enum PlantedS4 {
    static func copyAfterAStringHoldingSlashes(_ a: URL, _ b: URL) throws {
        let scheme = "file://"; try FileManager.default.copyItem(at: a, to: b); _ = scheme
    }

    static func hardLink(_ a: URL, _ b: URL) throws {
        try FileManager.default.linkItem(at: a, to: b)
    }

    static func hardLinkThroughDarwin(_ a: String, _ b: String) -> Int32 {
        link(a, b)
    }
}
EOF
cat > "$planted/PlantedS4.m" <<'EOF'
// Planted in a scratch copy by the security fix's guard check (review of 26 October 2026, finding S4); never in the
// repository's spike.
#import <Foundation/Foundation.h>

BOOL PlantedS4CopyItem(NSURL *a, NSURL *b, NSError **error) {
    return [[NSFileManager defaultManager] copyItemAtURL:a toURL:b error:error];
}

BOOL PlantedS4LinkItem(NSString *a, NSString *b, NSError **error) {
    return [[NSFileManager defaultManager] linkItemAtPath:a toPath:b error:error];
}
EOF
cat > "$planted/PlantedS4.c" <<'EOF'
// Planted in a scratch copy by the security fix's guard check (review of 26 October 2026, finding S4); never in the
// repository's spike.
#include <copyfile.h>

int planted_s4_copyfile_split(const char *a, const char *b) {
    return copyfile
        (a, b, NULL, COPYFILE_ALL);
}
EOF

{
  echo "command: Docs/Stage0/evidence/M0-DeviceFixes/fix-1/security/commands/run-scratch-guard.sh $name $base $guard '<expected>'"
  echo "expected (stated before the run): $expected"
  echo "working tree: $(git -C "$root" rev-parse HEAD) ($(git -C "$root" rev-parse --abbrev-ref HEAD))"
  echo "scratch copy: ${scratch#"$root/"}/Spikes/G05-Recovery, git archive of $base ($(git -C "$root" rev-parse "$base"))"
  echo "guard used: $guard: $test_file with sha256 $(shasum -a 256 "$pkg/$test_file" | cut -d' ' -f1)"
  echo "  (as committed in $short: sha256 $(git -C "$root" show "$base:Spikes/G05-Recovery/$test_file" | shasum -a 256 | cut -d' ' -f1);"
  echo "   in the working tree: sha256 $(shasum -a 256 "$root/Spikes/G05-Recovery/$test_file" | cut -d' ' -f1))"
  echo "host: macOS $(sw_vers -productVersion) ($(sw_vers -buildVersion)), $(sysctl -n machdep.cpu.brand_string); $(xcodebuild -version | tr '\n' ' ')"
  echo "screen lock (ioreg) at the start: $(lock_state)"
  echo "start: $(date -u +%Y-%m-%dT%H:%M:%SZ); load: $(uptime | sed 's/.*load averages*: //')"
  for f in PlantedS4.swift PlantedS4.m PlantedS4.c; do
    echo "---- planted: LockHarness/Core/$f"
    cat -n "$planted/$f"
  done
  echo "---- xcrun swift test --force-resolved-versions --filter noCopyKeepsTheSourceClass (in the scratch copy)"
} > "$out"
(cd "$pkg" && xcrun swift test --force-resolved-versions --filter noCopyKeepsTheSourceClass) > "$scratch/$name.out" 2>&1
status=$?
perl -pe 's/\e\[[0-9;]*[A-Za-z]//g' "$scratch/$name.out" | sed "s#$scratch/##g" | grep -vE '^\[[0-9]+/[0-9]+\] (Compiling|Write|Emitting|Linking|Applying)' >> "$out"
{
  echo "---- summary"
  echo "swift test exit: $status"
  echo "guard evidence line: $(grep -oE 'copy guard: .*' "$out" | head -1)"
  # The guard's issue lists each call it found on a line of its own: "  <file>:<line>: <code>".
  echo "planted calls the guard reported: $(grep -cE '^  LockHarness/Core/PlantedS4\.(swift|m|c):[0-9]+: ' "$out")"
  grep -E '^  LockHarness/Core/PlantedS4\.(swift|m|c):[0-9]+: ' "$out" | sed 's/^/  /'
  echo "other calls the guard reported: $(grep -E '^  [A-Za-z]+/.*\.(swift|c|h|m|mm):[0-9]+: ' "$out" | grep -cv 'LockHarness/Core/PlantedS4')"
  echo "pattern samples that failed: $(grep -cE 'pattern (missed|matched) ' "$out")"
  echo "screen lock (ioreg) at the end: $(lock_state)"
  echo "end: $(date -u +%Y-%m-%dT%H:%M:%SZ); load: $(uptime | sed 's/.*load averages*: //')"
} >> "$out"
tail -12 "$out"
exit 0
