# PR59 active cleaning CPU follow-up

Baseline: exact PR59 head `ff14aa5bd022c202a2fbbc009d2f37b3a75393b3`. This branch is independent of the v0.1.9 performance patch in PR62.

`FloorCleaningApproach.solve` performs the original swept furniture/body/wall checks on every active sweep/mop pose-update frame, including after the stance has settled. Each clear solve calls `blocked_by` twice. These scans resolve wall openings repeatedly even when the position, contact, stance and model geometry are unchanged.

The candidate retains that solver verbatim and memoizes one result per renderer staff key. The key includes model instance identity, model revision, authoritative position, contact point and current stance offset. Any changed input recomputes the complete original query. The current stance is included so the transition's swept segment is checked. Revision invalidates layout/ownership changes using the model's existing mutation contract. No route, claim, job, target, foot interpolation, limb geometry or service clock changes.

## CPU measurement

Run `qa/profile_dense_cleaning.gd` on baseline and candidate disposable projects with Godot 4.6.3:

```
godot --headless --path DISPOSABLE_PROJECT --editor --import
# OUTPUT points to a new writable evidence directory.
godot --headless --audio-driver Dummy --path DISPOSABLE_PROJECT --script res://qa/profile_dense_cleaning.gd
```

The same fixture creates 72 furniture pieces, 36 wall segments and three cleaners on owned floor, with active sweeping/mopping contacts. It warms 60 pose-update frames and samples three batches of 300 fixed 1/60 updates for each action. The renderer is hidden to avoid drawing the minimal fixture stub; the measured code is the real active `illustrated_cafe.update_motion` method. No saves are loaded or written. Measurements were serial after the other owned engine tests finished, on the connected Windows desktop. Background activity is not fully controlled.

| Pose-update workload | Before, mean ms/frame | After, mean ms/frame |
| --- | ---: | ---: |
| Settled sweeping, three cleaners | 23.628 | 0.072 |
| Settled mopping, three cleaners | 24.314 | 0.071 |
| Revision changes every frame, 30 updates | 24.087 | 23.317 |

Stable-input CPU work falls about 99.7% in this dense synthetic workload. All three stance offsets match exactly before/after. Forced revision changes retain the original query cost, confirming that the cache is not bypassing changed geometry. These are pose-update timings, not whole-game frame times, rendered FPS, energy or physical-iPhone thermal measurements. Graphical profiling remains paused during the separate desktop crash/contended-resource investigation.

An earlier fixture produced an automatic draw error after emitting its timing report. That run is retained as diagnostic evidence and excluded from the accepted results. The corrected hidden-renderer runs have no script errors.

Regression coverage compares cached and uncached offsets across headings/distances/current stances; tests furniture insertion, wall insertion/removal and replacement models at matching revision; and retains the original approach, body-clearance, foot-contact, held-work, depth, work-side, arm, washing and dining suites. Nine disposable engine suites passed 337,487 checks, including 1,745 new cache-parity/invalidation checks. The report records tested production source hashes. Exact-head hosted CI remains required.
