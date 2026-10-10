# Working on Little Leaf

Read the [canonical roadmap](docs/roadmap.md), the single current editing plan, for product scope, ownership and acceptance gates, then the [developer guide](docs/development/README.md) for detailed commands and references. Read the roadmap's current-state section before dated historical contracts; those contracts are evidence, not current completion status.

## Run and verify

Use Godot **4.6.3**, **GL Compatibility**, with matching export templates. Open `game/project.godot` and press F5, or run `godot --path game` only in an isolated test profile: normal play writes saves.

From the repository root, with Python 3 and Godot available:

```sh
python3 tests/run_integration_candidate.py --help
python3 tests/run_integration_candidate.py --only test_direct_janitor_cleanup --output /tmp/little-leaf-janitor-review
```

The second command is an example for janitor cleanup changes, not a default suite. Choose only the existing test names that observe the affected behavior and a new disposable output directory; use `python` where that is the Python 3 command and set `GODOT_BIN` when needed. The runner's disposable project does not establish browser or visual acceptance. Deeper diagnostics must answer a specific symptom or hypothesis; do not enable everything merely because the investigation is deeper. Follow required release gates separately.

## Edit boundaries and evidence

- Keep changes minimal and within the requested scope. Coordinate active owners before implementation; include each stacked dependency delta once in one coherent related PR.
- Title PRs `type: specific change`, without a version prefix. Apply the plain delivery-version label `0.1.10a` or `0.1.11`, using the earliest intended delivery confirmed by the roadmap and owner; list other affected versions in the body and report ambiguous scope rather than guessing. Use `fix`, `feat`, `refactor` or `docs`; use `test` only for independently meaningful testing changes. Keep related code, necessary tests and docs in one PR. Use GitHub Draft/Ready state rather than WIP/done in titles. Record roadmap IDs, changes, actual verification and remaining gaps in the body; link PRs from the canonical roadmap and update status on merge.
- Protect original player saves, account/session ownership, cleanup and tutorial behavior. Use generated fixtures or copied saves in disposable profiles; never clear the user's browser storage or alter live Firebase rules without explicit authorization.
- Implement the requested change and run the minimum relevant checks, then give the user an actual playable or visual candidate. After the user confirms it is good, finalize and merge within the authorized scope; avoid unrelated expanded test runs. Clearly report material save, build, security or data-loss blockers before acceptance or merge.
- Keep the Godot project and gameplay in `game/`, browser/cloud integration in `platform/web/` and `platform/firebase/`, verification in `tests/` (including `tooling/`, `diagnostics/` and `fixtures/`), and publishing helpers in `tools/` and `.github/workflows/`. Preserve assets, import settings, script UIDs, licenses and recovery evidence. See the developer guide for full boundaries.
- Keep generated logs, screenshots, exports and private handoffs outside tracked source. Maintain current product status in the roadmap; link detailed contracts instead of duplicating them or creating version-specific agent guides.
- Organize `docs/` within `design/`, `development/`, `art-audio/`, `testing/` and `release/`, with only `README.md` and `roadmap.md` at its root. Preserve every original license and evidence file; update build, diagnostic and link consumers atomically when paths move.
- Preserve the original 2D isometric art and camera presentation. Pin evidence to the tested commit/tree and distinguish code present, tests passed, inspected game pixels, merged and released. For visual changes, inspect rendered output and retain source-bound before/after evidence; test success alone does not accept the pixels or authorize publication.

For build and publication procedures, read [release guidance](docs/release/README.md); for reuse and distribution, read [licenses](docs/art-audio/README.md).
