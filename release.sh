#!/usr/bin/env bash
#
# release.sh — build / deploy / delete / re-deploy the WatchHomeControl app to a
# physical Apple Watch from the terminal, using Xcode's CLI tools (xcodebuild +
# devicectl). This wraps the workflow documented in .kiro/steering/tech.md.
#
# There is no server-side release here; this is purely on-device app management.
#
# Usage:
#   ./release.sh <command> [args]
#
# Commands:
#   devices              List paired/connected devices (raw devicectl output).
#   build                Clean-build + code-sign the app for the Watch.
#   install              Install the most recent build onto the Watch.
#   launch               Launch the installed app on the Watch.
#   uninstall            Remove the app from the Watch (also clears its Keychain).
#   deploy               build + install + launch (typical code-change flow).
#   redeploy             uninstall + clean build + install (required after icon change).
#   icon                 Regenerate AppIcon.png from the home-control UI icon.
#   verify-icon          Check the icon compiled into the built .app bundle.
#   test  [xcodebuild args]   Run the test suite on a watchOS Simulator. Extra
#                        args are passed through, e.g. for a fast single-test
#                        loop: ./release.sh test -only-testing:WatchHomeControlTests/URLValidatorPropertyTests
#   pair                 Mint a backend pairing code (needs API_KEY env or arg).
#   status               Show resolved device + whether the app is installed.
#
# Environment overrides:
#   WATCH_UDID   Target Watch UDID. If unset, the first connected physical
#                Apple Watch is auto-detected.
#   API_KEY      Backend API key, used by the `pair` command.
#   BASE_URL     Backend base URL for `pair` (default https://192.168.1.122:8443).

set -euo pipefail

# --- Constants -------------------------------------------------------------

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT="WatchHomeControl.xcodeproj"
SCHEME="WatchHomeControl Watch App"
BUNDLE_ID="ch.reber.watchhomecontrol.watchkitapp"
DERIVED="build/cli-device"
TEST_DERIVED="build/cli-test-liveapi"
APP_PATH="${DERIVED}/Build/Products/Debug-watchos/WatchHomeControl Watch App.app"
SIM_NAME="Apple Watch Ultra 2 (49mm)"
DEFAULT_BASE_URL="https://192.168.1.122:8443"

# Icon source (canonical home-control PWA icon) + destination in this repo.
ICON_SRC="/Users/martin/git/raspberry/home-control/web/icon-512.png"
ICON_DST="${REPO_ROOT}/WatchHomeControl Watch App/Assets.xcassets/AppIcon.appiconset/AppIcon.png"

# --- Helpers ---------------------------------------------------------------

log()  { printf '\033[1;34m▶ %s\033[0m\n' "$*"; }
ok()   { printf '\033[1;32m✔ %s\033[0m\n' "$*"; }
warn() { printf '\033[1;33m! %s\033[0m\n' "$*" >&2; }
die()  { printf '\033[1;31m✗ %s\033[0m\n' "$*" >&2; exit 1; }

# Resolve the target Watch UDID: honor $WATCH_UDID, else auto-detect the first
# connected physical Apple Watch from `devicectl list devices`.
resolve_udid() {
  if [[ -n "${WATCH_UDID:-}" ]]; then
    printf '%s' "$WATCH_UDID"
    return 0
  fi
  local udid
  udid="$(xcrun devicectl list devices 2>/dev/null \
    | awk '/[Ww]atch/ && /connected/ { for (i=1;i<=NF;i++) if ($i ~ /^[0-9A-Fa-f]{8}-[0-9A-Fa-f]{16}$/ || $i ~ /^[0-9A-Fa-f]{40}$/) { print $i; exit } }')"
  [[ -n "$udid" ]] || die "No connected Apple Watch found. Pair it in Device Hub, or set WATCH_UDID. See: ./release.sh devices"
  printf '%s' "$udid"
}

require_app_built() {
  [[ -d "${REPO_ROOT}/${APP_PATH}" ]] \
    || die "No built app at ${APP_PATH}. Run: ./release.sh build"
}

# --- Commands --------------------------------------------------------------

cmd_devices() {
  xcrun devicectl list devices
}

cmd_status() {
  local udid; udid="$(resolve_udid)"
  log "Target Watch UDID: ${udid}"
  if [[ -d "${REPO_ROOT}/${APP_PATH}" ]]; then
    ok "Local build present: ${APP_PATH}"
  else
    warn "No local build yet (run: ./release.sh build)"
  fi
  log "Installed apps matching bundle id:"
  xcrun devicectl device info apps --device "$udid" 2>/dev/null \
    | grep -i "$BUNDLE_ID" || warn "App not currently installed on the Watch."
}

cmd_build() {
  cd "$REPO_ROOT"
  local udid; udid="$(resolve_udid)"
  log "Clean-building '${SCHEME}' for Watch ${udid}"
  xcodebuild \
    -project "$PROJECT" \
    -scheme "$SCHEME" \
    -destination "id=${udid}" \
    -derivedDataPath "$DERIVED" \
    clean build
  ok "Build succeeded → ${APP_PATH}"
}

cmd_install() {
  cd "$REPO_ROOT"
  require_app_built
  local udid; udid="$(resolve_udid)"
  log "Installing onto Watch ${udid}"
  xcrun devicectl device install app --device "$udid" "${REPO_ROOT}/${APP_PATH}"
  ok "Installed ${BUNDLE_ID}"
}

cmd_launch() {
  local udid; udid="$(resolve_udid)"
  log "Launching ${BUNDLE_ID} on Watch ${udid}"
  xcrun devicectl device process launch --device "$udid" "$BUNDLE_ID"
  ok "Launched"
}

cmd_uninstall() {
  local udid; udid="$(resolve_udid)"
  warn "Uninstalling ${BUNDLE_ID} — this also clears the app's Keychain (re-pair needed)."
  xcrun devicectl device uninstall app --device "$udid" "$BUNDLE_ID"
  ok "Uninstalled"
}

cmd_deploy() {
  cmd_build
  cmd_install
  cmd_launch
  ok "Deploy complete (build + install + launch)."
}

cmd_redeploy() {
  warn "Re-deploy: uninstall → clean build → install (use after an icon change)."
  cmd_uninstall || warn "Uninstall failed or app was not installed; continuing."
  cmd_build
  cmd_install
  ok "Re-deploy complete. If the icon still looks stale, restart the Watch once."
  log "Keychain was cleared — re-pair with: ./release.sh pair"
}

cmd_icon() {
  [[ -f "$ICON_SRC" ]] || die "Icon source not found: ${ICON_SRC}"
  command -v python3 >/dev/null || die "python3 not found."
  python3 - "$ICON_SRC" "$ICON_DST" <<'PY'
import sys
from PIL import Image
src, dst = sys.argv[1], sys.argv[2]
img = Image.open(src).convert("RGBA")
bg = Image.new("RGBA", img.size, (255, 255, 255, 255))  # web background_color is #ffffff
flat = Image.alpha_composite(bg, img).convert("RGB")     # drop alpha (watchOS requirement)
flat.resize((1024, 1024), Image.LANCZOS).save(dst, "PNG")
print("wrote", dst)
PY
  ok "Icon regenerated → ${ICON_DST}"
  log "Now run: ./release.sh redeploy   (to clear the cached icon on the Watch)"
}

cmd_verify_icon() {
  cd "$REPO_ROOT"
  require_app_built
  local app="${REPO_ROOT}/${APP_PATH}"
  log "Icon renditions in Assets.car:"
  xcrun --sdk watchos assetutil --info "${app}/Assets.car" 2>/dev/null \
    | grep -iE "AssetType|RenditionName|PixelWidth" || warn "No icon renditions found."
  log "Info.plist icon keys:"
  /usr/libexec/PlistBuddy -c "Print :CFBundleIcons" "${app}/Info.plist" 2>/dev/null \
    || warn "CFBundleIcons not present."
}

cmd_test() {
  cd "$REPO_ROOT"
  # Pre-warm the simulator so xcodebuild doesn't pay a cold-boot wait, and pin
  # derived data locally so incremental compilation is reused across runs.
  xcrun simctl boot "$SIM_NAME" >/dev/null 2>&1 || true
  log "Running tests on simulator '${SIM_NAME}'"
  xcodebuild test \
    -project "$PROJECT" \
    -scheme "$SCHEME" \
    -destination "platform=watchOS Simulator,name=${SIM_NAME}" \
    -derivedDataPath "${TEST_DERIVED}" \
    "$@"
  ok "Tests passed"
}

cmd_pair() {
  local key="${1:-${API_KEY:-}}"
  local base="${BASE_URL:-$DEFAULT_BASE_URL}"
  [[ -n "$key" ]] || die "No API key. Pass as arg or set API_KEY:  ./release.sh pair <API_KEY>"
  command -v jq >/dev/null || warn "jq not found — printing raw JSON."
  log "Minting a pairing code from ${base}"
  local resp
  resp="$(curl -sS -X POST "${base}/pairing/codes" \
    -H "X-API-Key: ${key}" \
    -H "Content-Type: application/json")" \
    || die "Request failed — is the backend reachable at ${base}?"
  if command -v jq >/dev/null; then
    printf '%s\n' "$resp" | jq
    local code; code="$(printf '%s' "$resp" | jq -r '.code // empty')"
    [[ -n "$code" ]] && ok "Enter this 6-digit code on the Watch: ${code}"
  else
    printf '%s\n' "$resp"
  fi
}

usage() {
  sed -n '2,40p' "${BASH_SOURCE[0]}" | sed 's/^# \{0,1\}//'
}

# --- Dispatch --------------------------------------------------------------

main() {
  local cmd="${1:-}"; shift || true
  case "$cmd" in
    devices)     cmd_devices "$@" ;;
    status)      cmd_status "$@" ;;
    build)       cmd_build "$@" ;;
    install)     cmd_install "$@" ;;
    launch)      cmd_launch "$@" ;;
    uninstall)   cmd_uninstall "$@" ;;
    deploy)      cmd_deploy "$@" ;;
    redeploy)    cmd_redeploy "$@" ;;
    icon)        cmd_icon "$@" ;;
    verify-icon) cmd_verify_icon "$@" ;;
    test)        cmd_test "$@" ;;
    pair)        cmd_pair "$@" ;;
    ""|-h|--help|help) usage ;;
    *) die "Unknown command: ${cmd}. Run './release.sh help'." ;;
  esac
}

main "$@"
