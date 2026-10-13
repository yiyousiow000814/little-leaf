# Current floor facts and whole-furniture preview

The Decorate background shows current furniture occupancy, checkout claims, entrance/landing cells and mandatory work sides. It does not change with the selected product, its rotation or the wallet. An empty owned edge tile remains green even when a selected table's chair would extend onto unowned ground; the complete selected footprint then has a red preview and a specific “Chair needs owned floor” reason.

In the standard starter scene, 91 tiles are green and 17 are red: eight furnishings and nine required clear spaces. All 12 empty far-edge tiles remain green. The floor-facts cache only rebuilds when those current facts change. It never scans possible placements for every tile.

A separate plan validates only the current hovered whole furnishing and is reused by the actual click, release or rotation commit. It checks price, ownership, grouped footprint, work access, guests, workers and stale state. When a hidden worker obstructs an otherwise valid paused edit, the plan retains the accepted safe step-aside dependency: find a destination reachable in the old layout and clear in the new one, preserve jobs and carried payloads, then commit the staff and furnishing changes synchronously. A worker cannot escape through an already sealed wall. The original model and FurnitureMotion planner are unchanged.

Production scope is seven files: three small helpers (floor facts, one-hover plan and staff relocation), interaction integration, the floor/preview rendering calls, the live staff callback and the existing access-policy hook. The access policy still requires every existing station type; optional-stove behavior is not included.

## Verification and evidence

Run `python tests/run_floor_availability_native.py` with Godot 4.6.3. The runner copies the project and uses a disposable profile. All 725 checks passed: 50 floor/preview/cache checks, 121 worker/input checks, 16 carried-service/save checks and 538 approved-main regressions. The service test creates its entire fixture in code from MinimalStart and three explicitly placed table sets. Actual arrival and service code generate four admitted visits; after moving a carrying worker aside, all four finish and clean once, with exactly 1,000 coins earned. No imported runtime JSON or player save is used.

The native background comparison was reviewed separately on the same b75ba917 baseline. The accepted no-selection and selected-table floor regions were pixel-identical. This public draft contains only source, tests and textual verification; image payloads are not included. No new native captures were attempted during this integration.

Hover hint positioning and browser input remain outside this visual proof. Previously preserved hover captures had a synthetic-hover/physical-pointer offset, so they are not published as accepted layout evidence here. Headless input-path tests passed. Some full-scene harnesses report an existing shutdown-only ObjectDB warning after completing their checks.

One conservative limitation remains: when a placement needs a worker to step aside, another worker already trapped by a legacy layout can prevent the plan from finding an acceptable relocation. It rejects the edit rather than introducing an unsafe commit.

This source change does not deploy the game.
