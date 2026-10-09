# Routing stage-2 synthetic results

The [audit and compatibility boundary](routing-candidate-011-audit.md) precedes
implementation. Default gameplay remains unchanged. This is a planner/follower
candidate, not completed state-machine integration or eight-direction release.

Run on Windows with Godot `4.6.3.stable.official.7d41c59c4`:

```sh
python tests/run_navigation_candidate.py --godot /path/to/godot --output /new/evidence/directory
```

The runner copies scripts/data into a temporary project named **LittleLeaf
Navigation Synthetic**, redirects platform profile directories, and only runs
the new SceneTree script. It does not import art, launch the gameplay scene,
read live saves, access cloud services or perform timed rendering. Receipts
include source hashes, the base commit, tool version, command and log digest.

Final implementation run: **985 assertions passed**, no failed assertions,
seed **11011**, exit **0**, **zero profile JSON writes**. Twelve seeded 5x5
maps with 20 start/goal pairs each compare A* costs to independent Dijkstra;
additional assertions inspect determinism and each returned segment.

Coverage includes 10/14 and metric length, same-node success, distinct invalid/
unreachable/pending results, four diagonal wall edges, blocked/unowned side
cells, rectangle clearance sweeps, furniture/rugs, actual model geometry and
wall-cache invalidation, shared guest/staff/cashier planning, stale claim tokens,
30/60/120 Hz and large-delta distance consumption, pause, positive progress in
congestion, opposing narrow-corridor followers, affected versus unrelated
geometry changes, and stopping at exact mid-segment position without snapping.

These are portions of PR112's N/M/T/S specifications, not 50 completed QA cases.
Exclusive claim allocation, chair/workface docking, reception/departures,
service contacts, old/new save migration and reverse rejection remain **not_run**.
The module delegates endpoint ownership to a callback and does not allocate or
release claims. Budget exhaustion is `pending`; continuation by retry with a
larger budget is supported, but resumable sliced search is not implemented.
Snapshots capture the current one-cell furniture contract; proposed future
multi-cell cabinet geometry requires its owner adapter before integration.

Native pixels, Web/CG behavior and storage, business-state regression and FPS
are **not_run**. No production switch, codec change, version number, deployment,
release, push or PR was performed. The parent owns remote Draft PR coverage.

The first development attempt found a test fixture Array typing error and
incorrect door-jamb test coordinates; both were corrected before the successful
runs. Godot logs also report an unavailable Windows root certificate store;
this offline suite uses no network operation.
