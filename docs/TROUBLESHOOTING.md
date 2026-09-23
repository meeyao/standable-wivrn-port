# Troubleshooting

Each item is symptom -> cause -> fix.

## "error 305" / driver won't load

- Cause: an orphaned `ignition_server` process still holds the shared-memory
  bridge, so the runtime that starts next cannot attach.
- Fix: `vrswitch wivrn` (or `vrswitch steamvr`). It kills stray
  `ignition_server` processes before switching.

## SteamVR error 103

- Cause: the OpenVR runtime in `~/.config/openvr/openvrpaths.vrpath` still points
  at `/opt/xrizer` instead of SteamVR.
- Fix: `vrswitch steamvr`.

## VRChat opens in desktop mode

- Cause: missing `PRESSURE_VESSEL_IMPORT_OPENXR_1_RUNTIMES=1` launch option, so
  VRChat does not see the OpenXR runtime inside its container.
- Fix: add the launch options from the README verbatim.

## Standable GUI says SteamVR is missing

- Cause: expected. There is no Windows SteamVR; the port installer posts shims
  for the paths Standable probes.
- Fix: ignore it. The driver still loads and estimates.

## Standable floor / chaperone: "Failed to read chaperone file"

- Cause: the Proton prefix lacks the emulated SteamVR paths.
- Fix: re-run `./install.sh` so the port installer reapplies the path fixes.

## Trackers not in VRChat

- Cause: `XRIZER_TRACKER_SERIALS` is unset or its serials do not match the 8
  proxies.
- Fix: set it exactly as in the README, semicolon-separated, no extra spaces.

## IK proportions wrong (elbows off, spine/hips inverted)

- Cause: the driver is stuck at its default 105 cm height until a calibration
  completes, and manual in-driver T-pose calibration does not fire under WiVRn.
- Fix: use VRChat auto-calibration (OSC) mode. Known issue.

## WiVRn service stuck "failed" after stop

- Cause: the service hit the stop-sigterm timeout and systemd latched the failed
  state.
- Fix: `vrswitch wivrn` or `vrswitch steamvr`; both run `systemctl --user
  reset-failed wivrn.service` before starting anything.

## Reading logs

- WiVRn driver load and pose feed:
  `journalctl --user -u wivrn | grep "steamvr_lh driver"`
- VRChat: `output_log.txt` in the game's `_data` directory.
