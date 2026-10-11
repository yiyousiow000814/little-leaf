# Verification

Keep default checks observable and select deeper diagnostics for a specific
symptom. Tests, fixtures and manual captures now share this home:

| Location | Use |
| --- | --- |
| Root browser/Node tests and `run_*.py` | Current external entrypoints; further family moves must update executable consumers atomically. Reserved update-notice and shared fixture labels remain stable. |
| `tests/persistence/` | Save, cloud and platform engine/Node/browser regressions; CLI arguments and output IDs remain stable. |
| `tests/presentation/` | Startup, tutorial and HUD engine regressions; external entrypoints and receipts retain their IDs. |
| `tests/service/` | Guest/worker service and ordered staff-start engine regressions; use stable canonical IDs. |
| `tests/world/` | Environment, parking, traffic and outside-queue engine suites; stable `--only` IDs remain in the canonical runner. |
| `tests/building/` | Decoration, floors, walls, expansion and work-space engine suites; canonical suite IDs stay unchanged. |
| `tests/rendering/` | Camera, art and browser compatibility regressions; engine IDs, browser arguments and result identities remain stable. |
| `tests/tooling/` | Offline contracts for CI, artifacts, workflow wiring and release tools. Select a case with `python3 -m unittest tests.tooling.test_NAME.CASE`. |
| `tests/fixtures/` | Synthetic and historical-format fixtures, including the shell segment prototype. Never substitute player saves. |
| `tests/diagnostics/` | Manual captures, visual audits and profiling scripts. Relocation preserves each distinct script and UID; it does not make every diagnostic a routine check. |

The canonical engine runner owns the stable suite IDs and result markers in
`SUITES`. Select those IDs with `--only`; `staff-start` retains its five ordered
starts. The runner resolves each ID to one `test_*.gd` resource beneath `tests/`,
so organizing a suite does not rename its CLI ID, logs or result receipts.
Duplicate IDs/resources and missing explicitly selected suites fail before
staging. `tools/engine_shards.py` imports the same canonical list; do not add a
second runner or suite registry. Update direct resource consumers atomically
when moving a suite, and retain its `.uid`.

Build/release orchestration is in [`tools/README.md`](../tools/README.md).
For complete tooling discovery, use
`python3 -m unittest discover -s tests/tooling -t . -p 'test_*.py'`;
the package owns import setup. The two native UI CLI wrappers share
`native_ui_runner.py` staging, profiles, imports, GL captures and receipts,
while keeping distinct suite/capture resources and stable commands.

Old `qa/` and `tests/capture_*.gd` diagnostics resolve under `tests/diagnostics/`;
the shell prototype is `tests/fixtures/shell_segment_contract.gd`.
Historical source-bound receipts retain original paths/hashes. The frozen startup
toolkit's temporary `qa/startup_descent` is generated input. Root shared fixtures
and manual scenario inputs retain resource labels used across families.
