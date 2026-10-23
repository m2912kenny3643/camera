# 0.9.1 — half-press selection and focus indicators

## Behavior

- Hardware Camera Control exposes one fixed `快門 / 對焦／返回` index item with a no-op action. It has no zoom, focus-mode or other sliding adjustment. It stays enabled in A+; the effective A+ focus policy still applies. Screen wheel, pinch and area dragging are unchanged. Apple requires a [nonempty index-title array](https://developer.apple.com/documentation/avfoundation/avcaptureindexpicker/init(_:symbolname:localizedindextitles:)); single-item overlay reception must still be tested on the phone.
- HUD, Q and MENU editors share an identity-based draft session. All bindings update that draft immediately. SET and valid light-press activation consume the same current draft once and apply only its control's fields. Back cancels. A replaced/closed editor cannot re-register, commit or close a newer editor. Tapping the already-open Q item does not invalidate its session.
- A valid light-press proxy commits before requesting page dismissal and focuses after capture-page readiness. The scoped commit uses the original validated event time for synchronous shutter resets, allowing an already-queued immediate full press. Unrelated settings changes, stop/background and cancellation retain their normal invalidation boundaries. Pending single capture, held-only burst and release/cancel behavior remain unchanged.
- Destructive/reset/recovery/calibration/export dialogs are dismissed on return without confirming their actions. Only an actual registered settings editor supplies a draft. Native dialog input delivery still needs device validation.
- Seven non-whole focus areas keep their white area frames before acquisition. A selected subject remains blue; when acquisition actually commands area-center focus with no candidate, the previously omitted `areaFocusPoint` now displays a blue 36-point square at that normalized image coordinate. Blue indicates a selected point/subject, not optical focus confirmation. Whole-area fallback display is unchanged. MF hides AF indicators; region/AF changes, unlock and stop clear old point state.

## Validation

Pending Xcode 27 archive/tests and IPA/source verification. Tests target editor identity/latest draft/field isolation, cancelled/repeated callbacks, seven-mode center fallback in ONE SHOT and SERVO, subject/MF/whole-area display, single-item control construction, controller commit + queued full-click timing, burst release and stop rejection. UI tests now expect selected Q/MENU drafts to persist after light press and cover HUD/Q focus-area application, Back cancellation and center-blue-frame visibility.

## Phone acceptance

1. Slide the hardware key in each mode: no focus, zoom or settings change. Confirm the single-item overlay still activates reliably in A+, MF and other programs.
2. Select options in HUD/Q/MENU, light press to apply/return, then immediately fully press. Reopen to confirm the chosen value, including flexible-area geometry and drive/focus mode.
3. Verify blue frames with and without a detected subject in every non-whole area, moved regions and ONE SHOT/SERVO; MF must not drive AF or show AF blue frames.
4. Confirm Back cancels, SET commits, nested/destructive dialogs only dismiss, rapid editor switching cannot apply an old draft, held burst stops on release, and foreground/background cancels stale events.

The public overlay callback is not raw pressure and may not repeat while already active. Public API cannot reliably distinguish Camera Control from volume down. Injected inputs are not hardware reception evidence. If the fixed control proves unstable, retain the diagnostics and do not restore functional sliding or claim the half-press route works reliably. GitHub build waiting remains a local 120-second completion poll with final output only.
