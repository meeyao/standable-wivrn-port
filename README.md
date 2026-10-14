# Standable WiVRn Linux Port

Run the real Standable Full Body Estimation SteamVR driver under WiVRn on Linux.
No SteamVR. 8 proxy trackers in VRChat.

> # :warning: EXPERIMENTAL: UNDER ACTIVE DEVELOPMENT
>
> **THIS PORT WORKS BUT IS FRAGILE. Expect to re-run the installer or
> `vrswitch` after any SteamVR, WiVRn, Proton, VRChat or Standable update.**
>
> **Current status (Oct 2026):**
>
> - **Driver + estimation works.** The real Standable driver runs hosted,
>   manual in-driver T-pose calibration fires, 8 proxy trackers reach VRChat.
> - **Standable GUI launches** (Phase 2, in progress): window runs, VR backend
>   initializes. SteamVR-dashboard features have no equivalent under WiVRn.
> - **Known fragile:** the driver's Steam auth needs `steam_appid.txt`
>   (installer writes it; updates may wipe it — symptom: frozen slouched IK,
>   `Auth: 17777` in the wivrn log). Partial WiVRn upgrades break all VR
>   sessions (symptom: `ipc_client_check_git_tag` mismatch — reinstall).
> - The in-driver Standable GUI reports "SteamVR missing" if its VR backend
>   fails to init: check `game.log`, not the dialog.
>
> **USE AT YOUR OWN RISK. No support, no guarantees, may break your setup.**
>
> If you want a zero-fuss Standable setup today, use
> **[SteamVR Port](https://github.com/meeyao/standable-linux-port)** (SteamVR on
> Linux) or **SteamVR on Windows**. XD :stuck_out_tongue:

## Requirements

- WiVRn installed, or built by this installer
- Standable FBE owned on Steam
- VRChat (Steam)
- ~8 GB free disk (WiVRn build + Proton prefix)
- Arch/CachyOS or Debian/Ubuntu; other distros must provide WiVRn build deps

## Install

```sh
git clone https://github.com/meeyao/standable-wivrn-port
cd standable-wivrn-port
./install.sh
```

`install.sh` does three things:

1. Fetches the port installer (`meeyao/standable-linux-port`) into a cache dir and
   runs it. That handles the Standable/Proton side: Steam root, game library,
   Proton build, Standable install dir and its prefix, Windows-path emulation
   fixes (fake SteamVR `bin/win64` with `vrpathreg`/`vrmonitor` shims, `vrclient`
   DLLs, `SteamPath` registry, `S:` dosdevice, VRChat LocalLow symlink), and the
   Ignition shim + Standable driver hook.
2. Installs WiVRn (runtime + server) with the patches in this repo. Default is
   prebuilt artifacts from the latest release; `--source` builds the fork.
3. Writes the systemd user drop-in that enables `steamvr_lh` driver hosting.

Flags: `--prebuilt` (default), `--source`, `--skip-port-installer`, `--help`.
Env: `PORT_INSTALLER_REPO`, `PORT_INSTALLER_REF`, `WIVRN_REPO`, `WIVRN_REF`,
`REPO_RELEASE_BASE`.

## Run

```sh
vrswitch wivrn
```
Reconnect the headset, then launch VRChat with these launch options
(Steam -> VRChat Properties -> General):

```
IPC_IGNORE_VERSION=1 PRESSURE_VESSEL_IMPORT_OPENXR_1_RUNTIMES=1 XRIZER_TRACKER_SERIALS="Hips;Chest;Elbow Left;Elbow Right;Knee Left;Knee Right;Foot Left;Foot Right" %command%
```

## Uninstall

```sh
./uninstall.sh
```

## Notes / Known issues

- Calibrate in this order: in-driver T-pose first (sets height/floor), then
  VRChat avatar calibration. If proportions look wrong (straight legs when
  crouching), VRChat Avatar Measurement must be **Height**, not Arm Span,
  then recalibrate both.
- SteamVR owns the headset; WiVRn and SteamVR are mutually exclusive. `vrswitch`
  handles the handoff.

## How it works

See [docs/HOW-IT-WORKS.md](docs/HOW-IT-WORKS.md).

## Troubleshooting

See [docs/TROUBLESHOOTING.md](docs/TROUBLESHOOTING.md).
