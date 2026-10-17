# Support mail into owned Storage — item 20

Current source candidate: [PR329](https://github.com/yiyousiow000814/little-leaf/pull/329),
0.1.11, composed on main `f6ebeccd9fb8d2ded28895dc2f134c2a491f1ced`.
This replaces the earlier separate-Gifts proposal. The historical filename is
retained for links; there is **no Gifts inventory or special placement path**.
The original Draft head `076747fe956f08e34cf18e67bf0b4339d1aac00b` remains in history.

## Recorded requirement and quality gate

The owner requested mail for multiple selected public UIDs or all players,
with coins/items, a themed Inbox, and Claim into the existing Decorate Storage.
Storage349, recovery347 and Music348 are dependencies already on main, not
additional deltas to copy into this PR. Support Mail remains an admin-only
surface. A browser flag or visible button never grants permission.

Reuse the current HUD, wood/leaf panels, coin art, furniture thumbnail renderer,
Inbox list/read-state behavior and single outer form scroll. The composer uses
the real Array-shaped catalogue through `model.name_of()`. Keep quantities and
coins visible in the prepared review and letter detail. No world, camera, art,
audio, Shop geometry, Storage transaction or original-player-save changes.

UI/UX and game feel require actual desktop/portrait/landscape review. Authority,
save safety and technical correctness require atomic rollback/replay, old
client denial and interrupted-delivery checks. No new per-frame work or cache:
mail fetches on open, retains one 20-row page, and uses bounded picker controls.
Callbacks are account/request scoped. Read markers remain presentation only.

## Review and bounded delivery

Selected input accepts exact 12-digit ASCII public UIDs, beginning with 1–9.
The server independently validates, deduplicates and sorts up to 100 input
entries. Missing or mismatched selected identities reject the whole review.
Only the server resolves private Auth UID and current profile.

All players means existing valid cloud cafés found during the recorded review
interval, including cafés without an allocated public UID. It is not a claim
of an atomic point-in-time snapshot. The service reads at most 50 save documents
per preparation call, persists a cursor and immutable recipient records, and
requires Continue Review until complete. Invalid matched saves fail closed.
No public UID is allocated by mail, and joins after completion are excluded.

The completed review binds actor, normalized letter, mode, exact frozen cohort
digest, count and expiry. Preparing has no usable Send token. Review shows the
server-confirmed recipient count, per-player attachments, aggregate amounts and
capture interval. Send is a separate action. Editing invalidates a pre-send
review; an uncertain or partial Send retains the same issue identity.

Each Send/Continue Send call processes at most 10 recipients. Each recipient's
mail, issue, original-case dedupe, audit, immutable delivery receipt and progress
advance are one transaction. It rechecks active role/capability and frozen
profile/public identity. Changed profiles are reported as non-deliveries, never
silently retargeted. Counts distinguish sent, failed and pending; transient
failure leaves the remaining recipients resumable. A deterministic recipient
UUID avoids collisions in the existing global mail-claim audit keys. The
original case ID is not renamed to bypass duplicate-compensation protection.

Only an exact, unstarted, expired frozen request returns `PREVIEW_EXPIRED` from
the new audience Send path. It proves zero delivered/failed recipients and can
start a new review. Mismatch, missing preparation and uncertain transport do
not provide that guarantee. A started dispatch can resume after preview expiry.

Draft bounds remain 100,000 coins per letter and 1–10 of each supported item
(stove, beverage, sink, counter, bin, plant, lamp, bookshelf, rug, divider).
Lookup/prepare/new-dispatch quotas are 20/10/5 per actor per minute. These are
source bounds, not permission to enable an economy operation. Register, bundled
dining, staff, land, recipes and historical-refund inference remain excluded.

## One authoritative claim and normal Storage afterward

Send does not change wallet, save, ownership, stock or claim state. Claim is
recipient-self-only, checks the active owner/epoch/lease and exact current
profile/revision/digest, and atomically writes the wallet, canonical v17
`little_leaf.storage.v1` items, receipt, mail status and control watermark.
Items receive new monotonic physical IDs with `paid_cost=0`. The first claim
also retains the original cloud envelope. Replayed claims cannot grant twice.

Native Claim freezes input and durably preserves its current snapshot, then
the browser confirms the cloud head before invoking the service. Update/save
transitions cannot interleave it. The returned journal and native model are
validated before installation; stale lifecycle callbacks are ignored. Unknown
outcomes retain evidence and require recovery rather than making an unverified
grant spendable. Ordinary Store/place-back/Apply/Cancel use the existing Storage
model and journal, without a second stock balance.

Envelope 1/2 remains ordinary CAS until mail protection exists. The narrow rules
source denies direct saves after that control document is present, preventing
stale clients from overwriting claims. Protected saves use the existing trusted
operation and acquisition-history/watermark checks; this is not a fully
server-simulated economy. The private control path remains unreadable to clients.
Legacy draft gift stock/intents are quarantined as evidence, never converted or
replayed automatically. Existing compensation receipts, holds and archives stay
separate. PR347's owner-handoff retry and `session.js` are preserved.

## Verification and explicit limits

Recovered source was independently checked against the retained packet, then
adapted only to current v17/Storage v1. Its earlier wall6/v2 validator failed the
strict browser/server parity test; the corrected current mirror passes without
relaxing that test. Recovered claim/client/adapter/identity suites and new
audience checks use generated in-memory fixtures. Native claim tests use the
actual current Model/WebSave with generated payloads; renderer-method tests use
the actual composer/Inbox and real catalogue, mocking transport only.

The PR329-only native job binds exact source, preserves the qualified 83-input
atlas closure without regeneration, and plans 15 full-game PNGs across 1360×880,
390×844 and 844×390. Its separate loopback-only local emulator job tests actual
Firestore transactions/rules and audience cursor behavior. Receipt and pixel
inspection results belong in the PR after execution; neither is claimed here.
Full required exact-head CI, current visual acceptance, physical mobile/keyboard
behavior and compiled-browser real IndexedDB/Functions transport remain separate.

Source publication is authorized for this Draft only. Functions remain absent
from `firebase.json`; identity allocation and support-mail flags default off.
No real admin role, capability, account, UID, mail, grant, rule application,
credential, billing, service activation, deployment or release is authorized or
performed. Manifest retention/cleanup and final catalogue/cap policy need review
before activation. A source merge is not backend readiness or live acceptance.
