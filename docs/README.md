# Little Leaf documentation

Start with the [repository README](../README.md) to open the game. Read the [canonical roadmap](roadmap.md) before choosing work: it is the single current editing plan, with original requirements through 0.3.2, dependencies, ownership and acceptance gates. Library master v3 is a historical snapshot, not a synchronized editing copy.

Choose the guide for what you want to do:

| Purpose | Start here | What it covers |
| --- | --- | --- |
| Design | [Design](design/README.md) | Player outcomes, character and building contracts, routing rules |
| Development | [Development](development/README.md) | Open/build the project, implementation and save boundaries |
| Art and audio | [Art and audio](art-audio/README.md) | Asset permissions, provenance and source-bound visual records |
| Testing | [Testing](testing/README.md) | Acceptance criteria, browser gates, focused regression and visual evidence |
| Release | [Release](release/README.md) | Checked builds, platform previews, publication and recovery |

For agent work, [AGENTS.md](../AGENTS.md) links the canonical rules and developer commands. Generated profiles, screenshots, logs and private operational handoffs stay outside tracked source.

## Reading historical evidence

An area's `history/` preserves dated approvals, reviews, failed evidence and recovery records. Their statements describe the source and date recorded there; they do not establish current implementation, merge, release or pixel acceptance. Use the roadmap's current-state section first.

The [historical evidence directory](testing/history/README.md) links original reviews across these areas. [Source recovery records](development/history/repository-notes.md) and the [original manifest](development/history/SOURCE_MANIFEST.json) retain original hashes and paths. Commands and JSON inside historical records refer to their original repository or capture environment.

Distribution notices live under `art-audio/third-party/`; the retained QA output placeholders live under `testing/litter-remnants-visibility/` and `testing/role-boundaries/`. Their build and diagnostic consumers use these category paths.
