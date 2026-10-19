# Standable WiVRn Linux Port

Run the real Standable Full Body Estimation SteamVR driver on Linux with WiVRn, without running SteamVR. Adds 8 proxy trackers to VRChat.

> **Experimental. Expect breakage.**
>
> The driver and body estimation work, including T-pose calibration and all 8 trackers in VRChat. The Standable GUI launches, but some SteamVR-specific features are unavailable.
>
> Updates to Steam, Proton, VRChat, Standable, or WiVRn can break the setup. You may need to rerun the installer or switch runtimes again.
>
> This port was built with heavy use of AI assistance, followed by hardware testing. It has not been widely tested. It will likely break, and it will need troubleshooting. Treat it as a research project, not a supported product.
>
> **Want a less experimental setup?** Try the [SteamVR Linux port](https://github.com/meeyao/standable-linux-port) or run SteamVR on Windows.

## Requirements

- Linux with the dependencies needed to build WiVRn (the installer builds it from source)
- SteamVR installed in Steam. It is not run; the installer uses its paths to place compatibility shims.
- Standable FBE on Steam
- VRChat on Steam
- Around 8 GB of free disk space
- Arch/CachyOS or Debian/Ubuntu. On other distros, provide the WiVRn build dependencies (the installer prints them if a required tool is missing)
- `libopenvr_api.so` (the `openvr` package on Arch; `libopenvr-api1` or `libopenvr-api2` on Debian/Ubuntu, in `contrib` or `universe`). WiVRn links it, so the build and the runtime both need it. The installer checks for it.

## Install

```sh
git clone https://github.com/meeyao/standable-wivrn-port
cd standable-wivrn-port
./install.sh
```

The installer:

1. Sets up the Standable and Proton side (Steam root, Proton prefix, Windows-path shims, the Ignition shim, and the driver hook).
2. Builds upstream WiVRn at the tag in `wivrn-rev`, applying the patch series in `patches/`, and installs it (server, runtime libraries, and systemd unit).
3. Writes the systemd user drop-in that enables the `steamvr_lh` driver host.

The build takes a few minutes.

Options:

- `--skip-port-installer`: skip the Standable and Proton setup (already configured)
- `--help`: show installer options

Environment: `PORT_INSTALLER_REPO`, `PORT_INSTALLER_REF`, `WIVRN_REPO`, `WIVRN_REF`.

## Run

Switch to WiVRn:

```sh
vrswitch wivrn
```

Reconnect your headset, then add this to **Steam → VRChat → Properties → General → Launch Options**:

```sh
IPC_IGNORE_VERSION=1 PRESSURE_VESSEL_IMPORT_OPENXR_1_RUNTIMES=1 XRIZER_TRACKER_SERIALS="Hips;Chest;Elbow Left;Elbow Right;Knee Left;Knee Right;Foot Left;Foot Right" %command%
```

Calibrate in this order:

1. Run Standable's in-driver T-pose calibration.
2. Calibrate your avatar in VRChat.
3. If your proportions look wrong, set VRChat's Avatar Measurement to **Height**, then recalibrate both.

SteamVR and WiVRn cannot own the headset at the same time. Use `vrswitch` to switch between them.

## Standable GUI

Body estimation and T-pose calibration work without opening the GUI. To open the Standable settings window while WiVRn hosts the driver:

1. Make sure WiVRn is the current runtime (`vrswitch wivrn`).
2. Start it from your desktop application menu (**Standable GUI (WiVRn)**), or run:

   ```sh
   ~/.local/bin/standable-gui-wivrn
   ```

Launch it from a desktop session, not through Steam: Steam's sandbox forks a second wineserver, and the GUI would then be unable to talk to the driver.

The launcher runs Standable in host context so it shares one Proton prefix and wineserver with the driver. The desktop settings window works; the in-VR dashboard is experimental and needs an OpenComposite/xrizer bridge DLL (point `BRIDGE_DIR` at it in `~/.config/standable-wivrn/paths.conf`).

## Troubleshooting

Each item is symptom, cause, and fix.

**VRChat's IK is frozen, or the log shows `Auth: 17777`**

Standable's Steam authentication has no AppID context. The installer writes `steam_appid.txt` (`2370570`) next to `ignition_server.exe`. Updates can remove it. Recreate it, then restart WiVRn. Steam must be logged in.

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

**"error 305", or the driver will not load**

An orphaned `ignition_server` process is holding the shared-memory bridge. Run `vrswitch wivrn` (or `vrswitch steamvr`), which clears them first.

**VRChat opens in desktop mode**

The `PRESSURE_VESSEL_IMPORT_OPENXR_1_RUNTIMES=1` launch option is missing. Add the launch options from Run above.

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

## Layout

| Path | Purpose |
| --- | --- |
| `install.sh`, `uninstall.sh` | install and remove the WiVRn side |
| `patches/wivrn/`, `patches/monado/` | the patch series applied to upstream WiVRn and Monado |
| `wivrn-rev` | pinned upstream WiVRn tag |
| `vendor/` | Ignition shim binaries loaded by `steamvr_lh` |
| `src/steamvr_lh/` | reference copy of the pose-feed host code |
| `tools/standable-gui-wivrn.sh` | desktop launcher for the Standable settings window |
| `tools/vrswitch` | switch the OpenXR and OpenVR runtime between WiVRn and SteamVR |
| `tools/reap-ignition.sh` | remove orphaned Ignition shim processes |
