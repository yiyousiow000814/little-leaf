# Verification

Keep default checks observable and select deeper diagnostics for a specific
symptom. Tests, fixtures and manual captures now share this home:

| Location | Use |
| --- | --- |
| `tests/test_*.gd`, browser/Node tests and `run_*.py` | Existing focused gameplay, storage and browser regressions. Ordinary CI retains the critical save-integrity gates. |
| `tests/tooling/` | Offline contracts for CI, artifacts, workflow wiring and release tools. Select a case with `python3 -m unittest tests.tooling.test_NAME.CASE`. |
| `tests/fixtures/` | Synthetic and historical-format fixtures, including the shell segment prototype. Never substitute player saves. |
| `tests/diagnostics/` | Manual captures, visual audits and profiling scripts. Relocation preserves each distinct script and UID; it does not make every diagnostic a routine check. |

Build, release and diagnostic orchestration is documented in
[`ci/README.md`](../ci/README.md). Tooling discovery uses
`python3 -m unittest discover -s tests/tooling -t . -p 'test_*.py'` when a complete
tooling run is appropriate. The package sets its CI import path once; individual
test files do not carry competing import setup.

Old capture, audit and profiling paths under `qa/`, plus `tests/capture_*.gd`,
now resolve under `tests/diagnostics/`. The shell prototype moved separately to
`tests/fixtures/shell_segment_contract.gd`. Historical source-bound receipts preserve their original
paths and hashes. The startup comparison's frozen toolkit still stages its own
temporary `qa/startup_descent` directory; that is generated diagnostic input,
not a tracked source folder to relocate.
