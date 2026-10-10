# Reuse qualified exact-main Web artifacts

Freeze all reviewed code, workflows, version metadata and qualified atlas bindings
before the final main CI run. Review that actual package before creating an
approved immutable release tag. A PR's synthetic merge artifact is not an
artifact for its head SHA, even when their trees match.

The tag workflow calls `tools/reuse_main_ci.py --sha SOURCE --tag TAG --output DIR`.
It waits up to 20 minutes for an existing exact-source main CI run; it never
dispatches another engine/browser matrix. The latest trusted run must succeed
with all 13 mandatory jobs. Missing, failed, expired, duplicate or mismatched
evidence blocks publication rather than selecting an older source or rebuilding.
CI artifacts expire after seven days; qualify the unchanged intended source
again through main CI if its evidence is no longer available.

Trust requires the repository's CI workflow, a main push or main manual run,
exact source SHA, successful mandatory job inventory, exact attempt/artifact name
and ID, and GitHub's ZIP digest. Safe extraction rejects traversal, symlinks,
duplicate paths and oversized archives. The original manifest must match the
actual source commit, tree, version, qualified official tools, complete production
source hashes, file inventory and required notice. The ordinary Web variant is
required. PR, fork and alternate-platform packages cannot qualify.

Final checks retain main ancestry, exact tag/version binding, atlas verification
and actual packed-resource startup with official checksum-pinned Godot in a new
disposable profile. Only release metadata is added to the manifest; every runtime
and asset byte stays identical to the qualified packet. The original manifest
SHA and CI artifact identity remain in the receipt. Existing duplicate/rollback
checks, one-attempt Butler upload and confirmed processing remain mandatory.

`little-leaf-release-qualification-SHA-ATTEMPT` retains `qualification.json` and
`packed-startup.log` in the release run. After confirmed Butler completion,
`little-leaf-itch-publication-SHA-ATTEMPT` retains `receipt.json`, including the
tag, version, source, release run/attempt, build ID, manifest hash and nested CI
qualification. Consumers must independently verify exact successful workflow
origin, API artifact digest and publish-job success; a receipt's boolean fields
alone do not establish authority. No receipt is produced for failed processing.

Omitting `--tag` supports a coordinated future staging consumer. This change does
not wire Firebase staging, authorize Hosting/rules deployment, or replace its
focused platform and explicit security approval gates.

The previous successful tag release took 26m31s, including 25m49s in its repeated
build/qualification job and 28s in publishing. The optimized release's elapsed
time remains unmeasured until an authorized final-source release completes.
Focused tooling checks and PR CI are not an end-to-end release timing result.
