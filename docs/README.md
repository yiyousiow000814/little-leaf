# Development

## Run

Open `project.godot` in Godot **4.6.3**, use **GL Compatibility**, and press **F5**. From the repository root, `godot --path .` also starts the game.

Normal play reads and writes local saves. Use a separate profile and copied saves for experiments.

## Test

With Python 3 and Godot 4.6.3 on Linux or macOS:

```sh
python3 tests/run_integration_candidate.py --output /tmp/little-leaf-qa
```

Use a new output directory for each run. Set `GODOT_BIN` if the executable is not named `godot`. Add `--only` followed by test names for a focused run; `--help` lists the choices.

The runner uses a disposable project and generated saves. It checks engine behavior, not browser storage or rendered visuals.

[0.1.11 approved design directions and pending implementation](design-011-approved-plan.md): staff accessories and trousers, eight-direction routing, and coordinated save-capability gates; documentation only, with runtime and visual acceptance pending.

## Build

For automated builds and publishing, see [GitHub Web builds and releases](github-release.md).

Use the **Web** export preset with Godot 4.6.3 and its matching non-threaded release template at `export_templates/web_nothreads_release.zip`.

```sh
mkdir -p build/web
godot --headless --path . --export-release Web build/web/index.html
cp docs/third-party/GODOT-AA-LICENSE.txt build/web/
```

Serve the exported folder over HTTP to test it. Keep the license notice, custom HTML shell and export include/exclude rules.

## Repository boundaries

- `scripts/`: gameplay state, UI, rendering, and engine-side adapters. Keep game rules independent of publishing tools; route platform-specific behavior through the existing adapters.
- `web/`: browser shells and JavaScript storage/platform bridges. Keep browser persistence and SDK integration here rather than in release scripts.
- `tests/`: repeatable regression suites, browser harnesses, and small source-bound fixtures. State whether a check covers engine behavior, browser behavior, or rendered output.
- `qa/`: reusable capture, profiling, and diagnostic helpers. Generated screenshots, traces, logs, exports, and disposable profiles belong in ignored output directories, not beside the helpers.
- `ci/`: build, validation, release-metadata, and publishing helpers. Build/test success is separate from permission to publish.
- `.github/workflows/`: orchestration of checks, builds, GitHub Releases, and platform publication. Keep release creation and platform deployment as distinct operations.
- `docs/`: current development guidance and feature contracts; `docs/archive/` keeps historical review and recovery context. Link from this guide when adding an enduring development workflow.

## Branch and review hygiene

Keep each work branch tied to a focused PR. State its purpose, base, scope, validation, and any dependent PRs. Retire completed or superseded branches after their source and useful evidence are durably preserved.

A temporary integration or preview branch needs a clearly marked tracking draft with pinned source references and an explicit retirement plan. It does not replace separately reviewed feature or platform PRs, and must not become a bundled merge shortcut.

Keep runtime changes, platform integration, test-only repairs, and deployment changes independently reviewable. Prefer a small documentation update to an unrelated cleanup or file move. Preserve asset inputs, history, and recovery evidence before removing obsolete material.

## Project files

Keep asset inputs, `.import` settings and script `.uid` files tracked. Some fonts and HUD assets use `importer="keep"`; preserve those settings. Generated `.godot/` files, exports and player saves stay out of Git.

See [assets and licenses](licenses.md) before reusing or distributing content. Older review notes and recovery records are in the [archive](archive/README.md).
