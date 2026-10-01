#!/usr/bin/env bash
# lib.sh - shared prelude for install.sh / uninstall.sh.
# When invoked through sudo, $HOME and the XDG vars belong to root, not to the
# user who owns the WiVRn/Steam setup. Resolve the invoking user's home so the
# systemd drop-in and caches land in the right place.
# shellcheck disable=SC2034
INVOKING_USER="${SUDO_USER:-$(id -un)}"
if [ "$INVOKING_USER" = "root" ]; then
    INVOKING_HOME="$HOME"
else
    INVOKING_HOME="$(getent passwd "$INVOKING_USER" | cut -d: -f6)"
    [ -n "$INVOKING_HOME" ] || INVOKING_HOME="$HOME"
fi

say()  { printf '==> %s\n' "$*"; }
warn() { printf 'warning: %s\n' "$*" >&2; }
die()  { printf 'error: %s\n' "$*" >&2; exit 1; }

require() {
    command -v "$1" >/dev/null 2>&1 || die "required command not found: $1"
}

SUDO=""
if [ "$(id -u)" -ne 0 ]; then
    require sudo
    SUDO="sudo"
fi
run_root() { if [ -n "$SUDO" ]; then $SUDO "$@"; else "$@"; fi; }

# systemctl --user must run as the invoking user, on their session bus.
user_systemctl() {
    if [ "$(id -u)" -eq 0 ] && [ "$INVOKING_USER" != "root" ] && command -v runuser >/dev/null 2>&1; then
        XDG_RUNTIME_DIR="/run/user/$(id -u "$INVOKING_USER")" \
            runuser -u "$INVOKING_USER" -- systemctl --user "$@"
    else
        systemctl --user "$@"
    fi
}
