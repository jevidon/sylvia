#!/bin/bash
# M0 device fixes, fix-1, the security review of 26 October 2026 (finding S7): removes folders that the host-facts probe
# left in the temporary folder when it stopped early with the screen locked, each named on the command line, and lists
# each one's contents first. Only names of the probe's own form (g05-devicefix-probe- and 8 hexadecimal digits) are
# accepted; rm -R removes a link without following it. Build Mac only.
#   Docs/Stage0/evidence/M0-DeviceFixes/fix-1/security/commands/remove-probe-leftovers.sh <log name> <folder name>...
# Log: Docs/Stage0/evidence/M0-DeviceFixes/fix-1/security/<log name>.log
set -u
root="$(cd "$(dirname "$0")/../../../../../../.." && pwd)"
cd "$root" || exit 1
name="$1"
shift
out="Docs/Stage0/evidence/M0-DeviceFixes/fix-1/security/$name.log"
tmp="${TMPDIR:-$(/usr/bin/getconf DARWIN_USER_TEMP_DIR)}"
status=0
{
  echo "command: Docs/Stage0/evidence/M0-DeviceFixes/fix-1/security/commands/remove-probe-leftovers.sh $name $*"
  echo "commit: $(git -C "$root" rev-parse HEAD) ($(git -C "$root" rev-parse --abbrev-ref HEAD))"
  echo "time: $(date -u +%Y-%m-%dT%H:%M:%SZ)"
  echo "temporary folder: $tmp"
  for folder in "$@"; do
    if [[ ! "$folder" =~ ^g05-devicefix-probe-[0-9A-F]{8}$ ]]; then
      echo "refused, not a name of the probe's form: $folder"; status=1; continue
    fi
    if [[ ! -d "$tmp/$folder" || -L "$tmp/$folder" ]]; then
      echo "not found as a folder: $folder"; status=1; continue
    fi
    echo "---- $folder, before its removal (ls -lR, made $(stat -f '%Sm' -t '%Y-%m-%dT%H:%M:%S%z' "$tmp/$folder"))"
    (cd "$tmp" && ls -lR "$folder")
    rm -R "${tmp:?}/$folder"
    if [[ -e "$tmp/$folder" ]]; then echo "NOT removed: $folder"; status=1; else echo "removed: $folder"; fi
  done
  echo "the probe's folders left in the temporary folder:"
  found="$(cd "$tmp" && ls -d g05-devicefix-probe-* 2>/dev/null)"
  if [[ -n "$found" ]]; then echo "$found" | sed 's/^/  /'; else echo "  none"; fi
  echo "exit: $status"
} > "$out" 2>&1
cat "$out"
exit $status
