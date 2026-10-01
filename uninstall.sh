#!/usr/bin/env bash
# Undo what install.sh added: WiVRn binaries, the OpenXR manifest and the
# systemd drop-in. Does not touch Steam, Standable or the Proton prefix.
set -euo pipefail

REPO_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck disable=SC1091
. "$REPO_DIR/tools/lib.sh"

XDG_CONFIG_HOME="${XDG_CONFIG_HOME:-$INVOKING_HOME/.config}"
XDG_CACHE_HOME="${XDG_CACHE_HOME:-$INVOKING_HOME/.cache}"
CACHE_DIR="$XDG_CACHE_HOME/standable-wivrn-port"

WIVRN_LIBDIR="/usr/lib/wivrn"
WIVRN_BINDIR="/usr/bin"
OPENXR_DIR="/usr/share/openxr/1"
DROPIN="$XDG_CONFIG_HOME/systemd/user/wivrn.service.d/standable.conf"

RUN_PORT_UNINSTALL=0

usage() {
    cat <<'EOF'
Usage: uninstall.sh [--with-port-installer]

  --with-port-installer   also run the external port installer's uninstaller
  -h, --help              show this help
EOF
}

while [ $# -gt 0 ]; do
    case "$1" in
        --with-port-installer) RUN_PORT_UNINSTALL=1 ;;
        -h|--help) usage; exit 0 ;;
        *) die "unknown argument: $1 (try --help)" ;;
    esac
    shift
done

say "stopping wivrn.service"
if command -v systemctl >/dev/null 2>&1; then
    user_systemctl stop wivrn.service >/dev/null 2>&1 || true
    user_systemctl reset-failed wivrn.service >/dev/null 2>&1 || true
fi
pkill -f wivrn-server >/dev/null 2>&1 || true
pkill -f ignition_server >/dev/null 2>&1 || true

if [ -f "$DROPIN" ]; then
    say "removing $DROPIN"
    if [ "$(id -u)" -eq 0 ] && [ "$INVOKING_USER" != "root" ] && command -v runuser >/dev/null 2>&1; then
        runuser -u "$INVOKING_USER" -- rm -f "$DROPIN"
        runuser -u "$INVOKING_USER" -- rmdir "$(dirname "$DROPIN")" 2>/dev/null || true
    else
        rm -f "$DROPIN"
        rmdir "$(dirname "$DROPIN")" 2>/dev/null || true
    fi
fi

if command -v systemctl >/dev/null 2>&1; then
    user_systemctl daemon-reload || true
fi

say "removing WiVRn files"
run_root rm -f "$WIVRN_BINDIR/wivrn-server"
run_root rm -rf "$WIVRN_LIBDIR"
run_root rm -f "$OPENXR_DIR/openxr_wivrn.json"

if [ "$RUN_PORT_UNINSTALL" -eq 1 ]; then
    dst="$CACHE_DIR/port-installer"
    script=""
    for s in uninstall.sh uninstall; do
        if [ -f "$dst/$s" ]; then script="$dst/$s"; break; fi
    done
    if [ -n "$script" ]; then
        say "running port installer uninstaller: $script"
        chmod +x "$script"
        ( cd "$dst" && "./$(basename "$script")" )
    else
        warn "no port installer uninstaller found in $dst"
    fi
fi

cat <<'EOF'

Done. Steam, Standable and the Proton prefix were left untouched.
If you installed WiVRn from distro packages, reinstall them if needed.
EOF
