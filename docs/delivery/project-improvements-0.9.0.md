# 0.9.0 — recovery, storage and gallery improvements

## Changes

- Bird model load/runtime failure enables the general body model in bird-only mode on subsequent frames. Status distinguishes body fallback from both models being unavailable. No artificial eye points are introduced. A runtime-failed dedicated model remains disabled for this controller lifetime; recreate the camera to retry loading it.
- SessionLifecycle owns a thread-safe start generation. Permission completions, queued session starts and UI publication must still match the current foreground intent; stop, inactive scenes and interruptions revoke old starts. No long session operation holds its intent lock.
- Existing 0.8.1 content-view receiver and shutter gate remain. Simulator diagnostics separately count injection actions and actual AVKit callbacks, helping distinguish a missed UI trigger from return processing. The earlier intermittent Q-return failure is a regression risk, not a proven hardware defect or a proven fix.
- PhotoLibraryStore now owns serial disk rendering, export bookkeeping, retry and confirmed deletion. PhotoJob delegate resource collection and PhotoLibraryExporter are separate modules. At most one Photos export runs at once; queued/in-flight files cannot be deleted through the App. Export options copy files, never move originals.
- A local atomic export ledger prevents repeating confirmed-success exports. Queued/in-flight exports found after restart become uncertain and are never automatically retried. Legacy photos have unknown export history. Retrying unknown/uncertain photos requires confirmation and can duplicate a library asset; exactly-once delivery across a crash and Photos transaction cannot be guaranteed. Failed bookkeeping writes block new export admission. No photos are automatically deleted.
- MENU settings show App photo count/bytes, device free space and export failures. Playback shows per-photo export state/error and confirmed retry/deletion controls. Capture storage errors retain whatever originals were successfully written; insufficient capacity can still prevent all writes and is reported.
- GalleryLoader serially downsamples to the display/zoom request (maximum 4096 pixels per edge), reads EXIF in the background and caches at most six entries with a 32 MiB NSCache cost limit. Cancelled queued loads skip decode; cancelled completed loads cannot replace the visible image. Zoom uses a higher-resolution display thumbnail; sharing still uses original files. NSCache limits are advisory, not a measured peak-memory claim.
- SettingsStore writes a version-1 envelope, accepts older bare current/C1–C3 payloads with defaults for missing fields, and preserves explicit shutter opt-outs and focus geometry. Corrupt, wrong-storage-type, Boolean-version and unknown-version records block overwrite. MENU provides explicit recovery: exact failed payloads are backed up under unique UserDefaults recovery keys, valid presets stay intact, and failed presets must be resaved. Recovery is not automatic.

## Sources and constraints

- [Image I/O maximum thumbnail size](https://developer.apple.com/documentation/imageio/kcgimagesourcethumbnailmaxpixelsize)
- [Photos file copy/move behavior](https://developer.apple.com/documentation/photos/phassetresourcecreationoptions/shouldmovefile)

Public API cannot reliably distinguish Camera Control from volume down. Controls activation is not a raw half-press event and may not repeat while an overlay is active. Injection tests never prove phone hardware delivery or prevention of Apple's Camera launch.

## Verification

- Source: `f4113bc5090cf685d1f8956524677d9c1882b960`; app **0.9.0 (11)**.
- [Xcode 27 validation run 39995362348](https://github.com/m2912kenny3643/camera/actions/runs/39995362348): iPhone archive succeeded; **101 core, 114 iOS unit and 5 UI tests passed**. New tests include lifecycle generation, fallback policy, versioned/legacy presets and invalid envelope protection, export dedup/restart recovery, original retention on render failure, deletion blocked during export, ledger write failure blocking Photos, thumbnail dimensions/EXIF and cancellation. UI includes the previous Q/MENU/nested/playback hardware-return injection test.
- Local checks: **45 Python tests passed**, **66 Swift files syntax parsed**, whitespace diff check passed. Windows has no local Swift typechecker; typechecking was performed by Xcode. Independent Standards and Spec reviews found and verified fixes for Boolean/missing schema versions, non-Data settings and export admission after ledger write failure.
- IPA: `build/output/R6Camera-0.9.0-unsigned.ipa`, **30,086,783 bytes**, SHA-256 `d4d42b13d67958c700c57e78fc96dd8443d40933436cf188b3355bdca63bd739`. Embedded version/build/source, app license, pinned bird model and notice hashes verified. All three downloaded artifact ZIP hashes matched GitHub's digests. Artifact series name remains `R6Camera-0.8-focus-areas-IPA`; embedded app version is 0.9.0.
- Local evidence: `build/output/project-improvements-0.9.0/diagnostics`, `build/output/project-improvements-0.9.0/screenshots` and `build/output/focus-0.9.0-verification.json`. Settings screenshot inspected: storage/free capacity and existing shutter controls remain readable within the scrolling menu. Gallery memory and speed have not been benchmarked on a phone.
- Existing orientation deprecation and non-Sendable capture warnings remain, matching the 0.8.1 baseline; no publish-during-view-update warning appeared. This release does not claim full Swift 6 strict-concurrency migration.

### Remaining phone acceptance

1. Camera Control: two-stage off/on, capture/MENU/Q/playback/nested pages, quick full press, repeated light presses, held burst/release and accidental system-camera launch. Export the event JSON on failure; real SDK count must change for real reception evidence.
2. Lifecycle: late first permission response, repeated foreground/background changes, interruptions and resume. Confirm old starts cannot reactivate the background session or restore an outdated UI state.
3. Storage: denied/granted Photos permissions, failed export then confirmed retry, paired RAW/processed capture, low disk space, and deletion while exports queue. Confirm original files survive and confirmed successful exports cannot be queued again. Unknown crash/legacy history still carries the documented duplicate risk on explicit retry.
4. Gallery/model: large HEIF/JPEG/RAW libraries, rapid paging/2× zoom with Instruments memory and latency measurements; bird load/runtime fallback, focus behavior and burst cadence under inference load. Automated thumbnail bounds and policy tests are not device performance measurements.

GitHub waiting uses a local process polling completion every 120 seconds with only final output. Fetch job logs after completion and use focused failure excerpts only when needed.
