#!/bin/zsh
# Builds Pixelwright from this checkout and installs it as an app.
#
#   ./scripts/install.sh               build and install to /Applications
#   ./scripts/install.sh --open        ...and launch it afterwards
#   ./scripts/install.sh --to ~/Apps   install somewhere else
#   ./scripts/install.sh --uninstall   remove the installed app
#
# You build the app yourself on your own Mac, so macOS shows no "downloaded from the internet"
# warning, and the app matches your Mac's chip. Needs macOS 14+ and Xcode 16+ (Swift 6).
#
# What this script does and doesn't do:
#   - It only writes to build/ in this folder and to Pixelwright.app in the install folder.
#   - It never uses sudo, never touches the network, and never changes any other app.
#   - It leaves your current install untouched if the build fails, and swaps the new one in
#     only after it has been fully copied.
#   - It won't quit a running Pixelwright for you (you might have unsaved work); it asks you to.
set -euo pipefail
cd "$(dirname "$0")/.."

BUNDLE_ID="com.pixelwright.app"
DEST="/Applications"
OPEN=0
UNINSTALL=0
while (( $# > 0 )); do
  case "$1" in
    --open) OPEN=1 ;;
    --uninstall) UNINSTALL=1 ;;
    --to) shift; DEST="${1:?--to needs a folder}" ;;
    -h|--help) sed -n '2,10p' "$0" | sed 's/^# \{0,1\}//'; exit 0 ;;
    *) echo "Unknown option: $1 (try --help)"; exit 2 ;;
  esac
  shift
done
DEST="${DEST/#\~/$HOME}"
APP="$DEST/Pixelwright.app"

fail() { printf '\nCan'"'"'t continue: %s\n\n' "$1" >&2; exit 1; }

(( EUID != 0 )) || fail "don't run this with sudo. It would leave files in this folder that only an administrator can change. Run it as yourself."

# The id of an app bundle, or nothing if it isn't one.
bundle_id_of() { /usr/libexec/PlistBuddy -c "Print :CFBundleIdentifier" "$1/Contents/Info.plist" 2>/dev/null || true; }

# Only ever replace or remove an existing app if it really is Pixelwright.
check_existing_is_ours() {
  [[ -e "$APP" ]] || return 0
  [[ "$(bundle_id_of "$APP")" == "$BUNDLE_ID" ]] \
    || fail "$APP exists but isn't Pixelwright, so I won't touch it. Pick another folder with --to."
}

# We don't quit it for you: it could hold unsaved edits, and quitting from a script is rude.
# Only the copy we are about to replace matters; another copy running elsewhere is fine.
require_not_running() {
  pgrep -f -- "$APP/Contents/MacOS/Pixelwright" >/dev/null || return 0
  fail "Pixelwright is open. Quit it (press Command-Q in the app), then run this again."
}

if (( UNINSTALL )); then
  [[ -e "$APP" ]] || fail "nothing to remove: $APP doesn't exist."
  check_existing_is_ours
  require_not_running
  rm -rf "$APP"
  echo "Removed $APP"
  echo "Its settings live in ~/Library/Preferences/com.pixelwright.app.plist; delete that file too if you like."
  exit 0
fi

# --- Check the requirements, with plain-language fixes ---------------------------------------------
macos_major="$(sw_vers -productVersion | cut -d. -f1)"
(( macos_major >= 14 )) || fail "Pixelwright needs macOS 14 (Sonoma) or later. You have $(sw_vers -productVersion)."

# Ask where the developer tools are before running 'swift'; on a Mac without them, running it
# would pop up an installer window.
xcode-select -p >/dev/null 2>&1 || fail "Apple's developer tools aren't installed. Install Xcode (free, from the Mac App Store), open it once to accept the license, then run this again."
swift_version="$(swift --version 2>&1 | sed -n 's/.*Swift version \([0-9][0-9]*\.[0-9][0-9]*\).*/\1/p' | head -1)"
swift_major="${swift_version%%.*}"
[[ -n "$swift_major" ]] && (( swift_major >= 6 )) \
  || fail "Swift 6 or later is needed (found ${swift_version:-none}). Update Xcode to version 16 or newer."

check_existing_is_ours
require_not_running

# --- Build, then install ---------------------------------------------------------------------------
echo "Building Pixelwright $(tr -d '[:space:]' < VERSION). The first build takes a minute or two..."
./scripts/make-app.sh release
[[ "$(bundle_id_of build/Pixelwright.app)" == "$BUNDLE_ID" ]] || fail "the build didn't produce a valid app. Nothing was installed."

mkdir -p "$DEST" 2>/dev/null || true
[[ -w "$DEST" ]] || fail "can't write to $DEST. Try:  ./scripts/install.sh --to ~/Applications"

# Copy next to the final spot first, then swap, so a failed copy never leaves you without an app.
STAGING="$DEST/.Pixelwright-installing.app"
OLD="$DEST/.Pixelwright-previous.app"
rm -rf "$STAGING" "$OLD"
ditto build/Pixelwright.app "$STAGING"
[[ -e "$APP" ]] && mv "$APP" "$OLD"
if mv "$STAGING" "$APP"; then
  rm -rf "$OLD"
else
  [[ -e "$OLD" ]] && mv "$OLD" "$APP"   # put the previous version back
  fail "couldn't put the new app in place. Your previous install, if any, was restored."
fi

echo
echo "Installed: $APP"
echo "Open it from Launchpad, Spotlight or Finder. No security warning appears, because you built it yourself."
(( OPEN )) && open "$APP"
exit 0
