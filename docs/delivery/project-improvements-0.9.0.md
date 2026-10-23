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

Pending Xcode 27 archive/tests and IPA source verification. Windows checks parse Swift syntax only; no local Swift typechecking is available. Real-phone tests remain required for physical shutter reception, permission/background transitions, Photos authorization/low-storage behavior, gallery peak memory/latency, bird inference latency and burst cadence under load.

GitHub waiting uses a local process polling completion every 120 seconds with only final output. Fetch job logs after completion and use focused failure excerpts only when needed.
