# Interior drawing second pass

Base: 69ee0d1b02374a26e5b2c3e1149561500a4ae88d. Branch perf/interior-command-retention.
Scope: shell command preparation only, at original draw positions. Floor already uses two retained meshes. Existing background retention remains untouched.
Plan: bounded per-artist cache for two shell hosts; exact deep input snapshots and projection invalidation; replay existing poly/line/draw_polygon helpers. No render-order changes or artwork simplification. Verify ordered command parity, invalidation, bounded storage and isolated CPU/operation counts.
No player saves, GUI benchmark, push, merge or deployment. Headless evidence cannot establish GPU, browser or phone performance.

Implemented `cafe_shell_draw_cache.gd` with two bounded host slots and exact deep snapshots of hosts, attachments, walls and projection inputs. The two original shell draw positions now replay prepared commands through existing helpers. No native draw submission is removed or reordered.
First focused test passed: 682 checks including original/warm command parity across scales, detail levels, materials, heights; nested edits; projection invalidation; geometry operation counts. Remaining selected integration checks in progress. Evidence folder: sibling `performance-evidence/interior-pass2-focused`.

Completed final focused validation: 9 suites, 544,316 checks, no diagnostics.
Evidence: sibling `performance-evidence/interior-pass2-final2/summary.json` and logs.
New suite: 705 checks. Source checkpoint efa62d8; final tests/benchmark documentation e20bd1a. An intermediate extended-test run failed on a test-only local variable-name collision; corrected and final full focused rerun passed. No production-source changes after efa62d8.
Ready for parent independent review and integration. Original frozen baseline remains untouched. No uploads or deployment were performed. Benchmark details and limitations are in `docs/shell-draw-preparation-performance.md`.

Follow-up requested by parent after independent review: omit built-wall key dependency only for empty attachments. Verified `solid_panels -> cuts` cannot read wall content then; supplied host still covers shell shape changes. Added mutation/transition parity and synthetic dense-record timing. Four suites / 8,321 checks passed, no diagnostics, in sibling `performance-evidence/interior-pass2-empty-wall-key`. Frozen baseline/integration untouched; this delta is separately committed for review/cherry-pick.
