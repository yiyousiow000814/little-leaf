# Silent autosave feedback

Routine browser save submissions and durable successes no longer replace the
player's current notice with “Saving…” or “Saved”. The unsaved flag, generation
queue, revision validation, storage writes and close/lifecycle protections remain
unchanged. Native saves already succeeded silently.

A genuine failure uses the existing single persistent status-warning row.
The error remains visible during an automatic retry and clears only when the
latest generation receives a valid durable acknowledgement. Repeated failures
do not reissue transient toasts. Recoverable failures ask the player to keep the
game/page open while saving retries; blocked failures point to Quick help and
do not promise an automatic retry. Settings may cover the warning, as with the
existing status channel; dismissing Settings restores the still-current failure.
Quick help retains the underlying details for a blocked save.

Compensation is a separate meaningful outcome: newly credited coins or a deferred
grant still receive their existing one-time notice, without a generic “Saved”
prefix. This patch introduces no retry/error-code changes or new feedback manager.

## Current-base verification

The original feedback patch was applied cleanly to main
`df51724faa58f7e6af5f8b69c807eac82ccade5f`. Only `scripts/main.gd` and
`scripts/cafe_web_save.gd` differ among existing production files. All other
main files, original assets, and licenses are preserved byte-for-byte. In
particular, the later startup-retry implementation and browser vault are retained.

Run `python3 tests/run_autosave_feedback.py` using Godot 4.6.3 and Python 3.
It imports an isolated project and runs these headless checks:

- Original feedback cases: silent submission/success, queued edits, persistent
  retry warnings, validation failures, non-durable acknowledgements, compensation
- Adversarial cases: empty staging, malformed callbacks, stale generations,
  invalid profile/revision/durability/credits, wallet mismatch, native failure and
  success feedback through a zero-I/O model
- Real-scene UI state: meaningful action notices survive routine autosaves,
  genuine failures remain actionable at three viewport sizes, retries retain the
  warning, Settings dismissal restores it, and blocked-save Help retains details
- Existing service-notice and HUD layout checks
- Existing startup-retry and starter-geometry/migration checks

All application profile directories are redirected into one disposable folder.
Web MEMFS staging is redirected beneath that disposable project. The real scene
uses `--visual-qa` and `--fresh-review`; regular native game saves are suppressed.
Only generated synthetic fixtures are written. No actual player save is accessed.

A deliberate malformed-JSON callback produces the expected Godot parse diagnostic;
the controller retains the error and the assertions pass. The starter-migration
suite requires a `geometry-saveguard` directory name, enforced by the runner.

## Verification limits

These are engine/controller and headless UI-state/layout-geometry checks, not
native-rendered pixel checks or browser validation. No real browser, IndexedDB,
player profile, current itch build, or original player save was used. The
historical capture script and original before/after evidence were created on the
older candidate base and have not been rerun on this rebased source.

The actual browser storage durability/recovery incident remains unverified.
No push, merge, export, release, or deployment is performed by this package.

## Compatibility with Welcome

The isolated real-scene regression runners use `--skip-intro` so their unrelated HUD and error-message interactions are not consumed by the startup overlay. The controller adversarial harness retains its zero-I/O unsuppressed native-save invocation. All 1,072 assertions pass on the cumulative Welcome + HUD + silent-feedback source. This is not actual Web/IndexedDB verification.
