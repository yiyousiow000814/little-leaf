# Development

## Roadmap and documentation

Codex contributors start with the root [AGENTS.md](../../AGENTS.md); it links this guide without duplicating the detailed instructions.

The [all-version roadmap](../roadmap.md) is the single canonical editing home for product scope, dependencies and current status through 0.3.2, including the separate 10a changes and all 76 outcomes for 0.1.11. Read its current-state section before historical evidence. Library master v3 remains a historical snapshot and has not been synchronized to the merged repository roadmap; a refreshed document export is a separate requested action, not another editable plan.

This page contains developer instructions and the technical reference directory. Feature contracts describe their stated source/date; they do not maintain competing release status. The [archive](../testing/history/README.md) preserves historical approvals, failed evidence and source recovery.

## Run

Open `project.godot` in Godot **4.6.3**, use **GL Compatibility**, and press **F5**. From the repository root, `godot --path .` also starts the game.

Normal play reads and writes local saves. Use a separate profile and copied saves for experiments.

## Test

With Python 3 and Godot 4.6.3 on Linux or macOS:

```sh
python3 tests/run_integration_candidate.py --help
```

Choose the smallest check that observes the affected behavior, then use `--only` followed by those existing test names and `--output` with a new disposable directory. Set `GODOT_BIN` if the executable is not named `godot`.

Deeper diagnostics must answer a specific symptom or hypothesis; deeper does not mean enabling every test, profiler or recording. Expand only for a failure, dependency interaction or unresolved concern. Preserve important save-integrity checks and follow required release gates separately. Once relevant checks pass, continue the task instead of blanket reruns.

The runner uses a disposable project and generated saves. It checks engine behavior, not browser storage or rendered visuals.

The [verification entrypoint](../../tests/README.md) separates regression checks,
tooling guards, fixtures and manual diagnostics. The [CI command guide](../../ci/README.md)
classifies recurring checks, on-demand tools and historical investigations.

Current wardrobe visual acceptance is held until the finished 3D-authored character foundation. Candidate clothing code/tests do not substitute for that gate or approval of actual game pixels. Preserve the original 2D isometric game presentation. Coordinate active owners through the integration lead. FPS PR128 is user-owned; assistants do no FPS implementation or measurements.

## Build

For automated builds and publishing, see [GitHub Web builds and releases](../release/README.md).

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
- `tests/`: repeatable regression suites and browser harnesses; `tooling/` holds CI contracts, `fixtures/` holds synthetic source-bound inputs, and `diagnostics/` holds reusable captures, audits and profiling helpers. State whether a check covers engine behavior, browser behavior, or rendered output. Generated screenshots, traces, logs, exports and disposable profiles belong in ignored output directories.
- `ci/`: build, validation, release-metadata, and publishing helpers. Build/test success is separate from permission to publish.
- `.github/workflows/`: orchestration of checks, builds, GitHub Releases, and platform publication. Keep release creation and platform deployment as distinct operations.
- `docs/`: this developer guide, one roadmap, release guidance and licenses. `design/`, `development/`, `art-audio/`, `testing/` and `release/` group guidance by reader purpose. Each area keeps its dated evidence in `history/`; the roadmap alone maintains current product status. Keep current roadmap status in one place.
- `assets/`, `shaders/` and `data/`: preserve source/import identity, licensing and release metadata; documentation cleanup does not relocate runtime resources.
- `firebase/`: rules and emulator contracts; use synthetic fixtures, never player data or live rules without separate authorization.

## Branch and review hygiene

Keep each work branch tied to a focused PR. State its purpose, base, scope, validation, and any dependent PRs. Retire completed or superseded branches after their source and useful evidence are durably preserved.

One coherent related feature/change uses one principal PR, including its code, tests and fixes. Do not open successor experiment PRs for the same feature. Audit and consolidate existing overlaps with history and evidence preserved; include each dependency-relative delta once. Historical PR links are evidence, not additional completed features.

A temporary integration or preview branch needs a clearly marked tracking draft with pinned source references and an explicit retirement plan. It does not replace separately reviewed feature or platform PRs, and must not become a bundled merge shortcut.

Keep runtime changes, platform integration, test-only repairs, and deployment changes independently reviewable. Prefer a small documentation update to an unrelated cleanup or file move. Preserve asset inputs, history, and recovery evidence before removing obsolete material.

## Project files

Keep asset inputs, `.import` settings and script `.uid` files tracked. Some fonts and HUD assets use `importer="keep"`; preserve those settings. Generated `.godot/` files, exports and player saves stay out of Git.

See [assets and licenses](../art-audio/README.md) before reusing or distributing content. Older review notes and recovery records are in the [archive](../testing/history/README.md).

## Technical references

### Gameplay, service and persistence

- [Dishwashing](dishwashing.md), [meal patience](single-guest-patience.md), [stove work-space reservations](stove-work-reservation.md).
- [Outside FIFO queue](outside-queue.md), [parking](parking.md), [street pedestrians](street-pedestrians.md).
- [Baseline economy](economy-019.md), [furniture refunds](decoration-refund-010.md), [Build refunds](decoration-build-refund-010.md). Furniture and Build transaction semantics are distinct; neither document replaces the other.
- [Save diagnostics/recovery](save-log.md), [retained diagnostic eligibility](retained-cloud-diagnostic.md).

### Character, routing and building contracts

- [Character authoring/accessory contract](../design/cute-staff-accessories-011.md), [routing design](../design/rc-inspired-routing-011.md), [routing QA cases](../testing/rc-inspired-routing-011-qa.md).
- [Starter wall design](../design/starter-wall-grid-segments.md), [implementation review](../design/starter-wall-implementation-review.md).
- Scoped acceptance: [characters/wardrobes](../testing/acceptance/011-characters-wardrobes.md), [furniture/depth](../testing/acceptance/011-furniture-depth.md), [land/reception/routing](../testing/acceptance/011-land-reception-routing.md), [street/starter/interface](../testing/acceptance/011-street-starter-interface.md), [four separate gates](../testing/acceptance/10a-011-additional-gates.md).

### Startup, browser and publication

- [Branded startup](branded-startup-010.md), [Welcome entry motion](entry-motion-010.md).
- [Fresh tutorial browser gate](../testing/fresh-tutorial-browser-gate.md), [wall-save browser compatibility](../testing/wall-web-compatibility.md), [CrazyGames adapter/export contract](../release/crazygames-variant.md).
- [Trusted itch preview](../release/itch-trusted-preview-candidate.md): preparation and identity restrictions; preview is not deployed or hosted-accepted.
- [Interactive tutorial](../testing/interactive-tutorial.md), [compensation Inbox](../testing/compensation-inbox.md), [builds/releases](../release/README.md), [assets/licenses](../art-audio/README.md).

## Maintaining the documentation

Keep every unique requirement in the roadmap or a clearly linked technical contract. Before removing duplication, check inbound links, workflows/export manifests, runtime resource readers, QA output paths and private recovery dependencies. Move one coherent set at a time, preserve historical source/failed evidence, and update links atomically. Do not move runtime folders or shipped notices for cosmetic tidiness. Generated profiles, private reference images, account data and operational handoffs stay outside public documentation.

The existing `docs/litter-remnants-visibility/` and `docs/role-boundaries/` placeholders remain at their QA output paths. `docs/third-party/` remains at the paths consumed by build/export instructions.
