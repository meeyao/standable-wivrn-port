#!/usr/bin/env bash
# reap-ignition.sh - kill orphaned Standable/Ignition shim processes.
#
# Background: Ignition's driver.cpp (HmdDriverFactory) fork()s
# `wine ignition_server.exe` and never reaps it nor ties its lifetime to the
# host runtime. Every WiVRn restart, crash, or missed disconnect can therefore
# leave a stale shim (and its Proton wineserver) running. A pile-up of these
# fights over the pose feed and makes Standable see only the HMD.
#
# This script removes ONLY processes that are not descendants of a live,
# running wivrn-server. If wivrn-server is not running at all, every ignition
# shim/wineserver is an orphan and is removed. The live session tree is never
# touched, so it is safe to run while connected.
#
# It additionally reaps stale Wine/Proton service helpers (wineboot, services,
# winedevice, plugplay, rpcss, explorer) that were reparented to init after
# their Steam launch chain died. A hung `wineboot --init` on a wedged prefix
# makes the next game launch sit at iscriptevaluator forever; these are only
# killed when their ancestor chain no longer reaches a live Steam/launcher
# process, so an initializing game is never disturbed.
#
# Usage:
#   reap-ignition.sh            # report what would be killed, change nothing
#   reap-ignition.sh --kill     # actually kill the orphans
#   reap-ignition.sh --quiet --kill   # for systemd timers
set -euo pipefail

KILL=0
QUIET=0
for a in "$@"; do
  case "$a" in
    --kill|-k)   KILL=1 ;;
    --quiet|-q)  QUIET=1 ;;
    -h|--help)
      sed -n '2,21p' "$0" | sed 's/^# \{0,1\}//'
      exit 0 ;;
    *) echo "usage: $0 [--kill] [--quiet]" >&2; exit 2 ;;
  esac
done

log() { [ "$QUIET" -eq 1 ] || printf '%s\n' "$*"; }

# Cheap first: during a SteamVR session this timer must do nothing at all.
# The full scan below costs >1s of CPU and can make SteamVR's 5s compositor
# startup time out, leaving the "SteamVR has exited" window.
for _c in /proc/[0-9]*/comm; do
  if [ "$(cat "$_c" 2>/dev/null)" = "vrserver" ]; then
    log "reap-ignition: SteamVR is live - leaving the Standable tree alone"
    exit 0
  fi
done

# Single-pass awk over /proc/*/status is ~100x cheaper than a bash loop with a
# sed+awk per process (986 procs: 0.04s vs 4.7s).
scan_procs() {
  awk '
    FNR == 1 { pid = FILENAME; sub(/\/status$/, "", pid); sub(/^.*\//, "", pid) }
    /^PPid:/ { print pid, $2 }
  ' /proc/[0-9]*/status 2>/dev/null
}

# pid -> ppid for every process
declare -A PPID_OF=()
while read -r pid ppid; do
  [ -n "${pid:-}" ] && PPID_OF[$pid]="$ppid"
done < <(scan_procs)

# cmdline for candidate processes only (ignition / wineserver / wivrn-server).
# /proc/*/comm is a cheap pre-filter (one read, no fork); only matching pids get
# their (fork-heavy) cmdline read. /proc/*/cmdline is NUL-separated.
declare -A CMD_OF=()
# Wine/Proton helper names whose processes leak when a launch chain dies. These
# are the "service" processes each prefix starts alongside a game.
declare -A WINE_HELPER=()
cand="$(awk '
  FNR == 1 { pid = FILENAME; sub(/\/comm$/, "", pid); sub(/^.*\//, "", pid) }
  /^(ignition_server|wineserver|wivrn-server)/ { print pid }
' /proc/[0-9]*/comm 2>/dev/null)" || true
wine_cand="$(awk '
  FNR == 1 { pid = FILENAME; sub(/\/comm$/, "", pid); sub(/^.*\//, "", pid) }
  /^(wineboot|services|winedevice|plugplay|rpcss|explorer|svchost|conhost)(\.exe)?$/ { print pid }
' /proc/[0-9]*/comm 2>/dev/null)" || true
for pid in $cand; do
  cmd="$( { tr '\0' ' ' < "/proc/$pid/cmdline"; } 2>/dev/null )" || continue
  case "$cmd" in
    *ignition_server*|*wineserver*|*/wivrn-server*) CMD_OF[$pid]="$cmd" ;;
  esac
done

# Wine's start.exe wrapper carries the driver in argv but not in comm, and can
# outlive the helper. Only this wrapper is matched - never bash, which would
# also catch unrelated user commands.
wrapper_cand="$(awk '
  FNR == 1 { pid = FILENAME; sub(/\/comm$/, "", pid); sub(/^.*\//, "", pid) }
  /^start\.exe$/ { print pid }
' /proc/[0-9]*/comm 2>/dev/null)" || true
for pid in $wrapper_cand; do
  cmd="$( { tr '\0' ' ' < "/proc/$pid/cmdline"; } 2>/dev/null )" || continue
  case "$cmd" in
    *start.exe*ignition_server*) CMD_OF[$pid]="$cmd" ;;
  esac
done
# Wine helpers: capture comm + WINEPREFIX so we can group by prefix.
declare -A WINE_PREFIX=()
for pid in $wine_cand; do
  [ -n "${PPID_OF[$pid]:-}" ] || continue
  comm="$(cat "/proc/$pid/comm" 2>/dev/null)" || continue
  case "$comm" in
    wineboot*|services*|winedevice*|plugplay*|rpcss*|explorer*|svchost*|conhost*)
      WINE_HELPER[$pid]="$comm"
      pre="$( { tr '\0' '\n' < "/proc/$pid/environ"; } 2>/dev/null | grep -m1 '^STEAM_COMPAT_DATA_PATH=' | cut -d= -f2- )" || pre=""
      WINE_PREFIX[$pid]="${pre:-unknown}"
      ;;
  esac
done

# --- never touch ourselves or our own ancestry ------------------------------
declare -A SELF=()
sp=$$
while [ -n "$sp" ] && [ "$sp" != "0" ] && [ "$sp" != "1" ]; do
  SELF[$sp]=1
  sp="${PPID_OF[$sp]:-}"
done

# --- collect the live tree: each wivrn-server and all its descendants -------
declare -A LIVE=()
wivrn_count=0
mark_descendants() {
  local root="$1" changed=1 pid pp
  LIVE[$root]=1
  while [ "$changed" -eq 1 ]; do
    changed=0
    for pid in "${!PPID_OF[@]}"; do
      [ -n "${LIVE[$pid]+x}" ] && continue
      pp="${PPID_OF[$pid]}"
      if [ -n "${LIVE[$pp]+x}" ]; then
        LIVE[$pid]=1
        changed=1
      fi
    done
  done
}
for pid in "${!CMD_OF[@]}"; do
  case "${CMD_OF[$pid]}" in
    /usr/bin/wivrn-server*|*/wivrn-server\ *|*/wivrn-server)
      wivrn_count=$((wivrn_count + 1))
      mark_descendants "$pid" ;;
  esac
done

# SteamVR owns the Standable driver whenever vrserver is live. Its helper tree
# is parented to the Steam client, not to vrserver, so descendant protection
# does not cover it: reaping here kills the live driver and wedges SteamVR's
# quit (watchdog timeout -> "crashed" state on the next launch). Leave the
# whole tree alone for the duration of a SteamVR session.

log "reap-ignition: ${wivrn_count} live wivrn-server, ${#LIVE[@]} protected pids"

# --- is a pid still attached to a live Steam launch? ------------------------
# Walk the ancestor chain: if we reach a process whose comm is steam/reaper/
# pressures-vessel etc., the launch is alive and its Wine tree must be left
# alone. If we hit init/systemd (pid 1) first, the launch chain is gone and the
# process is a reparented orphan (the hung-wineboot / stale-winedevice case).
attached_to_launcher() {
  local pid="$1" hops=0 pp comm
  while [ -n "$pid" ] && [ "$pid" != "0" ] && [ "$pid" != "1" ] && [ "$hops" -lt 40 ]; do
    pp="${PPID_OF[$pid]:-}"
    [ -z "$pp" ] && return 1
    comm="$(cat "/proc/$pp/comm" 2>/dev/null)"
    case "$comm" in
      steam|steam.sh|reaper|srt-bwrap|pv-adverb|pv-runtime|pressure-vessel*|python3|wine|wine64|wineserver)
        return 0 ;;
    esac
    pid="$pp"; hops=$((hops + 1))
  done
  return 1
}

# --- find candidate orphan processes ----------------------------------------
declare -A ORPHANS=()
for pid in "${!CMD_OF[@]}"; do
  case "${CMD_OF[$pid]}" in
    *ignition_server*|*wineserver*) ;;
    *) continue ;;
  esac
  [ -n "${SELF[$pid]+x}" ] && continue
  [ -n "${LIVE[$pid]+x}" ] && continue
  ORPHANS[$pid]="${CMD_OF[$pid]}"
done

# Wine service helpers are only reaped when detached from any live launcher, so
# a game that is merely initializing its prefix (wineboot still running under
# Steam) is never touched.
for pid in "${!WINE_HELPER[@]}"; do
  [ -n "${SELF[$pid]+x}" ] && continue
  [ -n "${LIVE[$pid]+x}" ] && continue
  if attached_to_launcher "$pid"; then
    continue
  fi
  ORPHANS[$pid]="${WINE_HELPER[$pid]} (prefix ${WINE_PREFIX[$pid]})"
done

if [ "${#ORPHANS[@]}" -eq 0 ]; then
  log "reap-ignition: no orphaned ignition/wine processes"
  exit 0
fi

log "reap-ignition: ${#ORPHANS[@]} orphaned process(es):"
for pid in "${!ORPHANS[@]}"; do
  log "  $pid  ${ORPHANS[$pid]}"
  if [ "$KILL" -eq 1 ]; then
    kill -9 "$pid" 2>/dev/null || true
  fi
done

if [ "$KILL" -eq 1 ]; then
  log "reap-ignition: killed ${#ORPHANS[@]} orphaned process(es)"
else
  log "reap-ignition: dry run (pass --kill to remove)"
fi
