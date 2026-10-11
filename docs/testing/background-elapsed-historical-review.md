# Open-page business settlement candidate

This isolated candidate is based on e55c6a8838364ba1e731e45c457bd3589639516c, branch `fix/hidden-business-elapsed-review`. It covers hidden/frozen open pages and return. Closing/reopening is excluded. The versionless live idle-stall investigation is separate. No production rules, Auth grants, credentials, player saves or engine scheduler are changed.

On hide, a single token holds business simulation. On return, the existing service/staff/payroll path runs privately in 1/60-second steps, with at most 0.25 simulated seconds per replay turn. The public model is restored between turns. After the existing snapshot CAS confirms, the whole candidate is installed once. This work budget is not an income cap. There is no second reward rate, additive offline-income ledger, background-rendering promise or saved timestamp migration. Long intervals can take substantial time to settle; browser performance is not yet verified.

## Account authority and interrupted probe

The anchor is the exact server-confirmed owner/epoch/device/updatedAt with no request/ack. Renewal is held while the interval is open. At return, an existing rule-checked request transaction writes a unique private ID/requester and server timestamp only if the entire anchor is unchanged. Exact readback and exact-tag cancellation bind the end time and subsequent snapshot CAS stamp. The granted interval ends at the earlier of that marker and the original sixty-second server lease expiration. Expired tail, takeover, request/cancel/renew changes, unknown observed ownership, disconnect and account changes do not grant elapsed time.

This temporarily occupies the existing handoff slot. Its exact owner/epoch/device/anchor timestamp/private ID/requester intent is persisted in the same origin's localStorage before dispatch. Startup only clears that matching, unacknowledged tag in a guarded server transaction. Changed real requests are untouched; a matching changed/acknowledged tag remains explicitly blocked. Interrupted intervals are abandoned with zero replay. The slot interaction and cleanup contract still require independent review; no rules/schema change is implied.

## Persistent uncertain business transaction

Before cloud CAS, the existing account journal receives a distinct `elapsedPending` intent containing the exact trial record (profile, payload, revision and digest), base digest, original writer/epoch, commit server timestamp and token. It never enters ordinary `pending`/`uploading`; sync and old-runtime preservation cannot upload or overwrite it. Every pre-dispatch async stage and the actual CAS callback check captured claim identity/cancellation. A dispatched transaction is awaited directly rather than raced against a local timeout. Cancellation holds the claim and pauses the old model. A late successful receipt journals the exact confirmed record and requires reload instead of silently resuming stale gameplay.

On restart, an exact cloud trial digest installs that complete snapshot once. A cloud baseline read alone cannot prove abort. The original epoch must first be invalidated by a server-confirmed new epoch; then baseline means zero-credit abandonment. An unrelated cloud record uses conflict/recovery while preserving the actual journal entry. Recovery export contains that entry plus the exact baseline and trial records. An unconfirmed trial cannot be selected for a new-epoch upload; choosing the confirmed cloud snapshot requires a newer epoch and archives both original copies atomically. All ordinary snapshot writes, including update preparation and reload qualification, reject an active claim or unresolved intent before writing. Persisted seconds are never re-run, and the trial is never uploaded under a new epoch. Offline readback stays blocked. The exact-digest/new-epoch contract needs independent review and real SDK failure validation.

## Local guest authority

A named exclusive Web Lock is held over the whole open-page interval and private settlement. Ordinary new-client saves acquire the same lock. Duration uses the same page's monotonic clock; the full finite interval is retained. Existing IndexedDB digest/profile/revision comparison rejects a legacy or competing writer that changed the baseline. Unsupported Web Locks cannot establish elapsed authority and grant zero catch-up. Cancellation discards the token. IDB completion returns the complete verified save payload, including existing compensation planning, so the model consumes the canonical wallet without adding a duplicate grant.

## Focused evidence and remaining integration

Six synthetic Node checks cover account interval proof, production transaction fence, single settlement, cancellation/late acknowledgement, persistent lost-ack/new-epoch recovery and guest lock/CAS/reload. The existing compensation/inbox storage suite also passes, including old 0.1.8 receipts and lost acknowledgements. All are synthetic; no live Firebase writes were issued. The headless private-model test verifies original economy isolation, exact payroll time and split settlement across an existing wage boundary; its latest result is recorded externally.

Remaining: independent ownership/persistent-recovery review, one coordinated disposable muted browser flow using normal rAF for hidden/frozen return, long-interval responsiveness, and dependency integration with the Auth owner's current-main Web path migration. The guest vault's exact inline shell source is synchronized. Firebase modules are external packaging inputs, not embedded in this shell. No merge, release or deployment is authorized by this candidate.

## Independent review corrections

The 4129765 review requested two corrections: the shared update snapshot path could overwrite a protected intent, and unrelated-cloud recovery used a fabricated expected journal entry. The narrow recovery test now asserts rejected update leaves the journal unchanged, export retains baseline plus exact trial, trial selection is rejected, and cloud selection archives the actual entry. Cross-realm fixture values are normalized only for deep comparison; digests and record contents remain exact assertions. Browser acceptance and current-main integration remain pending.

The a9f4037 follow-up review found archive readers still required ordinary pending=true. Both readers now accept a fully validated pending=false entry with a separate elapsedPending intent. A focused test re-reads a cloud-choice archive, recovers through the legacy slot and exports the exact trial again; acknowledged baselines without either pending form remain rejected and untouched. No browser or engine workload was launched for this correction.

## Current-main integration

Integrated onto d2910b4 (merged PR128) using rename-aware dependency commits. Gameplay stays in game/, browser modules in platform/web/, and documentation in grouped directories. Auth boot changes add only the four elapsed bridge methods; real login handlers and qualified updater/rollback remain inherited from main. This does not establish new browser or engine acceptance of the integrated source. PR126 remains draft; no merge or deployment.
