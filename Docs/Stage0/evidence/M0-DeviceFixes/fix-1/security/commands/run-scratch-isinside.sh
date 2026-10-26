#!/bin/bash
# M0 device fixes, fix-1, the security review of 26 October 2026 (finding S2): on another commit's code, the
# expectations about BackupValidator.isInside that the security fix adds to PrivatePathTests.containmentFollowsLinks.
# The expectations are taken from the working tree's PrivatePathTests.swift (from its line "So `isInside` itself" to
# its line with "export/../../Outside/b.md"), put into a test of their own with the setup of containmentFollowsLinks
# (a bundle folder with export/markdown/a.md and, beside it, Outside/b.md), and run in a scratch copy of the recovery
# spike (git archive of <base commit> into .build/scratch, never the working tree), on the Mac under /var and through
# /private (PrivatePathTests.forms).
#   Docs/Stage0/evidence/M0-DeviceFixes/fix-1/security/commands/run-scratch-isinside.sh <log name> <base commit> <expected>
# Log: Docs/Stage0/evidence/M0-DeviceFixes/fix-1/security/<log name>.log. Build Mac only; no simulator, no device.
set -u
root="$(cd "$(dirname "$0")/../../../../../../.." && pwd)"
cd "$root" || exit 1
name="$1"; base="$2"; expected="$3"
out="$root/Docs/Stage0/evidence/M0-DeviceFixes/fix-1/security/$name.log"
source Scripts/lib/env.sh
source Docs/Stage0/evidence/M0-Decisions/harness/commands/lock-state.sh
short="$(git -C "$root" rev-parse --short=8 "$base")" || exit 1
scratch="$root/.build/scratch/security-fix/s2-isinside-$short"
pkg="$scratch/Spikes/G05-Recovery"
mkdir -p "$scratch"
find "$pkg" -mindepth 1 -maxdepth 1 ! -name .build -exec rm -rf {} + 2>/dev/null
git -C "$root" archive "$base" Spikes/G05-Recovery | tar -x -C "$scratch" || exit 1

lines="$(awk '/So `isInside` itself/ {on = 1} on {print} on && /export\/\.\.\/\.\.\/Outside\/b\.md/ {exit}' \
  "$root/Spikes/G05-Recovery/Tests/SylviaRecoveryTests/PrivatePathTests.swift")"
[[ -n "$lines" ]] || { echo "the expectations were not found in PrivatePathTests.swift" >&2; exit 1; }
test_file="$pkg/Tests/SylviaRecoveryTests/SecurityS2ScratchTests.swift"
{
  cat <<'EOF'
import Foundation
import Testing
@testable import SylviaRecovery

/// Scratch copy only (security review of 26 October 2026, finding S2): the expectations the security fix adds to
/// `PrivatePathTests.containmentFollowsLinks`, with that test's setup, run on another commit's code.
@Suite("Security fix S2, in a scratch copy")
struct SecurityS2ScratchTests {
    @Test("isInside never counts a path with . or .. below a missing folder as inside")
    func isInsideAlone() throws {
        let scratch = try Scratch()
        let fm = FileManager.default
        let root = scratch.dir("Bundle")
        try fm.createDirectory(at: root.appending(path: "export/markdown", directoryHint: .isDirectory), withIntermediateDirectories: true)
        try Data("x".utf8).write(to: root.appending(path: "export/markdown/a.md"))
        let outside = scratch.dir("Outside")
        try fm.createDirectory(at: outside, withIntermediateDirectories: true)
        try Data("y".utf8).write(to: outside.appending(path: "b.md"))
        for form in PrivatePathTests.forms(root) {
            let base = form.url
            print("isInside, \(form.label): " + ["missing/../../Outside/b.md", "missing/..", "export/../export/markdown/a.md", "export/../../Outside/b.md"]
                .map { "\($0) -> \(BackupValidator.isInside(base.appending(path: $0), base))" }.joined(separator: "; "))
EOF
  echo "$lines"
  cat <<'EOF'
        }
    }
}
EOF
} > "$test_file"

{
  echo "command: Docs/Stage0/evidence/M0-DeviceFixes/fix-1/security/commands/run-scratch-isinside.sh $name $base '<expected>'"
  echo "expected (stated before the run): $expected"
  echo "working tree: $(git -C "$root" rev-parse HEAD) ($(git -C "$root" rev-parse --abbrev-ref HEAD))"
  echo "scratch copy: ${scratch#"$root/"}/Spikes/G05-Recovery, git archive of $base ($(git -C "$root" rev-parse "$base"))"
  echo "the code under test, Sources/SylviaRecovery/Backup/Container.swift there: sha256 $(shasum -a 256 "$pkg/Sources/SylviaRecovery/Backup/Container.swift" | cut -d' ' -f1)"
  echo "host: macOS $(sw_vers -productVersion) ($(sw_vers -buildVersion)), $(sysctl -n machdep.cpu.brand_string); $(xcodebuild -version | tr '\n' ' ')"
  echo "screen lock (ioreg) at the start: $(lock_state)"
  echo "start: $(date -u +%Y-%m-%dT%H:%M:%SZ); load: $(uptime | sed 's/.*load averages*: //')"
  first="$(grep -n 'So `isInside` itself' "$test_file" | cut -d: -f1)"
  echo "---- the scratch test, Tests/SylviaRecoveryTests/SecurityS2ScratchTests.swift (lines $first-$(( first + $(echo "$lines" | wc -l) - 1 )) are the working tree's PrivatePathTests.swift lines)"
  cat -n "$test_file"
  echo "---- xcrun swift test --force-resolved-versions --filter SecurityS2ScratchTests (in the scratch copy)"
} > "$out"
(cd "$pkg" && xcrun swift test --force-resolved-versions --filter SecurityS2ScratchTests) > "$scratch/$name.out" 2>&1
status=$?
perl -pe 's/\e\[[0-9;]*[A-Za-z]//g' "$scratch/$name.out" | sed "s#$scratch/##g" | grep -vE '^\[[0-9]+/[0-9]+\] (Compiling|Write|Emitting|Linking|Applying)' >> "$out"
{
  echo "---- summary"
  echo "swift test exit: $status"
  grep -E '^isInside, ' "$out" | sed 's/^/  /'
  grep -E 'Test run with' "$out" | tail -1
  echo "screen lock (ioreg) at the end: $(lock_state)"
  echo "end: $(date -u +%Y-%m-%dT%H:%M:%SZ); load: $(uptime | sed 's/.*load averages*: //')"
} >> "$out"
sed -n '/^---- summary/,$p' "$out"
exit 0
