# Focus behavior correction — 0.9.2 (13)

Compared with the local EOS R6 Mark III Traditional Chinese manual, pages 504–511 and 522.

- SERVO center fallback continues evaluating new observations and can acquire a subject entering the area. Explicit touch focus remains fixed.
- ONE SHOT retains its commanded subject geometry until a new acquisition or reset. A moving detection no longer makes the indicator imply continuous lens tracking.
- SERVO expansion initially commands the central cell; subsequent observations can acquire surrounding assistance candidates. This does not wait for or claim optical focus success.
- A subject overlapping an acquisition cell remains eligible even when its preferred eye is outside. The command uses an eligible eye or the center of the intersecting head/body region. Body identity geometry is retained. Full-area tracking can subsequently follow outside the initial area when enabled.
- Acquisition records the current observation time for loss-grace accounting.

These are software approximations. They do not reproduce Canon sensor AF cells, distance-based selection, optical focus confirmation, or constrain the iPhone sensor's AF search region. Blue remains commanded-position feedback, including ONE SHOT, rather than Canon's confirmed-focus colors. Hardware Camera Control behavior is unchanged.

Validation: pending Xcode 27 build and regression run. Real-device moving-subject, body/eye boundary, and lens behavior require verification.
