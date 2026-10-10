# GitHub Web builds and releases

## One-time setup

In this repository, open **Settings → Secrets and variables → Actions → New repository secret**. Name it **`BUTLER_API_KEY`**, then personally paste the existing authorized itch Butler/wharf credential and save it. Never send its value in chat, commit it, or print it in logs.

No extra enable switch, new token, or paid service is needed. Saving a secret does not verify its validity; Butler checks access before uploading. See [GitHub Secrets](https://docs.github.com/en/actions/how-tos/write-workflows/choose-what-workflows-do/use-secrets) and [Butler CI authentication](https://itch.io/docs/butler/login.html).

## Daily development

Pull requests, pushes to `main`, and **Actions → Check and build Web → Run workflow** run the engine tests and produce a downloadable Web build. They do not receive the itch secret or publish the game. Merging the workflow does not publish anything.

Downloadable builds and test evidence stay in Actions for **7 days**. Keep any release artifact needed longer. Standard GitHub-hosted runners are free for public repositories; [billing rules](https://docs.github.com/en/billing/concepts/product-billing/github-actions) differ for private repositories or changed runner/storage settings.

## Publish an approved version

1. Update `project.godot` and `data/release_notes.json` in a reviewed PR. Both versions must match; release notes must be marked `released`, describe the changes, and have a nonfuture date.
2. Wait for **Check and build Web** to pass on the intended commit. Review the Web build in a fresh browser profile and a separate copied-save profile. Leave real player data untouched.
3. Only after publication is approved, create and push one new tag, such as **`v0.1.6`**, at that exact reviewed commit already in `main` history. Later changes on `main` do not block this fixed tag. Never move or reuse a release tag.
4. Watch **Release Web to itch.io**. It tests and rebuilds the tagged commit, then uploads to **`siowyiyou/little-leaf:html5`**. The summary records its source SHA, version and itch build ID.
5. Verify [the live game](https://siowyiyou.itch.io/little-leaf), including fresh and copied-save startup. Successful upload processing does not replace browser, persistence, rendering or audio checks.

Only a newly created `vX.Y.Z` or single-lowercase-letter hotfix `vX.Y.Z[a-z]` tag can publish (for example, `v0.1.10a`, `v0.1.10b`, `v0.1.10c`). Hotfixes order numerically by base, then by letter: `0.1.10 < 0.1.10a < … < 0.1.10z < 0.1.11`. Uppercase, multiple-letter, prerelease and build-metadata release tags are rejected. Existing valid SemVer prerelease/build-metadata itch baselines remain recognized; duplicates and rollbacks are still refused. Both the project and release notes must contain the exact hotfix version. Ordinary merges, PRs and manual build runs cannot. The workflow itself never creates a tag or changes itch embed settings.

## Checks and safety

- Official Godot **4.6.3**, its non-threaded Web template, Butler **15.31.0**, and GitHub actions are pinned. Downloads are SHA-256 checked before use; an installer receipt binds the extracted engine/template hashes to those archives
- Engine tests use disposable copies and synthetic profiles. Local `--local-tools` smoke exports are explicitly ineligible for publication. The export uses unchanged tracked game inputs and gets a packed-resource startup check
- Each Web artifact includes source/test/file hashes in `release-manifest.json`. The publisher downloads that run's exact artifact ID and checks its digest and files
- The required notice at `docs/third-party/GODOT-AA-LICENSE.txt` is copied to the Web artifact as `GODOT-AA-LICENSE.txt` and included in its hashes
- The itch key is used only by publishing steps. Raw Butler output is suppressed, and repository permissions are read-only
- One release runs at a time. Avoid simultaneous manual itch uploads or multiple queued release tags; GitHub keeps only one pending run by default

## If a release stops

- **Missing/invalid secret:** review its name and permissions personally; never print the value
- **Version mismatch or unmerged commit:** correct metadata or merge the reviewed source first
- **Pending itch build or unknown live version:** inspect the existing upload before trying again
- **Same/newer version already exists:** no upload occurs. An intentionally approved recovery needs a separately reviewed release; there is no automatic rollback override
- **Upload error or timeout:** the build may already be on itch. Check its build ID and channel before retrying; the script never retries an upload automatically

Status requests have a 60-second limit, the upload attempt ten minutes, and processing observation another ten minutes within a 30-minute job. Protect repository write/tag access: workflow code cannot defend against a compromised maintainer. Optional protected tags/reviewer settings are not changed by this pipeline.

[Godot export](https://docs.godotengine.org/en/4.6/tutorials/editor/command_line_tutorial.html) · [Godot assets](https://github.com/godotengine/godot-builds/releases/tag/4.6.3-stable) · [Butler assets/source](https://github.com/itchio/butler/releases/tag/v15.31.0) · [Butler uploads](https://itch.io/docs/butler/pushing.html)

## Latest reconciliation

Each tag publishes its own source-only GitHub Release independently, initially without changing Latest. A separate promotion job rereads all release API pages and qualifies the highest normal numeric/single-letter release against main ancestry and exact tagged metadata. Delayed older runs therefore cannot downgrade Latest. Unknown Latest, API failures or moved tags stop promotion. Existing release content remains unchanged; an idempotent rerun may repair Latest through this separate verified reconciliation.

Only promotion uses the shared concurrency group, with `cancel-in-progress: false` and GitHub's documented `queue: max` (up to 100 pending jobs, not unlimited). If an excess pending promotion is canceled, another reconciliation sees all already-published releases; tag publication itself is independent. This serialization does not lock manual maintainer edits outside the workflow.

Reference: https://docs.github.com/en/actions/concepts/workflows-and-actions/concurrency

## Platform boundaries and historical records

- [CrazyGames adapter/export contract](crazygames-variant.md)
- [Trusted itch preview](itch-trusted-preview-candidate.md): preparation is separate from hosted acceptance and publication
- Historical [CrazyGames slice](history/crazygames-split-ledger.md), [release-metadata ownership](history/split-draft-ownership.md) and [10a overlay provenance](history/010a-release-overlay-provenance.json)
- [Asset permissions and required notices](../art-audio/README.md)

Use the [roadmap](../roadmap.md) for current readiness and authorization. Historical ledgers describe their pinned source/date, not the current shipped tree.
