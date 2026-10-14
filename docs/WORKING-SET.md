# Working set, 2026-10-14 (verified: driver authed, T-pose fired, 8 trackers live)

The exact binaries + values a repeat install must reproduce. `vrselftest`
(when built) asserts this table instead of these notes.

## Atomic triple (one same-tree build — never mix)

| artifact | md5 |
|---|---|
| `/usr/bin/wivrn-server` | `21d9052fa1feb84dd2d42e2576b21d4d` |
| `/usr/lib/wivrn/libopenxr_wivrn.so` | `4f8105aabcbb89524bed54066a9c0974` |
| `/usr/lib/wivrn/libmonado_wivrn.so.0.0.0` | `728e96ef2f31ab5b92478b947ac26d98` |

Source: `wivrn-standable-port` @ `07a0fe9e` (server preset), monado pin
`f037264d23e2472a444a157370647fcd601ed81b`. Server reports `WiVRn 26.9`.

## Shim set (port-installer deployed 2026-10-14, all same run)

| file | md5 |
|---|---|
| `.../bin/linux64/driver_standable.so` | `bbedb4f28ccfbf2a09c6d822123cf2ce` |
| `.../bin/linux64/ignition_server.exe` | `e54aba905909adc35a60f31abc81eb6a` |
| `.../bin/linux64/steam_appid.txt` | `2370570` (no newline; installer writes it) |

Plus `C:\vrclient\bin\vrclient*.dll` in prefix `2370570` (copied from the
running Proton build; re-copy if missing).

## Live config that matters

- `standable.conf`: LH hosting on, IPC bypass on, reaper paused, no debug.
- `environment.d/wivrn-ipc.conf`: `IPC_IGNORE_VERSION=1`.
- `~/.local/bin/vrswitch` == repo `tools/vrswitch` (installer syncs).
- VRChat launch opts: `IPC_IGNORE_VERSION=1
  PRESSURE_VESSEL_IMPORT_OPENXR_1_RUNTIMES=1
  XRIZER_TRACKER_SERIALS="Hips;Chest;Elbow Left;Elbow Right;Knee Left;Knee
  Right;Foot Left;Foot Right" %command%`

## Calibration baseline

User Height `182.8799591064453`, Calibration Mode 1, binds for HMD + both
controllers in `bind_offsets.json`. If IK looks wrong, recalibrate before
touching anything else.

## Known-good signals (what "working" looks like in logs)

- `wivrn` log: `Auth: 1` (not 17777), `Active: 3 | Total: 3`,
  `feed[0..2]` streaming.
- No `ipc_client_check_git_tag ... does not match` (or bypass exported).
- `probe_record.gdb`: `xmm7>0.95`, `bl=1` in T-pose.
