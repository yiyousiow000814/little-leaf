# GitHub Web builds and releases

## Current publication status

itch.io publication is paused. `.github/workflows/release-itch.yml` is retained
for source history with a manual `workflow_dispatch` trigger and a constant-false
`gate` job (`if: ${{ false }}`). Tags, PRs and branch pushes do not start this
workflow. A manual dispatch skips the gate and cannot reach build or publish.
Adding `BUTLER_API_KEY`, merging a PR, or pushing a version tag does not enable
publication. Do not change the gate without separate publication authorization
and a reviewed workflow change.

CrazyGames is the current export target; CI produces a separate variant for
review, not an automatic deployment. See [the variant guide](crazygames-variant.md).
The `0.1.10` developer preview uses `draft` notes dated `2026-10-08`.
The prepared release was not published. Interactive tutorial and authentic
fresh-customer quality work must be validated before official submission.
Draft metadata suppresses the released-version label and unread update badge;
source, export, browser and portal acceptance remain separate checks.
The itch.io workflow remains disabled, and neither metadata nor test success
reenables it.

## Daily development

Pull requests, pushes to `main`, and **Actions → Check and build Web → Run workflow** run the engine tests and produce a downloadable Web build. They do not receive the itch secret or publish the game. Merging the workflow does not publish anything.

Downloadable builds and test evidence stay in Actions for **7 days**. Keep any release artifact needed longer. Standard GitHub-hosted runners are free for public repositories; [billing rules](https://docs.github.com/en/billing/concepts/product-billing/github-actions) differ for private repositories or changed runner/storage settings.

## Requirements before any future publication

This is a checklist for a separately authorized future release, not an active
publish procedure:

1. Resolve the candidate's review gaps and obtain explicit approval for the
   intended release and destination. Keep notes `draft` until that point.
2. Review the workflow change that would deliberately restore a publishing
   trigger and remove the constant-false gate. Do not assume a tag will publish;
   follow only the trigger in that approved workflow revision.
3. Update `project.godot` and `data/release_notes.json` in a reviewed PR. Both
   versions must match; publication checks still require notes marked `released`,
   shipped changes, a nonfuture date and a stable `vX.Y.Z` tag at the exact
   reviewed commit already in `main` history. Never move or reuse a release tag.
4. Require **Check and build Web** to pass on the intended commit. Review the Web
   build in a fresh browser profile and a separate copied-save profile, leaving
   real player data untouched. Passing prior-commit checks is not sufficient.
5. If the itch destination is authorized again, the retained publisher targets
   `siowyiyou/little-leaf:html5`, rebuilds the approved source and records its
   source SHA, version and itch build ID. Verify [the live game](https://siowyiyou.itch.io/little-leaf)
   after an authorized upload, including fresh and copied-save startup.

If credentials are needed for that future authorized release, the owner must
personally add the existing legitimate Butler/wharf credential as repository
Actions secret `BUTLER_API_KEY`. Never send its value in chat, commit it or print
it in logs. A saved secret does not verify access or enable the paused workflow.
See [GitHub Secrets](https://docs.github.com/en/actions/how-tos/write-workflows/choose-what-workflows-do/use-secrets)
and [Butler CI authentication](https://itch.io/docs/butler/login.html).

## Retained checks and safety

- Official Godot **4.6.3**, its non-threaded Web template, Butler **15.31.0**, and GitHub actions are pinned. Downloads are SHA-256 checked before use; an installer receipt binds the extracted engine/template hashes to those archives
- Engine tests use disposable copies and synthetic profiles. Local `--local-tools` smoke exports are explicitly ineligible for publication. The export uses unchanged tracked game inputs and gets a packed-resource startup check
- Each Web artifact includes source/test/file hashes in `release-manifest.json`. The publisher downloads that run's exact artifact ID and checks its digest and files
- The required notice at `docs/third-party/GODOT-AA-LICENSE.txt` is copied to the Web artifact as `GODOT-AA-LICENSE.txt` and included in its hashes
- The itch key is used only by publishing steps. Raw Butler output is suppressed, and repository permissions are read-only
- The retained publisher serializes release runs. If reauthorized, avoid simultaneous manual itch uploads or multiple queued releases; GitHub keeps only one pending run by default

## If a future authorized release stops

- **Missing/invalid secret:** review its name and permissions personally; never print the value
- **Version mismatch or unmerged commit:** correct metadata or merge the reviewed source first
- **Pending itch build or unknown live version:** inspect the existing upload before trying again
- **Same/newer version already exists:** no upload occurs. An intentionally approved recovery needs a separately reviewed release; there is no automatic rollback override
- **Upload error or timeout:** the build may already be on itch. Check its build ID and channel before retrying; the script never retries an upload automatically

Status requests have a 60-second limit, the upload attempt ten minutes, and processing observation another ten minutes within a 30-minute job. Protect repository write/tag access: workflow code cannot defend against a compromised maintainer. Optional protected tags/reviewer settings are not changed by this pipeline.

[Godot export](https://docs.godotengine.org/en/4.6/tutorials/editor/command_line_tutorial.html) · [Godot assets](https://github.com/godotengine/godot-builds/releases/tag/4.6.3-stable) · [Butler assets/source](https://github.com/itchio/butler/releases/tag/v15.31.0) · [Butler uploads](https://itch.io/docs/butler/pushing.html)
