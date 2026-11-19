# Scaling hot paths: batch 10

Exact base: #387 `079cee5bc8f02be6f5753940aec708a2f61c94c0` / tree `a5ec61adc47fc606dcee0643e2f5c0028be7d1ef`. [Mermaid map](scaling-hotpaths-10.mmd) · [Excel ledger](scaling-ledger-10.xlsx) · [Previous batch](../scaling-hotpaths-9/).

This candidate targets legacy wall projection, not the earlier #387 validation change that removed repeated A²W work. It replaces repeated attachment-by-wall scans in projection with the batch-nine host-subset table and a coordinate index. At W299/A300, the old path reconstructed 89,700 hosts and examined 96,000 edge rows; the new path makes 299 direct host resolutions and 300 coordinate support hits, excluding fixed setup. These are distinct operations. W is the number of walls and A is the number of attachments.

| Fixture | Direct projection median | Full operation median |
| --- | ---: | ---: |
| W96 / A97 | 97.474 → 4.645 ms | 102.737 → 18.142 ms |
| W299 / A300 | 787.777 → 12.746 ms | 755.662 → 45.128 ms |

These timings are separate runs and medians, not additive or subtracted stages. The final native run passed 40,875 checks across four suites, including 13 new permanent regression checks. Standalone v15/v16/v17 accepted 300 openings with exact raw projection parity and unchanged input. Support and duplicate/error order remain unchanged; unproven or noncanonical inputs use the original whole scan. Computed atlas inputs are unchanged against batch nine; inherited manifest adoption is separate. New #387 visual qualification is separate and underway. Nothing here establishes ordinary Web/save, FPS, publication or merge.
