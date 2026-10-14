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

- Cause: the driver is stuck at its default 105 cm height: either no
  calibration has completed yet, or VRChat Avatar Measurement is Arm Span
  instead of Height.
- Fix: hold a true side-side T-pose until the driver clicks twice, then set
  VRChat measurement to Height and recalibrate avatar + driver.

## Trackers frozen in a slouched pose, estimator dead

- Cause: the driver's Steam ownership check failed. The estimator never runs
  (no `Auth: 1` in the log).
- Fix: `journalctl --user -u wivrn | grep -i auth`. `Auth: 17777` means the
  check has no AppID context: make sure
  `.../Standable Full Body Estimation/bin/linux64/steam_appid.txt` contains
  `2370570` (the installer writes it; updates wipe it), then
  `systemctl --user restart wivrn.service`. Steam must be logged in.

## No OpenXR app can start a session (WayVR/VRChat fail, version mismatch)

- Cause: `wivrn-server` and the client `.so` libs came from different builds
  (e.g. a distro package overwrote one side). The log shows
  `ipc_client_check_git_tag ... does not match`.
- Fix: reinstall (same-tree triple), or export `IPC_IGNORE_VERSION=1` for
  the app. The installer sets it in all the places it controls.

## WiVRn service stuck "failed" after stop

- Cause: the service hit the stop-sigterm timeout and systemd latched the failed
  state.
- Fix: `vrswitch wivrn` or `vrswitch steamvr`; both run `systemctl --user
  reset-failed wivrn.service` before starting anything.

## Reading logs

- WiVRn driver load and pose feed:
  `journalctl --user -u wivrn | grep "steamvr_lh driver"`
- VRChat: `output_log.txt` in the game's `_data` directory.
