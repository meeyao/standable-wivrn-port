# Standable WiVRn Linux Port

Run the real Standable Full Body Estimation SteamVR driver on Linux with WiVRn, without running SteamVR. Adds 8 proxy trackers to VRChat.

> **Experimental. Expect breakage.**
>
> The driver and body estimation work, including the in-driver T-pose calibration and all 8 trackers in VRChat. The settings GUI runs; some SteamVR-only features are missing.
>
> Steam, Proton, VRChat, Standable, or WiVRn updates can break the setup. Rerun the installer or switch runtimes if that happens.
>
> Tested on real hardware, but not widely. It will break sometimes and need troubleshooting. Treat it as a research project, not a supported product.
>
> **Want a less experimental setup?** Try the [SteamVR Linux port](https://github.com/meeyao/standable-linux-port) or run SteamVR on Windows.

## Requirements

- Linux with the dependencies needed to build WiVRn (the installer builds it from source)
- SteamVR installed in Steam. It is not run; the installer uses its paths to place compatibility shims.
- Standable FBE on Steam
- VRChat on Steam
- Around 8 GB of free disk space
- Arch/CachyOS or Fedora. Ubuntu 25.10+ also has the required packages but is untested. Ubuntu 24.04 and Debian 13 cannot build this: their Vulkan headers are older than 1.4.304 and/or they have no OpenVR package. The installer prints the dependency command for your distro.
- `libopenvr_api.so` (the `openvr` package on Arch, `openvr-devel` on Fedora, `libopenvr-dev` on Ubuntu 25.10+, in `universe`). WiVRn links it, so the build and the runtime both need it. The installer checks for it.
- xrizer, the OpenVR -> OpenXR runtime VRChat uses. The installer installs it when missing: Fedora uses the `@xr-sig/xrizer` COPR, otherwise the pinned upstream release.
- WayVR (optional, recommended), used to center the playspace and set the floor height. Install it yourself (AUR, AppImage, or your distro); the installer only warns if it is missing. Without it, Standable falls back to 105 cm.

## Install

```sh
git clone https://github.com/meeyao/standable-wivrn-port
cd standable-wivrn-port
./install.sh
```

The installer:

1. Sets up the Standable and Proton side for the older Ignition path (Steam root, Proton prefix, Windows-path shims, the shim itself, and the driver hook). If the official v3.1 native driver is present, the installer skips this step and leaves it untouched.
2. Builds upstream WiVRn at the tag in `wivrn-rev`, applying the patch series in `patches/`, and installs it (server, runtime libraries, and systemd unit).
3. Installs xrizer if no runtime is found (Fedora: `@xr-sig/xrizer` COPR; fallback: pinned release in `/opt/xrizer`).
4. Installs the reaper binary and writes the systemd user drop-in that enables the `steamvr_lh` driver host.
5. Warns if WayVR is missing (optional floor-height helper).

By default only the core is installed. Optional components are off by default; select them in the checklist, or skip the checklist with `--yes`.

- standalone Standable GUI launcher (required on the v3.1 native driver; the older shim helper starts its own)
- background orphan timer (start/stop cleanup is always installed)

The build takes a few minutes.

Options:

- `--yes`: use the default (core) components without the checklist
- `--install-deps`: install the WiVRn build dependencies for Arch/Fedora/Debian (uses `sudo`)
- `--skip-port-installer`, `--skip-wivrn`, `--skip-xrizer`, `--skip-gui`, `--skip-reaper`: skip one component
- `--help`: show installer options

Environment: `WIVRN_REPO`, `WIVRN_REF`.

The Standable/Proton installer is vendored in `installer/`, so this repo installs
without cloning the SteamVR port. `installer/UPSTREAM` records what it came from and
the local WiVRn changes.

## Build from source

`./install.sh` is the supported path. It installs the Standable/Proton side
from `installer/`, builds WiVRn at the tag in `wivrn-rev` with the patches in
`patches/`, installs it under `/usr`, and writes the drop-in. Pass
`--install-deps` to install the distro packages with `sudo`; without it the
installer checks them first, before touching the Standable/Proton side, and
prints the command for your distro.

The build it runs is equivalent to this, from the port repo root:

```sh
git clone --depth 1 --branch "$(cat wivrn-rev)" https://github.com/WiVRn/WiVRn wivrn
cd wivrn
git apply ../patches/wivrn/*.patch
cp ../patches/monado/*.patch patches/monado/
cmake -S . -B build -G Ninja -DCMAKE_BUILD_TYPE=Release \
  -DCMAKE_INSTALL_PREFIX=/usr
cmake --build build
sudo cmake --install build
```

Notes:

- Builds verified on Arch/CachyOS and Fedora 44 (full installer on the host),
  plus Fedora 42 in a container. Ubuntu 25.10 package names were checked but
  not built.
- `x264` is required: it is the encoder WiVRn falls back to. On Fedora it is
  in RPM Fusion; `--install-deps` enables that repository and installs it.
- The Monado patches must be in `patches/monado/` before configure; WiVRn's
  FetchContent step applies them when it checks out Monado.
- `libopenvr_api.so` must be present at configure time. Without it Monado
  disables OpenVR support and the `steamvr_lh` host this port needs.
- Installing replaces the system `wivrn-server` and runtime libraries. If you
  run your own WiVRn build instead, it must include these patches and the
  drop-in environment from **How it works**; unpatched WiVRn has no Standable
  devices even though the shim may start.

### Distro WiVRn packages

Fedora and Arch package WiVRn (`wivrn`, `wivrn-server`, `wivrn-dashboard`), and
those builds work, but they do not contain this port's patches. `install.sh`
builds its own `wivrn-server` and libraries into `/usr`, overwriting the
packaged files. A later `dnf upgrade` / `pacman -Syu` of `wivrn` will replace
them with the stock build and Standable stops loading. Re-run `./install.sh`
after such an update, or exclude the package (`IgnorePkg = wivrn-server` on
Arch; `exclude=wivrn` on Fedora).

Keep the packaged `wivrn-dashboard` and xrizer/OpenComposite; the port does not
replace those.

## Run

1. Switch to WiVRn if SteamVR was active:

   ```sh
   vrswitch wivrn
   ```

2. Connect the headset to the WiVRn server.
3. Start WayVR (`wayvr --show`) if installed.
4. Start VRChat from Steam. Set these once in **VRChat → Properties → General → Launch Options**:

   ```sh
   IPC_IGNORE_VERSION=1 PRESSURE_VESSEL_IMPORT_OPENXR_1_RUNTIMES=1 XRIZER_TRACKER_SERIALS="Hips;Chest;Elbow Left;Elbow Right;Knee Left;Knee Right;Foot Left;Foot Right" %command%
   ```

5. On the v3.1 native driver, start the settings GUI now and keep it open:

   ```sh
   ~/.local/bin/standable-gui-wivrn
   ```

6. In WayVR, center the playspace and set the floor height.
7. Run Standable's in-driver T-pose calibration.
8. Calibrate your avatar in VRChat. If your proportions look wrong, set VRChat's Avatar Measurement to **Height**, then recalibrate both.

SteamVR and WiVRn cannot own the headset at the same time. Use `vrswitch` to switch between them.

## Verify the install

Run these checks in order.

1. The drop-in is installed and enables the host:

   ```sh
   systemctl --user cat wivrn.service | grep -E 'STEAMVR_LH|LH_LOAD|STANDABLE_GUI'
   ```

   Expect `WIVRN_USE_STEAMVR_LH=1`, `LH_LOAD_STANDABLE=1`, `STANDABLE_GUI=1`.

2. The runtime is switched: `vrswitch status` shows WiVRn for OpenXR and the
   xrizer runtime for OpenVR (`/usr/lib64/xrizer/runtime` on Fedora,
   `/opt/xrizer` on Arch).

3. Start WiVRn and connect the headset, then check the driver log:

   ```sh
   journalctl --user -u wivrn | grep -E 'Auth:|DeviceManager|InitRequest'
   ```

   `Auth: 1` and `[DeviceManager] Total: 3` (headset plus both controllers).
   `Auth: 17777` means the AppID file is missing or Steam is not logged in.
   On the older shim path, the same lines are in
   `~/.local/state/standable/server.out`.

4. The 8 proxies exist:

   ```sh
   journalctl --user -u wivrn | grep 'lighthouse tracker'
   ```

5. The GUI is connected when the driver log shows the init handshake:

   ```sh
   journalctl --user -u wivrn | grep -E 'InitRequest|UsingFLOOR'
   ```

   On the older shim path, `grep 'spawning GUI' ~/.local/state/standable/serverhelper.log` is the equivalent.

6. Launch VRChat from Steam with the launch options above; the 8 trackers
   appear in VRChat's Trackers menu.

The vendored installer can check the Standable/Proton side:

```sh
./installer/install.sh --check
```

It appends a system dump to `~/.local/state/standable/install.log`, which is
useful when asking for help.

If step 1 prints nothing, the drop-in did not install; re-run `./install.sh`.
If step 3 has no log at all, the driver never loaded; check
`journalctl --user -u wivrn` for `steamvr_lh`.

## Standable GUI

The settings window is what saves the calibrated height and floor, so keep it
open while you calibrate. Body estimation and T-pose calibration run without
it, but the result is not written to `saves/settings.json`.

**Official v3.1 native driver:** the driver does not start the GUI. After the
headset session is up, run:

```sh
~/.local/bin/standable-gui-wivrn
```

It connects to the running driver; the old wineserver restriction does not
apply to the native driver. Do not start a second copy.

If the GUI warns that the SteamVR driver path is missing or incorrect, run
`~/.local/bin/standable-fix-gui-path` once and restart it.

**Older Ignition shim:** the driver helper starts the GUI in the driver's
wineserver. If you are on that path, do not launch a separate copy.

**Start order:** WiVRn → headset → WayVR → VRChat → GUI.

The in-VR dashboard is experimental and needs an OpenComposite/xrizer bridge DLL. When the standalone launcher is installed, set `BRIDGE_DIR` in `~/.config/standable-wivrn/paths.conf`.

## Troubleshooting

Each entry gives the symptom, cause, and fix.

**Auto-calibration in VRChat does nothing**

VRChat OSC is off by default. In VRChat, enable Action Menu → **OSC** → **Enabled**; in Standable, enable **Configure VRChat for Auto Calibration**. Standable sets VRChat's IK-debug-logging and one-handed-calibration params over OSC, so until step 1 they never arrive. `./install.sh --check` reports the log link and the OSC state.

**VRChat's IK is frozen, or the log shows `Auth: 17777`**

The driver has no Steam app ID. `wivrn-server` is not started by Steam, so
`SteamAPI_Init()` fails. The installer sets `SteamAppId=2370570` in the WiVRn
drop-in. If an older install is missing that line, add it to
`~/.config/systemd/user/wivrn.service.d/standable.conf` and restart WiVRn.
Steam must be logged in.

**IK is frozen but the log shows `Auth: 1`**

The driver only saw the headset and one controller. In the log, `[DeviceManager] Total:` should be 3 (headset plus both controllers); `Total: 2` means a controller never reached the driver, and Standable cannot estimate without both hands.

```sh
journalctl --user -u wivrn | grep -E "wivrn-(hmd|left|right)|Total:"
```

If `wivrn-right` or `wivrn-left` is missing, get both controllers awake and tracked in the headset, then restart WiVRn (`vrswitch wivrn`). Frequent `XRT_DEVICE_INVALID` toggling alongside means the controllers are losing tracking.

**No OpenXR app can start a session (`ipc_client_check_git_tag` mismatch)**

The server and the runtime libraries came from different builds. Re-run `./install.sh`, or set `IPC_IGNORE_VERSION=1` for the app.

**The Standable GUI says "SteamVR is missing"**

Expected. There is no Windows SteamVR; the installer posts shims for the paths Standable probes. Check `game.log` rather than the dialog.

**The Standable GUI says "SteamVR driver path is missing or incorrect"**

The GUI's Windows-side `openvrpaths.vrpath` has a Linux path or a stale
`S:\` entry. Run:

```sh
~/.local/bin/standable-fix-gui-path
```

then restart the GUI. It repairs only the Proton prefix file; the native
driver and the host SteamVR registration are left alone.

**"error 305", or the driver will not load**

An orphaned `ignition_server` process is holding the shared-memory bridge. Run `vrswitch wivrn` (or `vrswitch steamvr`), which clears them first.

**WayVR does not appear in the headset**

A `wayvr` process from an earlier session still holds WayVR's single-instance
lock, so WiVRn's launch exits with “Looks like WayVR is already running.” Kill
it and attach a new one to the live session:

```sh
pkill -x wayvr
wayvr --openxr --show
```

**VRChat opens in desktop mode**

The `PRESSURE_VESSEL_IMPORT_OPENXR_1_RUNTIMES=1` launch option is missing. Add the launch options from Run above.

**`vrswitch status` says OpenVR runtime: ... (missing)**

xrizer is not installed. Re-run `./install.sh`, or on Fedora:
`sudo dnf copr enable @xr-sig/xrizer && sudo dnf install xrizer`. Native WiVRn
uses `/usr/lib64/xrizer/runtime`; the Flatpak dashboard's Custom path is
`/run/host/usr/lib64/xrizer/runtime`.

**`vrswitch status` says OpenXR runtime: unknown**

WiVRn removes the active-runtime symlink when it starts. If you restarted the
service manually after `vrswitch wivrn`, run `vrswitch wivrn` again to restore
it.

**The logs mention Standable, but there are no trackers and no GUI**

The shim started, but the `steamvr_lh` host never loaded Standable. Usual cause:
the running `wivrn-server` is a different build (your own, a distro package, or
an old install), so the patches and the drop-in do not apply.

```sh
systemctl --user show -p ExecStart wivrn.service
```

It must run the binary installed by `./install.sh` (`/usr/bin/wivrn-server`).
Then check the drop-in (Verify step 1). If `~/.local/state/standable/` does not
exist, `LH_LOAD_STANDABLE=1` never reached the driver.

**Fedora: configure fails on x264, nlohmann_json, avahi, or OpenSSL**

`x264-devel` is in RPM Fusion, `nlohmann_json` is Fedora's `json-devel`,
`avahi-glib.pc` is in `avahi-glib-devel` (not `avahi-devel`), the server needs
`openssl-devel`, and `x264-devel` is required (without an encoder WiVRn cannot
start a session). Run `./install.sh --install-deps`, which enables RPM Fusion
free for x264, or use the dependency command the installer prints.

**Trackers do not appear in VRChat**

The 8 proxies reach VRChat through xrizer, which maps OpenVR tracker roles to OpenXR. VRChat only sees them when the launch options reach it and the serial list matches the devices the driver reports.

1. Confirm the proxies exist. With WiVRn running and the headset connected:

   ```sh
   journalctl --user -u wivrn | grep "lighthouse tracker"
   ```

   You should see 8 lines: `Hips`, `Chest`, `Elbow Left`, `Elbow Right`, `Knee Left`, `Knee Right`, `Foot Left`, `Foot Right`. Use these exact names in the next step; if your build reports different names, use those instead.

2. Confirm the launch options are on VRChat. **Steam → VRChat → Properties → General → Launch Options** must contain, exactly:

   ```sh
   IPC_IGNORE_VERSION=1 PRESSURE_VESSEL_IMPORT_OPENXR_1_RUNTIMES=1 XRIZER_TRACKER_SERIALS="Hips;Chest;Elbow Left;Elbow Right;Knee Left;Knee Right;Foot Left;Foot Right" %command%
   ```

   The list must have one entry per proxy, matching spelling and case, with no extra spaces and no trailing separator. Launch options only apply when VRChat is started from Steam; a desktop shortcut or an already-running instance will not pick them up.

3. Confirm xrizer is the OpenVR runtime:

   ```sh
   vrswitch status
   ```

   `OpenVR runtime:` should be `/opt/xrizer`. If it points at SteamVR instead, run `vrswitch wivrn` again.

4. Restart cleanly. Set the options, fully quit VRChat, then launch it from Steam.

5. If they still do not appear, check VRChat's `output_log.txt` (in the game's `_data` directory) for tracker or xrizer lines. If the proxies exist in the WiVRn log but never move, the estimator is not running; see the frozen IK entry above.

**Calibration is off, or the floor height is wrong**

Start WayVR before VRChat and set the floor height there. Standable uses the
playspace floor; without WayVR the driver falls back to 105 cm. Install WayVR
from your package manager, the AUR, or the official AppImage; the installer
only warns if it is missing.

**Elbows are off, or the legs and spine look inverted**

The driver is using its default 105 cm height because no calibration has completed, or VRChat's Avatar Measurement is Arm Span instead of Height. Hold a true side-to-side T-pose until the driver clicks twice, set VRChat's measurement to Height, then recalibrate both.

**Standable floor or chaperone: "Failed to read chaperone file"**

The Proton prefix is missing the emulated SteamVR paths. Re-run `./install.sh`.

**The WiVRn service is stuck in "failed"**

The service hit its stop timeout. Run `vrswitch wivrn` or `vrswitch steamvr`; both reset it.

**Reading logs**

- Driver and pose feed: `journalctl --user -u wivrn | grep "steamvr_lh driver"`
- VRChat: `output_log.txt` in the game's `_data` directory

## How it works

Standable ships as a Windows SteamVR driver (`bin/win64/driver_standable.dll`) and cannot load into WiVRn directly. This port hosts the real driver inside WiVRn:

```
VRChat
  |  OpenVR
xrizer                    OpenVR to OpenXR bridge used by VRChat
  |  OpenXR
WiVRn runtime (libopenxr_wivrn.so)
  |  steamvr_lh OpenVR host (patched)
libdriver_ignition.so     Linux shim that presents itself as a SteamVR driver
  |  shared-memory IPC (ignition_bridge.dll)
ignition_server.exe       Windows process under Proton
  |  IVRDriverContext / IVRServerDriverHost
driver_standable.dll      the real Standable driver
```

A body-estimation driver reads the headset and controllers through `IVRServerDriverHost::GetRawTrackedDevicePoses`. The `steamvr_lh` patch (`patches/monado/0013-*.patch`) adds feeder devices so the hosted driver sees device 0 as the HMD and devices 1 and 2 as the controllers, the same indexing SteamVR uses. Standable then estimates the body and exposes 8 proxy trackers (Hips, Chest, Elbow L/R, Knee L/R, Foot L/R), which VRChat reads through xrizer.

The `steamvr_lh` host is enabled by the systemd drop-in installed by `install.sh`:

| Setting | Meaning |
| --- | --- |
| `WIVRN_USE_STEAMVR_LH=1` | use the OpenVR host inside WiVRn |
| `LH_LOAD_STANDABLE=1` | load the Ignition shim and Standable |
| `LH_LOAD_LIGHTHOUSE=0` | do not drive real base stations |
| `LH_DISCOVER_WAIT_MS=30000` | wait for the driver to enumerate its devices |

The Standable driver itself is proprietary and is not included here. The port installer configures the Proton prefix and the Windows-path emulation it needs.

## Uninstall

```sh
./uninstall.sh
```

The installer records which components it added. `uninstall.sh` reads that list
and offers the same checklist. `--yes` takes the defaults, and `--dry-run`
prints the actions without changing anything. The Standable/Proton side is
off by default; select it in the checklist or pass `--with-port-installer`.
Steam, Standable, and the Proton prefix are left alone otherwise.

## Layout

| Path | Purpose |
| --- | --- |
| `install.sh`, `uninstall.sh` | install and remove the WiVRn side |
| `installer/` | vendored Standable/Proton installer (`installer/UPSTREAM` has its origin) |
| `patches/wivrn/`, `patches/monado/` | the patch series applied to upstream WiVRn and Monado |
| `wivrn-rev` | pinned upstream WiVRn tag |
| `vendor/` | Ignition shim binaries loaded by `steamvr_lh` |
| `src/steamvr_lh/` | reference copy of the pose-feed host code |
| `tools/standable-gui-wivrn.sh` | desktop launcher for the Standable settings window |
| `tools/fix-standable-gui-path.sh` | repair the GUI's Windows-side driver path after Proton prefix changes |
| `tools/vrswitch` | switch the OpenXR and OpenVR runtime between WiVRn and SteamVR |
| `tools/reap-ignition.sh` | remove orphaned Ignition shim processes |
