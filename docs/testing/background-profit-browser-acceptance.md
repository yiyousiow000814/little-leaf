# Local native Web background-profit acceptance

Runtime source: `3b8a71401dbf8b9d51e6079ebccc19c0aa624c36`.
Official Godot 4.6.3 diagnostic export, fresh synthetic guest profile, localhost
only; no original save, account, hosting deployment or production rule access.

The initial headed-browser failure was reproduced independently of the game:
raw Chromium 151.0.7922.34 reported `document.hidden=true` for a focused pure HTML
page, another selected tab, and the first tab selected again. No visibility
events occurred. `document.hasFocus()` changed correctly. This desktop/window
condition prevents headed visibility acceptance; it is not evidence of a game
visibility regression.

The same raw browser with native `--headless=new` produced visible → hidden →
visible states and trusted visibility events when selecting two real tabs.
No visibility override, focus emulation, artificial animation frames, disabled
occlusion or background-throttling switches were used for this acceptance.

The actual native game then passed this narrowly bounded sequence:

- Save a synthetic open-cafe fixture, then inject explicit synthetic operating
  history into the confirmed current model. This is not observed gameplay income.
- Switch to the other tab, wait for the actual native interval to arm, deliver
  duplicate hidden notifications, and return after approximately 1.5 seconds.
- Assert exactly one canonical commit with coins and fractional carry matching
  frozen net-profit rate × proven duration × 0.75. Payroll, completed revenue and
  served count in the committed trial are unchanged; JSON payroll precision is
  compared within 1e-12.
- Deliver duplicate return notifications and assert no additional commit; reopen
  the guest adapter and verify its exact IndexedDB payload equals the receipt.
- Hide/return while manually paused and assert no additional profit commit.
- Arm another interval and call the real native `cancel_for_binding` bridge;
  receive `ok && backgroundCleared`, then return without another reward.

All eight focused checks passed; browser and HTTP server cleanup receipts are
true. This establishes local synthetic native lifecycle/guest settlement and
idempotency. It does not establish headed desktop rendering, signed-in Google
acceptance, deployed Firebase certificate rules, long background rendering or FPS.

The preceding exact-head CI run 38078626331 passed guard, all five native shards,
historical client, build, play, recovery and already-open-old compatibility. The
old-opened-after-new compensation fixture failed because its race assertion only
accepted `REVISION_CONFLICT`; real Web Locks now reject the losing contender with
`SAVE_BUSY` before its CAS. The focused repair accepts either rejection while
still requiring exactly one winner, one paid receipt, durable reload recovery and
no repeated compensation. Both deterministic and actual IndexedDB/Web Locks
storage suites passed after that repair. A fresh remote CI run remains required.
