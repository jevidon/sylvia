# XcodeGen helpers. Source after env.sh.
#
# Generated .xcodeproj bundles are not committed (ADR-0002), but their package lock is.
# Each project directory keeps its lock as <dir>/Package.resolved next to project.yml.
#
#   sylvia_generate Spikes/G04-Audio                 # xcodegen + install the committed lock
#   xcodebuild -project ... -disableAutomaticPackageResolution ...   # builds honor the lock
#   sylvia_resolve Spikes/G04-Audio                  # (re)resolve and save the lock after a dependency change

_sylvia_xcodeproj() {
  local dir="$1" proj
  proj="$(find "$dir" -maxdepth 1 -name '*.xcodeproj' -print -quit)"
  [[ -n "$proj" ]] || { echo "no .xcodeproj in $dir; run sylvia_generate first" >&2; return 1; }
  echo "$proj"
}

sylvia_generate() {
  local dir="$1" proj lock
  (cd "$dir" && xcodegen generate --quiet) || return 1
  proj="$(_sylvia_xcodeproj "$dir")" || return 1
  if [[ -f "$dir/Package.resolved" ]]; then
    lock="$proj/project.xcworkspace/xcshareddata/swiftpm"
    mkdir -p "$lock"
    cp "$dir/Package.resolved" "$lock/Package.resolved"
  fi
}

sylvia_resolve() {
  local dir="$1" proj resolved
  proj="$(_sylvia_xcodeproj "$dir")" || return 1
  xcodebuild -resolvePackageDependencies -project "$proj" >/dev/null || return 1
  resolved="$proj/project.xcworkspace/xcshareddata/swiftpm/Package.resolved"
  if [[ -f "$resolved" ]]; then
    cp "$resolved" "$dir/Package.resolved"
    echo "saved lock: $dir/Package.resolved"
  else
    echo "project has no package dependencies; nothing to save"
  fi
}
