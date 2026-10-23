#!/bin/bash
# ADR-0014 evidence under Xcode 27.1 (the pin since 20 October 2026): commands/resolve-locks.sh, then
# commands/linkage.sh, both unchanged, from clean, with no git remote reachable, so every pinned package comes from
# the local SwiftPM repository cache (~/Library/Caches/org.swift.swiftpm/repositories) and nothing is fetched.
#
#   Docs/Stage0/evidence/M0-dependencies/xcode-27.1/commands/run-offline.sh <folder> [--skip-grdb-submodule]
#
# <folder> is a new folder under Docs/Stage0/evidence/M0-dependencies/xcode-27.1/ for this run's logs.
#
# Why offline: both scripts resolve packages, which can fetch from git remotes, and the agent that ran this may not
# fetch from a remote (ADR-0014, open items: the run fell to the product owner, or to an agent the owner allows to
# fetch). So the run takes the packages from the local cache, or fails where it would need the network:
#  - GIT_ALLOW_PROTOCOL=file: git refuses every transport except the local one, so a clone, fetch or ls-remote of a
#    GitHub URL fails ("transport 'https' not allowed") instead of reaching the network. `swift build` and
#    `swift package resolve` run git for every package operation.
#  - xcodebuild is reached through a shim first on PATH (.build/scratch/offline-shim/xcodebuild) that adds
#    `-scmProvider system -skipPackageUpdates` to its package resolutions and builds: Xcode then runs the same git (its
#    built-in Git implementation would not read GIT_ALLOW_PROTOCOL) and never updates a package from its remote. No
#    other argument of any command changes.
#  - GIT_TRACE records every git command the run starts; git-network-check.log counts them and lists every one that
#    names a remote URL, with git's refusals.
#  - --skip-grdb-submodule: GRDB.swift 7.11.1 has one git submodule, SQLiteCustom/src
#    (https://github.com/swiftlyfalling/SQLiteLib.git), which the local cache does not hold, so its clone is refused
#    and every package resolution that reaches GRDB fails (run-1). With this option the run sets, through git's
#    environment configuration (GIT_CONFIG_COUNT; no configuration file changes), submodule.SQLiteCustom/src.update =
#    none, so git leaves that submodule empty. GRDB's Package.swift builds nothing from it: its targets are
#    GRDBSQLite (Sources/GRDBSQLite, a system library) and GRDB (path GRDB), and the submodule serves only GRDB's own
#    custom-SQLite Xcode project (GRDBCustom.xcodeproj). So what SwiftPM and Xcode compile and link is unchanged.
# Before the run, every build product under Apps/, Packages/ and Spikes/ is deleted (.build, DerivedData and the
# generated .xcodeproj bundles; it refuses if one holds a tracked file), as commands/ci-clean.sh does.
# Logs (in <folder>): resolve-locks.log, linkage.log, git-network-check.log and run-offline.log (this script's own
# record), never over the Xcode 27.0 logs in Docs/Stage0/evidence/M0-dependencies/, which ADR-0014 section 4 and its
# Evidence cite. Host only; no simulator is booted (generic destinations).
set -uo pipefail
ROOT="$(cd "$(dirname "$0")/../../../../../.." && pwd)"
source "$ROOT/Scripts/lib/env.sh"
cd "$ROOT" || exit 1
[[ $# -ge 1 && "$1" != -* ]] || { echo "usage: $0 <folder> [--skip-grdb-submodule]" >&2; exit 2; }
OUT="Docs/Stage0/evidence/M0-dependencies/xcode-27.1/$1"
SKIP=0; [[ "${2:-}" == --skip-grdb-submodule ]] && SKIP=1
[[ -e "$OUT" ]] && { echo "$OUT exists; name a new folder" >&2; exit 2; }
CMD=Docs/Stage0/evidence/M0-dependencies/commands
SHIM="$ROOT/.build/scratch/offline-shim"
TRACE="$ROOT/.build/scratch/offline-git-trace-$1.txt"
LOG="$OUT/run-offline.log"
mkdir -p "$SHIM" "$OUT"
rm -f "$TRACE"
REAL_XCODEBUILD="$DEVELOPER_DIR/usr/bin/xcodebuild"
cat > "$SHIM/xcodebuild" <<EOF
#!/bin/bash
# xcodebuild for run-offline.sh: package resolutions and builds use the system git and skip remote updates.
for a in "\$@"; do
  case "\$a" in
    -resolvePackageDependencies|build|build-for-testing)
      exec "$REAL_XCODEBUILD" "\$@" -scmProvider system -skipPackageUpdates ;;
  esac
done
exec "$REAL_XCODEBUILD" "\$@"
EOF
chmod +x "$SHIM/xcodebuild"

victims=$(find Apps Packages Spikes \( -name .build -o -name '*.xcodeproj' -o -name DerivedData \) -prune -print | sort)
for v in $victims; do
  if [[ -n "$(git ls-files -- "$v" | head -1)" ]]; then echo "refusing: $v has tracked files" >&2; exit 2; fi
done
rm -rf $victims

export PATH="$SHIM:$PATH" GIT_ALLOW_PROTOCOL=file GIT_TERMINAL_PROMPT=0 GIT_TRACE="$TRACE"
if (( SKIP )); then
  export GIT_CONFIG_COUNT=1 GIT_CONFIG_KEY_0=submodule.SQLiteCustom/src.update GIT_CONFIG_VALUE_0=none
fi

watched="Apps Packages Spikes Scripts/lib $CMD"
{
  echo "run-offline $1 started $(date -u +%Y-%m-%dT%H:%M:%SZ) at commit $(git rev-parse HEAD) ($0 $*)"
  echo "host: macOS $(sw_vers -productVersion) ($(sw_vers -buildVersion)), $(sysctl -n machdep.cpu.brand_string)"
  echo "toolchain: $(xcodebuild -version | tr '\n' ' '); $(xcrun swift --version 2>&1 | head -1); xcodegen $(xcodegen --version)"
  echo "xcodebuild on PATH: $(command -v xcodebuild) (the shim), real: $REAL_XCODEBUILD"
  echo "environment: GIT_ALLOW_PROTOCOL=$GIT_ALLOW_PROTOCOL GIT_TERMINAL_PROMPT=$GIT_TERMINAL_PROMPT GIT_TRACE=<scratch file>" \
       "$( (( SKIP )) && echo "GIT_CONFIG_COUNT=1 GIT_CONFIG_KEY_0=$GIT_CONFIG_KEY_0 GIT_CONFIG_VALUE_0=$GIT_CONFIG_VALUE_0")"
  echo "load: $(uptime)"
  echo "SwiftPM repository cache (names only): $(ls "$HOME/Library/Caches/org.swift.swiftpm/repositories" | tr '\n' ' ')"
  echo "build products deleted before the run (none tracked): $(echo $victims | wc -w | tr -d ' ')"
  echo "build products under Apps/, Packages/ and Spikes/ at the start: $(find Apps Packages Spikes \( -name .build -o -name '*.xcodeproj' -o -name DerivedData \) -prune -print | wc -l | tr -d ' ')"
  echo "changes under $watched at the start (git status --porcelain): $(git status --porcelain -- $watched | tr '\n' ';')"
} > "$LOG" 2>&1

start=$SECONDS
bash "$CMD/resolve-locks.sh" > "$OUT/resolve-locks.log" 2>&1
resolve=$?
echo "resolve-locks.sh exit status: $resolve ($((SECONDS - start)) s)" >> "$LOG"
start=$SECONDS
bash "$CMD/linkage.sh" > "$OUT/linkage.log" 2>&1
linkage=$?
echo "linkage.sh exit status: $linkage ($((SECONDS - start)) s)" >> "$LOG"

calls() { grep -E 'trace: (built-in|exec|run_command): git ' "$TRACE" 2>/dev/null; }
{
  echo "git commands started by the run (from GIT_TRACE), by subcommand:"
  calls | sed -E 's/.*trace: (built-in|exec|run_command): git //' | awk '{print $1}' | sort | uniq -c | sort -rn | sed 's/^/  /'
  echo "of them, commands that name a remote URL (https://, ssh://, git://, git@): $(calls | grep -cE 'https://|ssh://|git://|git@')"
  calls | grep -E 'https://|ssh://|git://|git@' | sed -E 's/^[0-9:.]+ +[^ ]+ +//' | sed -E "s|$ROOT/||g" | sort | uniq -c | sed 's/^/  /' | head -60
  echo "git's refusals of a non-local transport in the trace (\"transport '...' not allowed\"): $(grep -ohE "transport '[a-z+]+' not allowed" "$OUT/resolve-locks.log" "$OUT/linkage.log" "$ROOT"/.build/scratch/resolve/*.log "$ROOT"/.build/scratch/linkage/*.log 2>/dev/null | sort | uniq -c | tr '\n' ';')"
  echo "fetches and remote updates (each from a repository whose only remote is a URL, so refused, or a local path):"
  calls | grep -E 'git (fetch|remote) ' | sed -E 's/^[0-9:.]+ +[^ ]+ +//' | sed -E "s|$ROOT/||g" | sort | uniq -c | sed 's/^/  /'
} > "$OUT/git-network-check.log" 2>&1

{
  echo "changes under $watched at the end (git status --porcelain): $(git status --porcelain -- $watched | tr '\n' ';')"
  echo "committed Package.resolved files changed by the run: $(git diff --name-only -- '*Package.resolved' | tr '\n' ' ')"
  echo "run-offline $1 finished $(date -u +%Y-%m-%dT%H:%M:%SZ)"
  echo "load: $(uptime)"
} >> "$LOG" 2>&1
tail -n 7 "$LOG"
exit $(( resolve != 0 || linkage != 0 ))
