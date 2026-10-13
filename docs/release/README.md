# GitHub Web builds and releases

## Shared tag qualification and independent platforms

The current source candidate follows the2026-10-12 user requirement: one
immutable approved tag consumes one successful exact-main CI build and complete
ordinary qualification; its common tag job runs final packed startup once and
retains one package. The Firebase qualification workflow derives the frozen
source's `/itch/` entry and trusted wrapper, then runs all focused gates and the
complete compiled same-page flow against those exact runtime bytes. Both
platforms consume that qualified packet. The itch publisher uploads a separately
bound, byte-identical copy of the original ordinary export to the existing
`html5` channel. Its account link keeps the existing Firebase Root URL and opens
a new tab. The `/itch/` runtime, trusted wrapper and complete same-page evidence
remain separately retained and qualified; they are not substituted for the
played ordinary entry. This is
source implementation pending final review/CI and activation; no new tag or
delivery has occurred. Earlier after-itch/manual contracts below remain
historical and are not widened to admit this new receipt type.

The common receipt pins source/tree/version/tag, original main run/attempt and
archive digest, common run/attempt1 and payload hashes. Both consumers fetch and
authenticate those exact API objects and runtime bytes; they never pick a
newest artifact or rerun engine/export/ordinary browser tests. The shared
same-page qualification runs all ten focused checks and its compiled cloud flow
once before either publisher receives credentials. Hosting then authenticates
the completed same-source ordinary-entry receipt and adds its actual Butler channel
sequence beside the unchanged main first-parent order in both loaded markers.
This bounded metadata projection retains the original qualified manifest and
entry bytes; runtime, source and evidence bytes stay unchanged. It lets legacy
channel-order clients and current main-order clients compare their own authority,
without inventing an itch sequence. A currently loaded client with no order
still cannot receive a same-family prerelease notice from metadata alone.
Hosting activation
uses the existing deployment workflow identity and Hosting-only scope after
fresh common/Firebase/source/artifact checks. Its complete current configuration
and rollback version are preserved; public receipts contain its configuration
digest rather than the raw configuration. No Auth/rules/IAM change is included.

Each target serializes its own publication. Both refuse a source that is older
or unrelated to the current target's known immutable source. The qualified
source order is an exact main first-parent ordinal, repository/root authority
and immutable chain digest; it is not a SHA comparison or upload timestamp.
Firebase's loaded marker and update endpoint bind that order. Ordinary local
itch has no Firebase updater; its completed publication receipt records the
same common identity. Legacy Butler order remains a distinct authority and is
never compared numerically with common order. Already-open legacy SHA clients
cannot be claimed to receive this new notice format; their transition remains
separate acceptance work.

A partial outcome stays partial: inspect each platform's receipt separately.
An inspected platform-only retry reuses the original common run/attempt and
archive; there is no internal upload/deploy retry or common rebuild. Failed or
uncertain mutations require reconciliation first. Firebase recognizes an exact
already-current marker without requesting a Google token; itch retains its
strict completed-build/duplicate safeguards. Missing, expired or changed
common/original qualification evidence stops delivery. The common package has
30-day retention, but the original main evidence's shorter lifetime still
limits eligibility; retention is not a promise of continuing qualification.

After an inspected pre-upload failure and a reviewed coordinator repair, the
existing **Release Web to itch.io** manual request can take one exact
`qualified_run_id`. An empty value still runs status diagnosis only. The named
`Retry qualified itch <run ID>` job authenticates the completed original
Firebase attempt and all immutable inputs before credentials, then uses the
unchanged publisher. Hosting accepts its completed first-attempt publication
only when its receipt binds that same qualified run; ordinary status requests
cannot activate Hosting. Use the fresh reviewed main workflow for this scoped
retry: rerunning an old job retains its old SHA and does not load a repair.

Only a newly created valid version tag from reviewed main history can create a
common qualification. PRs, main pushes, manual status requests and synthetic
test packages cannot create qualification or publish via this route. A named
platform retry consumes existing qualification and never rebuilds it.
GitHub source Releases/Latest,
hosted Google acceptance and gameplay acceptance remain separate facts. See
[GitHub workflow-run semantics](https://docs.github.com/en/actions/reference/workflows-and-actions/events-that-trigger-workflows#workflow_run)
for default-main execution; upstream data and artifacts are verified before
platform credentials.

## One-time setup

In this repository, open **Settings → Secrets and variables → Actions → New repository secret**. Name it **`BUTLER_API_KEY`**, then personally paste the existing authorized itch Butler/wharf credential and save it. Never send its value in chat, commit it, or print it in logs.

No extra enable switch, new token, or paid service is needed. Saving a secret does not verify its validity; Butler checks access before uploading. See [GitHub Secrets](https://docs.github.com/en/actions/how-tos/write-workflows/choose-what-workflows-do/use-secrets) and [Butler CI authentication](https://itch.io/docs/butler/login.html).

## Daily development

Pull requests, pushes to `main`, and **Actions → Check and build Web → Run workflow** run the engine tests and produce a downloadable Web build. They do not receive the itch secret or publish the game. Merging the workflow does not publish anything.

Downloadable builds and test evidence stay in Actions for **7 days**. Keep any release artifact needed longer. Standard GitHub-hosted runners are free for public repositories; [billing rules](https://docs.github.com/en/billing/concepts/product-billing/github-actions) differ for private repositories or changed runner/storage settings.

## Urgent 0.1.11 prereleases

Approved user policy on 2026-10-11: independently verified urgent fixes may ship before the complete 0.1.11 scope is finished. Use **`0.1.11-pre.<shortSHA>`** (tag **`v0.1.11-pre.<shortSHA>`**) to identify one frozen exact source. A short SHA identifies source; it does not encode release age. Preserve immutable source/tag/package identity, retain prior tags and the frozen 0.1.10d release, and qualify matching Firebase and itch deliveries. A platform upload, a GitHub source release and user gameplay acceptance remain separate facts. Cleanup merge authority does not accept new gameplay or authorize deployment.

Mark each such GitHub Release as a **prerelease** and preserve stable Latest. Update chronology must use independently qualified monotonic publication information; never compare SHA text lexically or interpret an all-digit hash as a release counter. Deriving the display version from the frozen source at build time must preserve exact artifact binding and avoid a commit referring to its own hash. Retain the ordinary save/account, atlas, browser, source/package and platform qualification gates for the actual urgent fix.

Historical support gap: main `d30115b6932af1ab28e30672996eae09becaef16` rejected this format. Merged PR176/181 added source-derived metadata and prerelease publication; exact-e0 delivery and PR186 are recorded in the roadmap. That delivery does not qualify a new source or the independent common-tag candidate above. Frozen0.1.10d ignores this format, and legacy SHA clients do not understand common ordering; do not claim those clients receive its notices.

## Publish an approved version

1. Update `game/project.godot` and `data/release_notes.json` in a reviewed PR. Both versions must match; release notes must be marked `released`, describe the changes, and have a nonfuture date.
2. Wait for **Check and build Web** to pass on the intended commit. Review the Web build in a fresh browser profile and a separate copied-save profile. Leave real player data untouched.
3. Only after publication is approved, create and push one new tag, such as **`v0.1.6`**, at that exact reviewed commit already in `main` history. Later changes on `main` do not block this fixed tag. Never move or reuse a release tag.
4. With the reviewed common-tag route enabled, watch **Check and build Web** produce the common tag receipt, then **Qualify Firebase release** produce the complete packet with separate ordinary itch and same-page surfaces. **Release Web to itch.io** publishes the unchanged ordinary Root/new-tab entry; Hosting then uses that completed receipt for compatible update metadata and publishes the qualified Root and `/itch/` surfaces. Common source/atlas/packed-startup qualification occurs once. Each platform retains its own outcome; one platform success does not establish the other delivery. See [qualified artifact reuse](qualified-artifact-reuse.md).
5. Verify [the live game](https://siowyiyou.itch.io/little-leaf), including fresh and copied-save startup. Successful upload processing does not replace browser, persistence, rendering or audio checks.

Only a newly created normal `vX.Y.Z`, single-lowercase hotfix `vX.Y.Z[a-z]`, or exact-source `vX.Y.Z-pre.<8 lowercase hex digits>` tag can qualify. The SHA form requires the committed `X.Y.Z-pre` family, explicit prerelease flag and exact full source; an all-digit hash remains opaque. Normal/hotfix versions retain numeric/base-letter ordering. Uppercase, multiple-letter and build-metadata tags are rejected. Common publication additionally requires a known immutable current baseline tag and forward source ancestry; unknown legacy labels stop for inspection. Ordinary merges, PRs and manual status/build runs cannot publish. No workflow creates a tag or changes itch embed settings.

## Checks and safety

- Official Godot **4.6.3**, its non-threaded Web template, Butler **15.31.0**, and GitHub actions are pinned. Downloads are SHA-256 checked before use; an installer receipt binds the extracted engine/template hashes to those archives
- Engine tests use disposable copies and synthetic profiles. Local `--local-tools` smoke exports are explicitly ineligible for publication. The export uses unchanged tracked game inputs and gets a packed-resource startup check
- Each Web artifact includes source/test/file hashes in `release-manifest.json`. The publisher downloads that run's exact artifact ID and checks its digest and files
- The required notice at `docs/art-audio/third-party/GODOT-AA-LICENSE.txt` is copied to the Web artifact as `GODOT-AA-LICENSE.txt` and included in its hashes
- The itch key is used only by publishing steps. Raw Butler output is suppressed, and repository permissions are read-only
- One release runs at a time. Avoid simultaneous manual itch uploads or multiple queued release tags; GitHub keeps only one pending run by default

## Memory acceptance for affected releases

Renderer, export/runtime, cache and lifecycle changes require the
[memory regression standard](../testing/memory-regression.md). Ordinary CI runs
the fast deterministic lifecycle check; a focused browser soak, relevant repeated
scene/reload/resource cycles and post-GC memory/capacity trends are a separate
release gate. Use a matched control and justified budgets, record exact hashes
and live-versus-retained counts, and retain unsupported paths as gaps. A short
three-minute pass supports a candidate without proving every leak absent.
Keep this work proportionate; do not add long soaks to every PR or weaken the
existing CI/toolchain/atlas/save gates. An urgent shorter diagnostic must remain
explicitly unqualified against the longer gate.

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

- [Firebase release staging alignment](firebase-release-alignment.md): completed itch receipt selects the exact released runtime; automatic qualification is separate from production cutover.
- [CrazyGames adapter/export contract](crazygames-variant.md)
- [Trusted itch preview](itch-trusted-preview-candidate.md): preparation is separate from hosted acceptance and publication
- Historical [CrazyGames slice](history/crazygames-split-ledger.md), [release-metadata ownership](history/split-draft-ownership.md) and [10a overlay provenance](history/010a-release-overlay-provenance.json)
- [Asset permissions and required notices](../art-audio/README.md)

Use the [roadmap](../roadmap.md) for current readiness and authorization. Historical ledgers describe their pinned source/date, not the current shipped tree.

### Read-only itch diagnosis

The release workflow's manual dispatch on `main` runs only the fixed-channel status diagnostic; tag publishing remains separate. It first runs checksum-pinned Butler `--version` and `status --help` without credentials, then uses the existing credential solely for `--json status siowyiyou/little-leaf:html5`. The artifact records numeric exit codes, whitelisted error categories and verified channel identity, without raw command output, headers, URLs or credential values. HTTP debug is stripped. A successful diagnostic job does not establish publication or authorize a publisher retry. Preserve its exact workflow run/attempt alongside the original failed release evidence.
