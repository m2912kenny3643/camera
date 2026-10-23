# 0.8.0 — two-stage shutter routing and focus areas

## Approved behavior and implementation

- Two-stage hardware shutter defaults on for new/missing/reset settings. Explicit saved false remains false, including C1–C3. Unsupported controls fall back to the shared hardware shutter on the capture page.
- One `AVCaptureEventInteraction` is owned by `HardwareCaptureReceiver` and attached to the camera scene's UIWindow, rather than the preview removed by a full-screen cover. Lifecycle changes synchronously update admission; stopping/backgrounding detaches the receiver. Window changes revoke authorization. Destruction removes the window-owned interaction.
- Light-press **overlay activation** dismisses MENU, Q, playback, nested presentations and magnification, then focuses. A valid primary press during return queues one single shot; a burst starts only if still held when return completes. No capture while the UI transition is unconfirmed. The active-overlay/repeated-press behavior and 300 ms dismissal grace from 0.7.1 remain.
- Focus areas: spot, point, four-point expansion, surrounding expansion, flexible zones 1/2/3, whole area. Whole area is the default. A+ forces whole area without erasing personal settings; MF stores the region but never requests AF.
- The HUD, Q and AF MENU share glyphs, values, and SET/back draft semantics. Tap selects a target inside the area; drag the area frame to move it; two fingers still zoom. The zone editor provides width/height, center and reset. Each flexible zone retains its own geometry.
- Area masks constrain acquisition; expansion prioritizes the central cell. Half-press acquisition picks a fresh eligible candidate, with existing eye/head/body preference. Empty acquisition uses the region center with SERVO/ONE SHOT behavior preserved. Existing user-selected target/fixed point has priority.
- Whole-area SERVO tracking defaults on: acquisition starts within the area, an existing lock may continue outside. Off applies the region limit with the existing missing-target grace; no automatic switch to a bystander. Region/policy changes invalidate configuration/epochs and clear selection. The bird fast lane also refuses out-of-area focus when region tracking is restricted.

## Phone adaptation, not Canon sensor emulation

The local EOS R6 Mark III TW manual pp. 504–511, 521–522 and 587 define the eight areas, whole-area SERVO switch, movement and flexible sizing. Phone regions use top-left normalized image coordinates. Spot width is 2.5% of image width, single-point 5%, expansion a three-cell-wide 15% mask (five/nine cells). Defaults assume the app's landscape 4:3 image: flexible 1 is 30%×40%, 2 is 20%×60%, 3 is 60%×25%. These are app acquisition masks, not measurements of Canon AF cells. Geometry is clamped inside the image.

The app chooses software candidates and supplies AVFoundation point-of-interest coordinates. It cannot restrict the phone's underlying sensor AF array to a Canon-style hardware zone, reproduce Canon distance-based selection, or certify physical focus success by drawing a colored box.

## Evidence and unresolved hardware limits

Apple's [capture-event API](https://developer.apple.com/documentation/avkit/avcaptureeventinteraction) applies to foreground apps actively using the camera. Disabling its interaction restores system hardware behavior. [Full-screen presentation](https://developer.apple.com/documentation/uikit/uimodalpresentationstyle/fullscreen) can remove the presenting view. The previous implementation attached its interaction to that preview: this is the code-supported explanation for MENU losing events, **not a reproduced physical-device diagnosis**.

Public primary events cannot reliably distinguish Camera Control from volume down. Overlay activity is not raw half-press pressure and does not necessarily emit a new callback for every physical light press. During authorization, volume down can still shoot. No private key interception or guessed event source is used. An arbitrary physical half-press while the same overlay remains active cannot be promised to return from MENU.

Diagnostics export host/scene identity, receiver attachment/enabled state, scene/session availability, capture/covered/returning page state, event/time and admission reason. `source` remains unknown. Simulator injection checks window attachment before injecting, but does not prove the OS delivers physical events to that window.

## Required physical-device acceptance

Use iPhone 17 / iOS 27.0.1 and keep a diagnostic export for each failure:

1. From MENU, AF editor, nested bird diagnostic, Q, playback, share/confirmation UI and magnification: activate Camera Control, confirm return to live capture; test immediate full press during and after return.
2. Repeat fresh full presses after 2, 5 and 15 seconds of overlay activity; verify single press, release and held H/H+ burst behavior. Release/cancel/background must stop new burst requests. No system Camera launch while the receiver should be active.
3. Enter MENU while the control overlay is already active; test a second physical light press. Record whether iOS sends any new controls delegate callback. The app cannot synthesize an absent public event.
4. Start dragging with one finger, add a second finger to pinch before releasing, then release both: a cancelled drag must not commit. Verify a fresh one-finger drag after the pinch. Move and resize all areas near each image edge; tap inside/outside, acquire central vs surrounding subjects, compare whole-area tracking on/off, eye/head/body fallback, occlusion and stale inference. Verify actual lens behavior in SERVO, ONE SHOT and MF.
5. Check explicit opt-out, unsupported-device fallback, background/foreground and reset/preset persistence. Confirm authorized volume-down ambiguity remains documented.

If physical overlay routing remains unstable, disable capture admission for the failing return flow, retain diagnostic evidence, and report the limitation rather than claiming success. Device acceptance is pending until measured; automated view-hierarchy and injected-event tests do not close it.

## Validation status

Pending Xcode 27 compile, core/iOS/UI test results and installable artifact verification. Windows has no Swift/Xcode; local syntax parsing is not type checking. This section will be updated with the actual run and artifact evidence.
