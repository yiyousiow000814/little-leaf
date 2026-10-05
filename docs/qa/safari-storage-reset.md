# Safari refresh reset investigation

Status: diagnosis in progress. No production fix or physical iPad verification
is claimed by this packet. Live is commit
`9110ebd9a2d6cbf4d2af303be0e244e660c0f7fc`; the candidate was inspected at
`c9344cc8498e6de56ebcd442a6e1e22daa219c05`.

## Reported behavior

The iPad Safari player refreshes and returns to a fully playable, brand-new
café, with no Recovery screen. Desktop refresh retains progress. The exact
iPadOS version, browsing mode, embedding context, play duration, and whether a
save completed before refresh remain unknown. Do not treat an iframe or private
browsing hypothesis as an established explanation.

## Source findings

- `web/little_leaf_vault.js` propagates open/read/validation errors as `ok:false`.
  `cafe_web_save.gd::_block_startup` pauses gameplay and suppresses writes.
  That recovery path does not match the clarified playable fresh-start report.
- Boot returns `source:"fresh"` only after reading a valid revision-zero
  authority record and finding no eligible legacy save. An entirely absent
  database installs a new identity; a previously created but never committed
  profile retains its identity at revision zero.
- A first write failure is a different path from a boot failure. Quota errors
  and ordinary transaction aborts leave the revision-zero authority unchanged.
  The controller records the error but permits gameplay/retries. On reload,
  that same profile correctly looks fresh because no gameplay was committed.
- Failed-save details are available in Help. The regular `state_badge` is hidden
  by the compact HUD, and these failures do not automatically open Recovery.
  A report of no Recovery therefore does not establish successful saving.
- `_ready` does not submit the first gameplay snapshot. Autosave waits more than
  15 active seconds; the intro returns before advancing that timer and can add
  6.5 seconds. Save-triggering actions can submit earlier. Hide/pagehide requests
  are asynchronous best effort, not guaranteed page-termination flushes.
- The vault waits for transaction completion, not request success, before a
  durable acknowledgement. Its transaction body has no asynchronous `await`.
  There is no transaction deadline, however. A synthetic missing completion
  callback leaves boot/save pending indefinitely. This is a resilience gap,
  not evidence that a real iPad transaction stalled.
- `durable:true` describes a completed storage transaction; it cannot establish
  that an ephemeral browser storage partition persists across sessions.

## Discriminating signatures

`tests/storage_reset_diagnosis.js` verifies both exact live-vault fixture and
candidate using disposable deterministic storage:

1. First write quota failure, then reload: fresh, revision zero, **same** profile
   identity; no committed payload was overwritten.
2. Completed first write, then same-storage reload: authority, original identity,
   exact payload restored.
3. A separate empty storage area: fresh, revision zero, **different** identity.

The fixture is not a browser implementation. It demonstrates distinct code
paths without selecting one as the player's cause. No original player data,
browser profile, or computer is accessed, and no site data is cleared.

## Browser diagnosis packet

`tests/safari_storage_browser.js` uses the official Playwright API and locally
fulfilled synthetic HTTPS `.test` origins. It does not contact itch, transfer
private data, grant storage access, or disable browser security. It pins the
live-vault SHA and verifies candidate shell embedding.

The separate `check-storage.yml` workflow uses pinned Playwright 1.63.0 with
official WebKit on Ubuntu and sandboxed official Chrome as a control. It tests:

- top-level and same-origin frame save/reload/reopen retention, required to pass
- cross-site frame child reload, parent reload, and a new page in the same
  browser context, recorded as observed retention or loss
- storage identities under two distinct top-level sites
- open denial and read abort: no fresh fallback and authority bytes unchanged
- write abort and quota failure: no durable acknowledgement, bytes unchanged
- delayed transaction completion: no acknowledgement before completion
- initial write failure followed by same-identity fresh reload

Cross-site loss is a browser-policy observation, not automatically a test
failure. A passing diagnostic run is **not** proof of game persistence on iPad.
This harness does not run Godot, use the real itch embed, restart a browser
against a persistent disk profile, reproduce iOS suspension, or access a
physical iPad. Those limits must remain in any release conclusion.

## Primary platform references

- [WebKit tracking prevention](https://webkit.org/tracking-prevention/):
  third-party IndexedDB is partitioned per first-party website and ephemeral;
  private browsing uses ephemeral sessions. This is a platform constraint, not
  proof of the friend's context. The seven-day inactivity rule does not explain
  an immediate ordinary refresh by itself.
- [WebKit storage policy](https://webkit.org/blog/14403/updates-to-storage-policy/):
  cross-origin frames have a separate partition, quota failures must be handled,
  and best-effort data can be evicted. Transaction completion alone is not a
  cross-session retention guarantee.
- [Playwright browsers](https://playwright.dev/docs/browsers) and
  [CI guidance](https://playwright.dev/docs/ci): official browser installation and
  hosted runner setup. Linux WebKit is not Apple's physical iPad Safari build.

## Safe information still needed

Ask whether the first session lasted more than 30 seconds and included a
save-triggering action, whether Help showed an unsaved error, the iPadOS version,
whether Safari was private, and whether the game was embedded or opened alone.
Do not request another destructive refresh, raw saves, clearing data, or
disabling privacy protections. These answers narrow the hypotheses but do not
replace physical-device verification of a final fix.
