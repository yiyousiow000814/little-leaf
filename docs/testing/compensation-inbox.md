# Compensation Inbox regression guide

The Inbox is a view of verified, retained authoritative Web campaign receipts.
It does not award coins, create receipts, import saves, or write preferences.
The centered mailbox shows scrollable envelopes with a title, delivery date and
unread dot; its heading and Back button remain visible. Opening an envelope
shows padded letter paper, a salutation, concise truthful reason, original paid
amount/status and the Little Leaf sign-off. All player-facing copy is English.
Native builds have no corresponding authority; native tests inject synthetic
snapshot data and must not be described as browser-persistence proof.

## Data boundaries

- `snapshotJson()` is a serialized copy produced after verified startup or a
  completed durable transaction. Boot and commit acknowledgements carry the same
  projection. The Godot cache accepts the loaded identity/revision before use.
- Amount, grant revision and time come from the immutable receipt. Static English
  copy may name known campaigns; unknown or retired IDs remain visible with
  neutral copy. Ordinary autosave revisions never change a receipt's read key.
- Wallet-cap eligibility is reconstructed with the existing verified planner. It
  appears separately as an unpaid status, without a fabricated delivery date,
  unread dot or letter. A later durable paid receipt becomes a new letter.
- Letters disappear at age >= 14 * 24 real hours, based on immutable `grantedAt`.
  Retention is independent of game speed, pause and days spent away. The Godot
  view refreshes on open, source changes and real-second ticks, so an open letter
  also disappears when it expires. Expiry never changes the WebSave source cache.
- Every valid 0.1.8 receipt already requires `grantedAt`; format 1 has no receipts.
  There is no timestamp-free legacy fallback or delivery-date reset on reload.
- The existing independent localStorage read keys remain under
  `little-leaf.inbox.read.v1/`, scoped to profile/campaign/grant revision. Exact
  `1` means read. Expiry deletes only the read key of the exact expired receipt
  supplied by the verified snapshot. Other profiles, revisions and unrelated
  browser keys are preserved.
- Disposable `little-leaf.inbox.display.v1/` metadata stores a per-profile
  wall-clock high-water and independent receipt expiry markers. This prevents
  a backward clock or stale tab from reviving an expired letter while metadata
  is retained. A future-dated receipt uses one persisted first-seen display
  anchor, bounding its mailbox stay to 14 days; its original `grantedAt` is never
  altered. Append-only timestamp keys preserve the earliest anchor when two tabs
  first see the receipt concurrently. This rare fallback is disclosed in the mailbox.
- This is a device-clock policy, not a trusted server clock. A forward clock jump
  can expire letters early. Deleted, denied or full localStorage can reset clock
  protection after reload, with an inline notice for denied/full storage; expiry
  and read state still work in the current session. Neither metadata loss nor
  retention can regrant compensation because authoritative receipts remain.
- State is bounded to 2048 session acknowledgements/expiry/future anchors, 16
  cached profile clocks, 2048 stored read keys and 4096 display metadata keys.
  Expired flags and future anchors are retained within that bound because
  deleting them could revive mail under a corrected device clock.
- Review flags and progress-write suppression disable marker persistence. No
  original legacy bytes, authority checksums, receipt fields or save formats are
  changed by Inbox interaction.

## Checks

1. `node tests/compensation_inbox_storage.js` runs the production scripts against
   the explicit deterministic async transaction fixture. It includes the exact
   shipped 0.1.8 writer so paid history is tested without writing with the new code.
   This is synthetic storage-model evidence, not real browser evidence.
2. `test_inbox_save_cache` and `test_compensation_inbox` are registered in the
   standard disposable engine suite. They cover queued acknowledgements, repeated
   views, selective read status, profile separation, Settings return, Escape,
   outside-touch release ownership, keyboard focus, popup exclusivity, safe
   insets, long lists and narrow/short viewports. They also cover letter padding,
   a fixed footer, exact expiry of an open letter and backward-clock behavior.
   `--capture-dir=<directory>` enables native screenshots in the UI test.
   Native screenshots require a working display and remain synthetic-only.
3. The normal Web CI job freshly imports the exact source, runs the full engine
   suite, exports it, then runs `compensation_inbox_browser.js` under Xvfb with
   Chromium's sandbox enabled. Ubuntu 24.04 CI selects the runner's installed
   stable Chrome channel, which has the supported AppArmor sandbox profile;
   it never disables sandboxing or changes host security settings. The evidence
   records the selected channel, actual browser version and pinned Playwright
   1.63.0 version. Local runs default
   to bundled Chromium, or can set `PLAYWRIGHT_CHROMIUM_CHANNEL=chrome` when
   stable Chrome is installed. The browser test uses new disposable contexts and
   a localhost-only fixture server. It runs the same suite on real IndexedDB and
   localStorage, seeds only synthetic history, starts the actual export, opens
   Inbox via layout points from the exact engine test, reads a detail and reopens
   the modal, comparing authoritative records byte-for-byte. The official
   `--time-scale 0 -- --skip-intro` engine launch arguments remove ordinary autosave timing races
   without replacing the vault or UI path. A subsequent browser reload verifies
   persisted read status, wallet and receipt; its normal page-hide save may
   legitimately advance the progress revision. It saves screenshots and
   source/hash evidence before the artifact upload step.

   The launch helper binds the actual shell instance after its original feature
   check returns and before `startGame` runs. Godot 4.6 SafeEngine deliberately
   creates a different prototype for every instance, so a throwaway instance
   cannot supply a shared startup hook. The helper returns feature results and
   the real startup return value unchanged; it adds only the official test
   arguments. A regression executes the exact exported JavaScript with Wasm
   startup stubbed, checking both supported and missing-feature results and
   per-instance isolation. CI retains its report, the export/template hashes,
   and the separate real-browser launch and storage evidence.

   Intro is skipped through its existing command-line option, matching the
   native coordinate fixture: a zero simulation clock cannot finish the intro.
   Every Settings/list/detail step requires screenshot-visible text before the
   receipt assertions. Detail acknowledgement uses a bounded persisted-state
   wait, and failures retain the current screenshot and exact stage. No input
   signal or read marker is invoked directly by the test.

Example after the normal engine suite and Web export:

```
PLAYWRIGHT_MODULE=/path/to/playwright xvfb-run -a node tests/compensation_inbox_browser.js \
  --web-build /path/to/web \
  --layout-report /path/to/engine-evidence/test_compensation_inbox-result.json \
  --output /path/to/browser-evidence
```

The browser requires a supported sandbox and WebGL stack. A denied browser
launch, unavailable display/WebGL, fresh import failure, or failed screenshot is
an unresolved gate. Do not disable the sandbox, add unsafe GPU flags, or treat a
cached native run as an exported-Web pass.
