#!/usr/bin/env bash
# Standable WiVRn Linux Port installer.
#
# Runs the external port installer (Standable + Proton prefix side), then
# installs the WiVRn runtime/server and the systemd user drop-in that enables
# steamvr_lh driver hosting. Idempotent.
set -euo pipefail

REPO_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck disable=SC1091
. "$REPO_DIR/tools/lib.sh"

# --- overridable configuration ---------------------------------------------
PORT_INSTALLER_REPO="${PORT_INSTALLER_REPO:-https://github.com/meeyao/standable-linux-port}"
PORT_INSTALLER_REF="${PORT_INSTALLER_REF:-}"   # empty = repo default branch
WIVRN_REPO="${WIVRN_REPO:-https://github.com/meeyao/wivrn-standable-port}"
WIVRN_REF="${WIVRN_REF:-main}"
REPO_RELEASE_BASE="${REPO_RELEASE_BASE:-https://github.com/meeyao/standable-wivrn-port/releases/latest/download}"

XDG_CONFIG_HOME="${XDG_CONFIG_HOME:-$INVOKING_HOME/.config}"
XDG_DATA_HOME="${XDG_DATA_HOME:-$INVOKING_HOME/.local/share}"
XDG_CACHE_HOME="${XDG_CACHE_HOME:-$INVOKING_HOME/.cache}"
CACHE_DIR="$XDG_CACHE_HOME/standable-wivrn-port"

WIVRN_LIBDIR="/usr/lib/wivrn"
WIVRN_BINDIR="/usr/bin"
OPENXR_DIR="/usr/share/openxr/1"
REAPER_SRC="$REPO_DIR/tools/reap-ignition.sh"
REAPER_BIN="/usr/local/bin/reap-ignition"

MODE="prebuilt"
SKIP_PORT_INSTALLER=0

# --- output helpers ---------------------------------------------------------
usage() {
    cat <<'EOF'
Usage: install.sh [options]

  --prebuilt              install WiVRn from the latest release (default)
  --source                clone and build the WiVRn fork
  --skip-port-installer   do not run the external Standable/Proton installer
  -h, --help              show this help

Environment:
  PORT_INSTALLER_REPO     default https://github.com/meeyao/standable-linux-port
  PORT_INSTALLER_REF      git ref, default: repo default branch
  WIVRN_REPO              default https://github.com/meeyao/wivrn-standable-port
  WIVRN_REF               default main
  REPO_RELEASE_BASE       prebuilt download base URL
EOF
}

# --- path discovery ---------------------------------------------------------
detect_distro() {
    local id="" like=""
    if [ -r /etc/os-release ]; then
        # shellcheck disable=SC1091
        . /etc/os-release
        id="${ID:-}"
        like="${ID_LIKE:-}"
    fi
    case " $id $like " in
        *" arch "*|*" archlinux "*|*" cachyos "*) echo arch ;;
        *" debian "*|*" ubuntu "*|*" linuxmint "*) echo debian ;;
        *) echo unknown ;;
    esac
}

print_build_deps() {
    case "$(detect_distro)" in
        arch)
            cat <<'EOF'
WiVRn build deps (Arch/CachyOS):
  sudo pacman -S --needed base-devel cmake ninja git \
    vulkan-headers vulkan-icd-loader libgl ffmpeg libx264 pipewire eigen glib2 \
    libbsd libdrm libxrandr libxcb libx11
EOF
            ;;
        debian)
            cat <<'EOF'
WiVRn build deps (Debian/Ubuntu):
  sudo apt install build-essential cmake ninja-build git \
    libvulkan-dev libgl-dev \
    libavcodec-dev libavformat-dev libavutil-dev libswscale-dev libx264-dev \
    libpipewire-0.3-dev libeigen3-dev libglib2.0-dev \
    libbsd-dev libdrm-dev libxrandr-dev libxcb1-dev libx11-dev
EOF
            ;;
        *)
            cat <<'EOF'
Install build deps for WiVRn: cmake, ninja, C/C++ toolchain, Vulkan headers,
FFmpeg/libx264, PipeWire, Eigen, GLib, libbsd, libdrm, X11/XCB/Xrandr dev.
EOF
            ;;
    esac
}

# --- vendored Ignition bytes ------------------------------------------------
# Kept for verification and offline reference. The port installer ships its own
# copy of the same pinned bytes, so we check ours match the expected hashes.
verify_vendor() {
    local sums="$REPO_DIR/vendor/SHA256SUMS"
    [ -f "$sums" ] || die "missing vendor/SHA256SUMS"
    require sha256sum
    say "verifying vendored Ignition bytes"
    ( cd "$REPO_DIR/vendor" && sha256sum -c SHA256SUMS ) || die "vendor checksum verification failed"
}

# --- Standable / Proton side (external installer) ---------------------------
# The port installer owns the Standable/Proton side and ships its own pinned
# Ignition bytes. We keep a copy in vendor/ for verification and offline
# reference, and verify it before trusting the port installer's output.
run_port_installer() {
    say "port installer: Standable + Proton prefix side"
    require git
    mkdir -p "$CACHE_DIR"
    local dst="$CACHE_DIR/port-installer"
    if [ -d "$dst/.git" ]; then
        git -C "$dst" fetch --depth 1 origin ${PORT_INSTALLER_REF:+"$PORT_INSTALLER_REF"} || true
        git -C "$dst" checkout --detach "${PORT_INSTALLER_REF:-FETCH_HEAD}"
    else
        git clone --depth 1 ${PORT_INSTALLER_REF:+--branch "$PORT_INSTALLER_REF"} \
            "$PORT_INSTALLER_REPO" "$dst"
    fi
    local script="" s
    for s in install.sh setup.sh install; do
        if [ -f "$dst/$s" ]; then script="$dst/$s"; break; fi
    done
    [ -n "$script" ] || die "no installer script found in $dst"
    chmod +x "$script"
    # -y assumes yes to package-install prompts; use --help on the port
    # installer directly if you need finer control.
    ( cd "$dst" && "./$(basename "$script")" -y )
}

# --- WiVRn installation -----------------------------------------------------
write_openxr_json() {
    run_root install -d "$OPENXR_DIR"
    run_root tee "$OPENXR_DIR/openxr_wivrn.json" >/dev/null <<EOF
{
    "file_format_version": "1.0.0",
    "runtime": {
        "name": "Monado",
        "library_path": "$WIVRN_LIBDIR/libopenxr_wivrn.so",
        "MND_libmonado_path": "$WIVRN_LIBDIR/libmonado_wivrn.so"
    }
}
EOF
}

# The Monado shared object is built with SONAME libmonado_wivrn.so.25, so the
# loader needs both the versioned name and the unversioned .so symlink.
install_monado_lib() {
    local src="$1"
    run_root install -d "$WIVRN_LIBDIR"
    run_root install -m 0644 "$src" "$WIVRN_LIBDIR/libmonado_wivrn.so.0.0.0"
    run_root ln -sf libmonado_wivrn.so.0.0.0 "$WIVRN_LIBDIR/libmonado_wivrn.so.25"
    run_root ln -sf libmonado_wivrn.so.0.0.0 "$WIVRN_LIBDIR/libmonado_wivrn.so"
}

install_prebuilt() {
    say "WiVRn: prebuilt artifacts from $REPO_RELEASE_BASE"
    require curl
    require sha256sum
    local tmp
    tmp="$(mktemp -d)"
    local f
    for f in libopenxr_wivrn.so libmonado_wivrn.so.0.0.0 wivrn-server SHA256SUMS; do
        if ! curl -fL --retry 3 -o "$tmp/$f" "$REPO_RELEASE_BASE/$f"; then
            rm -rf "$tmp"
            return 1
        fi
    done
    if ! ( cd "$tmp" && sha256sum -c SHA256SUMS ); then
        rm -rf "$tmp"
        return 1
    fi
    run_root install -d "$WIVRN_LIBDIR" "$WIVRN_BINDIR"
    run_root install -m 0644 "$tmp/libopenxr_wivrn.so" "$WIVRN_LIBDIR/libopenxr_wivrn.so"
    install_monado_lib "$tmp/libmonado_wivrn.so.0.0.0"
    run_root install -m 0755 "$tmp/wivrn-server" "$WIVRN_BINDIR/wivrn-server"
    write_openxr_json
    rm -rf "$tmp"
}

install_source() {
    say "WiVRn: building from source ($WIVRN_REPO @ $WIVRN_REF)"
    require git
    if ! command -v cmake >/dev/null 2>&1 || ! command -v ninja >/dev/null 2>&1; then
        print_build_deps
        die "cmake/ninja missing"
    fi
    local src="$CACHE_DIR/wivrn"
    if [ -d "$src/.git" ]; then
        git -C "$src" fetch --depth 1 origin "$WIVRN_REF"
        git -C "$src" checkout --detach FETCH_HEAD
    else
        git clone --depth 1 --branch "$WIVRN_REF" "$WIVRN_REPO" "$src"
    fi
    # The fork carries the steamvr_lh pose-feed patch and the HTCX tracker patch.
    # WiVRn fetches its pinned Monado via FetchContent; the fork's pinned-rev tree
    # already contains the steamvr_lh changes, so no patch application is needed.
    cmake -S "$src" -B "$src/build" -G Ninja \
        -DCMAKE_BUILD_TYPE=Release \
        -DCMAKE_INSTALL_PREFIX=/usr
    cmake --build "$src/build"
    # WiVRn's own install rules place the runtime manifest and libs in the
    # expected layout (/usr/lib/wivrn, /usr/share/openxr/1).
    run_root cmake --install "$src/build"
    # Ensure the runtime manifest points at the installed Monado lib.
    write_openxr_json
}

# --- systemd drop-in --------------------------------------------------------
# Runs on behalf of the invoking user: when this script runs as root (sudo), the
# drop-in must live in that user's config dir, owned by them, and systemctl must
# talk to their user bus.
install_reaper() {
    [ -f "$REAPER_SRC" ] || die "missing reaper: $REAPER_SRC"
    say "reaper: $REAPER_BIN"
    run_root install -d "$(dirname "$REAPER_BIN")"
    run_root install -m 0755 "$REAPER_SRC" "$REAPER_BIN"
}

install_dropin() {
    local dir="$XDG_CONFIG_HOME/systemd/user/wivrn.service.d"
    local f="$dir/standable.conf"
    say "systemd drop-in: $f"
    if [ "$(id -u)" -eq 0 ] && [ "$INVOKING_USER" != "root" ]; then
        runuser -u "$INVOKING_USER" -- mkdir -p "$dir"
    else
        mkdir -p "$dir"
    fi
    # Write once to a temp file, then place it through the invoking user so the
    # file is not root-owned.
    local tmp
    tmp="$(mktemp)"
    cat >"$tmp" <<'EOF'
[Service]
Environment=WIVRN_USE_STEAMVR_LH=1
Environment=LH_LOAD_STANDABLE=1
Environment=LH_LOAD_LIGHTHOUSE=0
Environment=LH_DISCOVER_WAIT_MS=30000
# Bypass Monado IPC git-tag check: server and client libs can come from
# different monado checkouts (partial rebuilds/redeploys). Remove after a full
# same-tree rebuild + redeploy of wivrn-server and both .so libs.
Environment=IPC_IGNORE_VERSION=1
# Best-effort shim cleanup on start; the timer handles mid-session orphans.
ExecStartPre=-/usr/local/bin/reap-ignition --quiet --kill
ExecStopPost=-/usr/local/bin/reap-ignition --quiet --kill
EOF
    if [ "$(id -u)" -eq 0 ] && [ "$INVOKING_USER" != "root" ]; then
        runuser -u "$INVOKING_USER" -- cp "$tmp" "$f"
    else
        cp "$tmp" "$f"
    fi
    rm -f "$tmp"
    # Periodic orphan sweeper: ignition_server.exe survives its host and piles
    # up across restarts (Ignition driver.cpp forks without reaping). The timer
    # keeps removing shims/wineservers that are not in the live wivrn-server
    # tree, without touching an active session.
    local tdir="$XDG_CONFIG_HOME/systemd/user"
    mkdir -p "$tdir"
    cat >"$tdir/wivrn-reap.service" <<'EOF'
[Unit]
Description=Reap orphaned Standable/Ignition shim processes

[Service]
Type=oneshot
ExecStart=/usr/local/bin/reap-ignition --quiet --kill
EOF
    cat >"$tdir/wivrn-reap.timer" <<'EOF'
[Unit]
Description=Periodically reap orphaned Standable/Ignition shims

[Timer]
OnBootSec=1min
OnUnitActiveSec=30s
AccuracySec=5s

[Install]
WantedBy=timers.target
EOF

    if command -v systemctl >/dev/null 2>&1; then
        user_systemctl daemon-reload || true
        user_systemctl enable --now wivrn-reap.timer || true
    fi
}

print_next_steps() {
    cat <<EOF

Done.

Next steps:
  1. vrswitch wivrn
  2. Launch VRChat with these launch options:
     PRESSURE_VESSEL_IMPORT_OPENXR_1_RUNTIMES=1 XRIZER_TRACKER_SERIALS="Hips;Chest;Elbow Left;Elbow Right;Knee Left;Knee Right;Foot Left;Foot Right" %command%

Logs: journalctl --user -u wivrn | grep "steamvr_lh driver"
EOF
}

# --- main -------------------------------------------------------------------
while [ $# -gt 0 ]; do
    case "$1" in
        --prebuilt) MODE="prebuilt" ;;
        --source) MODE="source" ;;
        --skip-port-installer) SKIP_PORT_INSTALLER=1 ;;
        -h|--help) usage; exit 0 ;;
        *) die "unknown argument: $1 (try --help)" ;;
    esac
    shift
done

say "repo: $REPO_DIR"
mkdir -p "$CACHE_DIR"

verify_vendor

if [ "$SKIP_PORT_INSTALLER" -eq 0 ]; then
    run_port_installer
else
    warn "skipping port installer; the Standable/Proton side must already be set up"
fi

if [ "$MODE" = "prebuilt" ]; then
    if ! install_prebuilt; then
        warn "prebuilt download failed; falling back to source build"
        install_source
    fi
else
    install_source
fi

install_reaper
install_dropin
print_next_steps
