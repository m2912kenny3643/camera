# Hardware shutter 0.7.1 (build 8)

## Device evidence and cause

The user confirmed that light pressing worked and supplied a hardware event export. At monotonic time `39080.036483375006`, the overlay became active; the first full press at `39082.32026487501` was 2.284 seconds later and the old 2-second authorization rejected it. The next four full presses were also rejected while the overlay remained active. Another activation lasted 14.702 seconds, confirming that these callbacks follow overlay lifetime rather than each physical light press.

The separate H-mode burst sample contained 5 successful HEIF photos, measured 2.0103 fps, P95 relative interval deviation 1.0213%, no blocked reasons or rate reductions, and actual dimensions 4032×3024. It lasted about 2.32 seconds, so `tenSecondCadencePassed=false` is appropriate; it does not establish ten-second stability or explain the shutter's `not-authorized` rejections. No burst rate/image-quality policy was changed here.

## Changes

- Active overlay: repeated full presses remain authorized without the former 2-second or one-use restriction. Dismissed overlay: one final press within 300ms. Duplicate began events remain blocked until release; pre-authorization events cannot use a later activation. An unprepared held press is never retroactively captured, but the next fresh press can use the active overlay.
- Light pressing returns from Q/drafts, MENU/editors/nested bird diagnostics, playback, zoom and presented child UI. Unconfirmed drafts are discarded. The camera continues receiving controls events while an app page blocks capture; capture permission is restored only after the UI return is confirmed.
- A valid single click during return waits until dismissal, even if released first. A waiting burst starts only if still held. Cancellation, settings changes and backgrounding clear pending capture. Active-overlay evidence can survive settings changes on the capture page without pretending a new physical press occurred.
- Cross-modal window ownership is retained weakly. Full-screen covers use SwiftUI `onDismiss` to signal readiness; missing ownership or background callbacks never count as successful return. Simulator-only injection exercises the same controller path but never runs on a real device.
- Event reports include app version, original input, unknown source, event availability, capture permission, busy/return/pending state, and explicit reset reasons. The experiment remains opt-in; volume-down and other primary sources can still capture while the overlay authorizes input.

## Verification

- Local Python suite: 45 tests passed. Swift syntax parsing and diff whitespace checks passed.
- Regression cases replay the five rejected timestamps and cover long/repeated activation, held-event ordering, 300ms expiry, covered-page rejection, transition-queued single/burst capture, release/cancellation, lifecycle reset and legacy behavior.
- Added a simulator UI test returning from Q with an unconfirmed choice, menu editor, nested diagnostics, playback and zoom, with immediate full click queued during each return.
- Separate standards/spec reviews passed after fixing stale authorization, window ownership and background-dismissal issues.
- First CI source `8dc6d7ea034be8b8a6a6152a2d448800ec4ae784`, [run 39939642555](https://github.com/m2912kenny3643/camera/actions/runs/39939642555): 85 macOS tests, 91 iOS tests and device Release archive passed. The new UI test failed before exercising return because its simulator-only trigger overlapped Q; the failure hierarchy showed a mock shot count of 1 immediately after tapping Q. The trigger was moved away and a frame non-overlap assertion was added. All three existing UI tests passed. Final rerun and IPA verification are pending.

## Device retest still needed

The supplied device log validates the old failure mechanism, not the revised binary. Retest light press from MENU/Q/playback and nested pages, including when the native overlay was already active; the system must emit an activation/presentation callback for the app to observe a new gesture. Test waiting longer than 2 seconds, repeated full presses, quick half→full transitions, release during return, AF/MF, backgrounding and volume-key false accepts. These remain overlay proxies rather than raw pressure/source detection.
