# CI commands and contracts

Start with `.github/workflows/ci.yml` for ordinary validation. It calls
`build-web.yml`, which owns the full native/export/browser save gates. Select
deeper diagnostics only for the symptom being investigated; the table below is
an inventory, not a checklist to run after every edit.

## Recurring validation and build commands

| Command | Responsibility |
| --- | --- |
| `install_tools.py` | Install checksum-pinned tools into a disposable location. |
| `verify_prebaked_atlases.py` | Check checked-in atlas inputs before export. |
| `build_web.py` | Export the source already checked by the complete native gate. |
| `build_crazygames.py` | Build the separate platform variant after the Web gate. |
| `run_firebase_focused.py` | Run one named Firebase gate and bind its log to this source/run. |
| `prepare_browser_qa.py wall` | Derive old/new save compatibility coordinates from exact validated exports. |
| `prepare_browser_qa.py cloud` | Derive six synthetic cloud recovery layouts for compiled browser checks. |

The cloud scenario also serves the historical retained-artifact diagnostic. The
ordinary Web workflow selects it only for its optional Firebase preview gates.
The wall scenario remains required by the ordinary save compatibility gate.

## Parallel complete CI

The reusable Web workflow runs the source/atlas guard first, then four independent
engine shards alongside the historical client build. `engine_shards.py` assigns
every canonical suite and all five staff-start cases using measured suite times;
new suites receive a default weight and remain mandatory. Each runner keeps its
own lock, project and disposable profile. The merger rejects missing, duplicate,
failed or mismatched source/run/attempt reports before the unchanged full-suite
export validator permits one ordinary export and one CrazyGames variant.

Browser lanes cover play (Inbox and tutorial), compatibility (old/new saves),
and recovery (IndexedDB, save log and WebKit). Compatibility receives both
generated projects, including imported resources, and installs the same pinned
Godot toolchain. Optional Firebase staging receives the candidate project and
all required browser evidence; its freshness validator remains unchanged.
Artifacts are scoped to this run, attempt and source. Profiles are never uploaded.
The final `gate` exposes release outputs only after every required job succeeds;
failed, cancelled or skipped mandatory jobs cannot qualify an export.

The timing weights come from main `af61a3f` run `38058638557`: 26m18s overall,
11m18s for the native suite. Estimated shard work is about 167s each, excluding
import, setup, queues and artifact transfer; this estimate is not a measured CI
speedup. Parallelism uses the existing Ubuntu runners, capped at four engine
shards and three browser lanes. Extra setup/import and artifact transport can
increase total runner minutes even while reducing elapsed time.

## Explicit staging, publication, and diagnostics

| Command | Class | Responsibility |
| --- | --- | --- |
| `build_firebase.py` | On demand staging | Stage an unpublished Firebase variant with complete fresh source/run evidence. |
| `release_metadata.py` | Release preparation | Validate version/tag/release notes and main ancestry; also provide version ordering. |
| `publish_itch.py` | Authorized publication | Validate the tested release artifact and approved itch channel before publication. |
| `deploy_firebase_hosting.py` | Authorized publication | Verify/stage or deploy an exact Firebase variant; preserve WIF and hosting contracts. |
| `github_latest.py` | Release completion | Reconcile Latest after publication without creating a tag or release. |
| `reuse_welcome_web.py` | Manual diagnostic | Bind a retained Web artifact to its exact/equivalent full source tree. |
| `capture_cloud_recovery_ui.py` | On demand visual diagnostic | Capture paired historical/current frames with isolated profiles and retained receipts. |
| `cloud_flow_diagnostic.py` | Historical branch diagnostic | Validate eligibility and retained compiled artifacts for the branch-specific cloud flow investigation. |

Workflows retain their existing triggers: welcome audio and startup comparison
are manual; paired cloud visuals have scoped PR paths plus manual dispatch;
the retained cloud flow workflow is restricted to its named branch. Merely being
listed here does not authorize publication or deployment.

## Shared implementations and tests

`artifacts.py` owns file hashing, payload verification, and the complete Web
source gate. Firebase and CrazyGames call that contract directly; neither variant
depends on the other. Variant-specific provenance, staging, namespace and release
policy remain in their respective commands. `toolchain.json` pins the installer;
`release_metadata.py` is the single version ordering implementation.
`build_itch_trusted_preview.py` is a shared preparation module used by the
explicit Firebase preview option; it does not add a standalone launch command
or authorize deployment.

`test_*.py` files cover these contracts without engines or publication. Select
the affected cases with `python3 -m unittest tests.tooling.test_NAME.CASE`; do not run every
suite for a structural edit. `tests/tooling/test_prepare_browser_qa.py` uses synthetic engine
results to verify scenario selection, disposable profiles and measured-layout
failure handling. The native/browser save regressions remain in `tests/` and
the existing ordinary workflow.

The old `prepare_wall_compatibility.py` and `prepare_cloud_geometry.py` entrypoints
are retired in this source. Use the two scenarios above. Historical exports run
their own checked-out scripts; their old source files and evidence are retained
in Git history.
