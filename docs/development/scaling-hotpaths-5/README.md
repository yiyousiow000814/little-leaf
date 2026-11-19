# Scaling hot paths: batch 5

Exact base: #376 `08833ed`. Local candidate: sink reservation and save transport membership, plus sink renderer grouping. See [workflow](scaling-hotpaths-5.mmd) and [work-count ledger](scaling-ledger-5.xlsx). Counts are synthetic operations, not frame time or FPS.

| Path | Change and measured work | Behavior to preserve |
| --- | --- | --- |
| Sink reservation | Build membership per reservation scope. 32-sink synthetic: 2,146 → 66 row visits, plus 32 keyed lookups. | Simultaneous waiter front drop and cleaner washing; six-dish capacity and existing order. |
| Save transport validation | Reuse membership across references. 528 → 32 row visits for the synthetic fixture. | First error and save-validation ordering. |
| Sink renderer | Group dish rows by sink once. 48 sinks / 192 dishes: 18,432 → 192 dish-row visits, plus existing per-sink sort. | Existing dish order, sink state, and draw order. |

Reservation and save work passed 81,166 isolated assertions; renderer grouping passed 84,953 isolated assertions. Exact combined focused gate passed 88,621 assertions across 8 suites (local Godot runner); no integrated FPS result. The three changed candidate atlas-producer files are `cafe_dishwashing`, `cafe_sink_wash_art`, and `illustrated_cafe`. Exact real-sink pixel parity, canonical atlas output, ordinary Web/save, larger scene, and integrated cloud FPS remain pending. Do not rerun the frozen historical baseline or infer project-wide elimination of quadratic work from these fixtures.
