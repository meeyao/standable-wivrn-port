#!/bin/bash
# fix-standable-gui-path.sh - repair the Windows-side OpenVR path file used by
# the Standable GUI under Proton.
#
# The GUI reads
#   <prefix>/drive_c/users/*/AppData/Local/openvr/openvrpaths.vrpath
# and warns when a Standable entry is a Linux path or a stale S:\ variant.
# This rewrites just that file to the S:\ path for the game's Steam library.
# The native driver and the host openvrpaths are not touched.
set -u

GAME_DIR="${GAME_DIR:-$HOME/.local/share/Steam/steamapps/common/Standable Full Body Estimation}"
if [ ! -d "$GAME_DIR" ]; then
    echo "Standable game dir not found: $GAME_DIR" >&2
    echo "Set GAME_DIR if the game is in another Steam library." >&2
    exit 1
fi

LIB="$(cd "$GAME_DIR/../../.." 2>/dev/null && pwd)" || {
    echo "Could not derive the Steam library from $GAME_DIR" >&2
    exit 1
}
PFX="${PFX:-$LIB/steamapps/compatdata/2370570/pfx}"
if [ ! -d "$PFX" ]; then
    echo "Standable Proton prefix not found: $PFX" >&2
    echo "Launch the Standable GUI once from Steam, then run this again." >&2
    exit 1
fi

TEMPLATE="${XDG_DATA_HOME:-$HOME/.local/share}/standable-wivrn/win_vrpath.sh"
if [ ! -f "$TEMPLATE" ]; then
    TEMPLATE="$(cd "$(dirname "$0")/.." 2>/dev/null && pwd)/installer/templates/win_vrpath.sh.in"
fi
if [ ! -f "$TEMPLATE" ]; then
    echo "win_vrpath helper missing; re-run install.sh" >&2
    exit 1
fi

mkdir -p "$PFX/dosdevices"
ln -sfn "$LIB" "$PFX/dosdevices/s:"
bash "$TEMPLATE" "$PFX" "$GAME_DIR" "$LIB"
echo "Restart the Standable GUI."
