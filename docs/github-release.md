# GitHub Web builds and releases

## One-time setup

In this repository, open **Settings → Secrets and variables → Actions → New repository secret**. Name it **`BUTLER_API_KEY`**, then personally paste the existing authorized itch Butler/wharf credential and save it. Never send its value in chat, commit it, or print it in logs.

No extra enable switch, new token, or paid service is needed. Saving a secret does not verify its validity; Butler checks access before uploading. See [GitHub Secrets](https://docs.github.com/en/actions/how-tos/write-workflows/choose-what-workflows-do/use-secrets) and [Butler CI authentication](https://itch.io/docs/butler/login.html).

## Daily development

Pull requests, pushes to `main` or the named diagnostic maintenance branch, and **Actions → Check and build Web → Run workflow** run the engine tests and produce a downloadable Web build. They do not receive the itch secret or publish the game. Merging the workflow does not publish anything.

Downloadable builds and test evidence stay in Actions for **7 days**. Keep any release artifact needed longer. Standard GitHub-hosted runners are free for public repositories; [billing rules](https://docs.github.com/en/billing/concepts/product-billing/github-actions) differ for private repositories or changed runner/storage settings.

## Publish an approved version

1. Update `project.godot` and `data/release_notes.json` in a reviewed PR. Both versions must match; release notes must be marked `released`, describe the changes, and have a nonfuture date.
2. Wait for **Check and build Web** to pass on the intended commit. Review the Web build in a fresh browser profile and a separate copied-save profile. Leave real player data untouched.
3. Only after publication is approved, create and push one new tag, such as **`v0.1.6`**, at that exact reviewed commit already in `main` history. Later changes on `main` do not block this fixed tag. Never move or reuse a release tag.
4. Watch **Release Web to itch.io**. It tests and rebuilds the tagged commit, then uploads to **`siowyiyou/little-leaf:html5`**. The summary records its source SHA, version and itch build ID.
5. Verify [the live game](https://siowyiyou.itch.io/little-leaf), including fresh and copied-save startup. Successful upload processing does not replace browser, persistence, rendering or audio checks.

Only a newly created stable `vX.Y.Z` tag from `main`, or the one-off diagnostic tag below, can publish. Ordinary merges, PRs and manual build runs cannot. The workflow itself never creates a tag or changes itch embed settings.

## One-off save inspection diagnostic

`0.1.9-alpha-1` adds **Settings → Log** to inspect save presence and save/load diagnostics. It is based on shipped **0.1.8**, not the broader 0.1.9 gameplay work, and does **not** claim to fix the reported save loss or change the save schema.

1. Retain `v0.1.8` at exact commit `9110ebd9a2d6cbf4d2af303be0e244e660c0f7fc`, and retain a verified copy of its published Web artifact and itch build ID for any separately authorized recovery. GitHub's seven-day artifact retention is not a backup. Never reset/revert `main` or move the shipped tag.
2. Create the maintenance branch **`release/0.1.8-save-diagnostic`** at that exact 0.1.8 commit. Prepare only the diagnostic, its metadata, and the narrowly scoped release support in a PR targeting this branch. Review and **squash merge once** so the released commit has exactly one parent: the pinned 0.1.8 commit. The branch must have no extra merge or intermediate commits.
3. Wait for **Check and build Web** on the exact maintenance commit, including the diagnostic regression tests. Inspect its Web build in a fresh profile and a separate copied-save profile. Confirm the release notes date is the actual UTC publication date; the prepared date is **2026-10-05**.
4. Obtain publication approval that explicitly covers replacing the existing game entry at [Little Leaf](https://siowyiyou.itch.io/little-leaf). This is the same **`siowyiyou/little-leaf:html5`** channel, not a preview channel. Keeping the game entry helps reproduce the phone/browser storage problem but does not prove storage availability or persistence.
5. Only then create the new immutable tag **`v0.1.9-alpha-1`** at the reviewed maintenance tip. Both the pre-build gate and pre-upload gate fetch only fixed refs and verify: the base tag still names the pinned 0.1.8 source, the alpha tag equals the checked-out source and maintenance tip, and that source is the single squash commit on 0.1.8. No arbitrary branch/ref override or other prerelease tag is accepted.
6. The existing GitHub Actions → Butler route and `BUTLER_API_KEY` secret mechanism publish the exact tested artifact. The alpha may replace only a completed **0.1.8** HTML5 build with no pending upload. Duplicate alpha, stable 0.1.9, newer, unknown, and other live baselines stop before upload. After processing, verify the served version and Settings → Log on the user's existing phone/browser entry before interpreting the diagnostics.

Stable releases keep their existing `main` ancestry requirement. SemVer ordering permits a later reviewed stable `0.1.9` to replace `0.1.9-alpha-1`; it forbids publishing `0.1.8` over the alpha. The original source/tag and retained artifact are recovery material only: rollback still needs separate review and authorization, and there is no rollback bypass in this pipeline.

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
