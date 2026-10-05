# Shared environment for Sylvia scripts. Source it; do not execute it.
#   source "$(git rev-parse --show-toplevel)/Scripts/lib/env.sh"

SYLVIA_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]:-$0}")/../.." && pwd)"
export SYLVIA_ROOT

# Pinned toolchain (ADR-0001). Never change xcode-select; point DEVELOPER_DIR at Xcode instead.
export DEVELOPER_DIR="${DEVELOPER_DIR:-/Applications/Xcode.app/Contents/Developer}"
if [[ "$DEVELOPER_DIR" == */CommandLineTools* ]]; then
  export DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer
fi
export SYLVIA_XCODE_BUILD_PINNED="27A266a"

# Signing (ADR-0001). Simulator and host builds need no team.
export SYLVIA_TEAM_ID="${SYLVIA_TEAM_ID:-A4KBDX665Z}"
export SYLVIA_BUNDLE_PREFIX="com.jevidon.sylvia"

# Platform floor (D01, ADR-0001)
export SYLVIA_IOS_DEPLOYMENT_TARGET="26.0"
export SYLVIA_MACOS_DEPLOYMENT_TARGET="26.0"

# Default simulator: closest available runtime to the iOS 26 floor.
export SYLVIA_SIM_RUNTIME="${SYLVIA_SIM_RUNTIME:-com.apple.CoreSimulator.SimRuntime.iOS-26-5}"
export SYLVIA_SIM_RUNTIME_LATEST="com.apple.CoreSimulator.SimRuntime.iOS-27-0"
export SYLVIA_SIM_DEVICE_TYPE="${SYLVIA_SIM_DEVICE_TYPE:-com.apple.CoreSimulator.SimDeviceType.iPhone-17}"

# Shared caches outside any worktree
export SYLVIA_FIXTURE_CACHE="${SYLVIA_FIXTURE_CACHE:-$HOME/Library/Caches/SylviaFixtures}"
export SYLVIA_TOOLS_VENV="${SYLVIA_TOOLS_VENV:-$HOME/Library/Caches/SylviaTools/venv}"

sylvia_check_xcode() {
  local build
  build="$(xcodebuild -version 2>/dev/null | awk '/Build version/ {print $3}')"
  if [[ "$build" != "$SYLVIA_XCODE_BUILD_PINNED" ]]; then
    echo "warning: Xcode build is '$build'; ADR-0001 pins $SYLVIA_XCODE_BUILD_PINNED" >&2
    return 1
  fi
}

sylvia_python() {
  if [[ ! -x "$SYLVIA_TOOLS_VENV/bin/python" ]]; then
    "$SYLVIA_ROOT/Scripts/tools/bootstrap.sh" >&2 || return 1
  fi
  "$SYLVIA_TOOLS_VENV/bin/python" "$@"
}
