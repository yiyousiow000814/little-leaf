# Released 0.1.10 pending journal → final 0.1.10a diagnostic

Status: source/negative guards and JavaScript syntax PASS; real browser/emulator/native migration NOT RUN. Local sandboxed Chromium failed with `socket() failed: Operation not permitted`. No sandbox disabling or alternate path around this restriction was attempted. No CI dispatch, publication, production rule change, authentication, or player save access occurred.

## Scope and immutable inputs

- Released client: `b8b80eea57ac3cb141cb5c771b375207a284436a`. Two verbatim Git blobs in `tests/fixtures/released-0.1.10`, individually SHA-256 pinned.
- Candidate local `a0c320ba062cef37554e12e38fb9e8a9014c0a08`; remote PR113 `8d63f936245602628386026732a6dd030dce0fc9`; compiled tree `08bd2d87c4969dce910c7907682f4653b0110b65`.
- Existing final export manifest uses merge source `a6b8a3de4fb0f39529886b426fd7820a2c3c2ddc`, same tree. The harness requires the matching engine report source AND report SHA-256 in this export manifest. A same-tree report from the separate audio run is insufficient.
- Bound runtime source hashes include the final vault, Firebase adapter/session/boot/update, rules, payload fixture, and engine launch hook. Existing fullflow geometry and exported-file hash checks remain in force.
- `--legacy-pending-only` requires `--diagnostic-only`. It does not run the complete original suite and cannot qualify release.

## Three cases

Each starts with only a synthetic cloud fixture. The unchanged released adapter boots, commits a payload through its real IndexedDB journal implementation, then calls its actual Firebase SDK transaction under the new emulator rules. The observer only records/rethrows the real result. Assertions require `permission-denied`, no writer fence fields, unchanged cloud, and byte-identical durable pending record plus exact upload intent.

The page then navigates in the same browser context and same origin to the real final compiled UI, destroying the released runtime while retaining IndexedDB:

1. Cloud still matches pending base: exact legacy pending record is automatically cloud-acknowledged with the current writer fence; native save proves resumed coins.
2. Cloud has independently advanced, choose local: neither branch changes before choice; cancel preserves both; native confirmation protects both exact originals, uploads a monotonically newer fenced selected record, and resumes native coins.
3. Same conflict, choose cloud: same cancellation/preservation checks; exact legacy journal remains in protected choice backup; chosen cloud data is acknowledged and native coins resume.

Conflict cards also require correct coins, meaningful Last saved, and `Unknown device` for the historical journal lacking device metadata. Persisted diagnostic receipts contain bounded hashes/digests/revisions/coins/results, not profile bytes. Full records exist only in test memory for equality checks.

This tests old adapter-created durable pending data. It does not claim to recover memory-only unsaved edits, prove Google SSO, or replace historical wall-format compatibility or the complete final save/frontend gates.

## Review and execution

First run in the isolated checkout:

    node firebase/legacy_pending_fixture.test.mjs
    node --check firebase/fullflow.test.mjs
    node --check firebase/legacy_pending_fixture.mjs
    node --check firebase/legacy_pending_flow.mjs

After parent review and explicit authorization for a supported execution/CI route, obtain the exact final ordinary export AND its matching same-run engine evidence from General Web run `37933440818`. Do not modify an already-running gate or substitute the older retained a7 export. Existing test dependency installation and synthetic Firestore emulator setup from `build-web.yml` can be reused. Generate disposable geometry from this checkout with `ci/prepare_cloud_geometry.py`, respecting any shared engine lock. Then run:

    export CLOUD_GEOMETRY_PROJECT=/absolute/disposable-geometry/project
    export PLAYWRIGHT_MODULE=/absolute/browser-tools/node_modules/playwright
    export PLAYWRIGHT_CHROMIUM_CHANNEL=chrome
    cd firebase
    ./node_modules/.bin/firebase emulators:exec --only firestore --project demo-little-leaf "xvfb-run -a node fullflow.test.mjs --legacy-pending-only --diagnostic-only --web-build '/absolute/exact-final-web' --engine-report '/absolute/same-run-engine-evidence/summary.json' --output '/absolute/legacy-pending-evidence'"

The matching engine evidence directory must include `test_cloud_recovery_ui.log` and `test_update_notice.log`. Keep the browser sandbox enabled. All app reads/writes use the real local emulator and authenticated synthetic SDK; security-rules-disabled access is restricted to the existing fixture seed/read helper. No production endpoint or Google login is used.

Remaining gate: execute these three cases to completion, inspect the bounded receipt and screenshots, then separately require the complete final save/frontend tests. Any failure is a diagnostic finding, not permission to publish, deploy, or loosen rules.

## Prepared QA-only workflow (not published or dispatched)

`.github/workflows/legacy-pending-migration-diagnostic.yml` runs only for the same-repository `qa/legacy-pending-migration-010a` pull request branch. It has read-only contents/actions permissions, verifies an exact QA-only changed-path allowlist against remote final8d63, and fetches full history so the historical b8 Git object and final tree object are available. Static fixture tests compare final blobs via the immutable tree, avoiding dependence on an unpublished local commit object.

Retained artifacts are fixed to ordinary Web run37933440818: export11618320268, ZIP SHA256 a70dde4aad2564f9fdfd9069019c2d16da4969a03d25d99a42dd380d069225df; evidence11617553429, ZIP SHA256 b475db26ea04ef6cc286cfda7e6a87a0ecadf773194fd996d4804ea5b2f71f64. The validator checks safe extraction, exact manifest/native hashes, all276 production inputs, and all10 exported files. Only the three needed native evidence files are extracted. These existing artifacts were verified locally without copying exports or running an engine/browser.

The workflow installs the existing checksum-pinned official Godot and pinned test dependencies, uses a fresh disposable CI geometry project, and runs only the three migration cases. It never rebuilds/publishes the game or deploys rules. Uploads are limited to the bounded binding/result JSON and screenshots; profiles, raw source archives and engine data directories are excluded. This branch/workflow is independent of the audio QA publication. Parent review and publication authorization remain required.
