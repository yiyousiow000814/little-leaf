# Scaling hot paths

Scope: the first [#371 scaling batch](https://github.com/yiyousiow000814/little-leaf/pull/371) at measured head `a01104edc9eafc7edbe4705ff2c85a8c242353d2` (tree `dd1a6146`), composed against exact #364 base `2e3c7f6be9a633fff8e05450033ccdb3a2959c5f` (tree `3f76c412ecd12e4782b53ce037be378b019d7270`). No FPS, merge, or deployment result is claimed for this composition.

The combined candidate passed **8,983 assertions across 10 headless suites**, including 581 centered-wall assertions with dedicated parity/work-count regression coverage. The atlas closure changes four existing producer hashes and adds one producer. Art and import files are unchanged.

Scoped [#372 pixel verification](https://github.com/yiyousiow000814/little-leaf/actions/runs/44467477097/job/135368626868) passed on exact #371: all 16 same-input rendered pairs independently decoded to equal pixels. Scoped [canonical atlas verification](https://github.com/yiyousiow000814/little-leaf/actions/runs/44467477097/job/135368625971) passed for all three atlases through generation, import, READY, direct, and saved paths, with nine PNGs independently decoded equal. Ordinary exact-head CI/Web save compatibility, larger-scene coverage, and integrated FPS remain pending.

## Measurement

- [#369 phase attribution](https://github.com/yiyousiow000814/little-leaf/actions/runs/44465769164/job/135363069468) measured one 21-wall first-cooking scene on cloud Godot 4.6.3. Mean 42.04 ms per post-draw interval: other café draw script 3.42, actor commands 2.93, wall prep 1.86, gameplay excluding saves 1.61, and unassigned 32.18 ms. The remainder is not a GPU measurement. Autosave appeared in two of 285 intervals.
- [#368 frozen comparison](https://github.com/yiyousiow000814/little-leaf/actions/runs/44464488862/job/135358861281) measured 25.86 to 25.81 completed native draws/s for the earlier #364 save change. No post-scaling FPS result yet. Keep the baseline sealed, test only a new candidate on a matching cloud envelope, and do not equate native draw completions with Web or device FPS.
- [#370 boundary diagnostic](https://github.com/yiyousiow000814/little-leaf/pull/370) measured 40.889 of 58.396 ms in pre-draw to post-draw: 16.984 ms executing on the main CPU thread and 23.905 ms off-main or not executing on the main thread. It ran on a different CPU from #369. These are boundary timings, not a GPU measurement or a before/after comparison.

## Candidate status

| Path | Scoped evidence | Outstanding gate |
| --- | --- | --- |
| Wall drawing | Geometry dictionaries matched on starter, four density grids and two legacy/fallback fixtures. At 648 walls and 166 openings: 107,568 attachment visits became 166, 35,082,993 canonical support probes became an upper bound of 166 plus the wall-index build, and endpoint rows upper bound went from 1,259,712 to 7,420. Scoped native pixel and atlas qualification passed above. | Larger rendered scene and ordinary exact-head Web CI. |
| Live wall edges | 16/32/64/128/256-wall rebuild and proposed-component reachability results matched. At 256 walls, 256 calls to the legacy full lookup became zero; single headless timing 237.930 to 1.532 ms, not FPS. | Ordinary Web/save compatibility. |
| Dining migration and validation | 32 randomized parity cases. At 256 items, 16,348 table × seat pairs became 488 neighbor-cell probes. Keeps original candidate order and existing metadata selection. The combined candidate passed canonical atlas qualification. | Ordinary exact-head Web CI/save compatibility. |
| West corridor entry | Eleven cases cover dense layouts, in-place changes and clearance. At 96 items, 108 cell probes and 5,808 furniture rows became 9 west-edge probes and 96 indexed rows on cache miss. Does not remove navigation content-hash work. | Ordinary Web/save compatibility. |

## Remaining hot paths

The separate guest/item rendering prototype is **not included**. Its guest lookup fallback, normal meal/table and chair-rotation scans, and repeated actor/furniture lookups remain distinct work.

The gameplay scaling audit also identifies staff assignment and station/custody scans, per-guest item counts and batch removal, live segment/opening/body validation, repeated admission and checkout departure route searches, furniture move validation and commit lookups, wall proposal checks, and pending-checkout placement. Some paths run only on edits or save/load, not every frame. Legacy or unsupported geometry retains safe fallback. The unassigned frame time is still a separate investigation; there is no claim that every O(n²) path was removed or that such paths account for all slow frames.

Open `scaling-ledger.xlsx` for per-size counters, test status and measurement context.
