# Focus behavior correction — 0.9.2 (13)

Compared with the local EOS R6 Mark III Traditional Chinese manual, pages 504–511 and 522.

- SERVO center fallback continues evaluating new observations and can acquire a subject entering the area. Explicit touch focus remains fixed.
- ONE SHOT retains its commanded subject geometry until a new acquisition or reset. A moving detection no longer makes the indicator imply continuous lens tracking.
- SERVO expansion initially commands the central cell; subsequent observations can acquire surrounding assistance candidates. This does not wait for or claim optical focus success.
- A subject overlapping an acquisition cell remains eligible even when its preferred eye is outside. The command uses an eligible eye or the center of the intersecting head/body region. Body identity geometry is retained. Full-area tracking can subsequently follow outside the initial area when enabled.
- Acquisition records the current observation time for loss-grace accounting.

These are software approximations. They do not reproduce Canon sensor AF cells, distance-based selection, optical focus confirmation, or constrain the iPhone sensor's AF search region. Blue remains commanded-position feedback, including ONE SHOT, rather than Canon's confirmed-focus colors. Hardware Camera Control behavior is unchanged.

Validation: Xcode 27 archive succeeded; 109 core, 126 iOS unit, and 7 UI tests passed. Local 45 Python checks and 72 Swift syntax parses passed. Successful run: https://github.com/m2912kenny3643/camera/actions/runs/40055304399 .

IPA source: `e936d7f4173ab761a70e145d6309371d6421a1ff`, version 0.9.2, build 13. Download: `build/output/R6Camera-0.9.2-unsigned.ipa` (30,093,665 bytes). SHA256: `854b0d513b69f3ccc930ed90645ea059933da83589b2a19a3ea3284b98540269`. Embedded source, version, model, notices, and app license verified; report: `build/output/focus-0.9.2-verification.json`.

The initial UI fixture incorrectly assumed a body overlapping the central point was empty because its eye was outside. Tests now distinguish empty detections from overlapping-body acquisition. A subsequent run hung while resolving a UI button and timed out; the identical source passed a full rerun. No assertions were removed to bypass the hang.

Real-device moving-subject entry after center fallback, ONE SHOT lens/indicator stability, expansion assistance, body/eye boundaries, and whole-area tracking on/off remain to be verified. Simulator injections do not verify physical Camera Control delivery.
