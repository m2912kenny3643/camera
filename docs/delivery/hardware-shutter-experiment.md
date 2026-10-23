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

## Xcode 27 CI verification

The user explicitly authorized the GitHub upload after the initial approval-review rejection. Implementation commit `194f49a9c62d2803339aaeeb5c2d0f02aef0e611` was pushed to the feature branch and verified with the existing workflow: [run 39935212098](https://github.com/m2912kenny3643/camera/actions/runs/39935212098).

- Xcode 27 selection and public capture-event header inspection: passed.
- macOS Swift package suite: 80 tests passed, including all 9 hardware-shutter tests. Workflow Python checks passed; the local full Python suite separately passed 45 tests.
- Release device archive and unsigned IPA packaging checks: passed.
- iPhone 17 / iOS 27 simulator boot: passed.
- iOS simulator suite: 86 tests passed; all 3 UI tests passed, including `testExperimentalHardwareShutterDefaultsOffAndCanBeRestored` (15.501 seconds). No test failures.
- Final workflow outcome: success. IPA artifact ID `12493088755`; screenshot artifact ID `12493811639`; diagnostic artifact ID `12494071293`. Artifacts are available from the run linked above. The IPA is unsigned and requires re-signing before installation.
- Downloaded IPA: 29,995,968 bytes; SHA-256 `ad21e064dd42729d425915b9f674d6b057fc0a5f1f52e6f319fcc2ec5c1ce4fe`. ZIP integrity passed and bundled `SOURCE-COMMIT.txt` exactly matches the implementation commit. The full functional-model/notices gate passed against raw files from that commit; checking against the Windows checkout initially reported a notice mismatch caused solely by CRLF conversion in the model card, which was verified byte-for-byte against Git instead.
- Reviewed the actual simulator screenshot `Hardware-shutter-experimental-settings.png`: toggle, limitations, unsupported-simulator status and JSON share control are visible. This screenshot does not establish physical gesture handling.

## Outstanding physical-device evidence

No physical device is connected. Follow [the hardware test matrix](../DEVICE-TESTS.md) for actual light-press callbacks, A+ overlay behavior, pressure/full-press ordering, AF, volume-key false accepts, repeated gestures, system accessibility settings and burst release latency. Leave the experiment off by default; disable it if physical callbacks cannot support the sequence consistently. Do not describe it as Camera-Control-only capture.
