#!/usr/bin/env bash
# Generates the G0.4 stereo fixtures into $SYLVIA_FIXTURE_CACHE/generated/g04-audio/stereo (review R6-05: every other
# G0.4 fixture is mono, and the HE-AAC v2 one carries the mono master in both channels, so nothing showed what the
# decoder, the player and the excerpt export do with two different channels; StereoChannelTests uses these).
#
#   Scripts/fixtures/generate-g04-audio-fixtures.sh    # first: the masters (master-600s.wav, master-long.wav)
#   Scripts/fixtures/generate-g04-audio-stereo.sh      # then: this script (idempotent; under a minute)
#   Scripts/fixtures/generate-g04-audio-stereo.sh --force   # rebuild
#
# Content. master-stereo-300s.wav: 300 s, 44.1 kHz, 16-bit stereo. Its left channel is the first 300 s of
# master-600s.wav (LibriVox Meditations, section 01) and its right channel 300 s of master-long.wav from 1400 s
# (section 02: the same reader, other words), so the two channels carry different, uncorrelated speech at about the
# same level; the script checks that each channel is sample-identical to its source. It is also the WAV fixture. The
# other fixtures are encodes of it, with no metadata, in every provisional release format that can carry two channels
# (ADR-0006): MP3 CBR 128 kb/s (LAME joint stereo), MP3 VBR -q:a 5 with and without the Xing/LAME header, AAC-LC
# 128 kb/s, HE-AAC v1 64 kb/s and HE-AAC v2 32 kb/s (AudioToolbox; v2 is parametric stereo: one downmix plus
# parameters), ALAC, FLAC (native and in MP4), Opus 64 kb/s in Ogg (.ogg and .opus) and MP4, and Opus in CAF
# (afconvert, 64 kb/s). st-dual-mono.flac has the left channel of the master in both channels (the same speech in
# both, as in most stereo audiobooks): the level a mono excerpt keeps.
#
# Determinism and robustness as in the main script: bitexact flags, temporary names renamed on success, SHA-256 per
# file in manifest.tsv, and a stamp of this script, ffmpeg, macOS and both masters that triggers a rebuild on change.
#
# Requires: ffmpeg/ffprobe (Homebrew, with libmp3lame, libopus and AudioToolbox), afconvert (macOS), python3, shasum,
# and the main script's output.
set -euo pipefail
source "$(cd "$(dirname "$0")/../lib" && pwd)/env.sh"

BASE="$SYLVIA_FIXTURE_CACHE/generated/g04-audio"
OUT="$BASE/stereo"
M600="$BASE/master-600s.wav"
MLONG="$BASE/master-long.wav"
# The right channel: master-long.wav from frame 61,740,000 (1400 s at 44.1 kHz); both channels 300 s (13,230,000 frames).
RIGHT_START=61740000
FRAMES=13230000

force=0
[[ "${1:-}" == "--force" ]] && force=1
for tool in ffmpeg ffprobe afconvert shasum python3; do
  command -v "$tool" >/dev/null || { echo "missing tool: $tool (brew install ffmpeg)" >&2; exit 1; }
done
[[ -f "$BASE/.stamp" && -f "$M600" && -f "$MLONG" ]] || { echo "missing masters; run Scripts/fixtures/generate-g04-audio-fixtures.sh first" >&2; exit 1; }

FFMPEG_VERSION="$(ffmpeg -version | head -1)"
MACOS_VERSION="$(sw_vers -productVersion) ($(sw_vers -buildVersion))"
SCRIPT_SHA="$(shasum -a 256 "$0" | awk '{print $1}')"
MASTERS_SHA="$(cat "$M600" "$MLONG" | shasum -a 256 | awk '{print $1}')"
STAMP="$SCRIPT_SHA|$FFMPEG_VERSION|$MACOS_VERSION|$MASTERS_SHA"

mkdir -p "$OUT"
if [[ -f "$OUT/.stamp" && "$(cat "$OUT/.stamp")" == "$STAMP" && $force -eq 0 ]]; then
  echo "g04 stereo fixtures are current in $OUT"
  exit 0
fi
echo "# Command: ${0#"$SYLVIA_ROOT"/}${1:+ $1}; started $(date -u +%Y-%m-%dT%H:%M:%SZ)"
echo "# Environment: host, macOS $MACOS_VERSION, $(sysctl -n machdep.cpu.brand_string 2>/dev/null || echo 'unknown CPU'), $FFMPEG_VERSION"
rm -f "$OUT/.stamp"
find "$OUT" -name '.tmp-*' -delete

ff() { ffmpeg -nostdin -hide_banner -v error -y "$@"; }
BITEXACT=(-fflags +bitexact -flags:a +bitexact)
tmp() { echo "$OUT/.tmp-$1"; }
commit() { mv -f "$(tmp "$1")" "$OUT/$1"; echo "  $1"; }

echo "master"
ff -i "$M600" -i "$MLONG" -filter_complex \
  "[0:a]atrim=end_sample=$FRAMES,asetpts=N/SR/TB[l];[1:a]atrim=start_sample=$RIGHT_START:end_sample=$((RIGHT_START + FRAMES)),asetpts=N/SR/TB[r];[l][r]join=inputs=2:channel_layout=stereo:map=0.0-FL|1.0-FR[out]" \
  -map "[out]" -c:a pcm_s16le "${BITEXACT[@]}" -map_metadata -1 "$(tmp master-stereo-300s.wav)"
# Each channel must be exactly the samples of its source (no resampling, gain or dither on the way).
python3 - "$(tmp master-stereo-300s.wav)" "$M600" "$MLONG" "$RIGHT_START" "$FRAMES" <<'EOF'
import array, sys, wave
stereo, left_src, right_src = sys.argv[1], sys.argv[2], sys.argv[3]
right_start, frames = int(sys.argv[4]), int(sys.argv[5])
def read(path, start, count, channels):
    w = wave.open(path, "rb")
    assert w.getsampwidth() == 2 and w.getframerate() == 44100 and w.getnchannels() == channels, (path, w.getparams())
    assert w.getnframes() >= start + count, (path, w.getnframes())
    w.setpos(start)
    a = array.array("h")
    a.frombytes(w.readframes(count))
    assert len(a) == count * channels, (path, len(a))
    return a
s = read(stereo, 0, frames, 2)
assert s[0::2] == read(left_src, 0, frames, 1), "left channel differs from master-600s.wav"
assert s[1::2] == read(right_src, right_start, frames, 1), "right channel differs from master-long.wav"
print("  master-stereo-300s.wav: left = master-600s.wav [0, %d), right = master-long.wav [%d, %d): sample-identical" % (frames, right_start, right_start + frames))
EOF
commit master-stereo-300s.wav
M="$OUT/master-stereo-300s.wav"

echo "encodes of the stereo master"
# enc <output> <ffmpeg args after the input...>: encode master-stereo-300s.wav, no metadata.
enc() { local name="$1"; shift; ff -i "$M" "$@" "${BITEXACT[@]}" -map_metadata -1 "$(tmp "$name")"; commit "$name"; }
enc st-mp3-cbr.mp3        -c:a libmp3lame -b:a 128k                 # LAME joint stereo
enc st-mp3-vbr-xing.mp3   -c:a libmp3lame -q:a 5
enc st-mp3-vbr-noxing.mp3 -c:a libmp3lame -q:a 5 -write_xing 0  # VBR, no Xing/LAME and no VBRI header
enc st-m4a-aac-lc.m4a     -c:a aac -b:a 128k
enc st-m4a-heaac-v1.m4a   -c:a aac_at -profile:a 4 -b:a 64k       # AudioToolbox HE-AAC (SBR)
enc st-m4a-heaac-v2.m4a   -c:a aac_at -profile:a 28 -b:a 32k      # AudioToolbox HE-AAC v2 (SBR + parametric stereo)
enc st-m4a-alac.m4a       -c:a alac
enc st-flac.flac          -c:a flac
enc st-mp4-flac.m4a       -c:a flac -f mp4
enc st-opus.ogg           -c:a libopus -b:a 64k
enc st-mp4-opus.m4a       -c:a libopus -b:a 64k -f mp4
# ffmpeg cannot mux Opus into CAF; Apple's encoder can (it keeps the two channels).
afconvert -f caff -d opus@48000 -b 64000 "$M" "$(tmp st-caf-opus.caf)"; commit st-caf-opus.caf
# The same Ogg Opus bytes under the .opus extension.
cp "$OUT/st-opus.ogg" "$(tmp st-opus.opus)"; commit st-opus.opus
# The same speech in both channels (the left channel of the master copied to both), lossless: the level a mono
# excerpt keeps from a stereo book whose channels are the same, the common case for spoken audio.
ff -i "$M" -af "pan=stereo|c0=c0|c1=c0" -c:a flac "${BITEXACT[@]}" -map_metadata -1 "$(tmp st-dual-mono.flac)"
commit st-dual-mono.flac

echo "manifest"
{
  echo "# Generated by Scripts/fixtures/generate-g04-audio-stereo.sh"
  echo "# ffmpeg: $FFMPEG_VERSION"
  echo "# macOS (AudioToolbox, afconvert): $MACOS_VERSION"
  echo "# master-stereo-300s.wav: left = master-600s.wav frames [0, $FRAMES), right = master-long.wav frames [$RIGHT_START, $((RIGHT_START + FRAMES)))"
  printf '# file\tsha256\tbytes\tffprobe duration (s)\tcodec\tprofile\tsample rate\tchannels\n'
  (cd "$OUT" && find . -type f ! -name '.*' \( -name '*.mp3' -o -name '*.m4a' -o -name '*.flac' -o -name '*.ogg' -o -name '*.opus' -o -name '*.caf' -o -name '*.wav' \) | sed 's|^\./||' | LC_ALL=C sort) |
  while read -r f; do
    sha="$(shasum -a 256 "$OUT/$f" | awk '{print $1}')"
    bytes="$(stat -f %z "$OUT/$f")"
    dur="$(ffprobe -v error -show_entries format=duration -of default=nw=1:nk=1 "$OUT/$f")"
    codec="$(ffprobe -v error -select_streams a:0 -show_entries stream=codec_name,profile,sample_rate,channels -of default=nw=1:nk=1 "$OUT/$f" | paste -sd '\t' -)"
    printf '%s\t%s\t%s\t%s\t%s\n' "$f" "$sha" "$bytes" "$dur" "$codec"
  done
} > "$OUT/manifest.tsv"
cat "$OUT/manifest.tsv"
echo "$STAMP" > "$OUT/.stamp"
echo "done: $OUT"
