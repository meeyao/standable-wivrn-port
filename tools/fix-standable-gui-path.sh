#!/bin/bash
# fix-standable-gui-path.sh - make the Standable GUI's driver-path check pass.
#
# Proton copies ~/.config/openvr/openvrpaths.vrpath into the Standable prefix
# on every launch, and the GUI does a raw Win32 substring check for its own
# Windows-side path there. A Linux-only entry can never match, so the GUI pops
# "The SteamVR driver path is missing or incorrect" every boot. This adds the
# S:\ form to the host file (the durable fix) and repairs the current prefix
# copy. The native driver and the Linux SteamVR entry are left alone.
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

# S: maps to the Steam library root, or to its steamapps dir on some Proton
# builds. The GUI sees whatever the prefix link points at, so use that.
S_TARGET="$LIB"
if [ -L "$PFX/dosdevices/s:" ]; then
    S_TARGET="$(readlink -f "$PFX/dosdevices/s:")"
fi

# The host file is the source: Proton re-copies it into the prefix at every
# launch, so a prefix-only repair is overwritten before the GUI checks it.
HOST="${XDG_CONFIG_HOME:-$HOME/.config}/openvr/openvrpaths.vrpath"
mkdir -p "$(dirname "$HOST")"
python3 - "$HOST" "$GAME_DIR" "$S_TARGET" <<'PY'
import json, os, sys
host, game_dir, s_target = sys.argv[1:4]
try:
    rel = os.path.relpath(game_dir, s_target)
except Exception:
    rel = None
expected = 'S:\\' + rel.replace('/', '\\') if rel and not rel.startswith('..') else None
try:
    data = json.load(open(host))
except Exception:
    data = {"runtime": [], "version": 1}
ed = data.get('external_drivers') or []
new = [e for e in ed if not ('Standable' in e and e.startswith('S:') and e != expected)]
if expected and expected not in new:
    new.insert(0, expected)
if new != ed:
    data['external_drivers'] = new
    json.dump(data, open(host, 'w'), indent=2)
    print("seeded %s" % expected)
else:
    print("seed already present: %s" % expected)
PY

if [ ! -d "$PFX" ]; then
    echo "Standable prefix not created yet; launch the GUI once from Steam."
    exit 0
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
ln -sfn "$S_TARGET" "$PFX/dosdevices/s:"
bash "$TEMPLATE" "$PFX" "$GAME_DIR" "$S_TARGET"
echo "Restart the Standable GUI."
