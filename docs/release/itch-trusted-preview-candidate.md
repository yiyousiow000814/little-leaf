# Itch trusted-preview candidate

## Same-page account play candidate — 2026-10-11

The user confirmed Google authentication followed by continued play inside the
itch page. The existing explicit trusted-origin full-game wrapper is the local
candidate for this requirement. It now reuses the reviewed ordinary chooser
presentation and descriptions, replacing its outbound account anchor with the
existing account button. That button embeds the exact reviewed Firebase origin;
the user then clicks Google sign-in inside that frame. The SDK popup completes
authentication in the frame, whose existing UID/session/cloud-vault gates must
finish before its game starts. The itch local-vault boot remains unresolved in
account mode. No credentials, account state or save payloads cross into the
wrapper; local progress remains separate and never transfers automatically.
The candidate omits the old wrapper-level Back button, which immediately reloaded
and destroyed the account frame without checking pending saves. A future return
action must run inside the trusted game and confirm its existing save/pending
guards; no cross-origin save-status bridge is added here.

`prepare_stable` prepares a separately identified **nondeployable** `/itch/`
candidate on `https://little-leaf-41e5d.firebaseapp.com`, retaining the original
top-level variant. Only `/itch/` and `/itch/index.html` opt into the existing
two-ancestor popup guard. All embedded assets and `hosting-release.json` live
under that path, so the update adapter's relative marker fetch and reload stay
there; both loaded-page and marker identities bind the same source/package.
The proposed Hosting-only configuration adds exact frame-ancestors headers only
on those two entry paths and no-store for the embedded marker. It neither enables
the production selector nor changes live Hosting configuration. The old expiring
preview contract is retained. PR188 `a1c8446947350a0a1da85c47dba19d7ab8ab3819`
refresh source is composed locally once as an unaccepted dependency; its tests
do not establish genuine Google or crash/browser acceptance for this candidate.

PR216's sole effective-rule read `38151559763` on merged `94597c32` identified
the two previously unclassified rows as cache-only: an HTML suffix `no-cache`
rule and an absolute-literal `no-store` rule. Neither contains CSP or XFO.
The finalized baseline version is `5c3b69acc18fdc94`, with complete configuration
digest `09113ff8616e7f0d7dd26032952d4932d728f19c8014f2eb2cd54dcf093a53a7`.
This evidence resolves the unknown-rule diagnosis; it does not verify a future
served frame, authentication or an action-time configuration baseline.

The minimal proposal retains every existing rule in order. It adds CSP plus
`no-cache` for `/itch/`, CSP alone for `/itch/index.html` (the existing HTML
rule already supplies its cache policy), and `no-store` for
`/itch/hosting-release.json`. Only the two HTML paths permit the exact ancestors
`https://html-classic.itch.zone` and `https://siowyiyou.itch.io`. Root account
play remains top-level only; no general framing or new Auth domain is proposed.
The candidate manifest records these three exact additions separately from the
local package configuration. At activation, a separately reviewed route must
copy the then-current complete Hosting configuration in memory and apply only
the approved additions, preserving all unrelated fields and headers. The current
live selector preserves configuration unchanged and cannot activate this
proposal. Its live eligibility validator continues to reject this candidate;
the separately guarded test mode below is required.

The user authorized one bounded Hosting test update on 2026-10-11 after independent
review and final CI. Its scope is the `/itch/` additions and the three exact header
records above, preserving the homepage and current itch publication. Approval
does not qualify a package, authorize a full release, or accept Google/gameplay.
Real Google acceptance still requires the separately authorized isolated test
identity/profile and an identified test itch route; no original player profile
or cloud-save overwrite is covered. This source preparation performs no update.

### Bounded test qualification and activation

`stage-firebase.yml` has a separate `itch_test_entry` flag, default false. It
rejects combinations with preview/publication/released reuse and requires a first
manual main attempt. The existing complete native/export/browser gates and all
ten focused Firebase gates remain mandatory. Its compiled Firebase suite executes
the exact staged `/itch/` HTML/assets under the two synthetic HTTPS ancestors,
substituting only public configuration with emulator credentials and blocking
production traffic. This proves compiled synthetic flow, not real Google or
physical-mobile acceptance. The final packet has the distinct status
`fresh-itch-test-entry-not-live-eligible`; historical local packets retain their
NONDEPLOYABLE status and cannot be promoted by a helper-only CI pass.

#### Compiled iframe fixture transport correction

Official test stage `38165586296` on `06bc3ca7` failed its unchanged 90-second
startup assertion before completing any cloud-flow checks. The failure collector
also called an unavailable local-vault method, hiding bootstrap observations.
The retained failed artifact remains ineligible; its ordinary CI results do not
qualify the embedded game.

A separately admitted, no-game synthetic probe confirmed that the HTTPS frame's
HTTP loopback module import is blocked while its same-origin HTTPS control
succeeds. It did not reproduce a storage partition failure or establish the
actual SDK/game startup cause. The fixture correction serves the exact pinned
SDK bytes from the frame's HTTPS origin and forwards only the known demo-project
RPCs through a fixed Node-side loopback proxy. Local preflight accepts only the
six header names used by that pinned SDK; it grants no private-network access.
The real emulator mock credentials, settings and rules remain fenced, with only
the test transport's host/SSL changed. Synthetic journal setup and exact readback
occur in the actual nested frame before its game navigation.

The existing startup/read/update timeouts and cloud/save assertions are retained.
Failure evidence records bounded request categories and independently collects
bootstrap observations when later APIs are unavailable. Source review and finite
fixture checks do not prove buffered long-poll timing: fresh compiled full-flow
qualification is required before a new artifact can enter the bounded test
selector. No product, browser security flags, live endpoint, account, rules or
Hosting mutation is part of this fixture correction.

The existing `deploy-firebase.yml` identity has a separate `itch-test-entry` mode.
Before WIF it binds exact main source/tree, first staging attempt, completed API
job gates, immutable artifact digest, manifest/inventory and complete retained
native/export/focused/iframe evidence. Its token scope and 900-second lifetime
are unchanged. Existing live, preview, auth-pause and read modes are preserved.

The action pins release `1791701963370000`, finalized version
`5c3b69acc18fdc94`, and the complete config digest above. It exhausts the ACTIVE
file inventory, rejects an existing `/itch` namespace or relevant routing/header
uncertainty, copies all baseline paths/hashes, and uploads only new `/itch/`
payloads. The finalized candidate and unchanged baseline config/file maps/release
are rechecked immediately before a single release. Public checks compare the
homepage, root marker and their response headers, then verify both new HTML
paths' exact CSP/cache policy and embedded marker. Every newly served payload is streamed and compared with
its reviewed size/hash; baseline paths are never downloaded for re-upload.
Failed or uncertain results
require inspection; there is no automatic mutation retry or rollback.

The sanitized one-day receipt contains target hashes, map/config digests and the
previous release/version identity. Complete configuration, unrelated path values,
tokens and account identifiers are never output. The old finalized version is
verified intact as the rollback target; an actual rollback needs a separately
guarded decision after inspecting any intervening release. No Auth/IAM/rules,
local progress migration, itch publication or release tag is changed by this mode.

The proportionate design gate concerns UI/UX and browser ownership: the requested
outcome is Google popup sign-in followed by play on the same itch page, with a
separate official top-level entry. Reuse the existing chooser styles and the
centered short labels from frozen `1d5348ca`; retain PR188's guarded runtime and
the existing cloud-save/update owners. Game rules, art, audio, camera and economy
are untouched. The wrapper creates at most one account frame on explicit choice,
does no per-frame work, and keeps the local vault/game-start promise pending.
Its frame and any loaded wrapper resources live until page teardown; real
compiled startup, repeated/recovery lifecycle costs and hosted pixels remain
unqualified. Synthetic package checks prove the source boundaries, not user
acceptance or successful Google authentication.

This is preparation, not a production switch. Normal Firebase boot still rejects
frames; only the existing exact preview-origin and two-ancestor validation opts
into popup mode. The historical auth-only success did not exercise game startup,
ownership or saves. Existing package checks cover the synthetic chooser and
isolation, not real Google authentication or browser storage partitioning.

Before any hosted change, identify and review a stable dedicated origin, its
authorized-domain eligibility, exact CSP/ancestor contract, package/source and
update identity, and the deployment route. Any new persistent Auth/OAuth domain
authorization or security-sensitive framing access requires separate action-time
approval. No such settings are changed by this candidate. The expired auth-only
packet must remain frozen and must not be relabeled as a playable export.

Remaining acceptance: a genuine authorized isolated Google account on the actual
itch embedding, popup cancellation/block/retry, same-frame compiled startup and
cloud save/readback, refresh/device ownership/account changes/update, and target
browser/mobile storage behavior. Physical-device results must be distinguished
from emulated viewports. Ordinary release still uses its existing outbound link
until a reviewed, independently qualified delivery replaces that package.

## Auth-only verification and presentation candidate — 2026-10-10

The authorized auth-only v2 preview was deployed by run `38047867726`. User-provided evidence shows a fresh Google popup completed and Google authentication confirmed. This accepts sign-in only: game, session ownership and saves remain paused; cloud gameplay and save acceptance are still separate gates. The deployed update ZIP `f5aaf81d27500e5d82ac9bb2951852e67e7c56cf094adff68e7a1c7eb7c32778` and rollback ZIP `98b033b91535b63c7818d7f12bca17c567e97c41ba92473a67f832f7d4deb0e6` remain frozen.

The presentation candidate uses a compact cream/sage/brown card, the existing licensed Nunito font, responsive styled buttons, visible keyboard focus and short status copy. The derived HTML embeds the font and its OFL notice, without an extra network dependency. The chooser retains its account/local/back handlers; original local progress never transfers automatically. The auth check distinguishes a restored session from a completed fresh popup, shows generic reload feedback on bootstrap failure, and never offers a continue-to-game action.

`auth_verification_only=True` generates a dedicated HTML page containing only the auth bootstrap. It omits all engine, vault, preferences and save adapters. Its auth-only promise remains pending before Firestore or session setup. The ordinary Web shell, normal game/account path, scopes and persistence handlers are unchanged. `tests.tooling.test_entry_presentation` compares those handlers with the frozen v2 source and exercises both generated pages with synthetic boundaries, including a rejected SDK import. Local visual evidence at 1280×720 and 390×844 uses generated pages and synthetic authentication; it is not another real sign-in or gameplay test.

This source candidate does not replace the deployed packet or the bounded workflow recipe. New exact wrapper/Hosting package identities, independent package review and authorized update scope are required before deployment. No Auth domain, rules, permissions or original player saves are changed.

## Earlier full-game preview contract

### Remaining 10a acceptance after source-layout migration

PR124 retains its approved entry behavior under `platform/web`, `platform/firebase` and `tools`. Presentation inputs resolve through the shared source-layout helper, including the existing font and license. Frozen auth-only update/rollback fixtures and their recipe are unchanged; merging this source does not update the deployed preview.

| Gate | Evidence and remaining action |
| --- | --- |
| Fresh Google authentication | User-confirmed popup success on the deployed auth-only v2; accepted for sign-in only. |
| Auth-only isolation | Generated-page synthetic checks keep Engine, Firestore, sessions, journals, vaults and timers inaccessible; the boot promise stays pending. |
| Authenticated source continuation | Normal boot presentation checks cover signed-out, redirect return/failure and authenticated resume. The compiled-flow synthetic Auth module must link with the real boot imports before running a new compiled gate. |
| Cloud ownership and save protocol | Local synthetic adapter/session/choice checks cover fenced takeover, paused ownership loss, protected divergent branches and account races. They do not establish server authorization or playable UI acceptance. |
| Server rules compatibility | Repository rules include `players/{uid}/session/owner` and fenced `saves/cafe` writes. The previously observed hosted failure was permission denied on the session document; this source update neither checks nor changes deployed rules. Compare the exact deployed contract with reviewed source, then obtain separately scoped cutover permission if a mismatch remains. |
| Disposable compiled gameplay and cloud save | Run the source-bound compiled-flow gate against the local Firestore emulator, synthetic Google claims and a disposable profile. Verify ownership acquisition, game startup, save/readback and ownership-loss pause on the same source/export; retain the receipt. No original browser profile or save is eligible. |
| Hosted continuation | Prepare and independently review a separately identified full-game packet with compatible server rules before requesting exact deployment/test scope. The auth-only packet must not be switched to gameplay by removing its pause flag. |

The backend compatibility gate and compiled/hosted continuation remain open. There is no automatic transfer of origin-bound itch local progress, no fallback that bypasses ownership, and no cloud-game acceptance inferred from Google success.

This explicit test variant displays the account game inside the itch page while its Firebase SDK, authentication and UID journal execute on an exact controlled Firebase preview origin. The shared itch wrapper receives no tokens, saves or account SDK objects. The ordinary Web shell and default top-level Firebase redirect flow remain unchanged.

The preview boot uses `start(config, {surface:'trusted-itch-frame', runtimeOrigin:EXACT_PREVIEW_ORIGIN})`. The origin is baked into the reviewed own-origin HTML. Only a project preview hostname in the `itch-embed-test` channel is accepted. Its ancestor chain must be exactly, from nearest to topmost:

1. `https://html-classic.itch.zone`
2. `https://siowyiyou.itch.io`

The preview also emits `frame-ancestors` for those two origins on `/` and `/index.html`. Browsers without `location.ancestorOrigins` fail closed in this candidate; cross-browser acceptance is pending. The default mode still rejects all frames.

`tools/build/build_itch_trusted_preview.py` reuses existing Firebase staging and a complete reviewed Web export. It checks all recorded production inputs except the deliberately changed boot module before reusing compiled Godot binaries. The output distinguishes candidate runtime source from retained engine source, hashes runtime inputs and every packaged file, and is marked ineligible for production release. No new native run is claimed.

Upload only `itch-wrapper`, to a separate private test project. Selecting local play opens the original local vault. Selecting account mode embeds the exact preview and leaves the original vault boot promise unresolved; returning to the choice requires reloading. Progress is explicitly separate, with no automatic migration. Google sign-in requires a direct click within the trusted frame and uses the existing SDK popup result/auth-state listener. A cancelled/blocked popup cannot open the account journal or replace the local vault.

Preview deployment requires explicit approval. The narrow REST route never invokes Auth-domain synchronization. The exact generated hostname needs separate approval before real Google sign-in. Preview links are shareable, not private. No domain, OAuth scope, credential, Firestore rule, live hosting, original itch upload or user save is changed by preparation.

Targeted verification: `python -m unittest tests.tooling.test_firebase_boot_presentation` and `python -m unittest tests.tooling.test_itch_trusted_preview`. These use synthetic users/SDK/DOM and package fixtures. Hosted popup delivery, browser storage partitions and cloud continuation remain unverified.

## Compiled route teardown correction - 2026-10-12

Fresh current-source stage `38238105653` on `a9bfc3d0` recorded ten passing
cache/ownership checks, including the exact final cloud-save ACK, before an
uncaught route callback `frame.evaluate` failed as its context closed. Its
checkpoint contains no earlier failed assertion; the remaining cases and final
qualification did not complete. The old retained Linux ownership timeout is
separate evidence.

The fixture now owns and drains intercepted callbacks during explicit context
closure. Only a target-closed error from requested, confirmed teardown is
expected; live or unrelated errors remain fatal with their original cause.
The held update RPC releases on close even when its case fails. Cleanup and final
report writing preserve an earlier case failure, and late errors cannot mark a
report passed. Focused pure Node regressions reproduce the old callback rejection
and cover these lifecycle boundaries. No product, rule, allowlist, deadline or
save/ownership assertion changes. Fresh complete CI/compiled qualification and
hosted Google-to-game acceptance remain required; no deployment follows from
source or unit-test success.

## Packaged worklet fixture transport

The retained Windows Chrome-for-Testing153 diagnostic on `69f33801` with the
unchanged compiled `a897a31f` package passed its ten ownership/cache checks. Its
final zero-errors assertion failed on three `/itch/index.audio.worklet.js`404s.
Both worklet files exist with identical hashes in the ordinary and nested
packages; none of the instrumented routing, local-serving or response layers
observed those worklet fetches. The original Linux154 ownership timeout did not
reproduce, and the404 source and any connection to that timeout remain unknown.

The test fixture supplies only those two inventory-verified module byte strings
through Blob URLs created inside the exact `/itch/` document. It calls the real
AudioWorklet implementation, preserves options/results/errors and revokes each
URL after success or failure. All game, audio, Auth, SDK and persistence source,
browser security settings, cases, deadlines and final assertions are unchanged.
Pure transport checks pass; fresh browser/CI qualification is still required.
This does not establish live HTTP delivery, real Google sign-in or deployment
eligibility. The failed source-bound reports remain historical evidence.

## Source-bound manual route

`stage-firebase.yml` has an opt-in `itch_preview` input (default false). It forwards to the unchanged fresh native/export/browser/Firebase gates, then `build_firebase.py --itch-preview-bootstrap` prepares and retains the trusted-frame bootstrap with the exact source/tree, fresh evidence, inventory and wrapper. Ordinary staging remains the default. This unbound bootstrap is never uploaded to Hosting.

The existing main-only manual deployment workflow accepts `deployment_mode: itch-preview`. Before requesting its unchanged short-lived Hosting-only WIF token, it verifies the immutable successful same-repository staging run, exact source SHA, artifact ID, manifest hash and complete package. It then:

1. Confirms live release identity and absence of the one allowed channel.
2. Creates `itch-embed-test` with `ttl: 86400s` and records the server-returned URL/expiry before any file upload.
3. Builds the exact-origin packet and wrapper in a separate directory by binding the two reviewed shell markers, regenerating all changed inventory hashes and checking the complete package again. Any bootstrap origin left in public files rejects before version creation/upload.
4. Creates/uploads/finalizes only a same-site version, checks live remains unchanged, releases only the exact preview channel, and verifies its marker, URL, expiry and release. No live release, deletion, automatic retry, Auth endpoint, token bridge or permission change is allowed.

The final wrapper ZIP and bound manifest are retained for one day; the mutation receipt is retained even on failure. Real Google sign-in is pending separate exact-hostname authorization and hosted browser acceptance. The route does not upload anything to itch.
