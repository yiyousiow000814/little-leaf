# Post-decoration service guidance

The old fresh-start card appeared on launch, needed a “Got it” dismissal, and
was permanently removed as soon as Decorate was entered. This change removes
that separate card and shows its full, price-aware copy through the existing
three-second status notice only when the player finishes Decorate.

The existing status channel owns wrapping, safe-area placement, fade, modal
suppression, accessibility and interruption. There is no new timer, queue or
per-save setting. A new completed visit to Decorate starts a fresh notice;
refreshing the UI, loading a café or closing a popup cannot replay it.

## Verification

Run `python3 tests/run_service_notice.py` with Godot 4.6.3. The real-scene checks
cover fresh launch, entering and exiting Decorate, automatic expiry, repeated
visits, re-entry interruption, Settings overlap, loaded-café behavior and the
existing recovery guard. It also exercises startup-retry resume against the removed
starter card. The obsolete resume-time visibility assignment is removed; normal
UI synchronization still follows. Optional `--rendered` captures the real native window
under a working display with a disposable save profile.

The change was also rendered on Linux with Godot 4.6.3 / GL Compatibility.
Before: launch card and manual button visible. After: no launch card, full copy
shown after Done, then gone without input. Evidence and test logs are preserved
separately; no real player save or generated export is committed.

This source change does not deploy the game.
