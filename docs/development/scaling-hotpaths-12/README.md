# Scaling hot paths: batch 12

Exact #392 base: `0f04d4c196b48b7f6f41462801477a3accbbf510` / tree `737ef9445cc9462cd56b692c5fc9fe5af27e865f`. [Mermaid map](scaling-hotpaths-12.mmd) · [Excel ledger](scaling-ledger-12.xlsx).

The first waiter order attempt still uses the existing path. On the first blocked order in one assignment scan, build a transient occupancy, seating and active-guest lookup; later eligible diners in that scan reuse it. Preserve original guest order, guest identity for rear contact, reachable faces, claims, and final blocked diagnostic identity. Unusable or duplicate IDs retain the original path. No geometry persists across workers or frames. Topology fingerprint work is separate and remains open.

| Diners / items | Full occupancy calls, old → new | Local median, old → new |
| --- | ---: | ---: |
| 4 / 8 | 28 → 4 | 405 → 355 μs |
| 10 / 20 | 70 → 4 | 1,342 → 1,053 μs |
| 20 / 40 | 140 → 4 | 4,018 → 2,860 μs |
| 25 / 50 | 175 → 4 | 6,277 → 4,436 μs |

The local focused run passed 3,217 assertions in six suites, and a separate diagnostic passed 80 checks with 20 paired timing runs per fixture. Once-built index preparation is retained work; the table counts full occupancy calls, not total operations. Timings describe blocked order assignment, not frame time or FPS. The computed 85-source/three-atlas guard passed; Web/save and FPS are not established.

Source patch SHA-256: `4936f00b68e1a0aa70f7084e7064af64f6f9ae9f3325ea695ba93712d6ac9efa`. Regression patch SHA-256: `85d6ca75fce6b9b3be18744308eeffc1235d73bcd9ae8595f31ebda6e1d4a8d2`.
