#!/usr/bin/env bash
# Builds and runs the G0.4 capture probe on the host (ADR-0016, M0-contracts.md).
#
#   Docs/Stage0/evidence/M0-contracts/commands/run-g04-capture-probe.sh [g04-commit [output-directory]]
#
# Reads G0.4's capture code from git at the given commit (default: 943d5e7, the m0-g04-audio commit the committed
# records come from), compiles it with the probe's main.swift in Swift 6 language mode with complete strict
# concurrency and warnings as errors, and runs it on the four-file MP3 book from the G0.4 fixture generator.
#
# Without an output directory it replaces the committed records in Docs/Stage0/evidence/M0-contracts/g04-capture-records/
# and writes its log to g04-capture-probe-run.log beside them. With one (check-g04-head.sh passes a scratch directory)
# it writes the records, context.json and the log there and leaves the committed evidence alone.
#
# G0.4 moved on after 943d5e7: from 99808ca its capture code uses the per-file timing mode (Media/AssetTiming.swift,
# Media/MP3FrameScanner.swift; ADR-0006 decision 2). When those files exist at the commit they are compiled too and
# G04_ASSET_TIMING is defined, so the probe passes each member's import decision to CaptureService as the G0.4 harness
# does. Scratch files go under .build/scratch/m0-contracts/. Nothing is played: the probe only decodes and encodes.
set -euo pipefail
source "$(cd "$(dirname "$0")/../../../../../Scripts/lib" && pwd)/env.sh"

commit="${1:-943d5e778de2b58f47343f0e146f9e3ed7baa70e}"
commit="$(git -C "$SYLVIA_ROOT" rev-parse --verify "$commit^{commit}")"
here="$SYLVIA_ROOT/Docs/Stage0/evidence/M0-contracts/commands/g04-capture-probe"
scratch="$SYLVIA_ROOT/.build/scratch/m0-contracts/g04-probe-${commit:0:12}"
if [[ $# -ge 2 ]]; then
  mkdir -p "$2"
  evidence="$(cd "$2" && pwd)"
  log="$evidence/g04-capture-probe-run.log"
else
  evidence="$SYLVIA_ROOT/Docs/Stage0/evidence/M0-contracts/g04-capture-records"
  log="$SYLVIA_ROOT/Docs/Stage0/evidence/M0-contracts/g04-capture-probe-run.log"
fi
book="$SYLVIA_FIXTURE_CACHE/generated/g04-audio/multi"

exec > >(tee "$log") 2>&1

rm -rf "$scratch"
mkdir -p "$scratch/src" "$scratch/out"
git -C "$SYLVIA_ROOT" archive "$commit" Spikes/G04-Audio/Sources/G04AudioKit | tar -x -C "$scratch/src"
kit="$scratch/src/Spikes/G04-Audio/Sources/G04AudioKit"
files=(
  "$kit/Capture/CaptureModel.swift" "$kit/Capture/CaptureService.swift" "$kit/Capture/CaptureStore.swift"
  "$kit/Capture/VocabularyKey.swift" "$kit/Timeline/EditionTimeline.swift" "$kit/Excerpt/ExcerptExporter.swift"
  "$kit/Media/PCMDecoder.swift" "$kit/Media/AssetInspector.swift" "$kit/Media/ID3Chapters.swift"
  "$kit/Persistence/DurableFile.swift" "$here/main.swift"
)
defines=()
if [[ -f "$kit/Media/AssetTiming.swift" ]]; then
  files+=("$kit/Media/AssetTiming.swift" "$kit/Media/MP3FrameScanner.swift")
  defines=(-D G04_ASSET_TIMING)
fi

echo "command: Docs/Stage0/evidence/M0-contracts/commands/run-g04-capture-probe.sh $*"
echo "g04 commit read: $commit"
echo "m0-g04-audio head at run time: $(git -C "$SYLVIA_ROOT" rev-parse --verify --quiet m0-g04-audio || echo 'branch not present')"
echo "per-file timing mode: $([[ ${#defines[@]} -gt 0 ]] && echo 'yes (AssetTiming.swift present; G04_ASSET_TIMING defined)' || echo 'no (not at this commit)')"
echo "probe source: $(git -C "$SYLVIA_ROOT" log -1 --format=%H -- Docs/Stage0/evidence/M0-contracts/commands/g04-capture-probe/main.swift) (last commit of main.swift; uncommitted edits: $(git -C "$SYLVIA_ROOT" status --porcelain -- Docs/Stage0/evidence/M0-contracts/commands | wc -l | tr -d ' ') files)"
echo "output: ${evidence#$SYLVIA_ROOT/}"
echo "xcode: $(xcodebuild -version | tr '\n' ' ')"
echo "swift: $(xcrun swift --version 2>&1 | head -1)"
echo "host: $(sw_vers -productName) $(sw_vers -productVersion) ($(sw_vers -buildVersion)), $(sysctl -n machdep.cpu.brand_string)"
echo "load: $(uptime)"
echo "audio: none played (decode and encode only; no player, audio session or output node)"
echo "book: $book"
for f in "Part 1.mp3" "Part 2.mp3" "Part 3.mp3" "Part 10.mp3"; do
  echo "  $(shasum -a 256 "$book/$f" | cut -d' ' -f1)  $f"
done

xcrun swiftc -swift-version 6 -strict-concurrency=complete -warnings-as-errors -O ${defines[@]+"${defines[@]}"} \
  -target "$(uname -m)-apple-macos$SYLVIA_MACOS_DEPLOYMENT_TARGET" \
  -module-name G04CaptureProbe -o "$scratch/g04-capture-probe" "${files[@]}"
echo "compiled: ${#files[@]} files, 0 warnings (-warnings-as-errors)"

"$scratch/g04-capture-probe" "$book" "$scratch/out"

rm -rf "$evidence/records" "$evidence/context.json"
mkdir -p "$evidence/records"
cp "$scratch/out/records/"*.json "$evidence/records/"
cp "$scratch/out/context.json" "$evidence/context.json"
echo "kept: $(ls "$evidence/records" | wc -l | tr -d ' ') records in ${evidence#$SYLVIA_ROOT/}"
echo "exit 0"
