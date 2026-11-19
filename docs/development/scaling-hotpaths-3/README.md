# Scaling hot paths, batch 3

The third batch builds on [#373](https://github.com/yiyousiow000814/little-leaf/pull/373) at `29251c48c3a8e940bef4a8f600365833ac735dd4` (tree `60ea36b5aafe117a7ec0eaf336684a3f56b60dbb`). Counts cover specific operations in controlled fixtures, not ordinary frame cost. No FPS, merge, or deployment result is claimed.

| Path | Scoped evidence | Work reduced |
| --- | --- | --- |
| Installed opening support validation | Exact first-error parity for 120 deterministic randomized layouts. Ordered fallback remains for unsupported geometry. | 120-wall, 120-opening valid layout: aperture resolutions 14,400 to 120, plus one 120-wall index build. |
| Furniture move commit | Preserve first-match IDs, in-place object identity, merge rules, and writes. Planning, routing, and geometry checks are separate. | Analytic matched-join count at 128 items and 128 guests: source rows 16,512 to 256, plus 256 keyed probes. |
| Checkout departure | One route search with ordered selection. Separate focused run passed 870 assertions. | Stress BFS expansions: 463 to 63 at 8×8, 3,743 to 255 at 16×16, and 30,015 to 1,023 at 32×32. The 32×32 case is a synthetic stress case, not the current layout cap. |
| Collision broadphase | All 360 ordered segments matched. 1,800 movement and 1,800 radius checks returned equal results. Original narrow tests remain; long/out-of-profile queries keep full candidates. | At 288 walls and 72 doors: aperture resolutions 20,736 to 72. Actual narrow tests with early exit: movement 455,753 to 13,526 and body 412,106 to 12,553. |

## Qualification

- The support, furniture, and checkout departure composition passed **42,431 assertions in 10 headless suites**.
- The exact four-change local composition passed **45,945 assertions in 11 headless suites**. This supersedes the first-three result for the composition; do not add the two totals.
- The computed atlas producer closure is unchanged relative to exact #373. This batch does not change art or import files, but inherits #373's pending atlas metadata evidence. This is not standalone visual or atlas qualification.
- Ordinary exact-head Web CI, live save and cross-tab verification, larger-scene coverage and integrated FPS remain separate. Keep the [#368 frozen native baseline](https://github.com/yiyousiow000814/little-leaf/actions/runs/44464488862/job/135358861281) sealed. Only measure the new qualified candidate in a matching cloud envelope.

## Still open

Arrival and admission routing, pointer/editor opening lookup, and wall proposal and checkout placement work remain outside the batch, as do other geometry and staff paths. Legacy-safe fallbacks remain. These changes do not establish that every O(n²) path is gone or explain all slow-frame time.

See the Excel ledger for scoped counts and verification.
