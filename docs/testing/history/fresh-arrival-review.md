# Fresh arrival review — developer evidence

## Conclusion

Both the exact submitted 0.1.9 source (`11c1f8d904b0c4c9a2565cbd557d1552b4ba9401`) and frozen 0.1.10 source (`dd48fd9cc5f34f7ff84e6c87666c574c19e5c4b1`) naturally admit, serve, and collect payment from the first guest. A permanent native arrival failure was not reproduced. A serious first-impression delay was reproduced: the first guest starts at pavement z=82 and walks at 1.5 units/second, largely outside the default view, for nearly a minute.

This is a demonstrated contributor to the report, not proof of the reviewer's actual browser state. No hosted CrazyGames session, reviewer profile, actual SDK fault, or submitted ZIP execution was inspected.

## Method

`tests/run_observe_fresh_arrivals.py` copies the requested source to a disposable project and gives it empty isolated HOME, XDG, and application-data directories. `observe_fresh_arrivals.gd` instantiates the ordinary Main scene script and lets normal engine frames run in wall-clock time. It does not call model tick, spawn guests, change speed, force service phases, reset arrival timers, or assign tables. Default intro is untouched. Control variants send actual GUI mouse press/release events.

Run examples:

    python3 tests/run_observe_fresh_arrivals.py --project /path/to/source --output /tmp/new-arrival-run
    python3 tests/run_observe_fresh_arrivals.py --output /tmp/new-skip-run --scenario skip --until spawned
    python3 tests/run_observe_fresh_arrivals.py --output /tmp/new-controls-run --scenario controls --until spawned

Use a new output path every time. The default run ends at the first genuine payment, with a 180-second failure bound. The shorter variants explicitly stop at a natural guest creation rather than claiming a full service pass.

## Measured results

All times below are seconds since ordinary Main startup, at 1360×880 and 1×. The projection event means the first guest's feet enter the play rectangle; it is not a claim of the exact first visible pixel.

| Source / execution | Natural spawn | First play-rect entry | Seated | Order taken | First +200 payment |
|---|---:|---:|---:|---:|---:|
| Submitted 11c1f8d, native headless | 10.66 | 58.05 | 66.51 | 70.60 | 148.25 |
| Frozen dd48fd9, native headless | 5.14 | 52.54 | 60.99 | 65.07 | 142.83 |
| Frozen dd48fd9, actual cloud desktop rendering | 6.31 | 53.77 | 62.19 | 66.26 | 144.41 |

Both untouched headless runs and the rendered run passed 9 functional assertions. The submitted run emitted one nonfatal polygon triangulation error from `far_overlay_paw` near payment; the guest still completed payment. Do not describe that submitted engine log as error-free. No such error was observed in the frozen headless log.

Real screenshots from the rendered frozen run show staff and ambient street pedestrians at 10 and 30 seconds, but an empty café and no visible real arrival indicator. The first guest is clearly visible at the far-left pavement edge at the projection event, then at the table, and the actual +200 earnings cue appears after checkout. All original gameplay scripts in that render project were byte-identical to dd48. Only the observer scene and unique generated custom profile setting differed; its startup assertion confirmed no existing primary save.

## Controls and gates

- Both original sources start Open, unpaused, not decorating, with normal starter furniture and staff. No fixture intervention is needed to open the café.
- The submitted intro freezes simulation for approximately 6.5 seconds. Frozen dd48 starts live motion after its first title second, accounting for roughly 5.5 seconds of improvement.
- Clicking over the OPEN button to skip the intro does not activate that underlying button. Submitted and frozen skip tests passed 7 assertions each; their first natural admission remains four simulation seconds after play starts.
- Actual Decorate, Done, Pause, Resume, Close and Open clicks passed 15 frozen control assertions. Decorate and Pause hold both movement and the arrival clock. Closing resets/stops arrivals; reopening restores ordinary admissions. This test ends at the resumed natural admission.
- The compact HUD hides the general state badge and retains the OPEN admissions sign while decorating or paused. The controls do change their action/visual states, but OPEN alone does not mean simulation is running.
- Browser/profile loading failures block service. CrazyGames SDK readiness invalidation also sets paused/recovery protection. An undersized viewport and hidden tab suppress updates. Those source gates were inspected; none is established as the reviewer's cause.
- The existing `test_fresh_service.gd` directly spawns a guest and resets the arrival clock. It proves service-path behavior, not natural arrival latency or first impressions.

## Follow-up design (pending separate approval/validation)

Preserve real service and subsequent cadence, avoid visible mid-street pop-in, and leave existing saves/in-flight guests untouched. A first-new-profile approach just outside the actual viewport can reduce the initial empty minute without accelerating walking, cooking, payments, or the simulation. It requires first-visit eligibility that survives reload without repeating, conservative character bounds, and view-size/zoom/pan/skip/reload/closed-to-open tests. Do not change camera bounds or use camera-follow as a workaround.


## Validated first-visit improvement

Candidate source `27d99e20e8979a779e69b0ecdff0fc3138a221f4` keeps the normal four-second admission interval, 1.5-unit walking speed, service steps, +200 meal payment, subsequent world-end arrivals, and camera behavior. On a genuinely new profile only, the first natural admission can use a nearby point on the same lane whose conservative full character bounds are entirely outside the actual current viewport. If no safely hidden point exists within the already-supported short-route area, it falls back to the ordinary endpoint. No existing actor is moved.

Eligibility is an optional, strictly validated saved boolean. Existing saves without it retain existing behavior. It survives an early closed-profile reload and is consumed by the first actual request, including a request sent to the ordinary queue. The transient viewport-derived point is not saved. In-flight route/position/timing survives reload. Nearby guests use the existing bounded short-route representation, so no new route codec or invented far-end history is needed.

Actual cloud-native execution of that exact candidate, normal untouched new-profile startup at 1360×880 and 1×, passed nine assertions:

- Admission created offscreen at 6.48 seconds (four simulation seconds), street z=13.05
- Guest in the play rectangle at 8.03 seconds, as the welcome finishes
- Seated at 16.45 seconds, order received at 20.49 seconds
- Genuine +200 checkout at 98.71 seconds

The matched frozen-native baseline was 53.77 / 62.19 / 66.26 / 144.41 seconds for visible guest / seat / order / payment. Screenshots at 20 seconds show an empty table before and a real seated guest with the waiter taking an order after. The later settled-wallet frame shows 1,350 coins after one payroll cycle and the normal +200 payment; the earlier earning time is a consequence of the shorter first approach, not a bonus or changed reward.

Exact-candidate focused verification passed 488 assertions across seven suites: first-visit eligibility, saved round trips, closed/reopen, old-profile opt-out, unsafe-hint fallback, multiple viewport/zoom/pan bounds, existing endpoints, outside queue, street service saves, fresh service, starter geometry, and startup retry. Initial round-trip test failures were deep-equality int-versus-JSON-float differences; field-level evidence confirmed identical values, and the tests now use the same numeric semantic comparison as existing street-save tests.

The tutorial intentionally starts closed, unlike these before/after untouched arrival baselines. The observer's `tutorial` scenario therefore uses actual Open, Staff, Done, Decorate and Done controls, then waits on normal wall-clock frames for the real meal/payment and clicks the actual completion button. It does not force Open, spawn a guest, speed up service, or write tutorial progress. Combined tutorial-plus-arrival execution remains a distinct integration gate.
