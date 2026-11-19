# Scaling hot paths: batch 9

Local evidence for two separately filtered candidates. [Mermaid map](scaling-hotpaths-9.mmd) · [Excel ledger](scaling-ledger-9.xlsx) · [Previous batch](../scaling-hotpaths-8/). Exact combined local qualification passed 121,745 assertions across eight suites, including 1,298 clean layout reconciliation assertions. Source closure adoption and new combined atlas qualification remain pending.

| Lane | Evidence and scope |
| --- | --- |
| Live litter eligibility | Build eligibility lazily within an observation. Stationary path does not scan item rows. In known fixtures, item visits change from C × I × (3 + 4B) to one pass over I, with indexed cell tests remaining; C is crossed cells, I item rows and B the fixture's blocker count. Starter C=1: 34.38 → 24.87 μs. I=24/B=2, C=1/4/8: 102.47 → 36.84, 407.28 → 67.05, 542.12 → 67.76 μs. Verified isolated local receipt: 76,829 assertions / three suites. The same 99-check oracle passed on the baseline. Computed producer impact: `cafe_floor_tasks` only. |
| Supported legacy opening validator | Real valid 96 walls / 97 openings: whole operation 6.674 s → 98.873 ms; nested validator 6,529.683 → 4.226 ms. 40,861 scoped checks; covered v15/v16/v17 and wall1/wall2, accepted 300 and rejected 301. One-door and malformed behavior unchanged. The older projection phase still has O(A×W) work; atlas producer closure unchanged. |

The prior #384 dining and canonical atlas receipts do not qualify either ninth-batch variant. Work counts and local timings do not establish game FPS. No new hosted Web/save, FPS, merge, or publication is claimed.
