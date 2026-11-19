# Scaling hot paths: batch 11

Exact #389 base: `1556f2ad1e9985c723f7f3634a3f48535cc411a2` / tree `f449331e7ae64da7f19fa62b3554062381cb887c`. [Mermaid map](scaling-hotpaths-11.mmd) · [Excel ledger](scaling-ledger-11.xlsx).

- **Cold wall warning:** Current/proposed comparisons share one read-only occupancy and chair snapshot. Preserve guest/group/item priority, duplicate-ID fallback, first new warning, and existing reachability semantics. Both warning passes still perform BFS and edge generation.
- **Door move/removal guard:** After original validation and actor guards, check first-record IDs and one guarded proposed edge snapshot. Check current edges only if the proposed layout blocks a pair; pre-existing blocked pairs do not reject. Unsupported edge shapes retain direct resolution.
- **Largest fixture (45 pairs / 90 items / 181 walls):** 38.757 → 22.201 ms cold preview and 6.964 → 1.030 ms safe door guard (local method medians, 20 alternating runs, not frame time). Occupancy visits: at least 8,100 → 90 preparation rows plus keyed face checks. Safe door wall candidates: 8,145 → two 181-row scans plus 45 edge probes. ID search: 4,095 positions → 90 rows plus 90 keyed requests. Counts represent distinct operations.
- **Verification:** 1,240 assertions across five standard suites; 160 separate measured old/new warning matches; 128 final focused wall-action assertions. Do not add overlapping scopes. Computed 85-source/three-atlas guard unchanged. Web/save and FPS are not established.

Runtime patch SHA-256: `f7a67d69059641adc02c1841a36a97014ecbe05c59194687cce178914ecdadf5`. Regression patch SHA-256: `7c46f756b3f042d9f2b8976fc551b10ec0503db207e0ae3ddd998621a2c014cb`.
