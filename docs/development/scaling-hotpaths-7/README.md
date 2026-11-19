# Scaling hot paths: batch 7

Integration base: #380 `0eb610848ac54edbd234c552f2460de2b42871f4` / tree `41c1e83129f650f362adc0d3e62d3a21bf4cfea3`. See the [Mermaid map](scaling-hotpaths-7.mmd), [Excel ledger](scaling-ledger-7.xlsx), and [batch 6 cumulative record](../scaling-hotpaths-6/). Counts and local function timing do not establish whole-game FPS.

| Lane | Scope and evidence | Qualification |
| --- | --- | --- |
| Dining appearance, per draw | The old path repeatedly scanned dining groups and admitted rows (D² + N×D). For 8/16/32 groups, 108/408/1,584 old scans become 8/16/32 scans plus 24/48/96 keyed lookups. No group allocations for zero or one group; non-dining rows skip the lookup. Verified legitimate starter layout from two to four groups using product APIs. Local microbenchmark: 32 sets, 424.17 → 203.55 μs; tiny one-set dining-only workload, about 5.6 → 6.7 μs, with only a modest difference in the neutral-furniture scenario. These timings are not FPS. | 82,394 assertions across five focused suites for the independent implementation; fresh visual/atlas evidence pending. |
| West guest admission | Independent implementation tested 18 legal western thresholds created through three parcel purchases, actual doors, and save/reload. First pair: 954 → 115 edge checks and 4.148 → 1.625 ms median local function time. Reject the first and select the real second pair: 1,349 → 137 edge checks and 5.551 → 1.858 ms. Full route, customer and queue parity: 48/48. Eight or fewer entries, off-lane situations, unproved scores and unusual cases use the original path. | 844 assertions across five isolated native suites; earlier prototype passed 703 checks. Combined production tests passed (see below). |
| Multi-register scaling | Normal purchase and load confirm a hard cap of one register. | Synthetic multi-register candidate excluded from this batch. |

Exact combined local candidate: 67,593 assertions across 11 suites, no failures. The seven verified native floor pairs qualify the inherited floor lane only; batch-seven dining pixels and canonical atlases are still unverified.

Run new, qualified runtime comparisons on the matched cloud envelope; do not rerun the frozen native baseline. New pixel/atlas gates, ordinary Web/save, larger-scene coverage, and actual FPS remain open. These scoped improvements do not prove all O(n²) paths are gone.
