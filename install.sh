#!/usr/bin/env bash
# Standable WiVRn Linux Port installer.
#
# Runs the vendored port installer (Standable + Proton prefix side), then builds
# upstream WiVRn + the Standable patch series and installs the systemd user
# drop-in that enables steamvr_lh driver hosting. Idempotent.
set -euo pipefail

REPO_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck disable=SC1091
. "$REPO_DIR/tools/lib.sh"

# --- overridable configuration ---------------------------------------------
PORT_INSTALLER_DIR="$REPO_DIR/port"   # vendored Standable/Proton installer
# Upstream WiVRn + our patch series (patches/wivrn, patches/monado). The pinned
# ref lives in wivrn-rev; overriding WIVRN_REF is for testing new upstream tags.
WIVRN_REPO="${WIVRN_REPO:-https://github.com/WiVRn/WiVRn}"
WIVRN_REF="${WIVRN_REF:-$(cat "$REPO_DIR/wivrn-rev" 2>/dev/null || echo master)}"

XDG_CONFIG_HOME="${XDG_CONFIG_HOME:-$INVOKING_HOME/.config}"
XDG_DATA_HOME="${XDG_DATA_HOME:-$INVOKING_HOME/.local/share}"
XDG_CACHE_HOME="${XDG_CACHE_HOME:-$INVOKING_HOME/.cache}"
CACHE_DIR="$XDG_CACHE_HOME/standable-wivrn-port"

WIVRN_LIBDIR="/usr/lib/wivrn"
WIVRN_BINDIR="/usr/bin"
OPENXR_DIR="/usr/share/openxr/1"
REAPER_SRC="$REPO_DIR/tools/reap-ignition.sh"
REAPER_BIN="/usr/local/bin/reap-ignition"

SKIP_PORT_INSTALLER=0

# --- output helpers ---------------------------------------------------------
usage() {
    cat <<'EOF'
Usage: install.sh [options]

  --skip-port-installer   do not run the vendored Standable/Proton installer
  -h, --help              show this help

Environment:
  WIVRN_REPO              default https://github.com/WiVRn/WiVRn (upstream)
  WIVRN_REF               default: the pinned tag in ./wivrn-rev
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
        *" fedora "*|*" rhel "*|*" centos "*) echo fedora ;;
        *) echo unknown ;;
    esac
}

print_build_deps() {
    case "$(detect_distro)" in
        arch)
            cat <<'EOF'
WiVRn build deps (Arch/CachyOS):
  sudo pacman -S --needed base-devel cmake ninja git \
    vulkan-headers vulkan-icd-loader glslang spirv-tools libglvnd \
    ffmpeg libx264 pipewire eigen glib2 glib2-devel \
    nlohmann-json cli11 boost avahi \
    libbsd libdrm libxrandr libxcb libx11 wayland wayland-protocols openvr
EOF
            ;;
        debian)
            cat <<'EOF'
WiVRn build deps (Debian/Ubuntu):
  sudo apt install build-essential cmake ninja-build git \
    libvulkan-dev glslang-tools spirv-tools libgl-dev \
    libavcodec-dev libavformat-dev libavutil-dev libswscale-dev libx264-dev \
    libpipewire-0.3-dev libeigen3-dev libglib2.0-dev libglib2.0-dev-bin \
    nlohmann-json3-dev libcli11-dev libboost-all-dev \
    libavahi-client-dev libavahi-glib-dev libwayland-dev \
    libbsd-dev libdrm-dev libxrandr-dev libxcb1-dev libx11-dev libopenvr-api1
EOF
            ;;
        fedora)
            cat <<'EOF'
WiVRn build deps (Fedora):
  sudo dnf install gcc-c++ make cmake ninja-build git \
    vulkan-loader-devel vulkan-headers glslang spirv-tools libglvnd-devel \
    libavcodec-free-devel libavutil-free-devel libdrm-devel \
    pipewire-devel eigen3-devel glib2-devel json-devel cli11-devel boost-devel \
    avahi-devel libnotify-devel librsvg2-devel libarchive-devel libpng-devel \
    systemd-devel libXrandr-devel libxcb-devel libX11-devel wayland-devel \
    wayland-protocols-devel openxr-devel openvr-devel libbsd-devel python3

x264-devel comes from RPM Fusion:
  sudo dnf install x264-devel
EOF
            ;;
        *)
            cat <<'EOF'
Install build deps for WiVRn: cmake, ninja, a C/C++ toolchain, Vulkan headers,
glslang/spirv-tools, FFmpeg/libx264, PipeWire, Eigen, GLib (including
gdbus-codegen), nlohmann-json, CLI11, Boost, Avahi, libbsd, libdrm,
X11/XCB/Xrandr, Wayland, and the OpenVR API library (libopenvr_api.so).
EOF
            ;;
    esac
}

# --- vendored Ignition bytes ------------------------------------------------
# Kept for verification and offline reference. port/vendor ships its own copy
# of the same pinned bytes, so we check ours match the expected hashes.
verify_vendor() {
    local sums="$REPO_DIR/vendor/SHA256SUMS"
    [ -f "$sums" ] || die "missing vendor/SHA256SUMS"
    require sha256sum
    say "verifying vendored Ignition bytes"
    ( cd "$REPO_DIR/vendor" && sha256sum -c SHA256SUMS ) || die "vendor checksum verification failed"
}

# --- Standable / Proton side (vendored installer) ---------------------------
# port/ is a self-contained copy of the Standable/Proton installer, so this repo
# does not depend on another repo at install time. See port/UPSTREAM for the
# commit it was taken from.
run_port_installer() {
    say "port installer: Standable + Proton prefix side"
    local script=""
    local s
    for s in install.sh setup.sh install; do
        if [ -f "$PORT_INSTALLER_DIR/$s" ]; then script="$PORT_INSTALLER_DIR/$s"; break; fi
    done
    [ -n "$script" ] || die "no installer script found in $PORT_INSTALLER_DIR"
    chmod +x "$script"
    # -y assumes yes to package-install prompts; use --help on the port
    # installer directly if you need finer control.
    ( cd "$PORT_INSTALLER_DIR" && "./$(basename "$script")" -y )
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
install_source() {
    say "WiVRn: building upstream $WIVRN_REPO @ $WIVRN_REF + Standable patch series"
    require git
    if ! command -v cmake >/dev/null 2>&1 || ! command -v ninja >/dev/null 2>&1; then
        print_build_deps
        die "cmake/ninja missing"
    fi
    check_wivrn_runtime_deps
    local src="$CACHE_DIR/wivrn"
    if [ -d "$src/.git" ]; then
        git -C "$src" fetch --depth 1 origin "$WIVRN_REF"
        git -C "$src" checkout --detach FETCH_HEAD
    else
        git clone --depth 1 --branch "$WIVRN_REF" "$WIVRN_REPO" "$src"
        git -C "$src" checkout --detach FETCH_HEAD 2>/dev/null || true
    fi
    # Deterministic re-runs: drop any previously applied series before reapplying.
    git -C "$src" reset --hard >/dev/null
    git -C "$src" clean -fd >/dev/null

    # WiVRn-tree changes (server/driver proxies + session wiring) apply directly.
    local p
    for p in "$REPO_DIR"/patches/wivrn/*.patch; do
        say "applying $(basename "$p")"
        git -C "$src" apply --index "$p" || die "failed to apply $(basename "$p") to $WIVRN_REF"
    done
    # Monado changes ride WiVRn's own FetchContent patch step: drop them in the
    # tree's patches/monado/ so apply.sh picks them up alongside upstream's.
    say "installing Monado patch series (applied by WiVRn FetchContent)"
    cp -f "$REPO_DIR"/patches/monado/*.patch "$src/patches/monado/"
    cmake -S "$src" -B "$src/build" -G Ninja \
        -DCMAKE_BUILD_TYPE=Release \
        -DCMAKE_INSTALL_PREFIX=/usr
    cmake --build "$src/build"
    # WiVRn's install rules place the server, libs, unit file and manifest in the
    # expected layout (/usr/bin, /usr/lib/wivrn, /usr/lib/systemd/user, /usr/share/openxr/1).
    run_root cmake --install "$src/build"
    # Ensure the runtime manifest points at the installed Monado lib.
    write_openxr_json
}

# wivrn-server links libopenvr_api.so (Arch: openvr), a build and runtime
# dependency of WiVRn. Without it, Monado's find_library() disables OpenVR
# support, which removes the steamvr_lh host this port relies on.
check_wivrn_runtime_deps() {
    # NB: do not pipe ldconfig into `grep -q`: under `set -o pipefail` grep exits
    # on the first match and ldconfig dies of SIGPIPE, so the pipeline reports
    # failure even when the library is present.
    local libs=""
    if command -v ldconfig >/dev/null 2>&1; then
        libs="$(ldconfig -p 2>/dev/null || true)"
    fi
    case "$libs" in
        *libopenvr_api.so*) return 0 ;;
    esac
    local d
    for d in /usr/lib /usr/lib64 /usr/local/lib /usr/local/lib64; do
        [ -e "$d/libopenvr_api.so" ] && return 0
    done
    print_build_deps
    die "libopenvr_api.so not found; install the OpenVR API library and re-run"
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
# Launch the Standable GUI from the driver helper so it joins the driver's
# wineserver (sockets/discovery are unreliable under Proton). The SteamVR port
# leaves this unset.
Environment=STANDABLE_GUI=1
# Bypass Monado IPC git-tag check: server and client libs can come from
# different monado checkouts (partial rebuilds/redeploys). Remove after a full
# same-tree rebuild + redeploy of wivrn-server and both .so libs.
Environment=IPC_IGNORE_VERSION=1
# Best-effort shim cleanup on start; the timer handles mid-session orphans.
# reap-ignition now protects the live host tree in BOTH modes (a running
# wivrn-server, or vrserver/vrmonitor under SteamVR), so it is safe to run.
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
        # reap-ignition protects the live host tree in both modes now, so the
        # periodic sweeper is safe to enable.
        user_systemctl enable --now wivrn-reap.timer >/dev/null 2>&1 || true
        say "wivrn-reap.timer installed and enabled"
    fi
}

print_next_steps() {
    cat <<EOF

Done.

VRChat launch options (Steam -> Properties -> General), exact:
  IPC_IGNORE_VERSION=1 PRESSURE_VESSEL_IMPORT_OPENXR_1_RUNTIMES=1 XRIZER_TRACKER_SERIALS="Hips;Chest;Elbow Left;Elbow Right;Knee Left;Knee Right;Foot Left;Foot Right" %command%

Next steps:
  1. vrswitch wivrn
  2. Reconnect the headset, launch VRChat with the options above.

Logs: journalctl --user -u wivrn | grep "steamvr_lh driver"
Status: vrswitch status
EOF
}

install_user_env() {
    # Manager-level env for apps the server spawns as transient units
    # (WayVR dashboard): the IPC tag bypass must be in the user manager env,
    # service drop-ins do not propagate to spawned units.
    local d="$XDG_CONFIG_HOME/environment.d"
    local f="$d/wivrn-ipc.conf"
    mkdir -p "$d"
    cat >"$f" <<'EOF'
# Bypass Monado IPC git-tag check (server/libs may come from different
# checkouts after partial rebuilds). Remove after a full same-tree rebuild.
IPC_IGNORE_VERSION=1
EOF
    say "user env: $f"
    if command -v systemctl >/dev/null 2>&1; then
        user_systemctl set-environment IPC_IGNORE_VERSION=1 || true
    fi
}

install_vrswitch() {
    # Always sync: a stale ~/.local/bin copy silently drops fixes.
    local dst="$INVOKING_HOME/.local/bin/vrswitch"
    mkdir -p "$(dirname "$dst")"
    cp -f "$REPO_DIR/tools/vrswitch" "$dst"
    chmod +x "$dst"
    say "vrswitch: $dst"
    case ":$PATH:" in
        *":$INVOKING_HOME/.local/bin:"*) ;;
        *) warn "$INVOKING_HOME/.local/bin is not on PATH; add it or run $dst directly" ;;
    esac
}

ensure_steam_appid() {
    # The Standable driver's Steam ownership check fails (Auth: 17777,
    # estimator never runs, IK frozen) without AppID context: no GUI running,
    # no steam_appid.txt. Drop the file next to the server exe.
    local exe
    exe="$(find "$XDG_DATA_HOME/Steam/steamapps/common/Standable Full Body Estimation/bin/linux64" \
        -maxdepth 1 -name ignition_server.exe -print -quit 2>/dev/null)"
    if [ -z "$exe" ]; then
        warn "ignition_server.exe not found; skipping steam_appid.txt (port installer must run first)"
        return 0
    fi
    printf '2370570' >"$(dirname "$exe")/steam_appid.txt"
    say "steam_appid.txt: $(dirname "$exe")/steam_appid.txt"
}

check_vrchat_launch_options() {
    # Steam owns localconfig.vdf and rewrites it; never edit while Steam runs.
    # Verify and print the exact string instead.
    local want='IPC_IGNORE_VERSION=1 PRESSURE_VESSEL_IMPORT_OPENXR_1_RUNTIMES=1 XRIZER_TRACKER_SERIALS="Hips;Chest;Elbow Left;Elbow Right;Knee Left;Knee Right;Foot Left;Foot Right" %command%'
    local f
    f="$(find "$XDG_DATA_HOME/Steam/userdata" -path "*/config/localconfig.vdf" -print -quit 2>/dev/null)"
    if [ -z "$f" ]; then
        warn "localconfig.vdf not found; set VRChat launch options manually:"
        say "  $want"
        return 0
    fi
    if grep -qF "$want" "$f" 2>/dev/null; then
        say "VRChat launch options: OK"
    else
        warn "VRChat launch options mismatch. Set in Steam -> VRChat Properties -> General:"
        say "  $want"
    fi
}

# Read KEY="value" or export KEY="value" from a file, first match. Avoids
# `sed | head`, which trips `set -o pipefail` on SIGPIPE.
hookval() {
    local key="$1" file="$2" line
    while IFS= read -r line; do
        case "$line" in
            "$key"=*|export\ "$key"=*)
                line="${line#*=}"
                line="${line#\"}"
                line="${line%\"}"
                printf '%s' "$line"
                return 0
                ;;
        esac
    done <"$file"
}

install_gui_launcher() {
    # Desktop launcher for the Standable settings window under WiVRn. It reuses
    # the paths the port installer baked into the launch hook (same prefix,
    # Proton and game dir) so the two cannot drift.
    local hook="$INVOKING_HOME/.local/bin/standable_launch_hook.sh"
    if [ ! -f "$hook" ]; then
        warn "launch hook not found; skipping the Standable GUI launcher"
        return 0
    fi
    local gd compat client proton appid
    gd="$(hookval GAME_DIR "$hook")"
    compat="$(hookval STEAM_COMPAT_DATA_PATH "$hook")"
    client="$(hookval STEAM_COMPAT_CLIENT_INSTALL_PATH "$hook")"
    proton="$(hookval PROTON "$hook")"
    appid="$(hookval SteamAppId "$hook")"
    if [ -z "$gd" ] || [ -z "$compat" ] || [ -z "$proton" ] || [ -z "$appid" ]; then
        warn "could not read paths from $hook; skipping the Standable GUI launcher"
        return 0
    fi
    local confdir="$XDG_CONFIG_HOME/standable-wivrn"
    mkdir -p "$confdir" "$INVOKING_HOME/.local/bin" "$INVOKING_HOME/.local/share/applications"
    cat >"$confdir/paths.conf" <<EOF
GAME_DIR='$gd'
STEAM_COMPAT_DATA_PATH='$compat'
STEAM_COMPAT_CLIENT_INSTALL_PATH='$client'
PROTON='$proton'
APP_ID='$appid'
# Optional: a directory holding an OpenComposite/xrizer vrclient_x64.dll for the
# in-VR dashboard. Empty means desktop window only.
BRIDGE_DIR=''
EOF
    install -m 0755 "$REPO_DIR/tools/standable-gui-wivrn.sh" "$INVOKING_HOME/.local/bin/standable-gui-wivrn"
    cat >"$INVOKING_HOME/.local/share/applications/standable-gui-wivrn.desktop" <<EOF
[Desktop Entry]
Type=Application
Name=Standable GUI (WiVRn)
Comment=Open the Standable settings window while WiVRn hosts the driver
Exec=$INVOKING_HOME/.local/bin/standable-gui-wivrn
Terminal=false
Categories=Utility;
EOF
    say "GUI launcher: $INVOKING_HOME/.local/bin/standable-gui-wivrn"
}

# --- main -------------------------------------------------------------------
while [ $# -gt 0 ]; do
    case "$1" in
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

install_source

install_reaper
install_dropin
install_user_env
install_vrswitch
install_gui_launcher
ensure_steam_appid
check_vrchat_launch_options
print_next_steps
