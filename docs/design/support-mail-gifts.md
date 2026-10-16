# Support mail and owned Storage — implementation candidate

Status (2026-10-16 UTC): isolated source candidate, not accepted, merged or deployed.
This composes PR339 final `98ff2d983dfeed8a387e08f6eb485bba6bb4f7af`, the required
PR329 ownership/claim contract at `6341889999c1a213b26918afdab9c19b521480c9`, and
the independently reviewed mail-composer presentation from `ff1054658bf8c93897c91a3afe1f95e4b0fca650`,
plus its independently source-reviewed R4 inline-category/height correction. R3
actual pixels were rejected; R4 pixels are not accepted by this source review.
The user explicitly brought the Storage slice of roadmap0.1.17 forward on16October:
pack purchased furniture without selling; reuse Shop inside Decorate; Claim enters
Storage, never a separate player-facing Gifts inventory. Ingredient mechanics and
batch/all-player mail remain outside this slice. No release version is inferred.

## Proportionate design quality gate

- Player outcome: distinguish buying, owning, packing, replacing and selling;
  freely pack/re-place the same object, with a complete session Cancel.
- Reuse: the existing Shop cards, categories, paging, thumbnails, selection and
  placement planner. Shop and Storage are source tabs in Decorate; Storage adds
  All, search, quantities and a clear empty state. Search reuses the existing
  category popup; the header keeps its original height, including short landscape.
  Store and Sell are separate.
- Ownership: `CafeStorage` manages the unplaced location of existing physical
  identities. `CafeModel` owns the same wallet/session; `CafeEditPlan.Source`
  distinguishes SHOP from STORAGE without overloading339's typed Context.
- Functional behavior:339's existing held-service registry retains all orders,
  dishes, clocks, FIFO and payment custody when a host is absent. It is not an
  asset ledger and creates no saleable duplicate. Apply/retry reconciles once;
  Store never resets service. Cancel restores the whole pre-session state.
- No new artwork or generalized inventory framework. Existing catalogue entries
  determine categories and names. Unsupported future ingredients are not shown,
  grantable, placeable or simulated as furniture.
- Evidence gates: exact-source engine and backend tests, independent source review,
  actual desktop/portrait/landscape pixels and interaction, then user acceptance.
  Headless rectangles do not prove painted-frame fit or visual acceptance.

## One canonical owned-asset representation

Native save17 requires `storage_format: "little_leaf.storage.v1"` and
`storage: {items: [...], dining_sets: [...]}`. `items` holds the same physical
records as the placed array: positive stable `id`, `kind`, last `x/z/rot`, and
optional `paid_cost`. Last coordinates are provenance, not occupied floor.
IDs are unique across placed and stored arrays, with `next_item_id` above all
owned IDs and historical held hosts. Stored/held IDs may coincide only with the
same kind. Exactly one register may exist across both locations. Dining groups
transfer both members and their exact existing variant/rotation/paid_cost.

Quantities are views over those records, counting a dining group once. A move
between locations neither allocates an ID nor changes coins or recorded basis.
A paid new purchase records its actual charge. Existing absent individual cost
stays absent and uses the prior catalogue-based resale fallback; historical
prices are not fabricated. Existing dining costs remain exact. The approved
included-bin legacy resale exception is unchanged. A claimed item explicitly
records paid_cost0, so this candidate gives no unapproved resale entitlement.
The original bench/table group has an owned-only display key and retains its real
bench preview, not a purchasable new product. Changing that claim policy or enabling issuance needs a separate decision.

Stock is not capped by the old gift-only100-per-kind or10-per-Finish limits.
Existing file byte ceilings and positive-ID range still apply. Native saves
preflight their existing1MiB limit before replacing a file; cloud envelope
limits remain900k. Whole-session interruption saves only the baseline, including
stock, wallet, identity counter and purchase receipts. Cancel cannot manufacture
stock, refund twice, or replay an already applied external grant.

## Claim, persistence and compatibility

Claim uses the existing authenticated active-writer/epoch/head/CAS transaction.
Coins go to the existing wallet, items receive fresh IDs directly in save17
Storage, and receipt/audit/control/save are committed atomically. Reading a
letter never claims. Duplicate Claim returns the authoritative head, not another
asset. Native freezes and flushes before Claim, validates the returned payload,
and publishes it through the existing journal/model transaction boundary. A lost
reply reuses its original base/operation. An independent duplicate against a newer
head freezes for recovery instead of accepting an arbitrary newer revision.

The outer format3 `mailState {schema:1, claimSequence, stockRevision}` remains a
fence, not another inventory. Ordinary saves cannot change claimSequence.
stockRevision advances on local stock changes; coalesced writes allow a monotonic
increase bounded by save revision growth, including a store/re-place round-trip
whose final stock matches. Surviving IDs retain kind and optional paid_cost
presence/value. New IDs cannot reuse an ID below the previous allocation counter.
This is stale-client/identity protection, not server simulation of the economy.

There are no new writes to giftStock or giftPlacements. Existing pre17 sidecar
stock, including an empty document, and unconfirmed earlier placement intents
fail closed and remain exportable for review. No automatic live migration or
replay is performed. Ordinary15/16 saves remain readable; old versions cannot
hide Storage markers. Save17 composes339's matched outer/runtime/service hold
markers. An untouched ordinary save can remain15, or16 while held; using
Storage or recording a new individual purchase basis requires17. Original player
saves, session ownership, backups and source recovery evidence remain intact.

Google Auth, stable public UID, live narrow server-role checks, issue preview and
idempotency remain the existing mail contract. Production identity-allocation and
support-mail flags remain off. No role, identity, mail, gift, billing, live rules
or deployment is provisioned here. More than one recipient and All players stay
fail closed; this is not broadcast delivery.

## Focused acceptance and evidence limits

- Purchase/store/unpack across all four dining variants and individual furniture:
  unchanged IDs, basis, group members, wallet and quantity.
- Invalid/stale/double placement; repeated Cancel; interrupted baseline save;
  Apply/reload; zero-basis claim resale; duplicate/corrupt IDs; old-version markers.
- Natural cooking, counter handoff, dining, washing FIFO and payment:
  store/reload/re-place same host without lost/duplicated jobs, clocks or money.
- Shared source tabs, owned-only filtering, case-insensitive search, >100 real
  quantities, empty state, distinct Store/Sell and viewport geometry.
- Backend duplicate claim/rollback, protected save fencing, coalesced stock
  revisions, basis and monotonic identity preservation; legacy sidecar quarantine.

Local Firestore emulator and Node contract tests are evidence only for those
paths. The test runtime is Node24.19, while deployment declares Node22. Functions,
Auth, real IndexedDB and compiled-browser end-to-end, combined CI, rendered
pixels and user acceptance are separate remaining gates. The retained source
receipt identifies the exact candidate and individual test results.
