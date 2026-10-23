# 0.8.1 — restore capture-event content hosts

## Report and evidence

The user physically tested 0.8.0 and reported that full presses launch Apple's Camera with two-stage shutter both on and off; light presses also stop producing the expected overlay response. The user confirmed live preview continues updating before the press. This points to capture-event delivery rather than the two-stage authorization gate, but no event export is available yet.

0.8.0 moved the interaction from the working preview view to UIWindow. Its tests proved installation and enabled state, not OS event delivery. That approach is withdrawn. Apple's [AVCaptureEventInteraction example](https://developer.apple.com/documentation/avkit/avcaptureeventinteraction) attaches the interaction to a view controller's content view. The documentation does not establish that any arbitrary UIWindow installation will receive hardware events. The user's report is the evidence for reverting the window strategy; this is not a claim that Apple documents a universal UIWindow prohibition.

## Change

- Restore the capture-page interaction to PreviewSurface, the actual content-view location used before 0.8.0. UIWindow remains a scene identity/dismissal reference only; the receiver rejects it as a capture host.
- MENU, playback and nested bird diagnostics register their own ordinary content UIView. One interaction transfers to the last registered host still attached to the same scene window. Disappearance/dismantling removes the host and restores an eligible earlier host. Same-scene handoff preserves the shutter state; changing scene/window revokes authorization.
- Registration/unregistration runs after SwiftUI mount transactions. Cleanup preserves weak controller ownership and retains a dismantled host only until its queued unregister completes.
- Keep default-on/explicit-opt-out, AF areas, focus policy, primary/secondary routing, active-overlay authorization and dismissal grace unchanged.
- Published diagnostic records keep the exported JSON current even when no photo is produced. `receiverHostBound`/`receiverHostRemoved` describe installation, not gate resets or physical input. `receivedEvents` counts only the actual AVKit handler invocations; simulated controller inputs do not increment it. It counts phases, not photos or physical clicks.

## Verification and physical retest

Automated tests must assert a normal content-view owner, no interaction on UIWindow, a single interaction after host handoff/rebind, detached-host removal, cleanup and zero real delivery count without an SDK callback. UI injection must verify the named preview/menu/playback/nested host before each simulated input. None of these substitutes for an iPhone hardware event.

Retest in this order on the user's iPhone:

1. Turn two-stage shutter **off**, return to live capture and fully press once. Verify the photo stays in R6 Camera. This isolates basic AVKit routing from overlay authorization.
2. Turn it **on**, return to capture, light press and then full press. Check the event export for controls activation and actual primary phases. Volume down can still produce primary events; source remains unknown.
3. Repeat from MENU, Q, playback and nested diagnostics. Test a fast full press during return, repeated presses and burst release.
4. Retest native share/confirmation UI separately. A content host being installed behind native presentation does not prove that iOS delivers events through it. An already-active controls overlay may not emit a new callback on each light press.
5. If a press still launches Apple's Camera, return to R6 Camera and share MENU → 設定 → 分享硬體快門事件 JSON. Include the receiver status shown there. An unchanged `receivedEvents` with live preview distinguishes absent SDK delivery from a gate rejection; the JSON must be read together with the recorded session/scene/host state.

Do not label the physical regression fixed until the new build receives real events on the phone. Public overlay callbacks still are not raw pressure events and cannot reliably separate Camera Control from volume down.

## Build evidence

Pending final Xcode 27 validation and IPA/source verification. Physical-device verification remains pending.
