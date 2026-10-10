# Firebase qualification after itch publication

This candidate adds automatic **staging**, not production activation. A successful
`Release Web to itch.io` completion wakes `release-firebase.yml`. The event is only
a notification: read-only GitHub API calls revalidate the completed workflow,
exact attempt's successful publish job, completed Butler receipt/build ID,
immutable artifact ZIP digests, peeled tag, tagged project/release metadata,
main ancestry and all thirteen mandatory original CI gates. PR artifacts and
failed, processing, missing, expired or changed artifacts cannot select a source.

Before starting staging, the coordinator retains a request artifact named
`little-leaf-firebase-request-${release_run_id}`. An existing request, including an
expired one still listed by GitHub, blocks automatic retry. The shared concurrency
group serializes requests for that release, and both selection and staging reject
attempts greater than one. The callable released lane has no direct manual input;
one inspected catch-up uses the coordinator's `release_run_id` dispatch input.
Intent artifacts are retained for 90 days. Once GitHub removes an old artifact
entirely there is no permanent ledger: old catch-up must be inspected by an
operator; this is not a lifetime deduplication guarantee.

`stage-firebase.yml` checks out **the peeled released source**, separately from
the reviewed coordinator. `reuse_released_web.py` pins the original qualification
run/attempt/artifact/digest recorded in the completed publication. It never
selects a newer CI run for the same SHA. It validates the complete source and Web
inventory, original manifest hash, official toolchain and packed startup. Runtime
payload bytes remain unchanged. If original CI is rerun or its artifact expires,
staging stops; no fallback or new whole engine matrix is started.

The original CI evidence archive supplies its hash-bound native summary, export
report, native geometry logs and ordinary browser receipts. All ten focused
Firebase gates, rules emulator and compiled two-device cloud/update flows run
again against the same released PCK/JS/Wasm and source modules. These checks use
synthetic accounts and a disposable local emulator. They do not test real Google
sign-in, production Firestore or player data. Packed startup and disposable
geometry probes still execute native processes; the complete engine suite is
reused rather than rerun.

The existing source's `build_firebase.stage` performs the shell transformation.
The receipt explicitly records released CI reuse, new Firebase gate hashes and
the staging run/attempt. Output is retained as
`little-leaf-firebase-${source_commit}-${staging_attempt}` with status
`qualified-release-staged-not-deployable`. This status is deliberately rejected
by the current live deployer. No auth-only diagnostic, frozen preview recipe,
login recovery, updater/rollback, security rules or game source is modified.
The existing default manual fresh-build lane retains its complete build gates.

## Current release and verification

Ordinary `v0.1.10c` has already completed itch publication: source
`a5dd2b2b3a0cfee9c79fcd75eb870a9892afbf27`, tree
`4b3e3dd5aae014e6b74654181e66dd446d2b193a`, itch build `2101666`, release
[run38076826740](https://github.com/yiyousiow000814/little-leaf/actions/runs/38076826740).
Its original main qualification is
[run38075641414](https://github.com/yiyousiow000814/little-leaf/actions/runs/38075641414),
ordinary artifact `11678820132`, ZIP SHA256
`8aad768dcea5c7c2908c5becccc27a05f94a7d13064b1a6126912d4c0ec3f848`.
Independent read-only selection and actual original evidence preparation passed.
Fresh Firebase qualification through this new route remains pending its reviewed
publication on main and one inspected catch-up. Ordinary itch must not be repeated.

## Production cutover remains separate

Existing `deploy-firebase.yml` names the Hosting-only service account
`little-leaf-hosting-deployer@little-leaf-41e5d.iam.gserviceaccount.com`, WIF provider
`projects/865267465971/locations/global/workloadIdentityPools/github-little-leaf/providers/github`
and 900-second token scoped to Firebase Hosting. This is existing workflow
configuration and historical successful use, not a fresh assertion that current
IAM/auth access was tested. The staging route never requests a Google token,
receives no deployment secrets and uses only contents/actions read permissions.
That identity does not provide an implemented Firestore/Auth administrative route.

After an actual same-source Firebase package qualifies, prepare a separate reviewed
Hosting-only cutover inside the existing deploy workflow identity:

1. Bind its successful coordinator/staging API run, attempt, immutable artifact,
   complete manifest and fresh focused/full-flow evidence. Keep the released
   PCK/JS/Wasm bytes exact; do not activate older d291/f6 packages.
2. Read and pin the current live release/version and **complete** Hosting config,
   including CSP, headers, redirects and rewrites. Upload/finalize a candidate
   without activating it. Refuse changed baselines and retain intent before every
   uncertain mutation. The current helper's abbreviated `CONFIG` must not be used
   for this cutover.
3. Present the exact proposed Firestore rules/hash, observed live rules baseline,
   emulator coverage and coordinated operator route for explicit approval. No
   new rules or grants are included here. Current released-source canonical rules
   SHA256 is `54b8c54ca686839b0dde12ef2de5aaf6f3dc9ed4410bb052dcf5c5e89e3895f5`;
   this is **not** evidence of the currently deployed rules.
4. Activate only after the approved rule application receipt and unchanged
   Hosting baseline are verified. Verify public marker/file hashes and perform
   isolated real Google/save acceptance. A failed/uncertain activation or smoke
   must pause for inspection; never automatically roll back static code after
   users may have written cloud saves under new rules.

Until those steps exist and are accepted, Firebase automatic **alignment/live
activation remains incomplete**. The staging package alone cannot authorize it.
