#!/usr/bin/env bash
# Undo what install.sh added: WiVRn binaries and unit, the OpenXR manifest, the
# systemd drop-in and helper files. Does not touch Steam, Standable or the
# Proton prefix.
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
UNIT="/usr/lib/systemd/user/wivrn.service"
REAPER_BIN="/usr/local/bin/reap-ignition"
SYSTEMD_USER="$XDG_CONFIG_HOME/systemd/user"
DROPIN="$SYSTEMD_USER/wivrn.service.d/standable.conf"
RUNTIME_LINK="$XDG_CONFIG_HOME/openxr/1/active_runtime.json"
GUI_CONF_DIR="$XDG_CONFIG_HOME/standable-wivrn"

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
# Reap by PID (pkill can hang on the agent/session shell).
for pat in wivrn-server ignition_server; do
    for p in /proc/[0-9]*; do
        cmd="$(tr '\0' ' ' <"${p}/cmdline" 2>/dev/null || true)"
        case "$cmd" in
            *"$pat"*) kill -9 "${p#/proc/}" 2>/dev/null || true ;;
        esac
    done
done

say "removing systemd drop-in and helper units"
if [ -f "$DROPIN" ]; then
    rm -f "$DROPIN"
    rmdir "$(dirname "$DROPIN")" 2>/dev/null || true
fi
rm -f "$SYSTEMD_USER/wivrn-reap.service" "$SYSTEMD_USER/wivrn-reap.timer"
if command -v systemctl >/dev/null 2>&1; then
    user_systemctl daemon-reload || true
fi

say "removing WiVRn files"
run_root rm -f "$WIVRN_BINDIR/wivrn-server"
run_root rm -rf "$WIVRN_LIBDIR"
run_root rm -f "$OPENXR_DIR/openxr_wivrn.json"
run_root rm -f "$UNIT"
run_root rm -f "$REAPER_BIN"

say "removing user helper files"
rm -f "$XDG_CONFIG_HOME/environment.d/wivrn-ipc.conf"
rm -f "$INVOKING_HOME/.local/bin/vrswitch"
rm -f "$INVOKING_HOME/.local/bin/standable-gui-wivrn"
rm -f "$INVOKING_HOME/.local/share/applications/standable-gui-wivrn.desktop"
rm -f "$GUI_CONF_DIR/paths.conf"
rmdir "$GUI_CONF_DIR" 2>/dev/null || true

# Drop the OpenXR active-runtime symlink only if it points at the manifest we
# just removed, so we do not clobber a runtime the user set themselves.
if [ -L "$RUNTIME_LINK" ] && [ "$(readlink "$RUNTIME_LINK" 2>/dev/null || true)" = "$OPENXR_DIR/openxr_wivrn.json" ]; then
    rm -f "$RUNTIME_LINK"
fi

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
