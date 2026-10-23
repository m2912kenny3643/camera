# Camera Control shutter without volume-button capture

Checked: 2026-10-22; experimental implementation added 2026-10-23 (Asia/Taipei). Target: iPhone 17 / iOS 27; project deployment target remains iOS 18. The initial research was read-only; the experimental implementation changes app behavior without resolving hardware identity.

## Verdict

The documented public capture-event API does not establish a way to keep Camera Control as a shutter while excluding both volume buttons. Treat this requirement as a blocker, not a completed feature. Do not invent an `event.source`, `event.button`, or input-filter property.

This conclusion is based on Apple's current DocC declarations, official presentation, and the actual Xcode 27 iPhoneOS public headers inspected in GitHub run 39702346520. No source/filter property was found in those headers.

## Verified API contract

Apple's current `AVCaptureEvent` symbol inventory exposes `phase`, `shouldPlaySound`, and `play(_:)`. It does not document a source/button identity. `phase` distinguishes began, ended and cancelled; it is not a hardware identifier. [Apple event reference](https://developer.apple.com/documentation/avkit/avcaptureevent), [primary DocC JSON](https://developer.apple.com/tutorials/data/documentation/avkit/avcaptureevent.json)

The interaction exposes these handler choices:

```swift
init(handler: (AVCaptureEvent) -> Void)
init(primary: (AVCaptureEvent) -> Void,
     secondary: (AVCaptureEvent) -> Void)
```

It also exposes `isEnabled`, which enables/disables the whole interaction. The latest inventory includes alternative imported initializer spellings, but no documented per-button filter or enabled-sources collection. The class was introduced in iOS 17.2; no iOS 27 source-filter addition was found. Disabling the interaction restores default system button behavior. [Apple interaction reference](https://developer.apple.com/documentation/avkit/avcaptureeventinteraction), [primary DocC JSON](https://developer.apple.com/tutorials/data/documentation/avkit/avcaptureeventinteraction.json)

Apple explicitly assigns Camera Control, volume down and Action button to the **primary** handler, and volume up to the **secondary** handler. Without a separate secondary handler, volume up also goes to primary. Therefore a secondary no-op alone cannot make capture exclusive to Camera Control. [Apple WWDC25, event handling at 3:37 and Camera Control at 10:44](https://developer.apple.com/videos/play/wwdc2025/253/)

The SwiftUI capture modifier also delivers `AVCaptureEvent`; switching to it does not provide documented source identity. `shouldPlaySound` concerns AirPods feedback, not Camera Control versus volume-down identity. [SwiftUI modifier](https://developer.apple.com/documentation/swiftui/view/oncameracaptureevent%28isenabled%3Adefaultsounddisabled%3Aaction%3A%29), [Apple sound property](https://developer.apple.com/documentation/avkit/avcaptureevent/shouldplaysound)

Camera Control's light-press zoom/exposure controls are a separate interface. Control activation/presentation callbacks do not establish which button originated a subsequent capture event. [Apple controls article](https://developer.apple.com/documentation/avfoundation/enhancing-your-app-experience-with-the-camera-control)

## 0.8.0 update (2026-10-23)

The user requested default-on two-stage shutter while preserving explicit opt-outs. New/missing/reset settings now enable it; unsupported controls retain shared-button capture on the capture page. One scene-window receiver replaces the preview-owned interaction so full-screen MENU no longer detaches the receiving view. The actual OS hardware routing remains pending device acceptance. Diagnostics add window/scene attachment and enabled state; presentation tests assert the real interaction remains installed, separately from injected events. An already-active overlay may not issue another activation on a subsequent physical light press, so universal half-press return cannot be promised. See [0.8.0 delivery and device checklist](../delivery/focus-areas-0.8.0.md).

## Existing app behavior

The initial app installed the single-handler initializer. The experimental implementation now registers primary and secondary handlers separately, routes phases into a testable gate, and preserves shared-button capture when the experiment is off. This routing does not identify Camera Control versus volume-down. The controller synchronizes the scene-window interaction through `isEnabled`. [Current implementation](../../R6Camera/Camera/HardwareCaptureReceiver.swift)

No validated change to only that closure can distinguish Camera Control from volume down using the documented event object. Do not mark a primary-only rewrite as meeting the requirement.

## Implementation decision and remaining proof

The requested combination has no verified public solution in the evidence above. Either retain this requirement as unresolved until a supported API is identified, or explicitly revise the product requirement. Globally disabling/removing capture interaction would stop both volume-button captures, but it would also remove this app's Camera Control shutter handler; it is not full acceptance of the requested combination.

Do not infer button identity from audio-volume changes, timing, the zoom overlay being visible, or prior light presses. None of those is a documented event-source contract; they could cause volume-down to capture or cause a real shutter press to be discarded. The experiment below uses an explicit interaction authorization, not an identity assertion. Do not use private selectors, private notifications or hardcoded undocumented button raw values.

At the next macOS build, inspect the installed Xcode 27 SDK's public `AVKit.framework/Headers` for `AVCaptureEvent` and `AVCaptureEventInteraction`. Record the selected SDK version and any newly discovered declaration. If no public source/filter exists there, the limitation is confirmed against the actual compile SDK, not just documentation.

Physical acceptance must separately exercise: volume-up short/long press, volume-down short/long press, Camera Control short/held press in single/burst modes, app launch versus foreground capture, overlays open/closed, and interruption/cancellation. Acceptance requires **zero** photo/burst requests from either volume key while retaining the approved Camera Control behavior. Simulator tests or a successful build cannot establish hardware source separation.
# iOS 27 SDK verification

The actual Xcode 27 iPhoneOS public AVKit headers were printed in [build 39702346520](https://github.com/m2912kenny3643/camera/actions/runs/39702346520). `AVCaptureEvent` exposes phase and sound handling; `AVCaptureEventInteraction` exposes shared or primary/secondary handlers. No source-button identifier/filter was found. The user explicitly chose to retain the common hardware handler temporarily, accepting volume-button capture. This requirement remains unresolved, rather than being described as fixed.

## 2026-10-23: opt-in overlay authorization experiment (revised in 0.7.1)

The user accepted a hardware-first approximation: activate the controls overlay to prepare AF, then press fully to capture; direct full presses without this preparation are rejected. After testing, the user confirmed light-press operation but reported full presses not capturing and requested light-press return from all app pages. This is **not** source detection or a raw half-press API. `.began`/`.ended` are press-down/release phases of a capture event, not half/full pressure levels. [Apple capture events](https://developer.apple.com/documentation/avkit/avcaptureevent), [Apple controls integration](https://developer.apple.com/documentation/avfoundation/enhancing-your-app-experience-with-the-camera-control)

- In 0.7.1, MENU → 設定 → 實驗性兩段硬體快門 defaulted off; 0.8.0 supersedes that default as described above. Off restores the shared primary/secondary shutter. Enabling registers only an AF-mode picker (SERVO AF / ONE SHOT / MF), never a zoom control. A+ keeps its effective SERVO mode and disables mode changes.
- The controls delegate reports overlay activation/presentation, **not** a physical pressure threshold or half-release. Activation requests AF while preserving a selected subject or fixed point; MF never requests AF, and a temporarily missing selected target holds focus. No AE lock is introduced.
- The initial 2-second, one-use authorization was disproved by the device log: activation at `39080.036483375006`, first full press at `39082.32026487501` (2.284s later) rejected as `not-authorized`, followed by four more rejected presses while the overlay remained active. Another activation lasted 14.702s. Controls activation is an overlay-lifetime callback, not one callback per light press.
- In 0.7.1, a currently active overlay authorizes repeated primary presses without a 2-second limit. After dismissal, at most one additional press is allowed within 300ms. Duplicate began events are still rejected until release, and a press timestamp before activation cannot use later authorization. A previously rejected held press is not captured retroactively; after release a fresh press can use the now-active overlay.
- Light-press activation or active-overlay presentation requests return to capture from Q, settings/editors/diagnostics, playback and zoom overlays. This clears unconfirmed drafts. UI dismissal and capture permission are separate: overlay events remain receivable while an app page covers the camera, but no capture is executed until the presentation is confirmed dismissed. A single full click during that transition can wait for the page; a queued burst is cancelled if released before return. Background/cancellation/settings changes clear pending capture. AF mode/settings changes on the capture page preserve an already observed active overlay without fabricating another physical light press.
- Single shot still starts on `.began`; bursts continue until release/cancellation even after overlay dismissal. Secondary events do not capture. MENU/playback, stop, background and cancellation revoke pending capture and cancel hardware bursts. Full-screen covers use `onDismiss` confirmation; missing window ownership never counts as a successful return.
- **Volume-down (and other primary sources) can still capture inside the authorization window.** Suppressing secondary capture does not promise normal volume behavior: the capture interaction overrides system button handling. Neither private APIs nor volume-change/timing identity guesses are used.
- The AF picker callback and `selectedIndex` updates share `sessionQueue`, as required by [Apple's selectedIndex contract](https://developer.apple.com/documentation/avfoundation/avcaptureindexpicker/selectedindex). Camera/UI and authorization state run on main. Late queued input predating lifecycle/settings reset is rejected.
- Share the last 200 events as JSON from MENU → 設定. It records app version, monotonic seconds, original input category, **unknown** source, event availability versus capture permission, transition/pending/busy state, gate state/deadline, requested actions and reset/decision reason. It contains no images and is not uploaded automatically. A photo action is a request, not proof of saved output.

### Validation boundary

Regression tests replay the five rejected device timestamps and cover repeated active-overlay presses, dismissal grace, stale ordering, held presses, transition-queued single/burst capture, interruption, secondary rejection, duplicates, legacy behavior and backward-compatible settings. UI event injection covers returning from Q drafts, menu editors, nested bird diagnostics, playback and zoom, including an immediate full click. Injection is simulator-only and is not physical gesture validation. The user supplied initial physical light-press evidence; the revised page-return flow, A+ availability, AF, source false accepts and burst-release latency still need device retesting. The 0.7.1 default-off policy is superseded by the user-approved 0.8.0 default-on policy above; do not claim Camera-Control-only capture.

