# Standable WiVRn Linux Port

Run the real Standable Full Body Estimation SteamVR driver under WiVRn on Linux.
No SteamVR. 8 proxy trackers in VRChat.

> # :warning: EXPERIMENTAL: BROKEN / INCOMPLETE STATE
>
> **THIS IS AN EXPERIMENTAL, PARTIALLY BROKEN PORT. IT IS NOT READY FOR
> NORMAL USE.**
>
> **Known to be broken or missing right now:**
>
> - **Manual in-driver T-pose calibration does not fire.** The driver's own
>   calibration gesture never completes under WiVRn.
> - **Body proportions/IK are wrong.** The driver runs at a default 105 cm
>   height until a calibration completes, so arms/legs/spine are scaled wrong
>   (elbows off, hips/spine inverted).
> - **Only the VRChat auto-calibration (OSC) path works**, and only roughly
>   (~70% accuracy observed).
> - **The in-driver Standable GUI reports "SteamVR missing"**: expected; ignore
>   it. The GUI is not required.
> - Expect breakage on any SteamVR, WiVRn, Proton, VRChat or Standable update.
>   Nothing here is stable.
>
> **USE AT YOUR OWN RISK. No support, no guarantees, may break your setup.**
>
> If you want a working Standable setup today, use
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

Launch VRChat with these launch options:

```
PRESSURE_VESSEL_IMPORT_OPENXR_1_RUNTIMES=1 XRIZER_TRACKER_SERIALS="Hips;Chest;Elbow Left;Elbow Right;Knee Left;Knee Right;Foot Left;Foot Right" %command%
```

## Uninstall

```sh
./uninstall.sh
```

## Notes / Known issues

- Manual in-driver T-pose calibration does not fire under WiVRn yet; use VRChat
  auto-calibration (OSC) mode. Trackers reach VRChat and estimation works.
- SteamVR owns the headset; WiVRn and SteamVR are mutually exclusive. `vrswitch`
  handles the handoff.

## How it works

See [docs/HOW-IT-WORKS.md](docs/HOW-IT-WORKS.md).

## Troubleshooting

See [docs/TROUBLESHOOTING.md](docs/TROUBLESHOOTING.md).
