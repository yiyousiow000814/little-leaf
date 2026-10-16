# Support mail and gifts — item 20 draft

Status: technical proposal and partial Draft implementation, integrated with merged save-polling PR #328 (2026-10-16 UTC). It is not an accepted or deployed feature. The user asked for an owner-only in-game way to look up one UID, write to that player, and send coins and items after reviewing records. Item 19's historic stove refund eligibility and amount remain separate and unknown for current level-less saves. The release gate remains all 20 requested items completed and verified before any deployment.

## Player and owner flow

The player-facing UID is a stable **12-digit ASCII decimal string** beginning with 1–9. A trusted service allocates it with a cryptographic random source and transactionally pairs a private `players/{authUid}/identity/public` record with `playerUidIndex/{publicUid}`; collisions retry, pairs are never recycled, and a broken pair fails closed. The owner UI accepts only this public UID. The private Firebase Auth UID continues to own save/mail/session paths and is resolved only on the server. The separately owned Settings PR #330 must consume the confirmed public UID, show loading/unavailable when it cannot be confirmed, and never fall back to a raw Auth UID, local hash or truncation. This Draft does not edit its Settings/bridge ownership. Guest and other identities have no public UID. An authorized owner sees Support Mail after a live capability check, enters one exact public UID, reviews a limited current-save summary with an explicit history-availability label, composes plain text and bounded attachments, previews the full recipient/content, and sends by a second action. A sent letter is not a paid grant. The existing Inbox presents new mail alongside the existing 0.1.5 paid receipt letters, with separate IDs/read markers and no 14-day expiry for unclaimed mail. Claim requires a confirmed cloud head; the existing Decorate shelf shows real unplaced Gifts stock, uses the same placement validation and consumes stock atomically with Finish. Reading never claims.

The initial V1 excluded broadcast mail; the later owner request below adds batch/all-player delivery to pending scope. V1 still excludes automatic historical-refund inference, arbitrary save edits, custom products, unique register, bundled dining, and staff/land/recipes. Initial proposed items are stove, beverage, sink, counter, bin, plant, lamp, bookshelf, rug and divider. The owner must confirm this catalogue and normal post-placement resale policy before item issuance can be enabled. Draft caps are 100,000 coins per letter, 10 units per supported product and 100 unplaced units per product, plus 20 lookups, 10 previews and 5 new sends per actor per minute. These are review values, not approved economy policy.

## Authority and interruption

Only Google-authenticated accounts can use the service. A server-managed `supportAdmins/{uid}` role document supplies narrow lookup/issue capabilities; this Draft creates no real role. Every owner operation rechecks it. Production `LITTLE_LEAF_PUBLIC_UID_ENABLED` and `LITTLE_LEAF_SUPPORT_MAIL_ENABLED` both default off. The former blocks **new** identity allocation until explicitly activated while preserving reads of existing verified UID pairs; turning the latter off stops issue/claim but leaves already protected ordinary saves available. No browser flag, client-authored receipt or local role changes authorization. No service identity, billing, live security-rule change, role or reward is provisioned by this Draft.

Issue IDs are stable across retries. Preview binds normalized content, exact public UID and profile for ten minutes. The send transaction privately resolves the public UID and creates issue, recipient mail, case key and audit once; retry with the same ID and content returns the same mail. One recipient and case key rejects accidental second awards under another ID. A send timeout means check the same issue ID. A claim transaction checks Google Auth UID, active writer/epoch, live lease, exact save revision/digest, profile, wallet and stock caps. It then creates stock, receipt, audit and a format-3 checksummed save with claim/stock watermark, or changes nothing. Its first enrollment preserves one raw pre-transition cloud record. Repeated claims return the current authoritative save head. Existing 0.1.5 receipts and pre-grid archives remain separate.

Firestore client rules deny all direct save writes once a server-owned control document exists. Subsequent saves must use the trusted protected-save operation with the exact current head and watermark. This protects against stale official tabs and old clients; it is not a fully server-simulated economy. The supported client must freeze and flush its current native snapshot before claim, hold the save-serialization gate until the claim result, then validate/install the returned head through the existing journal and model transaction controller. A local durable receipt alone does not prove cloud confirmation. A timeout, storage failure or account change must retain recovery evidence and must not make the grant spendable early. Gift Finish first confirms pending ordinary progress, validates a finished candidate without destroying the live Cancel baseline, and commits saved furniture with stock consumption. Cloud startup never silently uploads an unconfirmed gift-placement intent: Help offers explicit confirmation to retry the same operation and export of the preserved pending entry. A visible selector without this transaction is not a completed item feature.

The Draft now includes a default-hidden owner compose/preview/send surface, authenticated Inbox list and claim action, a Gifts section in the existing Decorate shelf, native gift staging/cancel/removal, browser journal intent recovery, server claim and placement transactions, public UID allocation, and protected-save routing. The callable export matches the reviewed PR #330 Settings bridge, `ensureMyPublicUid(null)`; Settings ownership remains in that separate PR. Pure contract, identity, adapter and synthetic Godot tests exercise these paths. Its Functions source is deliberately absent from `firebase.json`; production issuance and claims remain default-disabled. The actual exported Web was visually inspected with a disposable browser and a synthetic in-page mail fixture for Settings, owner compose, Inbox letter and Gifts shelf at desktop, portrait and short-landscape sizes. The latest mail-surface receipt is pinned to `b4b7c8d` and its screenshots/export hashes are retained in the local evidence directory; it includes the recovery/pagination source and the newer mail design. The fixture cannot send/claim or validate live backend persistence. Actual exported Web with Functions/Firestore/Auth emulators and real IndexedDB has **not** passed: this environment could not download the Firestore emulator JAR. No owner visual approval exists. Switch candidates still need overlap review.

## Quality gate and evidence

Purpose/authority: support case handling requested by the owner, with user-visible UID from a separate task. UI/UX and Game Feel need source-bound review of Settings, preview, Inbox and Decorate, including the changed recovery/pagination UI. Gameplay and save authority need repeated, interrupted, stale-client and recovery cases. Art, Technical Art, Audio and Living World sources are unchanged. No per-frame work is planned; mail pages are fetched on open and shown one bounded 20-row window at a time, with cursor-based forward navigation and return to latest. Read-state cache holds at most 128 session keys. Callbacks are account-scoped, and closing/account change must release references. Stock is bounded by product and server policy.

Focused contract, public-UID allocation, adapter and journal tests are in `platform/firebase/support_mail_contract.test.mjs`, `support_mail_identity.test.mjs`, `support_mail_adapter.test.mjs` and `support_mail_client.test.mjs`; the client test covers ordinary-save preflight, lost gift-placement response, no silent startup upload, export and explicit same-operation recovery. Synthetic native draft/Inbox/pagination checks are in `tests/persistence/test_support_gifts.gd`; the synthetic recovery bridge checks are in `tests/persistence/firebase_recovery_presentation.js`. The Firestore emulator service and rules tests are `support_mail.test.mjs` and `support_mail_rules.test.mjs`; an actual emulator pass is still required. Existing cloud-save and Inbox regressions pass on synthetic fixtures. Compiled Web/real IndexedDB **backend workflow**, post-fix visual review, full required CI and product acceptance remain pending. Inspected images show pixels under a synthetic fixture only, not authorization, persistence or a paid gift.

Open decisions: initial grantable products, resale behavior, final caps, claimed-mail display retention and release version. A future review must also verify exact owner UID at provisioning time, authorize any Functions/billing/rules activation separately, and keep a compatible protected-save path during rollback.

## Mail surface redesign candidate — 2026-10-16

The owner rejected the earlier `f084780` composer and letter presentation, including its competing vertical scrollbars. This scoped successor changes the mail surfaces intentionally: warm cream with existing Noto Sans/Nunito type, quieter letter cards, grouped Recipient / Message / Attachments / Review content, compact quantity rows, and a fixed navigation/action area. It does not establish a new global theme or Golden Reference.

The composer owns one ScrollContainer. Its multiline TextEdit fits its content height; wrapping, caret visibility and the outer scroll replace editor scrolling. Attachment rows use two columns on desktop/landscape and one on narrow portrait. Both surfaces retain safe-inset sizing. Tab stays inside the composer and includes Inbox claim/paging actions; navigation returns through the existing Settings/Inbox routes. Lookup, preview, send, claim and protected-save entrypoints are unchanged. No new assets, timers or per-frame work are introduced: the surface owns a fixed set of controls, and layout updates follow content/viewport changes.

Synthetic native checks pass 69 support/gift assertions, including a 30-line letter without an inner scrollbar, safe bounds and final-attachment reachability at 1360×880, 390×844 and 844×390, keyboard containment, Claim focus, deferred review-card reveal, and client validation of the exact UID/case format and subject/body UTF-16 limits. The editor displays live counts and refuses preview above server limits without truncating text, moving the caret or destroying undo/IME composition; the server remains authoritative. The existing Inbox regression passes 118 assertions with its decorative-envelope inset expectation updated for the text-card layout. Actual Godot 4.6.3 Web/Chromium frames were inspected at those three sizes using a disposable synthetic bridge that cannot send, claim or place gifts. Real key input produced a 20-line letter plus final text; wheel input reached the last attachment, touchscreen-emulated drag moved the same outer form, and Review revealed the recipient first with the final contents reachable. The latest preview request included one Leaf Coin to satisfy the service's existing nonempty-gift rule. Decorative cards pass pointer events to that single scroll owner. The retained receipts pin source/export and screenshot hashes; the earlier unsuccessful text-insertion and touch probes are not passing evidence. User acceptance, physical-device input/keyboard occlusion, measured frame pacing, backend end-to-end qualification, CI, merge and deployment remain separate gates.


## Owner feedback follow-up: original Inbox, visible gifts and audiences

Recorded requirement (2026-10-16): the tidier form still hides how to give coins
and items; the player Inbox should retain its earlier structure and Little Leaf
theme. The owner also requested sending to several pasted UIDs and to all players.
This extends the earlier single-recipient V1 scope. It does not authorize any real
mail, reward, role provisioning, rules change, billing activation or deployment.

### Isolated presentation candidate

The candidate restores the existing textured wood/leaf frame, 460-pixel Inbox,
envelope rows and warm letter paper. Support mail joins that same list; historic
paid receipts retain their original interpretation and 14-day projection. The
unclaimed support letter keeps Claim in the fixed footer beside the existing
back route, rather than placing it below a long message. Reading still cannot
claim. Support letters are not relabeled as already-paid receipts.

The owner composer reuses the existing HUD panel/button textures, original coin
art and existing catalogue thumbnail rendering. Coins and an expandable item
picker precede the message. A fixed footer states the amount **per player**.
There is one outer ScrollContainer; both growing text editors hand caret
visibility to it. Collapsing the item picker preserves quantities. No new art,
per-frame polling, generated texture cache or alternate grant path is added.
The fixed set of ten thumbnail nodes is owned by the existing composer panel.

Selected UIDs accept whitespace, comma and semicolon separators, deduplicate exact
12-digit strings, report invalid tokens without silently dropping them, and
reject oversized paste. The draft UI cap is 100 unique UIDs, not an approved
send/economy policy. A unique-UID count is explicitly **not** a confirmed-player
count. The All players choice removes UID input and requires a server count.
The isolated patch has no audience backend: more than one unique UID and All
players fail closed with an explicit unavailable message; they cannot fall back
to the existing single-player send. This is intentionally incomplete feature
work, not a broadcast implementation or release-ready substitute.

### Server audience implementation contract (pending)

1. **Authorization:** retain Google authentication and live server role checks.
   Introduce narrow batch and all-player capabilities rather than expanding the
   meaning of existing `issue`. Capabilities, preview, confirmation, dispatch
   continuation and status must recheck the actor. The kill switch stays closed
   by default. Creating/granting any real capability needs separate approval.
2. **One canonical message contract:** reuse the existing subject/body UTF-16,
   control-character, coin, item and catalogue validation on the server. UID
   parsing in Godot is only input hygiene. The server independently validates,
   deduplicates and canonicalizes the list. Malformed, missing or mismatched
   explicitly selected UIDs block the entire preview, with a public-UID-only
   explanation. Do not silently reduce a selected audience.
3. **Freeze recipients before send:** an authenticated server operation builds
   a private immutable manifest containing resolved Auth owner, public UID and
   current profile ID. All players means existing eligible cloud cafés, not
   guests or future signups. A paged scan must state its actual capture interval;
   do not claim an atomic point-in-time snapshot unless the SDK/storage read-time
   contract is implemented and tested. Once complete, the manifest is frozen.
   Cafés changing profile before delivery are not silently retargeted.
4. **Bounded preparation:** do not enumerate accounts or fan out writes in the
   browser, and do not put the whole audience in one Firestore document or one
   transaction. Use private server-owned manifest pages and a resumable job with
   deterministic cursor/page state. Establish total and excluded-profile counts
   from the completed manifest. Pages and retries are idempotent. Incomplete,
   expired or failed preparation cannot enable Send. Reads and job transitions
   need workload quotas and an explicit upper bound/continuation budget.
5. **Exact preview binding:** bind actor, stable dispatch UUID, recipient mode,
   normalized message hash, immutable manifest hash/version, confirmed count,
   per-player gifts, aggregate coin/item totals and expiry. Show all of those
   consequences in Review; require a distinct final all-player confirmation.
   Any edit invalidates the preview. Send accepts the server preview identity
   and hash, never a client-provided expanded private recipient list or count.
6. **Delivery, not payment:** after confirmation, a server transaction changes
   the job from prepared to queued exactly once. A trusted resumable worker
   creates one ordinary unclaimed mail for each frozen recipient. Each page
   rechecks role/kill switch and each recipient's public-ID pair and profile.
   Case deduplication, immutable payload and per-recipient terminal status are
   atomic with mail creation. Delivery writes no wallet, stock, save, ownership,
   session ACK or claim receipt. Interrupted work resumes the same dispatch;
   do not retry by allocating a new issue ID or an entire new broadcast.
7. **Identity detail that must not be missed:** current claim audit documents
   use `${mailId}-claimed`. Giving every recipient the same campaign mail UUID
   would collide on the second claimant. Prefer a deterministic unique UUID
   derived from dispatch plus private recipient identity, with a fixed reviewed
   namespace and explicit collision check. Keep the campaign UUID separately.
   Then existing per-player mail paths, UUID cursor contract, claim receipt and
   audit keys remain unique without weakening the claim transaction. An
   alternative recipient-qualified audit key requires its own migration review.
8. **Claim authority stays unchanged:** the existing claim path owns wallet and
   stock mutation. Preserve profile/revision/digest CAS, writer ID/epoch, fresh
   lease, null ACK/request fence, stock and wallet caps, one migration backup,
   native save serialization, journal installation and response-loss recovery.
   The same delivered mail can be claimed only once, even under simultaneous
   requests or a lost response. A campaign delivery receipt is never a claim
   receipt or permission to make gifts spendable.
9. **Truthful status and recovery:** owner status reports prepared, queued,
   delivering, completed, paused or failed, with confirmed delivered/remaining/
   skipped counts. It distinguishes sent/unclaimed from claimed. A timeout is
   uncertain, not a failed send. Reopen/query by the same dispatch identity.
   Role revocation or kill switch pauses undelivered work; it must not fabricate
   success or delete the evidence needed to resume safely. Cancellation stops
   future delivery only; delivered letters cannot be silently recalled.
10. **Data and deployment:** private manifest/job collections are server-owned
    and direct client access is denied. Expose only authorized public summaries.
    Do not add Functions to production configuration, deploy rules, create a
    service identity, enable billing, set an owner role or run a real campaign
    as part of this isolated candidate. Cleanup/retention of expired preparation
    and completed manifests needs a separately reviewed policy.

Required tests before enabling the new modes: invalid/duplicate/missing UIDs;
100 and 101 input boundaries; unauthorized, revoked and changed actors; empty
all-player audience; capture/expiry/hash binding; concurrent confirmation;
response loss and restart at every page; recipients resetting/changing profile;
per-case duplicate delivery; new accounts after the frozen manifest; two
recipients claiming the same campaign without audit collision; simultaneous
claim, stale CAS, transfer request/ACK, ownership loss, wallet/stock full and
replayed claim after later ordinary saves. Run real Firestore/Auth/Functions
emulator plus browser IndexedDB tests, then source-bound responsive/input visual
review on the exact integrated PR head. No such audience-service pass is claimed
by this presentation patch.

### Quality gate and current limits

UI/UX and the visible letter presentation are intentionally changed; original
world/art/camera/economy remain unchanged. Authority and interruption rules above
are design requirements, not implemented backend behavior. Test the original
receipt list, support list/detail, Claim/back focus, long letter, expanded item
picker, collapsed quantity retention, selected/all switching and small landscape.
Synthetic headless layout checks do not establish actual imported game pixels,
physical-device input, user approval, backend behavior, full CI or release.
