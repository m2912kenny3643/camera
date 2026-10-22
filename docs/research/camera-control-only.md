# Camera Control shutter without volume-button capture

Checked: 2026-10-22 (Asia/Taipei). Target: iPhone 17 / iOS 27; project deployment target remains iOS 18. No app code changed by this research.

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

## Existing app behavior

`R6Camera/UI/CameraPreview.swift:15` installs the single-handler initializer. Its `.began` branch calls `camera.shutter()` or `camera.beginBurst()` without source filtering; `.ended` stops the burst. Thus the documented volume-button events currently share the capture path. `updateUIView` only toggles the interaction globally through `isEnabled`. [Current implementation](../../R6Camera/UI/CameraPreview.swift)

No validated change to only that closure can distinguish Camera Control from volume down using the documented event object. Do not mark a primary-only rewrite as meeting the requirement.

## Implementation decision and remaining proof

The requested combination has no verified public solution in the evidence above. Either retain this requirement as unresolved until a supported API is identified, or explicitly revise the product requirement. Globally disabling/removing capture interaction would stop both volume-button captures, but it would also remove this app's Camera Control shutter handler; it is not full acceptance of the requested combination.

Do not infer button identity from audio-volume changes, timing, the zoom overlay being visible, or prior light presses. None of those is a documented event-source contract; they could cause volume-down to capture or cause a real shutter press to be discarded. Do not use private selectors, private notifications or hardcoded undocumented button raw values.

At the next macOS build, inspect the installed Xcode 27 SDK's public `AVKit.framework/Headers` for `AVCaptureEvent` and `AVCaptureEventInteraction`. Record the selected SDK version and any newly discovered declaration. If no public source/filter exists there, the limitation is confirmed against the actual compile SDK, not just documentation.

Physical acceptance must separately exercise: volume-up short/long press, volume-down short/long press, Camera Control short/held press in single/burst modes, app launch versus foreground capture, overlays open/closed, and interruption/cancellation. Acceptance requires **zero** photo/burst requests from either volume key while retaining the approved Camera Control behavior. Simulator tests or a successful build cannot establish hardware source separation.
# iOS 27 SDK verification

The actual Xcode 27 iPhoneOS public AVKit headers were printed in [build 39702346520](https://github.com/m2912kenny3643/camera/actions/runs/39702346520). `AVCaptureEvent` exposes phase and sound handling; `AVCaptureEventInteraction` exposes shared or primary/secondary handlers. No source-button identifier/filter was found. The user explicitly chose to retain the common hardware handler temporarily, accepting volume-button capture. This requirement remains unresolved, rather than being described as fixed.

