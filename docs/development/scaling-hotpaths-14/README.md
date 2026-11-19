# Scaling hot paths: batch 14

Exact #394 base: `16a34fd73e871d42725b251568374487c0fdab70` / tree `dabc8d321765dfece5fac55e02f697871c34c8da`. [Mermaid map](scaling-hotpaths-14.mmd) · [Excel ledger](scaling-ledger-14.xlsx).

Furniture-drag advisory warnings now use one invocation-local layout query with indexed side checks. Reuse one landing-reachability flood per layout, even when empty; prepare the original layout only if a possible new warning needs comparison. Preserve original first-warning semantics, duplicate/malformed handling, ownership and edge tests. The edit transaction, rendering, saves and simulation routes are unchanged.

| Dining sets / bins / rows | Full-array side probes | Bin floods | Local method median |
| --- | ---: | ---: | ---: |
| 4 / 2 / 17 | 31 → 0 | 2 → 1 | 2.009 → 1.128 ms |
| 12 / 4 / 35 | 63 → 0 | 4 → 1 | 4.208 → 1.281 ms |
| 20 / 6 / 53 | 95 → 0 | 6 → 1 | 6.049 → 1.370 ms |

Legal fixtures used normal parcel/item APIs. Actual method measured separately on each revision with five warm-ups and 25 samples; 216 checks per revision. A separate 217-check oracle counted full-array probes and floods, not individual edges. Broader local native run passed 49,087 assertions across six suites. Computed 85-source/three-atlas closure unchanged. No Web/save, visual acceptance, whole-game FPS or release claim.

Patch SHA-256: `5a1722c6b8c7719aaefd6aaa6646ab071217ea4d01bc210089757de4dc018056` (model and Decorate regression only).
