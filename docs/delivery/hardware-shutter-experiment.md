# Experimental two-stage hardware shutter — 2026-10-23

Target: iPhone 17 / iOS 27. Branch: `codex/camera-control-two-stage`.

## Behavior

MENU → 設定 → 實驗性兩段硬體快門 is off by default, including older current/C1–C3 payloads. Off preserves the common hardware shutter. On registers an AF-mode picker, uses overlay activation to request AF and authorizes one primary press for 2 seconds; dismissal shortens the remaining window to at most 300ms. Direct unprepared presses and secondary capture are rejected. Burst capture ends on release/cancellation, not on authorization expiry. Settings/lifecycle changes revoke authorization. Existing selected subjects/points are retained; MF does not request AF. No hardware zoom control or AE lock was added.

This is an overlay authorization experiment, **not** reliable Camera Control source detection or raw half/full pressure sensing. A volume-down press inside the window can still capture. A+ disables AF mode changes, and its overlay availability still needs physical verification. The last 200 unknown-source inputs and requested actions can be shared as JSON from the settings page.

## Validation performed locally

- Existing Python suite: 45 tests passed before and after implementation.
- Tree-sitter Swift parser: all 46 Swift source/test files parsed without syntax errors. This is not Swift typechecking or compilation.
- `git diff --check`: passed.
- Separate standards/spec reviews found and resolved two issues: pre-authorization queued input and unnecessary session reconfiguration on unrelated settings updates.
- Added Swift tests for legacy settings decoding/default-off behavior, settings round-trip, direct/secondary rejection, pre-authorization ordering, duplicate callbacks, one-use authorization, exact deadline, dismissal grace, long burst release, cancellation/reset/unavailability and legacy behavior. Added UI test for default-off → enable → disable with an event-report link.

## Outstanding evidence

Windows has no usable Swift/Xcode installation. Swift/XCTest execution, Xcode 27 device archive and simulator UI execution are not yet verified. The planned GitHub push was rejected by automatic approval review because explicit source-upload authorization was missing; no source changes were pushed by that attempt. GitHub CI requires approval to upload this feature branch to the existing remote `m2912kenny3643/camera`.

No physical device is connected. Follow [the hardware test matrix](../DEVICE-TESTS.md) for actual light-press callbacks, A+ overlay behavior, pressure/full-press ordering, AF, volume-key false accepts, repeated gestures, system accessibility settings and burst release latency. Leave the experiment off by default; disable it if physical callbacks cannot support the sequence consistently. Do not describe it as Camera-Control-only capture.
