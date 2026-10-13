#!/usr/bin/env bash
# Generates the long (3 h and 10 h) G0.4 fixtures for every provisional release format other than the AAC M4B and
# the MP3 files the main script already makes long, into $SYLVIA_FIXTURE_CACHE/generated/g04-audio/long-formats
# (review R3-01: open time under precise timing grows with file length in some containers, so every format proposed
# for the release list is measured long, not only as a 10-minute file).
#
#   Scripts/fixtures/fetch.sh                                # first: the LibriVox sources (SHA-256 pinned)
#   Scripts/fixtures/generate-g04-audio-fixtures.sh          # then: the masters and the main fixtures
#   Scripts/fixtures/generate-g04-audio-long-formats.sh      # then: this script (idempotent; about 25 minutes the first time)
#   Scripts/fixtures/generate-g04-audio-long-formats.sh --force   # rebuild everything
#
# Content. Every file is master-long.wav (sections 01 and 02 of the public-domain LibriVox Meditations, 44.1 kHz mono,
# 2161.45 s; made by the main script) looped 17 times (10.2 h) or 5 times (3.0 h), encoded the same way as the
# 10-minute file of the same format in the main script, so the tests fold any position back into master-long and
# measure timing by cross-correlation. Containers that carry chapters get one chapter per loop, written the way the
# main script writes that container's chapters (QuickTime chapter track in MP4/M4A, CHAPTERxxx Vorbis comments in
# FLAC and Ogg); WAV and CAF get none (AVFoundation reads no WAV cue chapters, and no tool here writes CAF chapters).
#
# Native FLAC gets a SEEKTABLE with a seek point every 10 s, as the reference encoder (`flac`, default -S 10s) writes
# one: ffmpeg 8.1.2's FLAC muxer writes none, so it is inserted below from ffprobe's packet positions, and every seek
# point is checked to land on a frame header. The audio frames are copied byte for byte.
#
# Sizes: about 9 GB in all (the 10-hour WAV alone is 3.2 GB, the FLAC and ALAC files 1-1.5 GB each). Determinism and
# robustness as in the main script: bitexact flags, temporary names renamed on success, SHA-256 per file in
# manifest.tsv, and a stamp of this script, ffmpeg and macOS that triggers a rebuild when any of them changes.
#
# Requires: ffmpeg/ffprobe (Homebrew), afconvert (macOS), python3, and the main script's output.
set -euo pipefail
source "$(cd "$(dirname "$0")/../lib" && pwd)/env.sh"

BASE="$SYLVIA_FIXTURE_CACHE/generated/g04-audio"
OUT="$BASE/long-formats"
MLONG="$BASE/master-long.wav"

force=0
[[ "${1:-}" == "--force" ]] && force=1

for tool in ffmpeg ffprobe afconvert shasum python3; do
  command -v "$tool" >/dev/null || { echo "missing tool: $tool (brew install ffmpeg)" >&2; exit 1; }
done
[[ -f "$BASE/.stamp" && -f "$MLONG" ]] || { echo "missing $MLONG; run Scripts/fixtures/generate-g04-audio-fixtures.sh first" >&2; exit 1; }

FFMPEG_VERSION="$(ffmpeg -version | head -1)"
MACOS_VERSION="$(sw_vers -productVersion) ($(sw_vers -buildVersion))"
SCRIPT_SHA="$(shasum -a 256 "$0" | awk '{print $1}')"
MASTER_SHA="$(shasum -a 256 "$MLONG" | awk '{print $1}')"
STAMP="$SCRIPT_SHA|$FFMPEG_VERSION|$MACOS_VERSION|$MASTER_SHA"

mkdir -p "$OUT"
if [[ -f "$OUT/.stamp" && "$(cat "$OUT/.stamp")" == "$STAMP" && $force -eq 0 ]]; then
  echo "g04 long-format fixtures are current in $OUT"
  exit 0
fi
if [[ ! -f "$OUT/.stamp" || "$(cat "$OUT/.stamp")" != "$STAMP" ]]; then
  force=1
fi
rm -f "$OUT/.stamp"
find "$OUT" -name '.tmp-*' -delete

ff() { ffmpeg -nostdin -hide_banner -v error -y "$@"; }
BITEXACT=(-fflags +bitexact -flags:a +bitexact)
need() { [[ $force -eq 1 || ! -s "$OUT/$1" ]]; }
tmp() { echo "$OUT/.tmp-$1"; }
commit() { mv -f "$(tmp "$1")" "$OUT/$1"; echo "  $1 ($(stat -f %z "$OUT/$1") bytes)"; }

LONG_FRAMES="$(ffprobe -v error -select_streams a:0 -show_entries stream=duration_ts -of default=nw=1:nk=1 "$MLONG")"
echo "master-long.wav: $LONG_FRAMES frames at 44100 Hz"

# chapters <loops> <ffmeta|vorbis>: one chapter per loop, as an ffmetadata file or as -metadata arguments.
chapters() {
  python3 - "$LONG_FRAMES" "$1" "$2" <<'EOF'
import sys
frames, loops, kind = int(sys.argv[1]), int(sys.argv[2]), sys.argv[3]
if kind == "ffmeta":
    print(";FFMETADATA1\ntitle=Sylvia G04 long fixture")
    for i in range(loops):
        print("[CHAPTER]\nTIMEBASE=1/44100\nSTART=%d\nEND=%d\ntitle=Loop %d" % (i * frames, (i + 1) * frames, i + 1))
else:
    print("title=Sylvia G04 long fixture")
    for i in range(loops):
        ms = round(i * frames * 1000 / 44100)
        h, rem = divmod(ms, 3600000)
        m, rem = divmod(rem, 60000)
        s, ms3 = divmod(rem, 1000)
        print("CHAPTER%03d=%02d:%02d:%02d.%03d" % (i + 1, h, m, s, ms3))
        print("CHAPTER%03dNAME=Loop %d" % (i + 1, i + 1))
EOF
}
chapters 17 ffmeta > "$OUT/chapters-17.ffmeta"
vorbis_args() { local a=(); while IFS= read -r line; do a+=(-metadata "$line"); done < <(chapters "$1" vorbis); printf '%s\0' "${a[@]}"; }
VORBIS17=(); while IFS= read -r -d '' x; do VORBIS17+=("$x"); done < <(vorbis_args 17)
VORBIS5=(); while IFS= read -r -d '' x; do VORBIS5+=("$x"); done < <(vorbis_args 5)

# loop <loops> <output> <ffmpeg args...>: master-long looped, no metadata from the input.
loop() { local loops="$1" name="$2"; shift 2; need "$name" || return 0
  echo "  encoding $name"
  ff -stream_loop $((loops - 1)) -i "$MLONG" "$@" "${BITEXACT[@]}" "$(tmp "$name")"; commit "$name"; }
# loopchap <output> <ffmpeg args...>: master-long looped 17 times with the 17-chapter table (MP4/M4A chapter track).
loopchap() { local name="$1"; shift; need "$name" || return 0
  echo "  encoding $name"
  ff -stream_loop 16 -i "$MLONG" -i "$OUT/chapters-17.ffmeta" -map 0:a -map_metadata 1 -map_chapters 1 "$@" "${BITEXACT[@]}" "$(tmp "$name")"
  commit "$name"; }

# seektable <file>: inserts a FLAC SEEKTABLE (one point every 10 s of samples) after STREAMINFO, in place.
seektable() {
  local f="$OUT/$1" packets
  packets="$(mktemp "${TMPDIR:-/tmp}/g04-flac-packets.XXXXXX")"
  ffprobe -v error -select_streams a:0 -show_packets -show_entries packet=pts,pos -of csv=p=0 "$f" > "$packets"
  python3 - "$f" "$packets" "$(tmp "$1")" <<'EOF'
import struct, sys
src, packets, dst = sys.argv[1], sys.argv[2], sys.argv[3]
frames = []
for line in open(packets):
    pts, pos = line.strip().split(",")[:2]
    frames.append((int(pts), int(pos)))
frames.sort()
with open(src, "rb") as f:
    head = f.read(1 << 20)
assert head[:4] == b"fLaC"
blocks, p = [], 4
while True:
    h = head[p]
    last, kind, n = h >> 7, h & 0x7F, int.from_bytes(head[p + 1:p + 4], "big")
    blocks.append((kind, head[p + 4:p + 4 + n]))
    p += 4 + n
    if last:
        break
audio_start = p
assert frames[0] == (0, audio_start), (frames[0], audio_start)
assert all(k != 3 for k, _ in blocks), "already has a SEEKTABLE"
info = blocks[0][1]
rate = int.from_bytes(info[10:13], "big") >> 4
total = int.from_bytes(info[13:18], "big") & ((1 << 36) - 1)
assert rate == 44100 and total > 0, (rate, total)
# One point per 10 s: the frame that contains each target sample (as the reference encoder's -S 10s).
points, j = [], 0
for target in range(0, total, rate * 10):
    while j + 1 < len(frames) and frames[j + 1][0] <= target:
        j += 1
    if not points or points[-1][0] != frames[j][0]:
        nxt = frames[j + 1][0] if j + 1 < len(frames) else total
        points.append((frames[j][0], frames[j][1] - audio_start, nxt - frames[j][0]))
table = b"".join(struct.pack(">QQH", s, off, n) for s, off, n in points)
order = [blocks[0], (3, table)] + blocks[1:]
out = bytearray(b"fLaC")
for i, (kind, body) in enumerate(order):
    out += bytes([kind | (0x80 if i == len(order) - 1 else 0)]) + len(body).to_bytes(3, "big") + body
with open(src, "rb") as f, open(dst, "wb") as o:
    o.write(out)
    new_audio_start = len(out)
    f.seek(audio_start)
    while True:
        chunk = f.read(1 << 24)
        if not chunk:
            break
        o.write(chunk)
# Every seek point must land on a frame sync code (0xFFF8 or 0xFFF9) in the output.
with open(dst, "rb") as o:
    for s, off, n in points:
        o.seek(new_audio_start + off)
        sync = o.read(2)
        assert sync in (b"\xff\xf8", b"\xff\xf9"), (s, off, sync.hex())
print("  seektable: %d points, every 10 s of %d samples at %d Hz, verified on frame headers" % (len(points), total, rate))
EOF
  rm -f "$packets"
  commit "$1"
}

echo "native FLAC with a seek table (Vorbis-comment chapters, one per loop)"
# (Every run that gets this far rebuilds everything: a run that stopped early wrote no stamp, so the encode and its
# seek table are always made together.)
loop 5 long-flac-3h.flac -c:a flac -map_metadata -1 "${VORBIS5[@]}"
seektable long-flac-3h.flac
loop 17 long-flac-10h.flac -c:a flac -map_metadata -1 "${VORBIS17[@]}"
seektable long-flac-10h.flac

echo "Ogg Opus (Vorbis-comment chapters in OpusTags), .ogg and .opus"
loop 5 long-opus-3h.ogg -c:a libopus -b:a 32k -map_metadata -1 "${VORBIS5[@]}"
loop 17 long-opus-10h.ogg -c:a libopus -b:a 32k -map_metadata -1 "${VORBIS17[@]}"
if need long-opus-10h.opus; then cp "$OUT/long-opus-10h.ogg" "$(tmp long-opus-10h.opus)"; commit long-opus-10h.opus; fi

echo "MP4/M4A (QuickTime chapter track)"
loopchap long-mp4-flac-10h.m4a -c:a flac -f mp4
loopchap long-mp4-opus-10h.m4a -c:a libopus -b:a 32k -f mp4
loopchap long-m4a-alac-10h.m4a -c:a alac
loopchap long-m4a-heaac-v1-10h.m4a -c:a aac_at -profile:a 4 -b:a 32k
loopchap long-m4a-heaac-v2-10h.m4a -ac 2 -c:a aac_at -profile:a 28 -b:a 32k

echo "WAV (PCM 16-bit) and Opus in CAF (no chapters)"
loop 17 long-wav-10h.wav -c:a pcm_s16le -map_metadata -1
if need long-caf-opus-10h.caf; then
  echo "  encoding long-caf-opus-10h.caf (afconvert)"
  afconvert -f caff -d opus@48000 -b 32000 "$OUT/long-wav-10h.wav" "$(tmp long-caf-opus-10h.caf)"; commit long-caf-opus-10h.caf
fi

echo "MP3 VBR without Xing/VBRI header"
loop 17 long-mp3-vbr-noxing-10h.mp3 -c:a libmp3lame -q:a 5 -write_xing 0 -map_metadata -1

echo "manifest"
{
  echo "# Generated by Scripts/fixtures/generate-g04-audio-long-formats.sh"
  echo "# ffmpeg: $FFMPEG_VERSION"
  echo "# macOS (AudioToolbox, afconvert): $MACOS_VERSION"
  echo "# master-long.wav sha256 $MASTER_SHA, $LONG_FRAMES frames at 44100 Hz"
  printf '# file\tsha256\tbytes\tffprobe duration (s)\tcodec\tprofile\tsample rate\tchannels\tchapters\n'
  (cd "$OUT" && find . -type f ! -name '.*' ! -name '*.ffmeta' ! -name 'manifest.tsv' | sed 's|^\./||' | LC_ALL=C sort) |
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
