# Temporary save diagnostic

Open **Settings → Log**. **Copy log** copies this session's bounded diagnostic
history. Copy it **before refreshing or closing**, then copy the new session's
log after reopening. Logs are kept only in memory and are never sent anywhere.
If clipboard access fails, the read-only text is selected for manual copying.

The log distinguishes these stages:

- `read_result`: browser storage supplied a source, opaque profile fingerprint,
  and revision. `read_accepted`: the game validated and loaded that result.
- `save_requested` / `save_validated`: requested and passed the existing checks.
- `save_submitted`: submitted and still pending; this is **not success**.
- `save_confirmed` (vault): IndexedDB completed the write transaction.
- `save_accepted` (controller): the game accepted the durable acknowledgement.
- `save_failure`, `read_failure`, `save_skipped`, and `save_queued` distinguish
  failures, suppression, and waiting behind another request.

A completed transaction does not guarantee a browser will keep storage forever.
Comparing the source, fingerprint, revision, and origin before and after a reset
helps identify what happened. The latest read remains in the header after older
history rolls off the 240-event limit. Native builds identify codec acceptance
separately and do not claim browser durability.

Only bounded event types, error categories, timestamps, app version, revisions,
and opaque fingerprints are recorded. Web context includes only the current
origin, top-level/embedded status, referrer origin if available, and a bounded
browser name/version. No save payload, wallet amount, full profile identifier,
URL path/query/hash, raw error message, credentials, or external telemetry is
included. There is no clear-save control or additional persistent storage.

This diagnostic preserves the shipped 0.1.8 save and recovery behavior. It is not
a fix for a reset and does not migrate, repair, delete, or replace saved data.
