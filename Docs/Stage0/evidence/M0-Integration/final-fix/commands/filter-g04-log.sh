#!/bin/bash
# Writes a copy of a 60-g04-audio drop-in log without the harness process's own system-log lines (those that begin
# with a timestamp and "G04AudioHarness[", about 85 % of the log: AVFoundation and AudioQueue messages), and with any
# line longer than 2,000 characters cut there (Swift Testing prints a failed expectation's captured values in full,
# for example a tap collector's sample arrays on one line of megabytes). Every other line is kept as it was. The
# header says how many lines were left out and how many were cut.
#   Docs/Stage0/evidence/M0-Integration/final-fix/commands/filter-g04-log.sh <drop-in log> <output>
set -u
in="$1"; out="$2"
pattern='^20[0-9]{2}-[0-9]{2}-[0-9]{2} [0-9:.+]+ G04AudioHarness\['
total="$(wc -l < "$in" | tr -d ' ')"
dropped="$(grep -c -E "$pattern" "$in" || true)"
long="$(grep -v -E "$pattern" "$in" | awk 'length($0) > 2000' | wc -l | tr -d ' ')"
{
  echo "# $(basename "$in"), filtered by commands/filter-g04-log.sh: $dropped of its $total lines, the harness process's own"
  echo "# system-log lines (a timestamp, then G04AudioHarness[pid:tid]), are left out, and $long line(s) longer than 2,000"
  echo "# characters are cut there; every other line is kept as it was."
  grep -v -E "$pattern" "$in" | awk '{ if (length($0) > 2000) print substr($0, 1, 2000) " [... " length($0) - 2000 " characters cut]"; else print }'
} > "$out"
