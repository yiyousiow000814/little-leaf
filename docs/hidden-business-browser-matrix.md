# Hidden business browser acceptance matrix

Status: prepared, not executed. Revision r3 has lightweight DOM evidence; its changed engine guards still require focused Godot tests. The prior r2 1968-check engine result does not validate r3.

## Evidence and test isolation

Use an exported r3 source bound by Git tree, source SHA256, Godot 4.6.3 binary/template hashes, export hashes and test-fixture hashes. Use localhost and a new disposable browser profile for every account scenario. The fixture must create synthetic cafe state and expose sanitized counters for delivered callbacks, accepted simulation delta, service/staff/payroll, coins/served, manual Pause, browser_hidden, browser_suspended, process_mode and save revision. Observe actual model state; do not infer economics from animation or a status label. Record source hashes before and after. No player database, Google account, live Firebase, external paid service or production rule access.

For account cases use the existing synthetic account/session remote and isolated vault fixtures. Mock ownership/account/recovery transitions, including a contradictory snapshot after a local marker; a current active status or successful return renewal must never create a hidden budget. Record observed visibility/pagehide/pageshow events and their persisted flag. Do not infer that elapsed hidden seconds equal simulated seconds. No performance/FPS claim follows from this matrix.

## Desktop browsers available to provision after a measurement window

Run each row in current Chrome, Edge and Firefox on Windows, recording exact versions, viewport, renderer and profile path. Run Safari/macOS and mobile Chrome/Safari on separate available hardware later; mark unavailable combinations untested. Do not use the user's own applications to drive switching tests. Create and switch only task-owned browser windows/tabs; leave normal applications untouched.

| Scenario | Synthetic actions | Required assertions |
| --- | --- | --- |
| Ordinary tab hide, guest running | Switch to task-owned blank tab for 2s, 30s, 120s; return | Pause unchanged; subtree not visibility-disabled; only delivered callbacks <=0.25s advance; no hidden elapsed-time debt or return windfall; record browser throttling |
| Minimized task browser/window occlusion | Minimize only owned window, then restore | Record whether visibility actually changes; apply the observed event contract, never equate blur to hidden; no promised background rendering |
| Blur while still visible | Focus owned adjacent window without hiding canvas | Input previews/held gestures canceled; no save-on-hide, no implicit Pause, normal delivered delta |
| Manual Pause | Pause, hide, return, duplicate visible event, Resume | No service/staff/payroll/coins/served changes while paused; Pause remains until explicit Resume; no replay on Resume |
| Duplicate visibility events | Inject duplicate events around real hide/show | One best-effort hide save per visible-to-hidden episode; boundary not reset by duplicates; economic time processed once per delivered accepted callback |
| Long callback gap | Fixture delivers delta .25, .250001, 1, 60, 3600 while hidden | .25 accepted once for eligible guest; every larger delta wholly discarded; no service/staff/payroll call for rejected delta; no later queued debt |
| Pagehide without visible hide | Task-owned same-origin navigation with BFcache return where supported | Pagehide still disables subtree; visibility visible before pageshow cannot resume; Pause unchanged; close-save success not asserted |
| BFcache visible-first ordering | pagehide(persisted), visibility visible, pageshow | Remain suspended until pageshow; then restore exact previous process_mode; return boundary delta zero |
| BFcache pageshow-first ordering | pagehide(persisted), pageshow while hidden, visibility visible | Hidden pageshow does not resume or clear save latch; real visible return restores once; subsequent new hide saves once |
| Background initial load/restoration | Start synthetic page in hidden tab; pageshow(hidden), repeated hidden | Initial hide saves once; pageshow does not reopen hide-save episode; no visible notification until visibility becomes visible |
| Input quarantine across hide | Start touch/drag on canvas; hide/cancel; return with old ending/new start | No accidental purchase, placement or click; canceled contact remains inert until existing touchdrained contract confirms endings |
| Account active, then hidden | Synthetic signed-in active owner, hide, renew on return | Zero hidden service/payroll/reward; renewed/active state creates no historical credit; normal safety reconciliation precedes business |
| Unknown/account/conflict transition | Marked local adapter then accountChanged, cloud active, missing bridge observation, busy/conflict | Marker cannot override the observation; hidden delta zero even if preservation is busy; no old profile's time enters another profile |
| Disconnect/reconnect and takeover | Synthetic outage, reconnect same owner; second synthetic owner requests/forces takeover | No outage or takeover-gap credit, duplicate award or automatic writer ping-pong; fenced local pending progress retained by existing session fixtures |
| Old save | Fixture copies supported legacy bytes into disposable profile | Existing read-only import preserves source bytes; no timestamp/checkpoint migration invents hidden earnings; same economy revision/receipt behavior |
| Safety error | Synthetic unavailable storage, account switch, malformed recovery response | Recovery gate wins; no background economic mutation; no attempt to repair/reset production or player storage |

## Browser facts informing boundary tests

Pageshow can occur for background/prerendered pages and BFcache restoration; it is not evidence of visibility. [MDN pageshow](https://developer.mozilla.org/en-US/docs/Web/API/Window/pageshow_event).

Pagehide is not reliably dispatched in every mobile termination path. Preserve its existing suspension contract without promising termination saves. [MDN pagehide](https://developer.mozilla.org/en-US/docs/Web/API/Window/pagehide_event).

Visibility and focus differ, and browsers throttle background timers and commonly stop requestAnimationFrame callbacks. Record observed progress rather than promising background animation or one simulated second per wall-clock second. [MDN Page Visibility API](https://developer.mozilla.org/en-US/docs/Web/API/Page_Visibility_API).

## Pending commands

After the parent grants a measurement window, run only updated test_hidden_time_policy and test_pause_only in the existing disposable integration runner; include the policy suite through the task-owned runner driver. Save a new receipt directory rather than overwriting engine-r1/r2. If those pass, request/provision the isolated browser fixture and execute the matrix on supported available browsers. Source review and DOM permutations are not real-browser acceptance.
