# Verification

Keep default checks observable and select deeper diagnostics for a specific
symptom. Tests, fixtures and manual captures now share this home:

| Location | Use |
| --- | --- |
| `tests/test_*.gd`, browser/Node tests and `run_*.py` | Existing focused gameplay, storage and browser regressions. Ordinary CI retains the critical save-integrity gates. |
| `tests/service/` | Guest/worker service and ordered staff-start engine regressions; use stable canonical IDs. |
| `tests/world/` | Environment, parking, traffic and outside-queue engine suites; stable `--only` IDs remain in the canonical runner. |
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

Build, release and diagnostic orchestration is documented in
[`tools/README.md`](../tools/README.md). Tooling discovery uses
`python3 -m unittest discover -s tests/tooling -t . -p 'test_*.py'` when a complete
tooling run is appropriate. The package sets its CI import path once; individual
test files do not carry competing import setup. The Build/Tiles and shell-segment
native CLI entrypoints share `native_ui_runner.py` for disposable staging,
profiles, imports, GL captures and receipts; their commands and suite/capture
resources remain distinct.

Old capture, audit and profiling paths under `qa/`, plus `tests/capture_*.gd`,
now resolve under `tests/diagnostics/`. The shell prototype moved separately to
`tests/fixtures/shell_segment_contract.gd`. Historical source-bound receipts preserve their original
paths and hashes. The startup comparison's frozen toolkit still stages its own
temporary `qa/startup_descent` directory; that is generated diagnostic input,
not a tracked source folder to relocate.
