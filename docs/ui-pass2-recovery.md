# Second-pass UI investigation

Frozen baseline: `69ee0d1b02374a26e5b2c3e1149561500a4ae88d`.
Worktree: `cloud-integration/ui-performance-pass2`, branch `perf/ui-pass2`.

Scope: controller/UI presentation only. No deployment, no GUI benchmark, no player saves. Draw work is owned separately. Current hypothesis: unchanged decorating action-board guards repeatedly stringify nested button state on each pointer frame; preserve validation and immediate updates while replacing that serialization with typed comparisons. Measure before accepting.

Use `tests/run_integration_candidate.py` for isolated synthetic engine suites. Headless timings are CPU-method evidence, not delivered FPS, GPU cost, temperature, or visual verification.

## Implemented candidate

`cafe_shop_ui.gd:358–380`: retain the same style repair and button minimum-size checks, but build one flat typed signature inside the existing child loop. This replaces nested array `map`, a second minimum-size lookup per button, string conversion of button IDs/sizes, and string comparison. No throttling or new dirty-event assumptions. The guard also includes the price font size, alongside the already-tracked title font size.

Frozen baseline method is retained only in the synthetic regression fixture, not production. The fixture uses the same real controls for both implementations, alternating seven 3,000-call samples at each width. Results from `/tmp/leaf-ui-pass2-a/test_ui_guard_performance.log`:

- Width 960: baseline 47,293 µs / 3,000 calls; candidate 35,894 µs. About 24.1% faster for this helper, 3.80 µs saved per call.
- Width 390: baseline 42,614 µs / 3,000 calls; candidate 32,858 µs. About 22.9% faster for this helper, 3.25 µs saved per call.
- 16 equivalence checks pass: desktop/mobile initial geometry; immediate changed title, price, action visibility, button text, minimum size, viewport width; play/edit transitions.

Absolute savings are small. This is not a whole-frame benchmark. Do not describe this as a material FPS or heat improvement.

## Other audited paths intentionally retained

- `main.gd:_process` calls `_update_ui` at the existing 0.2-second cadence and synchronously on interaction. Do not increase that interval or gate on incomplete state signatures.
- `main.gd:_sync_staff_duty` also refreshes moving checkout staff/route claims. A blanket unchanged-duty shortcut would lose dynamic claims; no change.
- `cafe_interaction.gd:refresh` already exits outside decoration. Its projection updates and commit validation preserve camera/input correctness.
- `cafe_build_tools.gd:refresh` clears inactive previews; active quotes depend on actors/geometry/coins. No new caching of mutable quote state.
- `cafe_compact_ui.gd:sync` already gates closed staff cards, closed help, and hidden shop refreshes. The remaining inexpensive assignments are not justification for complex invalidation.
- `cafe_workface_guidance.gd:_refresh` already compares a short typed selection/revision signature before reachability work.
- Save serialization and validation are deliberately unchanged; authoritative validation must still run.

## Verification

Focused isolated runner: `/tmp/leaf-ui-pass2-a`, run log `/tmp/leaf-ui-pass2-run.log`. Uses disposable project and generated test profile. Import, 16 new action-board checks, 429 shell UI checks, 806 HUD checks, and 2,214 mobile toolbar checks pass. Build-tile UI also passed 2,156 checks. Final focused result: all 5 suites, 5,621 checks passed, no diagnostics. Full aggregate validation belongs to the final combined candidate. No GUI or export run here.
