#!/bin/bash
# standable-gui-wivrn.sh - open the Standable desktop settings window while
# WiVRn hosts the driver.
#
# Launch this from a desktop session, NOT through Steam: Steam's
# pressure-vessel sandbox forks a second wineserver, and named pipes do not
# cross servers, so the GUI could not talk to the driver.
#
# It mirrors launch_serverhelper.sh / the SteamVR launch hook: same compatdata
# prefix, same resolved Proton, foreign wineservers cleared, s: link and the
# Windows-side path registration repaired, so the GUI joins the driver's
# wineserver.
#
# Paths are written by install.sh to ~/.config/standable-wivrn/paths.conf.
set -u

CONF="${XDG_CONFIG_HOME:-$HOME/.config}/standable-wivrn/paths.conf"
if [ ! -r "$CONF" ]; then
    echo "standable-gui-wivrn: $CONF not found; re-run install.sh" >&2
    exit 1
fi
# shellcheck disable=SC1090
. "$CONF"

: "${GAME_DIR:?}"; : "${STEAM_COMPAT_DATA_PATH:?}"; : "${STEAM_COMPAT_CLIENT_INSTALL_PATH:?}"; : "${PROTON:?}"; : "${APP_ID:?}"
export STEAM_COMPAT_DATA_PATH STEAM_COMPAT_CLIENT_INSTALL_PATH
export SteamAppId="$APP_ID" SteamGameId="$APP_ID"
export IPC_IGNORE_VERSION=1

# Resolve the Proton the driver is actually using (shared resolver).
if [ -f "$GAME_DIR/bin/linux64/proton_resolve.sh" ]; then
    # shellcheck disable=SC1090
    . "$GAME_DIR/bin/linux64/proton_resolve.sh"
    _R=$(proton_resolve "$STEAM_COMPAT_DATA_PATH" "$STEAM_COMPAT_CLIENT_INSTALL_PATH" "$APP_ID" "$PROTON" 2>/dev/null)
    [ -n "$_R" ] && PROTON="$_R"
    unset _R
fi

PFX="$STEAM_COMPAT_DATA_PATH/pfx"
S_LINK="$PFX/dosdevices/s:"
S_ROOT="$(cd "$GAME_DIR/../.." 2>/dev/null && pwd)"
[ -n "$S_ROOT" ] || S_ROOT="$STEAM_COMPAT_CLIENT_INSTALL_PATH"
if grep -q 'get_validated_steamapps_parent' "${PROTON%/proton}/proton" 2>/dev/null; then
    S_TARGET="$S_ROOT"
else
    S_TARGET="$S_ROOT/steamapps"
fi
fix_s() { ln -sfn "$S_TARGET" "$S_LINK" 2>/dev/null; }
fix_s

# Free foreign-Proton wineservers on our prefix so this launch joins the
# driver's wineserver instead of starting its own.
if [ -f "$GAME_DIR/bin/linux64/sweep.sh" ]; then
    # shellcheck disable=SC1090
    . "$GAME_DIR/bin/linux64/sweep.sh"
    clear_foreign_wineservers
fi

# Keep the Windows-side driver registration clean.
if [ -x "$GAME_DIR/bin/linux64/win_vrpath.sh" ]; then
    "$GAME_DIR/bin/linux64/win_vrpath.sh" "$PFX" "$GAME_DIR" "$S_TARGET" || true
fi

# Host OpenXR runtime -> WiVRn (the GUI's wineopenxr bridge reads this).
mkdir -p "$HOME/.config/openxr/1"
ln -sfn /usr/share/openxr/1/openxr_wivrn.json "$HOME/.config/openxr/1/active_runtime.json" 2>/dev/null || true

# Optional in-VR bridge: an OpenComposite/xrizer vrclient_x64.dll at BRIDGE_DIR
# is dropped into the game dir only for this run (removed on exit) so SteamVR
# never sees it. Without it the desktop window still works; the in-VR dashboard
# is the part that needs the bridge.
BRIDGE_DST="$GAME_DIR/vrclient_x64.dll"
BRIDGE_BAK="$BRIDGE_DST.wivrn-bak"
cleanup() {
    if [ -e "$BRIDGE_BAK" ]; then
        mv -f "$BRIDGE_BAK" "$BRIDGE_DST" 2>/dev/null || true
    elif [ -n "${BRIDGE_COPIED:-}" ]; then
        rm -f "$BRIDGE_DST"
    fi
}
if [ -n "${BRIDGE_DIR:-}" ] && [ -f "$BRIDGE_DIR/vrclient_x64.dll" ]; then
    [ -e "$BRIDGE_DST" ] && cp -f "$BRIDGE_DST" "$BRIDGE_BAK"
    if cp -f "$BRIDGE_DIR/vrclient_x64.dll" "$BRIDGE_DST"; then
        BRIDGE_COPIED=1
        export WINEDLLOVERRIDES="vrclient_x64=n,b"
        trap cleanup EXIT
    fi
fi

LOG="${XDG_STATE_HOME:-$HOME/.local/state}/standable/gui-wivrn.log"
mkdir -p "$(dirname "$LOG")"
{
    echo "=== $(date -Iseconds) launch ==="
    echo "proton: $PROTON"
    echo "game:   $GAME_DIR/Standable.exe"
} >> "$LOG"

cd "$GAME_DIR" || exit 1
"$PROTON" run ./Standable.exe >> "$LOG" 2>&1
_code=$?
echo "exit:   $_code ($(date -Iseconds))" >> "$LOG"
exit "$_code"
