# Bounded auth-pause preview update

This one-off route updates only the already existing `itch-embed-test` channel at
`https://little-leaf-41e5d--itch-embed-test-0b0pnaf7.web.app`. It expires at
`2026-10-11T07:18:58.475792680Z`; the route refuses an expired channel and never
creates a replacement or extends its expiry. It is not a production/game
qualification route. Independent source review is required before dispatch.

The frozen overlay is an auth-only page: no engine, adapters, local vault or
preferences scripts. Restored sessions are distinct from Google popup completion;
both credential provider and token provider must identify Google. Success and
failure remain paused. Firebase Auth persistence is allowed; application save,
Firestore, session, game and timer activity is not.

`recipe.json` pins the source, original qualified artifact, 15 public file hashes,
12 unchanged qualified files, and both original ZIPs:

- Update: `f5aaf81d27500e5d82ac9bb2951852e67e7c56cf094adff68e7a1c7eb7c32778`.
- Rollback: `98b033b91535b63c7818d7f12bca17c567e97c41ba92473a67f832f7d4deb0e6`.

Only the three public overlay files and their exact rollback counterparts are
retained here, plus ZIP metadata and the diagnostic manifest. The unchanged
engine bytes come from successful staging run `38029738586`, immutable artifact
`11662670060`, exact source `1d7b7b5f12cced3d682cb37ecd0957e2585f19d0`.
The original full qualified package is checked by the unchanged deployment
validator before reuse. Windows Python 3.14.2/zlib-ng and streamed 8 KiB writes
reconstruct the reviewed ZIPs; any digest mismatch stops before a Google token.

After review/publication, dispatch the existing `deploy-firebase.yml` workflow on
`main` with mode `auth-pause-update`. Use these exact existing input values:

```text
source_sha: 1d7b7b5f12cced3d682cb37ecd0957e2585f19d0
variant_run_id: 38029738586
variant_artifact_id: 11662670060
variant_manifest_sha256: 79ec16fe11ff9ccee09902194b00be135fce51ab651a9caa6d7767d41a19daa9
```

For the approved exact restoration, use `auth-pause-rollback` with the same values.
Update requires the current public inventory to match rollback; rollback requires
it to match update. Unexpected current bytes, host, expiry, concurrent channel or
live-head change stop the operation. Existing receipts and uncertain mutations
require inspection; there is no automatic retry or rollback.

Both modes retain the existing short-lived Hosting-only WIF identity and scope.
The API gate permits staging one new Hosting version and releasing it only to
this existing channel. It denies live release mutations, channel creation/patch/
deletion, arbitrary versions, Auth, Firestore and IAM. The entire current Hosting
configuration is copied unchanged, including ancestor CSP. Public hashes and
unchanged host/expiry/live head are checked after release. No credentials,
persistent permissions, authorized-domain changes or itch wrapper upload are
introduced. A workflow edit/merge is not a deployment or Google acceptance.

Protocol references: [channel release creation](https://firebase.google.com/docs/reference/hosting/rest/v1beta1/sites.channels.releases/create),
[channel expiry fields](https://firebase.google.com/docs/reference/hosting/rest/v1beta1/sites.channels).

Focused offline checks:

```sh
python -m unittest tests.tooling.test_auth_preview_update -v
python tools/update_auth_preview.py --stage /qualified/base --output /new/disposable/packets
node tests/fixtures/auth_preview_pause.js /new/disposable/packets/update/public/index.html tools/auth_preview_pause/update/diagnostic-manifest.json /new/disposable/packets/update/public/little_leaf_firebase_boot.mjs
```

Retire this bounded mode when its channel expires; do not repurpose its fixed
digests or host for another deployment.
