# Architecture: shippable Standable-on-WiVRn stack

Goal: a package anyone can install that works every launch, maintained as a
**patch + verifier**, not a fork of the world.

## What broke, distilled (all observed, Oct 2026)

1. **Partial upgrades**: server from one build, client libs from another
   (paru stock 26.9 vs fork build) → IPC tag check fails → no sessions.
2. **Supervision tied to transient parents**: shell helpers die with whoever
   spawned them; stale lock files block legitimate respawns.
3. **GUI launch kills driver**: prefix/wineserver contention, mechanism open.
4. **Auth gate**: driver needs Steam AppID context or estimator never runs.
5. **Safe-mode latch**: SteamVR remembers crashes forever; UI clears nothing.
6. **Orphan pile-ups**: shim forks without reaping; strays fight over devices.

## Principles

1. **Verify behavior, not versions.** Pinning everything makes us the sole
   maintainer of a frozen world (and we get mugged by every upstream update).
   The installer and the launcher assert *observable contracts*
   (auth code == 1, estimator ticking, session creatable) and repair, rather
   than demanding exact package versions.
2. **Atomic artifact sets.** The three WiVRn binaries
   (`wivrn-server`, `libopenxr_wivrn.so`, `libmonado_wivrn.so`) are ONE unit
   with one recorded build id. The doctor refuses a mixed set loudly instead
   of failing weirdly at runtime. Never deploy one without the other two.
3. **systemd supervises, scripts don't.** Shell supervisors with PID lock
   files are banned for anything that must outlive a command. One
   `wivrn-standable.service` (bound to `wivrn.service`), systemd restarts it,
   systemd is the single-instance guard. Delete the lock mechanism.
4. **Upstream first.** Our delta must shrink to: one monado patch
   (steamvr_lh feeder), one launcher, one doctor, one test. Everything else
   rides upstream releases. If a component can be deleted by an upstream
   feature, file the issue and track it.
5. **Serialize prefix access.** One writer at a time for the Proton prefix
   (flock around boot/mutation paths). Concurrent boots are the #1 killer.

## Components to build

| # | Piece | What it is |
|---|---|---|
| 1 | **patch-pack CI** | CI applies our monado patch to each upstream WiVRn tag, builds, publishes the atomic triple. No standing fork to rebase by hand; a red CI job names the exact upstream change that broke us. |
| 2 | **`vrselftest`** | Headless contract test, one command, RED/GREEN per link: runtime resolvable → instance creatable → session creatable → feed ticking → shim spawned → auth == 1 → estimator ticking → 8 trackers enumerated. Users paste this output instead of "it doesn't work". |
| 3 | **doctor / reconcile** | `vrswitch` grows `doctor`: runs vrselftest, repairs what it can in dependency order (stale lock → mixed set → dead server → auth context → safe-mode latch), reports what it can't with the exact failed link. Runs on every switch and on a timer while in VR. |
| 4 | **systemd supervision** | Replace `launch_serverhelper` respawn loops for the *steady state* with a user service bound to the session. Keep the helper for boot-time prefix surgery only. |
| 5 | **GUI coexistence gate** | Until the GUI-kills-driver mechanism is proven, the launcher refuses concurrent GUI+driver boot (or orders them: driver healthy first, GUI joins). A failing gate prints why. |

## Explicitly NOT ours to maintain

- WiVRn/Monado themselves (upstream releases + our patch file).
- Proton's vrclient/OpenXR bridge (ships with Proton; we only copy + verify).
- Ignition upstream (we vendor + keep one lifetime patch; push it upstream).
- Steam, VRChat, Standable binaries (we integrate, never patch).

## Migration from today

1. `vrselftest` first (makes every later step verifiable).
2. Atomic-set check inside `doctor` (md5 triple vs recorded build id).
3. Move respawn supervision into a user service; delete lock files.
4. Patch-pack CI; archive the standing fork once CI is green.
5. Root-cause the GUI/driver kill with vrselftest running during GUI boot.

## Anti-mugging clause

If maintaining any row above requires tracking upstream internals
release-to-release (not just our patch + behavior contracts), that row gets
cut or upstreamed. A package we can't ignore for 3 months is a package we
shouldn't ship.
