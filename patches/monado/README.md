# Monado patches

These patches apply to **Monado inside the WiVRn fork**
(`meeyao/wivrn-standable-port`), not to upstream WiVRn or a raw Monado checkout.

WiVRn pulls Monado through CMake FetchContent at the rev in `monado-rev`. The
fork carries three commits on top of that rev:

| Commit | What |
|---|---|
| `c37181c62` | `d/steamvr_lh: load Standable Ignition shim (LH_LOAD_STANDABLE)` and `LH_LOAD_LIGHTHOUSE` |
| `5c896b5e5` | `d/steamvr_lh: Add LH_MAX_EXTRAPOLATION_MS` |
| `336a8f4c3` | `st/oxr: implement XR_HTCX_vive_tracker_interaction with FBT tracker roles` |

`0013-d-steamvr_lh-host-device-pose-feed.patch` is generated against
`336a8f4c3` (the fork's HEAD) and is already included there. It is shipped here
for review and for people patching their own WiVRn tree.

Applying to a custom tree:

```sh
git -C <monado-src> apply /path/to/0013-d-steamvr_lh-host-device-pose-feed.patch
```

It will not apply to the bare pin `f037264d2`; the surrounding context
(`create_steamvr_side_devices`, the `LH_LOAD_STANDABLE` loader) comes from the
fork commits above.
