# Itch trusted-preview candidate

This explicit test variant displays the account game inside the itch page while its Firebase SDK, authentication and UID journal execute on an exact controlled Firebase preview origin. The shared itch wrapper receives no tokens, saves or account SDK objects. The ordinary Web shell and default top-level Firebase redirect flow remain unchanged.

The preview boot uses `start(config, {surface:'trusted-itch-frame', runtimeOrigin:EXACT_PREVIEW_ORIGIN})`. The origin is baked into the reviewed own-origin HTML. Only a project preview hostname in the `itch-embed-test` channel is accepted. Its ancestor chain must be exactly, from nearest to topmost:

1. `https://html-classic.itch.zone`
2. `https://siowyiyou.itch.io`

The preview also emits `frame-ancestors` for those two origins on `/` and `/index.html`. Browsers without `location.ancestorOrigins` fail closed in this candidate; cross-browser acceptance is pending. The default mode still rejects all frames.

`tools/build_itch_trusted_preview.py` reuses existing Firebase staging and a complete reviewed Web export. It checks all recorded production inputs except the deliberately changed boot module before reusing compiled Godot binaries. The output distinguishes candidate runtime source from retained engine source, hashes runtime inputs and every packaged file, and is marked ineligible for production release. No new native run is claimed.

Upload only `itch-wrapper`, to a separate private test project. Selecting local play opens the original local vault. Selecting account mode embeds the exact preview and leaves the original vault boot promise unresolved; returning to the choice requires reloading. Progress is explicitly separate, with no automatic migration. Google sign-in requires a direct click within the trusted frame and uses the existing SDK popup result/auth-state listener. A cancelled/blocked popup cannot open the account journal or replace the local vault.

Preview deployment requires explicit approval. The narrow REST route never invokes Auth-domain synchronization. The exact generated hostname needs separate approval before real Google sign-in. Preview links are shareable, not private. No domain, OAuth scope, credential, Firestore rule, live hosting, original itch upload or user save is changed by preparation.

Targeted verification: `python -m unittest tests.tooling.test_firebase_boot_presentation` and `python -m unittest tests.tooling.test_itch_trusted_preview`. These use synthetic users/SDK/DOM and package fixtures. Hosted popup delivery, browser storage partitions and cloud continuation remain unverified.

## Source-bound manual route

`stage-firebase.yml` has an opt-in `itch_preview` input (default false). It forwards to the unchanged fresh native/export/browser/Firebase gates, then `build_firebase.py --itch-preview-bootstrap` prepares and retains the trusted-frame bootstrap with the exact source/tree, fresh evidence, inventory and wrapper. Ordinary staging remains the default. This unbound bootstrap is never uploaded to Hosting.

The existing main-only manual deployment workflow accepts `deployment_mode: itch-preview`. Before requesting its unchanged short-lived Hosting-only WIF token, it verifies the immutable successful same-repository staging run, exact source SHA, artifact ID, manifest hash and complete package. It then:

1. Confirms live release identity and absence of the one allowed channel.
2. Creates `itch-embed-test` with `ttl: 86400s` and records the server-returned URL/expiry before any file upload.
3. Builds the exact-origin packet and wrapper in a separate directory by binding the two reviewed shell markers, regenerating all changed inventory hashes and checking the complete package again. Any bootstrap origin left in public files rejects before version creation/upload.
4. Creates/uploads/finalizes only a same-site version, checks live remains unchanged, releases only the exact preview channel, and verifies its marker, URL, expiry and release. No live release, deletion, automatic retry, Auth endpoint, token bridge or permission change is allowed.

The final wrapper ZIP and bound manifest are retained for one day; the mutation receipt is retained even on failure. Real Google sign-in is pending separate exact-hostname authorization and hosted browser acceptance. The route does not upload anything to itch.
