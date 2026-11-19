# Scaling hot paths, batch 4

Batch 4 builds on the runtime of [#375](https://github.com/yiyousiow000814/little-leaf/pull/375) at `afd147120b9f0af41471b0fcf41b0aa58af0731f`. Successor `cf04b3eafb830273beb3598f243bd7dfa5555a70` changes inherited metadata only. These are controlled operation counts, not frame times or FPS.

| Path | Scoped work and semantics | Separate test coverage |
| --- | --- | --- |
| Pointer selection | In a 648-wall, 216-opening fixture, wall-identity rows including the index build were 70,092 before and 864 after. Reuses canonical wall/support lookups; preserves ordering, hit tests, sort and legacy fallback. | 10,186 checks in four native headless suites. |
| Guest admission routes | Reuses one incremental search per west entrance for each outside start during a synchronous seat scan. Same tie ordering, endpoints and routes. In synthetic 24×24, beyond the 18×18 layout envelope, edge checks were 388,641 before and 13,417 after. E entrances × V walkable cells remains bounded work. | 802 scoped checks. |
| Wall egress and motion | Proposal-local blocked-edge reuse preserves warning order, chair/relocation semantics and legacy or unsupported geometry fallback. In a canonical 288-wall, 36-door, 392-query fixture, wall rows 71,568 to 576 and door resolutions 10,368 to 36, plus 392 indexed edge probes. | 5,372 scoped checks. |
| Stable bulk departures | For 128 alternating departed/survivor rows, replaces 2,080 searches and 4,096 shifted slots with 320 row reads and 64 survivor writes. Preserves callback order, in-place survivor identities and original ambiguous-row fallback. | 274 checks in four standard suites. |

The pointer + admission composition passed **11,136 assertions in 10 headless suites**. The first exact four-change run stopped at a stale `_wall_reachable` override signature in the departing-route test. The corrected fixture accepts the new optional argument. After that fixture-only correction, the exact four-change composition passed **39,937 assertions in 15 headless suites**. Production code and assertions were unchanged by the correction. These are separate runs; do not add totals.

The computed atlas producer dependencies are unchanged versus latest #375. This does not certify new rendered scenes or ordinary exact-head Web and live save compatibility. Larger-scene coverage and final FPS remain pending. No merge or deployment is claimed. Measure only the qualified new candidate in the matching cloud envelope against the [sealed #368 baseline](https://github.com/yiyousiow000814/little-leaf/actions/runs/44464488862/job/135358861281); do not rerun the old game.

Remaining work includes cold staff floor/stance, section and chair scans, and bounded or legacy fallbacks. Do not infer that all O(n²) paths are gone from the local improvement counts.
