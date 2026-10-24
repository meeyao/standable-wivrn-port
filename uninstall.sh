#!/usr/bin/env bash
# Remove what install.sh added. The installer records its component choices in
# ~/.local/state/standable-wivrn/installed; this script reads that manifest and
# offers the same choices, so a minimal install gets a minimal uninstall.
#
# Steam, Standable, and the Proton prefix are only touched if you select the
# "Standable/Proton side" component.
set -euo pipefail

REPO_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck disable=SC1091
. "$REPO_DIR/tools/lib.sh"

XDG_CONFIG_HOME="${XDG_CONFIG_HOME:-$INVOKING_HOME/.config}"
WIVRN_BINDIR="/usr/bin"
OPENXR_DIR="/usr/share/openxr/1"
UNIT="/usr/lib/systemd/user/wivrn.service"
REAPER_BIN="/usr/local/bin/reap-ignition"
SYSTEMD_USER="$XDG_CONFIG_HOME/systemd/user"
DROPIN="$SYSTEMD_USER/wivrn.service.d/standable.conf"
RUNTIME_LINK="$XDG_CONFIG_HOME/openxr/1/active_runtime.json"
GUI_CONF_DIR="$XDG_CONFIG_HOME/standable-wivrn"
APP_DIR="$INVOKING_HOME/.local/share/applications"
MANIFEST="$INVOKING_HOME/.local/state/standable-wivrn/installed"

declare -A M=()
if [ -f "$MANIFEST" ]; then
    while IFS='=' read -r k v; do
        [ -n "$k" ] && M["$k"]="$v"
    done <"$MANIFEST"
fi

DO_WIVRN=${M[wivrn]:-1}
DO_PORT=0
DO_XRIZER=0
[ "${M[xrizer_installed]:-0}" = "1" ] && DO_XRIZER=${M[xrizer]:-1}
DO_GUI=${M[gui]:-1}
DO_REAPER=${M[reaper]:-1}
DO_WIRING=${M[wiring]:-1}
ASSUME_YES=0
DRY_RUN=0

usage() {
    cat <<'EOF'
Usage: uninstall.sh [options]

  --yes                   accept the default selection
  --dry-run               show what would be removed, change nothing
  --with-port-installer   also run the vendored Standable/Proton uninstaller
  -h, --help              show this help

Without --yes, a checklist lets you toggle components. The defaults come from
the manifest written by install.sh.
EOF
}

while [ $# -gt 0 ]; do
    case "$1" in
        --yes) ASSUME_YES=1 ;;
        --dry-run) DRY_RUN=1 ;;
        --with-port-installer) DO_PORT=1 ;;
        -h|--help) usage; exit 0 ;;
        *) echo "error: unknown argument: $1 (try --help)" >&2; exit 1 ;;
    esac
    shift
done

act() {
    if [ "$DRY_RUN" -eq 1 ]; then
        printf '  would: %s\n' "$*"
    else
        "$@"
    fi
}
act_root() {
    if [ "$DRY_RUN" -eq 1 ]; then
        printf '  would (root): %s\n' "$*"
    else
        run_root "$@"
    fi
}

choose_components() {
    [ "$ASSUME_YES" -eq 1 ] && return 0
    [ -t 0 ] || return 0
    local choice n
    while true; do
        printf '\nStandable WiVRn uninstaller\n'
        printf '  1) [%s] Patched WiVRn server + runtime\n' "$([ "$DO_WIVRN" -eq 1 ] && echo x || echo ' ')"
        printf '  2) [%s] Standable/Proton side (Steam shims, prefix changes)\n' "$([ "$DO_PORT" -eq 1 ] && echo x || echo ' ')"
        printf '  3) [%s] xrizer (%s)\n' "$([ "$DO_XRIZER" -eq 1 ] && echo x || echo ' ')" "${M[xrizer_kind]:-not installed by this installer}"
        printf '  4) [%s] Standable GUI launcher\n' "$([ "$DO_GUI" -eq 1 ] && echo x || echo ' ')"
        printf '  5) [%s] Background orphan timer (start/stop cleanup stays on)\n' "$([ "$DO_REAPER" -eq 1 ] && echo x || echo ' ')"
        printf '  6) [%s] vrswitch + OpenXR/env wiring\n' "$([ "$DO_WIRING" -eq 1 ] && echo x || echo ' ')"
        printf '\n  Numbers toggle, Enter removes, q quits.\n'
        read -r -p '> ' choice || die "aborted"
        case "$choice" in
            "") break ;;
            q|Q) die "aborted" ;;
            *)
                for n in $choice; do
                    case "$n" in
                        1) DO_WIVRN=$((1 - DO_WIVRN)) ;;
                        2) DO_PORT=$((1 - DO_PORT)) ;;
                        3) DO_XRIZER=$((1 - DO_XRIZER)) ;;
                        4) DO_GUI=$((1 - DO_GUI)) ;;
                        5) DO_REAPER=$((1 - DO_REAPER)) ;;
                        6) DO_WIRING=$((1 - DO_WIRING)) ;;
                        *) warn "no component $n" ;;
                    esac
                done
                ;;
        esac
    done
}

say "manifest: $MANIFEST"
[ -f "$MANIFEST" ] || warn "no manifest; defaulting to a full uninstall"
choose_components

if [ "$DRY_RUN" -eq 1 ]; then
    say "dry run: nothing will be changed"
fi

# --- stop the runtime -------------------------------------------------------
if [ "$DO_WIVRN" -eq 1 ] || [ "$DO_WIRING" -eq 1 ]; then
    say "stopping wivrn.service"
    if command -v systemctl >/dev/null 2>&1; then
        act user_systemctl stop wivrn.service || true
        act user_systemctl reset-failed wivrn.service || true
    fi
    if [ "$DRY_RUN" -eq 0 ]; then
        # Exact process names only: a cmdline substring scan also matches
        # editors, greps and the caller's own shell.
        for p in /proc/[0-9]*; do
            comm="$(cat "$p/comm" 2>/dev/null || true)"
            case "$comm" in
                wivrn-server|ignition_server) kill -9 "${p#/proc/}" 2>/dev/null || true ;;
            esac
        done
    fi
fi

# --- WiVRn server/runtime ---------------------------------------------------
if [ "$DO_WIVRN" -eq 1 ]; then
    say "removing WiVRn files"
    act_root rm -f "$WIVRN_BINDIR/wivrn-server"
    act_root rm -rf /usr/lib/wivrn /usr/lib64/wivrn
    act_root rm -f "$UNIT"
    act_root rm -f "$OPENXR_DIR/openxr_wivrn.json"
    if [ -L "$RUNTIME_LINK" ] && [ "$(readlink "$RUNTIME_LINK" 2>/dev/null || true)" = "$OPENXR_DIR/openxr_wivrn.json" ]; then
        act rm -f "$RUNTIME_LINK"
    fi
fi

# --- Standable/Proton side --------------------------------------------------
if [ "$DO_PORT" -eq 1 ]; then
    if [ -x "$REPO_DIR/installer/install.sh" ]; then
        say "running the vendored Standable/Proton uninstaller"
        if [ "$DRY_RUN" -eq 1 ]; then
            echo "  would: (cd $REPO_DIR/installer && ./install.sh --uninstall)"
        else
            ( cd "$REPO_DIR/installer" && ./install.sh --uninstall )
        fi
    else
        warn "installer/install.sh not found; skipping the Standable/Proton side"
    fi
fi

# --- xrizer -----------------------------------------------------------------
if [ "$DO_XRIZER" -eq 1 ]; then
    case "${M[xrizer_kind]:-}" in
        copr)
            say "removing the xrizer package (COPR)"
            if command -v dnf >/dev/null 2>&1; then
                act_root dnf remove -y xrizer || warn "could not remove xrizer"
            else
                warn "dnf not found; remove xrizer with your package manager"
            fi
            ;;
        pacman)
            say "removing the xrizer package (pacman)"
            if command -v pacman >/dev/null 2>&1; then
                act_root pacman -Rns --noconfirm xrizer || warn "could not remove xrizer"
            else
                warn "pacman not found; remove xrizer with your package manager"
            fi
            ;;
        release)
            say "removing /opt/xrizer"
            act_root rm -rf /opt/xrizer
            ;;
        *)
            say "xrizer was not installed by this installer; leaving it"
            ;;
    esac
fi

# --- GUI launcher -----------------------------------------------------------
if [ "$DO_GUI" -eq 1 ]; then
    say "removing the Standable GUI launcher"
    act rm -f "$INVOKING_HOME/.local/bin/standable-gui-wivrn"
    act rm -f "$APP_DIR/standable-gui-wivrn.desktop"
    act rm -f "$GUI_CONF_DIR/paths.conf"
    if [ "$DRY_RUN" -eq 0 ]; then
        rmdir "$GUI_CONF_DIR" 2>/dev/null || true
    fi
fi

# --- background cleanup -----------------------------------------------------
if [ "$DO_REAPER" -eq 1 ]; then
    say "removing the background orphan timer"
    if command -v systemctl >/dev/null 2>&1; then
        act user_systemctl disable --now wivrn-reap.timer || true
    fi
    act rm -f "$SYSTEMD_USER/wivrn-reap.service" "$SYSTEMD_USER/wivrn-reap.timer"
    act rm -f "$SYSTEMD_USER/timers.target.wants/wivrn-reap.timer" \
        "$SYSTEMD_USER/default.target.wants/wivrn-reap.timer"
fi
if [ "$DO_WIRING" -eq 1 ]; then
    say "removing the reaper binary"
    act_root rm -f "$REAPER_BIN"
fi

# --- runtime wiring ---------------------------------------------------------
if [ "$DO_WIRING" -eq 1 ]; then
    say "removing vrswitch / drop-in / environment wiring"
    act rm -f "$DROPIN"
    if [ "$DRY_RUN" -eq 0 ]; then
        rmdir "$(dirname "$DROPIN")" 2>/dev/null || true
    fi
    act rm -f "$INVOKING_HOME/.local/bin/vrswitch"
    act rm -f "$XDG_CONFIG_HOME/environment.d/wivrn-ipc.conf"
    if command -v systemctl >/dev/null 2>&1; then
        act user_systemctl daemon-reload || true
    fi
fi

# Keep the choices that were not removed, so a second run does not default to
# a full uninstall.
if [ "$DRY_RUN" -eq 0 ]; then
    r_wivrn=$([ "$DO_WIVRN" -eq 1 ] && echo 0 || echo "${M[wivrn]:-1}")
    r_port=$([ "$DO_PORT" -eq 1 ] && echo 0 || echo "${M[port]:-0}")
    r_xrizer=$([ "$DO_XRIZER" -eq 1 ] && echo 0 || echo "${M[xrizer]:-0}")
    r_xrizer_installed=$([ "$DO_XRIZER" -eq 1 ] && echo 0 || echo "${M[xrizer_installed]:-0}")
    r_gui=$([ "$DO_GUI" -eq 1 ] && echo 0 || echo "${M[gui]:-1}")
    r_reaper=$([ "$DO_REAPER" -eq 1 ] && echo 0 || echo "${M[reaper]:-1}")
    r_wiring=$([ "$DO_WIRING" -eq 1 ] && echo 0 || echo "${M[wiring]:-1}")
    if [ "$r_wivrn$r_port$r_xrizer$r_gui$r_reaper$r_wiring" = "000000" ]; then
        rm -f "$MANIFEST"
    else
        mkdir -p "$(dirname "$MANIFEST")"
        {
            echo "version=1"
            echo "updated_at=$(date -Iseconds)"
            echo "wivrn=$r_wivrn"
            echo "port=$r_port"
            echo "xrizer=$r_xrizer"
            echo "xrizer_kind=${M[xrizer_kind]:-found}"
            echo "xrizer_installed=$r_xrizer_installed"
            echo "gui=$r_gui"
            echo "reaper=$r_reaper"
            echo "wiring=$r_wiring"
        } > "$MANIFEST"
        say "manifest updated: $MANIFEST"
    fi
fi

cat <<'EOF'

Done.
Steam, Standable and the Proton prefix were left untouched unless you selected
the Standable/Proton side.
If you installed WiVRn from distro packages, reinstall them if needed.
EOF
