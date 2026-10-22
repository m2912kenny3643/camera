# R6 Camera 0.4 implementation checkpoint

Approved scope: user-confirmed next-version plan, 2026-10-22.

## Implemented for native validation

- Shared-center angular zoom, CCW increases zoom, high stops above pointer;
  unwrapped per-touch deltas, immediate wheel updates, latest hardware command acknowledgement.
- H+ / H / L ceilings 4 / 2 / 1 fps, legacy burst preset compatibility,
  10s timer continuous count 2–10. Monotonic admission deadlines, no catch-up,
  cancellation checked again before submission, readiness coordinator, capacity
  split into at most two photo jobs and three total capture/render jobs.
- Actual exposure-callback timing samples retained for burst cadence measurement.
  No claim that the 20% device-jitter target has been measured.
- Effective A+ automatic policy preserves personal settings; Tv fixed shutter;
  M AUTO ISO retains M, manual M disables compensation; Fv preserves the other
  parameter when switching AUTO/manual. Manual exposure uses required speed
  prioritization; burst never substitutes video frames or changes file format.
- ONE SHOT sends one selected-subject lens command; SERVO follows the subject.
- Gravity-based fixed-landscape level filter (30Hz monitor, 0.15s smoothing,
  ±1° threshold), unavailable/singular sensor data returns no reading.
- Optional bundled bird pose adapter and pure tensor decoder: exact 640-square
  letterbox, [1,23,8400], confidence gates, NMS, real eyes/crown/beak only,
  observed head envelope and body fallback without changing selected identity.

## Awaiting required UI confirmation

Six deterministic design proposals are in `docs/design/0.4/` and are explicitly
labelled proposals, not running-app screenshots. User was asked to confirm
them before a major HUD/Q/MENU/editor re-layout. Until then the prior UI remains,
including controls that still need exposing for timer count, level, drive labels,
AUTO underlining and per-program editing restrictions. A whole redesign must not
be claimed complete from these core changes.

## Bird model release gate

The owner accepts AGPL-3.0 for original app source. The complete GNU license is
in LICENSE; third-party resources retain their own notices. The candidate's
actual checkpoint metadata says AGPL while its publisher card says MIT. CUB
image terms do not automatically decide rights in derived weights. Redistribution
evidence remains unresolved. No model weights or manual screenshots are tracked.

`docs/bird-release.json` records the known gaps. `check_bird_release.py` fails
closed for missing redistribution evidence, package digest, independent 100-image
evaluation, or device report. CI checks this before compiling any bird resource.
Model-free builds are validation builds and cannot satisfy full bird-eye delivery.

## Verification and remaining acceptance

Windows has no Swift/Xcode toolchain. Tree-sitter parsing is syntax inspection,
not compilation. Native core tests, iOS archive and UI tests must run in GitHub
Actions against the exact committed source. Python packaging and release-gate
tests can run locally. Existing uncommitted UI-fixture/test-export improvements
from the prior iteration are preserved.

No actual 100-image bird evaluation or phone latency result exists. Hardware
camera/volume buttons, actual focusing, continuous preview, burst timing, level
tilt signs and sustained use still require iPhone verification. The shared public
capture event still permits volume-button capture, as previously accepted.
