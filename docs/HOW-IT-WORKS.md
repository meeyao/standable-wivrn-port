# How it works

Standable Full Body Estimation ships as a Windows SteamVR driver
(`bin/win64/driver_standable.dll`). It cannot load in WiVRn directly, and WiVRn
does not run SteamVR. This port hosts the real driver inside WiVRn.

## Layers

```
VRChat
  |  OpenVR
xrizer                    OpenVR -> OpenXR bridge VRChat uses
  |  OpenXR
WiVRn runtime (libopenxr_wivrn.so)
  |  steamvr_lh OpenVR host (patched)
libdriver_ignition.so     Linux shim, pretends to be a SteamVR driver
  |  shared-memory IPC (ignition_bridge.dll)
ignition_server.exe       Windows process under Proton
  |  IVRDriverContext / IVRServerDriverHost
driver_standable.dll      the real Standable driver
```

- `vendor/libdriver_ignition.so` is loaded by WiVRn's `steamvr_lh` OpenVR host as
  if it were a SteamVR driver.
- The shim spawns `vendor/ignition_server.exe` under Proton, which loads
  Standable's real `driver_standable.dll` from the Steam install.
- `vendor/ignition_bridge.dll` is the shared-memory IPC between the shim and the
  server process.

## Pose feed

A body-estimation driver needs the headset and controllers as input. On SteamVR
it reads them through `IVRServerDriverHost::GetRawTrackedDevicePoses`. Under
WiVRn the hosted driver calls the same interface, so the `steamvr_lh` host must
synthesise those poses.

`patches/monado/0013-d-steamvr_lh-host-device-pose-feed.patch` adds feeder
devices to the `steamvr_lh` context:

- `set_feeder_devices()` registers the WiVRn headset and both controllers.
- `GetRawTrackedDevicePoses` writes device 0 = HMD, 1 = left controller,
  2 = right controller, matching SteamVR indexing, and fills every requested
  slot so the driver sees the same array shape it expects.
- Velocity and validity flags are passed through so the driver can differentiate
  tracked and untracked frames.

Standable then estimates the body and exposes 8 proxy trackers (Hips, Chest,
Elbow L/R, Knee L/R, Foot L/R). VRChat reads them through xrizer.

## Runtime and environment

The `steamvr_lh` host is enabled by the systemd user drop-in installed by
`install.sh`:

```
WIVRN_USE_STEAMVR_LH=1   use the OpenVR host inside WiVRn
LH_LOAD_STANDABLE=1      load the Ignition shim / Standable
LH_LOAD_LIGHTHOUSE=0     do not try to drive real base stations
LH_DISCOVER_WAIT_MS=30000  wait for the driver to enumerate its devices
```

`vrswitch` selects which runtime owns the headset. It points
`~/.config/openxr/1/active_runtime.json` at WiVRn or SteamVR and rewrites the
OpenVR `runtime` entry in `~/.config/openvr/openvrpaths.vrpath` (`/opt/xrizer`
for WiVRn, the SteamVR dir for SteamVR). WiVRn and SteamVR cannot run at the
same time.

## Files

| Path | Purpose |
| --- | --- |
| `vendor/libdriver_ignition.so` | Ignition shim loaded by `steamvr_lh` |
| `vendor/ignition_server.exe` | Windows host process (Proton) |
| `vendor/ignition_bridge.dll` | shared-memory IPC |
| `patches/monado/0013-*.patch` | pose feed for hosted drivers |
| `/usr/lib/wivrn/libopenxr_wivrn.so` | WiVRn OpenXR runtime |
| `/usr/lib/wivrn/libmonado_wivrn.so.0.0.0` | WiVRn Monado build |
| `/usr/bin/wivrn-server` | WiVRn server |
| `/usr/share/openxr/1/openxr_wivrn.json` | OpenXR manifest |
| `~/.config/systemd/user/wivrn.service.d/standable.conf` | hosting env |

The Standable driver itself is proprietary and is not in this repo. The port
installer sets up its Proton prefix and the Windows-path emulation it needs.
