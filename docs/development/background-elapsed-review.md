# Open-page background profit candidate

Draft PR126 targets [0.1.11 background earnings](../roadmap.md#background-earnings-011). This is implemented candidate behavior, not merge or release acceptance. The historical simulation prototype is preserved in [its review record](../testing/background-elapsed-historical-review.md).

## Formula and scope

On a proven return: **eligible hidden duration × observed average net operating profit per second × 0.75**. The same-page rolling observation uses approximately the last 300 active gameplay seconds, requires at least 60 seconds and actual meal revenue, and includes paid, due and accrued payroll costs. Purchases, refunds, campaign credits and old-save balances do not become operating profit. The rate is frozen at hide. No history yields zero income.

Only a still-open page hidden by tab/application switching is eligible. Manual Pause, closed café, editing, intro, account/recovery pauses and page termination are excluded. Browser throttling remains real. A single private whole-wallet snapshot adds coins plus a persisted fractional remainder; customer, service and payroll simulation are not replayed. Old saves default the optional remainder to zero; invalid fractions or overflow reject the candidate.

## Proven authority and once-only settlement

Guest authority holds an exclusive Web Lock over the interval and uses same-page monotonic time and IndexedDB digest/profile/revision CAS. An account interval uses an immutable server-timestamp certificate tied to the original owner, epoch, anchor and exact baseline. Start/seal/consume transactions and rules couple the session, certificate and whole save. A later active flag or renewal alone proves nothing about past ownership. Changed ownership, requests/acks, conflict, disconnect or unknown proof grant zero replay. Normal 60-second session leases still protect ordinary writes; the separate certificate proves eligible intervals without inventing a client-only lease extension.

Before consume, a distinct durable elapsedPending stores the exact trial record, original writer/epoch and fence. It is never ordinary pending/uploading. All ordinary update, reload and snapshot paths reject protected intent. A dispatched transaction is awaited without a local timeout race. Late authoritative success installs/journals the exact canonical snapshot once and requires reload; uncertain outcomes remain blocked. Restart never re-runs seconds or uploads an old trial under a new epoch. Exact cloud trial digest consumes the whole snapshot; unrelated cloud data preserves baseline and trial in recovery. Baseline read alone cannot prove abort: the original transaction must first be terminally fenced. Rules changes are candidate source only and have not been deployed.

## Binding cancellation interface

`await client.cancelBackground()` and `LittleLeafVault.cancelBackground(callback)` return a receipt. Only `ok:true` AND `backgroundCleared:true` confirms the background fence cleared; it grants no account/session authority. `ELAPSED_UNCERTAIN` blocks UID changes until the exact pending snapshot is reconciled. Both a dispatched commit and a protected prepared journal return uncertainty. Guest commits use the same refusal.

Native binding calls `game.background_elapsed.cancel_for_binding(completed:Callable)` (use the actual controller property named in Main). It invalidates the background generation then returns the dictionary through the completion callback. Call before applying the binding-owned input freeze because stop restores previously held input; freeze immediately after initiating it. Binding owns its pause restoration and must still check save status, recovery, account/profile and permission gates. Duplicate in-flight native cancellation returns SAVE_BUSY. Existing stop remains a fire-and-forget lifecycle cancellation, never evidence of a terminal fence.

## Evidence and limits

Synthetic Node tests cover full 20-minute certificate duration, exact whole-save consumption, duplicate visibility/settlement, deferred start/seal/consume acknowledgement, offline/reconnect invalidation, listener cleanup, manual cancellation, old-save/recovery protections, takeover/account switch and ordinary Auth permission recovery. Focused actual Firestore SDK/emulator checks cover bidirectional rules and certificate fences. Headless Godot checks verify the formula, fractional carry, no customer/payroll replay, public-model isolation, bounded history, closed café exclusion and immediate account cancellation pause.

These checks use generated fixtures and disposable profiles. They do not establish actual signed-in browser acceptance, background rendering, FPS stability, long-soak qualification or production rules readiness. No original player saves, live Firebase rules or credentials are modified; no merge, release or deployment is authorized.

## Atlas source qualification

At 63422faa, official Godot4.6.3 GL Compatibility regenerated all three atlases for current main a5dd2b2 and this candidate in disposable profiles. Same-renderer Windows RGBA was identical 3/3; both have the same inherited differences from canonical cached output. All three cached PNG/import pairs are unchanged, and both imported-canonical suites passed 16 checks. Only the changed non-painter gameplay dependency bindings are refreshed; original canonical RGBA hashes and native producing-run provenance remain intact. This does not assert cross-renderer procedural/cache equality or replace the canonical art.
