# Hidden business 10a candidate

Base: PR113 head f690cb7e0c7d1e04c64dc6a3cf6a8cfbb0b50473. This is an isolated, incomplete candidate, not a release or cloud hidden-business implementation.

## Protocol finding and bounded plan

Session schema 1 records only current owner, epoch, updatedAt, request and ack. It retains neither authoritative historical intervals nor a simulation checkpoint. The rules permit force takeover ten seconds after a request, before the sixty-second lease expires. Renewal of the same owner/epoch may succeed after lease expiry. Cached active status and a fresh renewal therefore prove no uninterrupted historical hidden interval.

The current proven interval set for cloud catch-up is empty. Its bounded catch-up plan is exactly zero seconds, with no pending debt, wall-clock accrual, economic award, replay, or timestamp migration. Repeating visibility, reconnection, renewal, or save loading cannot increase this budget. Cloud or unknown ownership gets zero hidden callback delta. Zero delta also bypasses service and staff work, preventing immediate business transitions on a rejected step.

The local IndexedDB adapter explicitly identifies itself; Firebase guests must explicitly report serverOwnership=false and have no account/recovery/conflict/busy gate. Only these guests can use delivered hidden callbacks of at most 0.25 seconds each. Longer callbacks are discarded in full. This is bounded callback progress, not elapsed-time catch-up. The transition frame is discarded in either direction; duplicate events do not reset the boundary. Existing manual Pause/Resume, editing, save recovery and account/session safety pauses remain gates. Hidden state never changes the Pause toggle or disables the subtree. The current local eligibility observation is checked again before each hidden business callback.

Visibility hide retains input cancellation and a best-effort save. Pagehide still uses the original suspended subtree and best-effort save: closing/navigation is outside this request. Native focus loss retains its existing input cancellation. No render loop, worker, or browser timer guarantee is introduced. Browsers may throttle or stop callbacks; the guest may make little or no progress while hidden.

## Necessary design for full cloud catch-up

### Player-facing limitation

Guest cafes can keep working while the browser delivers short game updates. Browsers may slow or stop those updates when you switch applications or hide the game, so hidden progress is limited and missing time is not recovered. Manual Pause still stops business.

For a signed-in account, business currently waits while the game is hidden. The connection or active status seen when you return cannot establish who owned the cafe throughout that time, so the game does not award hidden earnings or wages for it. Closing the page remains outside this candidate. This is a guest callback improvement, not full offline or account-mode background business.

### Minimum future protocol

Use three backend-controlled records, all scoped to uid/profile and fenced by writerId/epoch:

1. **Authority event ledger:** append-only `{sequence, serverAt, event, writerId, epoch, runId, expiryAt}` entries for grant, renewal, business pause/resume, handoff request, revocation and takeover. The backend writes the ownership document and event in the same transaction. A renewal after a gap starts a new interval; it cannot backdate or bridge expired/unknown authority. A handoff request closes the eligible business interval before early forced takeover. An incomplete ledger gives no settlement budget.
2. **Simulation checkpoint:** `{revision, digest, economyVersion, randomState, paused, operatingOpen, editing, consumedThrough, lastSettlementId}` alongside the cafe state. The hidden start uses the last acknowledged running checkpoint. Pending manual pause, account change or conflict cancels settlement until reconciled. Old saves without this checkpoint receive a new foreground baseline and zero historical credit.
3. **Settlement receipt:** an idempotency key `{uid, profileId, epoch, checkpointRevision, windowId}` plus `{intervals, seconds, beforeDigest, afterDigest, cursor, resultRevision}`. A backend transaction checks the current fence and checkpoint, verifies the complete ledger interval set, and reserves at most 60 seconds. Finish atomically CASes the result save, receipt and consumed cursor. Reservations must resolve before a writer transfer; failures/unknown acknowledgments are looked up by the same key before retry. A duplicate returns its original receipt and never repeats simulation or payment.

A foreground reconciliation consumes only the proven running intersections in at most 600 steps of 0.1 seconds through the existing economy, then applies the confirmed receipt once. Server-side validation must reject client-proposed intervals and arbitrary economy deltas; server execution or a validated deterministic simulation service is needed for authoritative rewards. These fields are a concrete future contract, not a new capability in this patch.

Implement a backend-authorized ledger keyed by account, profile, writer epoch and run identity. Record server-clock grant, request/pause/revocation and expiry boundaries; make those records immutable and available to reconciliation. Authority ends at the earliest safety boundary, even if a later renewal succeeds. Missing history, failed reads, account switch, takeover, conflict, expired authority and unknown time all truncate or reject the corresponding interval. A lease deadline alone is insufficient under the current early takeover rules.

Add a durable simulation checkpoint containing profile revision/digest, engine/economy version, deterministic random state, manual pause/open/edit state, consumed interval cursor and unique settlement ID. The server must atomically validate the ownership intervals and expected checkpoint, reserve a bounded budget (proposed maximum 60 seconds per reconciliation), and CAS the resulting checkpoint/save and consumed cursor exactly once. Duplicate settlement must return the existing receipt; uncertain transactions must resolve that receipt before retrying. Do not acknowledge or transfer a writer until pending settlement is resolved. An epoch/account/profile switch cancels the old run and loads the new authoritative checkpoint; it never replays old debt into the new profile.

Advance only the intersection of proven authority and explicitly running business intervals, using the actual service/staff/customer/payroll machinery in deterministic bounded slices (proposed 0.1 seconds, at most 600 slices). No separate coin/payroll formula. Discard overflow for this narrow bounded design; expose that policy to the player if adopted. Persist before accepting the cursor, and verify idempotent economy at transaction/crash boundaries. This requires a backend/protocol design review and emulator tests before any production rule changes. It is deliberately not implemented here.

## Validation and limits

### r3 boundary hardening, pending engine acceptance

Review against the actual browser lifecycle contract found that pageshow may arrive while still hidden. The DOM listener now preserves the hide-save latch in that case and fences a pagehide suspension until pageshow, whichever order visible/pageshow takes. Blur still only cancels input. Nineteen deterministic event-order assertions exercise the actual embedded DOM source. See [browser matrix](hidden-business-browser-matrix.md) for planned real-browser acceptance and source binding.

The local adapter marker now applies only to an empty observation from a bridge-free local vault. It cannot override a live cloud/account/conflict observation or a missing observation from an existing bridge. Eligibility is rechecked for every adapter before hidden economic callbacks; busy/update/retry transitions fail closed. Ownership mode must be an actual boolean. New policy and Main integration boundary cases are supplied, including the inclusive .25-second budget and immediate rejection above it.

The r3 engine changes have not been run: heavy engine/export/browser work is held during the parent's FPS measurement. The earlier engine result below belongs to frozen r2. Preserve both patches/receipts; do not treat r2's passing assertions as proof for r3.

Only in-memory/synthetic profiles were used. Seven lightweight Node/Python suites passed, covering actual DOM duplicates/pagehide order, session takeover/account races, disconnect/reconnect and conflict, legacy saves, compensation exactly once, and explicit counterexamples showing why active/renewed/leased state cannot authorize historical replay.

After the parent authorized focused engine tests, official Godot 4.6.3 passed the policy test (27 checks), economy revision suite (175 checks), and Pause/Main integration suite (1766 checks), totaling 1968 checks. The integration fixture includes actual hidden service/staff/payroll exactly once, rejected long gaps, manual/edit/recovery gates, cloud/unknown hidden delta rejection, and duplicate hide/show boundaries. All tests ran headless with separate generated profiles and disposable projects; the runner confirms the disposable fixture was removed. Each process reported a root certificate store diagnostic under the restricted environment; there were no script errors or assertion failures. No network test was required for these synthetic suites.

The first engine attempt stopped at the Windows Python runner's Unicode log encoding; its independent failed receipt is retained. The UTF-8 retry's independent summary and logs are in evidence/engine-r2. Exported browser visibility behavior, native app switching, rendering and FPS remain untested. The original patch and seven-suite receipts remain preserved separately from this documentation update.

No player saves, credentials, live Firebase rules, production services, merge, push or release were touched. All source edits are in this task's new clone. Repeat Godot validation only in a disposable project/profile and pause heavy tests during any announced hardware FPS measurement window; see the existing integration runner. Do not run the supplied economy test against the normal player profile.
