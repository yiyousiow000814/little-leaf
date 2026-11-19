# Scaling hot paths, batch 2

The second batch builds on [#371](https://github.com/yiyousiow000814/little-leaf/pull/371) at `c352e6629ae9f56db58e9f1ecd162b02c1e85875`. Source-isolated workload counters are not frame timings. No integrated FPS, merge, or deployment result is claimed.

## Changes and measured work

| Path | Scoped test | Work reduced |
| --- | --- | --- |
| Renderer lookups | 480 equal outputs for 48 guests and 144 items; 365 checks in six separate headless suites. | Table guest-row lookup upper bound 2,304 to 48; chair lookup upper bound 4,608 to 48. Draw/motion scopes preserve source order for guest keys, item IDs, adjacent chair/bench choices and docking. |
| Per-tick service capacity | 24 state parity cases across cooking, cleaning and drink phases, including synchronous listener mutations. | At 64 guests per phase and 135 furnishings, old count/speed-loop visits 17,820 became 270. Transient counts invalidate after legacy payment listeners that may change the layout in place. |
| Cashier FIFO and checkout | 40 cashier states, plus register claim/deployment candidate-order checks. | At 128 guests, readiness calls 128 to 1 and busy-guest checks 16,384 to 128. Preserve FIFO, held/cancelled state and original placement order. |
| Staff station assignment | 64 parity cases for cook/brew (two roles, four sizes, eight scenarios). | Blocked synthetic 64-station × 64-diner case: 64 to 1 station searches and 8,256 to 129 workface oracle calls. Availability was deterministic; this is not live CPU timing or FPS. |

## Qualification

- Three-change local combination (renderer, capacity, cashier) passed **10,947 assertions in nine targeted headless suites**.
- The four-change local composition, including staff station indexing, passed **10,955 assertions in nine targeted headless suites**. These are separate runs; do not add their totals.
- Before claiming production readiness, rerun native same-input pixel pairs and canonical original-three atlas checks for this renderer source; #371's earlier visual qualification does not qualify this renderer change. Ordinary exact-head CI, live Web/save compatibility, larger-scene coverage and integrated FPS remain pending.
- Reuse the [#368 frozen cloud baseline](https://github.com/yiyousiow000814/little-leaf/actions/runs/44464488862/job/135358861281). Do not rerun the old FPS baseline. Time only the qualified new candidate on a matching cloud envelope; do not equate native draws with Web or device FPS.

## Still open

There is no claim that all O(n²) paths are fixed. Remaining work includes wall opening lookup in pointer/editor interactions, segment and body validation, repeated route/admission searches, furniture move checks and commit lookups, checkout placement's equipment/route work, and staff path occupancy/signature costs. Keep separately scoped changes and unsupported geometry fallbacks explicit; the counters here do not explain all slow-frame time.

See the Excel ledger for before/after counts, status, and verification scope.
