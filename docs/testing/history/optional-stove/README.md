# Optional blocked stoves

Furniture edits may block an optional stove without blocking unrelated cafe service. An assigned meal keeps its ownership and elapsed cooking state while the chef safely pauses. Clearing the workface resumes it. Beverage, sink, counter and register access remain mandatory.

Play mode omits only blocked-stove guidance; Decorate mode still exposes the actionable station issue. The station's world-space marker is not displaced by the screen-space notice.

## Validation

Run `python3 tests/run_integration_candidate.py --output /absolute/new/evidence --only test_stove_optional test_stove_pause_service test_access_location_ui test_floor_availability test_furniture_worker_egress test_staff_relocation_service test_service_notice test_role_boundaries test_role_release staff-start`.

The runner uses a disposable project, generated HOME/XDG profiles, an engine lock, and suppressed normal scene saves. It reports exact source hashes. This issue also has integrated native synthetic-layout coverage: a 90-second hold and save/reload, another chef continuing work, safe relocation, access release, and single payment/cleanup ownership. Browser storage remains a separate check.

Only the layout-access policy, model, workface guidance and their main-scene coordination change in production. Recipe durations, economy, authoritative save format and existing migration or compensation behavior are unchanged. No new assets or license terms are introduced.
