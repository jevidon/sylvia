#!/usr/bin/env bash
# Generates the G0.4 audio fixtures into $SYLVIA_FIXTURE_CACHE/generated/g04-audio (plan 3.1, 8.3, 10; T14, T18-T23).
#
#   Scripts/fixtures/fetch.sh                          # first: the LibriVox sources (SHA-256 pinned)
#   Scripts/fixtures/generate-g04-audio-fixtures.sh    # then: this script (idempotent; about 10 minutes the first time)
#   Scripts/fixtures/generate-g04-audio-fixtures.sh --force   # rebuild everything
#
# Content. Every generated file except the tone is an encode of one of two PCM masters cut from the public-domain
# LibriVox recording of Marcus Aurelius' Meditations (Fixtures/LICENSES.md):
#   master-600s.wav   first 600 s of section 01 (a 22.05 kHz MP3), decoded and resampled by ffmpeg to 44.1 kHz mono s16
#   master-long.wav   sections 01 and 02 decoded, resampled and concatenated, 44.1 kHz mono s16 (2161.45 s)
#   tone-1khz-60s.wav a generated 1 kHz sine, 60 s, 44.1 kHz mono s16 (rate and pitch checks)
# Because every encode comes from a known master, the tests compare any decoded window with the exact master
# samples (normalized cross-correlation) and so measure seek and excerpt timing independently of the decoder
# and of the timestamps it reports.
#
# Determinism. ffmpeg runs with bitexact flags so no encoder version string or time stamp is written. Output bytes
# are reproducible for the same ffmpeg build and, for the files encoded by Apple's AudioToolbox (HE-AAC through
# ffmpeg's aac_at, Opus-in-CAF through afconvert), the same macOS version. The SHA-256 of every output is written to
# manifest.tsv beside the files together with the tool versions, so any drift is visible.
#
# Robustness. Every output is written to a temporary name and renamed only when its encoder exits successfully,
# so an interrupted run never leaves a truncated fixture behind. When this script, ffmpeg or macOS changes, the
# stamp no longer matches and everything is rebuilt.
#
# Requires: ffmpeg/ffprobe (Homebrew; built with libmp3lame, libopus and AudioToolbox), afconvert (macOS), python3.
set -euo pipefail
source "$(cd "$(dirname "$0")/../lib" && pwd)/env.sh"

SRC="$SYLVIA_FIXTURE_CACHE/downloads"
OUT="$SYLVIA_FIXTURE_CACHE/generated/g04-audio"
SEC01="$SRC/meditationsofmarcusaurelius_01_aurelius_64kb.mp3"
SEC02="$SRC/meditationsofmarcusaurelius_02_aurelius_64kb.mp3"
M4B="$SRC/MeditationsMarcusAurelius_librivox.m4b"

force=0
[[ "${1:-}" == "--force" ]] && force=1

for tool in ffmpeg ffprobe afconvert shasum python3; do
  command -v "$tool" >/dev/null || { echo "missing tool: $tool (brew install ffmpeg)" >&2; exit 1; }
done
for f in "$SEC01" "$SEC02" "$M4B"; do
  [[ -f "$f" ]] || { echo "missing source $f; run Scripts/fixtures/fetch.sh first" >&2; exit 1; }
done

FFMPEG_VERSION="$(ffmpeg -version | head -1)"
MACOS_VERSION="$(sw_vers -productVersion) ($(sw_vers -buildVersion))"
SCRIPT_SHA="$(shasum -a 256 "$0" | awk '{print $1}')"
STAMP="$SCRIPT_SHA|$FFMPEG_VERSION|$MACOS_VERSION"

mkdir -p "$OUT/multi"
if [[ -f "$OUT/.stamp" ]]; then
  if [[ "$(cat "$OUT/.stamp")" == "$STAMP" && $force -eq 0 ]]; then
    echo "g04 audio fixtures are current in $OUT"
    exit 0
  fi
fi
if [[ ! -f "$OUT/.stamp" || "$(cat "$OUT/.stamp")" != "$STAMP" ]]; then
  # No stamp (first or interrupted run) or a different script/tool version: rebuild everything.
  force=1
fi
rm -f "$OUT/.stamp"
find "$OUT" -name '.tmp-*' -delete

ff() { ffmpeg -nostdin -hide_banner -v error -y "$@"; }
BITEXACT=(-fflags +bitexact -flags:a +bitexact)
need() { [[ $force -eq 1 || ! -s "$OUT/$1" ]]; }
# tmp <relative name>: a temporary path in the same directory that keeps the extension (ffmpeg picks the muxer from it).
tmp() { local d b; d="$(dirname "$OUT/$1")"; b="$(basename "$1")"; echo "$d/.tmp-$b"; }
commit() { mv -f "$(tmp "$1")" "$OUT/$1"; echo "  $1"; }

# The chapter layout written into the generated chaptered files (milliseconds). The tests hold the same table.
cat > "$OUT/chapters-600s.ffmeta" <<'EOF'
;FFMETADATA1
title=Sylvia G04 chapter fixture
[CHAPTER]
TIMEBASE=1/1000
START=0
END=95500
title=Opening
[CHAPTER]
TIMEBASE=1/1000
START=95500
END=241250
title=Chapter Two
[CHAPTER]
TIMEBASE=1/1000
START=241250
END=400000
title=Chapter Three
[CHAPTER]
TIMEBASE=1/1000
START=400000
END=600000
title=Chapter Four
EOF

echo "masters"
if need master-600s.wav; then
  ff -i "$SEC01" -t 600 -ac 1 -ar 44100 -c:a pcm_s16le "${BITEXACT[@]}" -map_metadata -1 "$(tmp master-600s.wav)"
  commit master-600s.wav
fi
if need master-long.wav; then
  ff -i "$SEC01" -i "$SEC02" -filter_complex "[0:a]aresample=44100[a0];[1:a]aresample=44100[a1];[a0][a1]concat=n=2:v=0:a=1,aformat=sample_fmts=s16:channel_layouts=mono[out]" \
     -map "[out]" -c:a pcm_s16le "${BITEXACT[@]}" -map_metadata -1 "$(tmp master-long.wav)"
  commit master-long.wav
fi
if need tone-1khz-60s.wav; then
  ff -f lavfi -i "sine=frequency=1000:sample_rate=44100:duration=60" -af "volume=-6dB" -ac 1 -c:a pcm_s16le "${BITEXACT[@]}" -map_metadata -1 "$(tmp tone-1khz-60s.wav)"
  commit tone-1khz-60s.wav
fi
M600="$OUT/master-600s.wav"
MLONG="$OUT/master-long.wav"
LONG_FRAMES="$(ffprobe -v error -select_streams a:0 -show_entries stream=duration_ts -of default=nw=1:nk=1 "$MLONG")"
echo "  master-long.wav: $LONG_FRAMES frames at 44100 Hz"

# enc <output> <ffmpeg args after the input...>: encode master-600s.wav, no metadata.
enc() { local name="$1"; shift; need "$name" || return 0; ff -i "$M600" "$@" "${BITEXACT[@]}" -map_metadata -1 "$(tmp "$name")"; commit "$name"; }
# encchap <output> <ffmpeg args...>: encode master-600s.wav with the chapter table.
encchap() { local name="$1"; shift; need "$name" || return 0
  ff -i "$M600" -i "$OUT/chapters-600s.ffmeta" -map 0:a -map_metadata 1 -map_chapters 1 "$@" "${BITEXACT[@]}" "$(tmp "$name")"; commit "$name"; }

echo "format matrix (encodes of master-600s.wav)"
# Every container that can carry chapters gets the chapter table, written the way ffmpeg writes it for that
# container (the tests record which ones AVFoundation reads): MP3 as ID3v2.3 CHAP/CTOC frames, MP4/M4A as a
# QuickTime chapter text track, FLAC and Ogg as CHAPTERxxx Vorbis comments, WebM as Matroska chapters, and WAV as
# cue points with labels (below). The plain MP3 variants stay without chapters (the ID3 CHAP file covers MP3), and
# no tool here writes chapter metadata into CAF.
enc     fmt-mp3-cbr.mp3        -c:a libmp3lame -b:a 64k
enc     fmt-mp3-vbr-xing.mp3   -c:a libmp3lame -q:a 5
enc     fmt-mp3-vbr-noxing.mp3 -c:a libmp3lame -q:a 5 -write_xing 0      # VBR, no Xing/LAME and no VBRI header
encchap fmt-mp3-chap.mp3       -c:a libmp3lame -b:a 64k -id3v2_version 3 # ID3v2.3 CHAP + CTOC frames
encchap fmt-m4a-aac-lc.m4a     -c:a aac -b:a 64k                         # ipod muxer: QuickTime chapter text track
encchap fmt-m4a-heaac-v1.m4a   -c:a aac_at -profile:a 4 -b:a 32k         # AudioToolbox HE-AAC (SBR)
encchap fmt-m4a-heaac-v2.m4a   -ac 2 -c:a aac_at -profile:a 28 -b:a 32k  # AudioToolbox HE-AAC v2 (SBR + PS, needs stereo input)
encchap fmt-m4a-alac.m4a       -c:a alac
# FLAC and Ogg Opus carry the chapter table as Vorbis comments in the chapter extension's form, CHAPTERxxx and
# CHAPTERxxxNAME (three digits, from 001), set directly: ffmpeg 8.1.2's FLAC muxer writes no chapters, and its Ogg
# muxer wrote the 95.5 s chapter start as 00:01:36.500 (observed while building these fixtures).
VORBIS_CHAPTERS=(-metadata title="Sylvia G04 chapter fixture"
  -metadata CHAPTER001=00:00:00.000 -metadata CHAPTER001NAME=Opening
  -metadata CHAPTER002=00:01:35.500 -metadata CHAPTER002NAME="Chapter Two"
  -metadata CHAPTER003=00:04:01.250 -metadata CHAPTER003NAME="Chapter Three"
  -metadata CHAPTER004=00:06:40.000 -metadata CHAPTER004NAME="Chapter Four")
enc     fmt-flac.flac          -c:a flac "${VORBIS_CHAPTERS[@]}"
encchap fmt-mp4-flac.m4a       -c:a flac -f mp4
enc     fmt-opus.ogg           -c:a libopus -b:a 32k "${VORBIS_CHAPTERS[@]}"  # comments in the OpusTags header
encchap fmt-webm-opus.webm     -c:a libopus -b:a 32k                     # Matroska chapters
encchap fmt-mp4-opus.m4a       -c:a libopus -b:a 32k -f mp4
if need fmt-caf-opus.caf; then  # ffmpeg cannot mux Opus into CAF; Apple's encoder can
  afconvert -f caff -d opus@48000 -b 32000 "$M600" "$(tmp fmt-caf-opus.caf)"; commit fmt-caf-opus.caf
fi
if need fmt-opus.opus; then     # the same Ogg Opus bytes under the .opus extension
  cp "$OUT/fmt-opus.ogg" "$(tmp fmt-opus.opus)"; commit fmt-opus.opus
fi
if need fmt-wav.wav; then
  # The master's PCM with the chapter table as a RIFF 'cue ' chunk (one cue point per chapter start, in sample
  # frames) and a 'LIST'/'adtl' chunk with one 'labl' (title) per cue point, appended after the data chunk.
  python3 - "$M600" "$(tmp fmt-wav.wav)" <<'EOF'
import struct, sys
src, dst = sys.argv[1], sys.argv[2]
chapters = [(0, "Opening"), (95500, "Chapter Two"), (241250, "Chapter Three"), (400000, "Chapter Four")]
data = bytearray(open(src, "rb").read())
assert data[:4] == b"RIFF" and data[8:12] == b"WAVE"
rate = None
pos = 12
while pos + 8 <= len(data):
    cid, size = data[pos:pos + 4], struct.unpack("<I", data[pos + 4:pos + 8])[0]
    if cid == b"fmt ":
        rate = struct.unpack("<I", data[pos + 12:pos + 16])[0]
    pos += 8 + size + (size & 1)
assert rate == 44100, rate
cue = struct.pack("<I", len(chapters))
for i, (ms, _) in enumerate(chapters):
    frame = ms * rate // 1000
    cue += struct.pack("<II4sIII", i + 1, frame, b"data", 0, 0, frame)
adtl = b"adtl"
for i, (_, title) in enumerate(chapters):
    text = title.encode("ascii") + b"\0"
    body = struct.pack("<I", i + 1) + text
    adtl += b"labl" + struct.pack("<I", len(body)) + body + (b"\0" if len(body) & 1 else b"")
out = data + b"cue " + struct.pack("<I", len(cue)) + cue + b"LIST" + struct.pack("<I", len(adtl)) + adtl
out[4:8] = struct.pack("<I", len(out) - 8)
open(dst, "wb").write(out)
EOF
  commit fmt-wav.wav
fi
if need fmt-librivox-mp3-22k.mp3; then
  # The LibriVox section 01 MP3 itself (MPEG-2 Layer III, 22.05 kHz mono, 64 kb/s CBR), the commonest public-domain
  # audiobook MP3. master-600s.wav is ffmpeg's decode of its first 600 s, so it is measured against that master.
  cp "$SEC01" "$(tmp fmt-librivox-mp3-22k.mp3)"; commit fmt-librivox-mp3-22k.mp3
fi
if need tone-1khz-60s.m4a; then
  ff -i "$OUT/tone-1khz-60s.wav" -c:a aac -b:a 64k "${BITEXACT[@]}" -map_metadata -1 "$(tmp tone-1khz-60s.m4a)"; commit tone-1khz-60s.m4a
fi

echo "multi-file book (T14): file names and embedded track numbers disagree"
# Member content is consecutive slices of master-long.wav; the true order is the embedded track order.
# name           content slice of master-long (s)   track tag
# Part 2.mp3     0.000    - 137.500                 1/4
# Part 1.mp3     137.500  - 299.750                 2/4
# Part 3.mp3     299.750  - 449.750                 3/4
# Part 10.mp3    449.750  - 569.850                 4/4
member() {
  local name="$1" start="$2" dur="$3" track="$4"
  need "multi/$name" || return 0
  ff -ss "$start" -t "$dur" -i "$MLONG" -c:a libmp3lame -b:a 64k "${BITEXACT[@]}" -map_metadata -1 \
     -metadata title="Meditations sample, member $track" -metadata album="Sylvia G04 multi-file book" -metadata track="$track/4" \
     -id3v2_version 3 "$(tmp "multi/$name")"
  commit "multi/$name"
}
member "Part 2.mp3"  0       137.5  1
member "Part 1.mp3"  137.5   162.25 2
member "Part 3.mp3"  299.75  150    3
member "Part 10.mp3" 449.75  120.1  4

echo "long files (>= 10 h): master-long.wav looped 17 times"
LOOPS=17
python3 - "$LONG_FRAMES" "$LOOPS" > "$OUT/chapters-long.ffmeta" <<'EOF'
import sys
frames, loops = int(sys.argv[1]), int(sys.argv[2])
print(";FFMETADATA1\ntitle=Sylvia G04 long fixture")
for i in range(loops):
    print("[CHAPTER]\nTIMEBASE=1/44100\nSTART=%d\nEND=%d\ntitle=Loop %d" % (i * frames, (i + 1) * frames, i + 1))
EOF
if need long-aac-10h.m4b; then
  echo "  long-aac-10h.m4b (AAC-LC 48 kb/s, one chapter per loop; several minutes)"
  ff -stream_loop $((LOOPS - 1)) -i "$MLONG" -i "$OUT/chapters-long.ffmeta" -map 0:a -map_metadata 1 -map_chapters 1 \
     -c:a aac -b:a 48k -f ipod "${BITEXACT[@]}" "$(tmp long-aac-10h.m4b)"
  commit long-aac-10h.m4b
fi
if need long-mp3-cbr-10h.mp3; then
  echo "  long-mp3-cbr-10h.mp3 (MP3 CBR 64 kb/s; several minutes)"
  ff -stream_loop $((LOOPS - 1)) -i "$MLONG" -c:a libmp3lame -b:a 64k "${BITEXACT[@]}" -map_metadata -1 "$(tmp long-mp3-cbr-10h.mp3)"
  commit long-mp3-cbr-10h.mp3
fi
if need long-mp3-vbr-10h.mp3; then
  # VBR with a Xing/LAME header: the seek-latency versus seek-accuracy trade-off of long VBR MP3s (ADR-0006).
  echo "  long-mp3-vbr-10h.mp3 (MP3 VBR -q:a 5 with Xing/LAME header; several minutes)"
  ff -stream_loop $((LOOPS - 1)) -i "$MLONG" -c:a libmp3lame -q:a 5 "${BITEXACT[@]}" -map_metadata -1 "$(tmp long-mp3-vbr-10h.mp3)"
  commit long-mp3-vbr-10h.mp3
fi

echo "manifest"
{
  echo "# Generated by Scripts/fixtures/generate-g04-audio-fixtures.sh"
  echo "# ffmpeg: $FFMPEG_VERSION"
  echo "# macOS (AudioToolbox, afconvert): $MACOS_VERSION"
  echo "# master-long frames at 44100 Hz: $LONG_FRAMES"
  printf '# file\tsha256\tbytes\tffprobe duration (s)\tcodec\tprofile\tsample rate\tchannels\tchapters\n'
  (cd "$OUT" && find . -type f ! -name '.*' \( -name '*.mp3' -o -name '*.m4a' -o -name '*.m4b' -o -name '*.flac' -o -name '*.ogg' -o -name '*.opus' -o -name '*.webm' -o -name '*.caf' -o -name '*.wav' \) | sed 's|^\./||' | LC_ALL=C sort) |
  while read -r f; do
    sha="$(shasum -a 256 "$OUT/$f" | awk '{print $1}')"
    bytes="$(stat -f %z "$OUT/$f")"
    dur="$(ffprobe -v error -show_entries format=duration -of default=nw=1:nk=1 "$OUT/$f")"
    codec="$(ffprobe -v error -select_streams a:0 -show_entries stream=codec_name,profile,channels,sample_rate -of default=nw=1:nk=1 "$OUT/$f" | paste -sd '\t' -)"
    chapters="$(ffprobe -v error -show_chapters -of csv=p=0 "$OUT/$f" | grep -c . || true)"
    printf '%s\t%s\t%s\t%s\t%s\t%s\n' "$f" "$sha" "$bytes" "$dur" "$codec" "$chapters"
  done
} > "$OUT/manifest.tsv"
cat "$OUT/manifest.tsv"
echo "$STAMP" > "$OUT/.stamp"
echo "done: $OUT"
