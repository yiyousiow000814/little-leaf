# Natural new-game staff placement

A genuinely fresh game with no saved service snapshot places the initial staff at the existing reachable work/standby posts before the first illustrated frame. The chef starts at the stove, the waiter near the pass counter, the cleaner near the sink, and the cashier behind the register. The existing post-selection rules keep the standing cells distinct, clear and reachable.

Saved positions, paths, jobs and progress use the unchanged restoration path. A loaded standalone model save without a service snapshot keeps its historical fallback. Invalid saves remain blocked in recovery mode; a failed load never becomes a new game. There is no save-format or job-assignment change.

## Verification

Run `python3 tests/run_staff_start.py` with Godot 4.6.3 installed. It copies the project into a disposable directory, isolates all user-profile paths and suppresses normal writes. Every saved fixture is generated during the run.

The suite checks ordinary empty-profile startup as well as explicit fresh-review startup, distinct reachable posts, first-step stability, real service, saved fields and active jobs, actual saved-profile startup, standalone-model loading and corrupt-profile protection. It also runs the role, cleanup-completion, carried-service, floor-availability and furniture/worker-egress regressions. The two relocation tests explicitly arrange their obstruction actors instead of relying on the former startup row.

Matched native first-frame comparisons were reviewed separately at 1360×880 without advancing the gameplay clock. No private images, imported player data or copied full baseline source are included. Browser, physical mobile and audio behavior remain unverified. No game deployment is included.
