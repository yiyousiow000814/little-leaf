# Owned Storage in Decorate

This is the Storage-only dependency for the later mail integration. Current
delivery and review status belong in the [canonical roadmap](../roadmap.md).

## Recorded direction and reference

The user asked to keep purchased furniture without selling it, use the same
interface as Shop inside Decorate, and show only owned items, inspired by
Restaurant City. Preserved Restaurant City inventory, editor-menu and sale-dialog
screenshots were inspected on 17 October 2026. They show an inventory source tab
inside the editor catalogue, shared item categories, ownership counts and paging,
with selling as a separate action. The preserved inventory image and its
[original guide](https://www.gamezebo.com/walkthroughs/restaurant-city-walkthrough/)
were revisited after the first candidate was rejected: the small crate beside a
plain number at each card's upper-right communicates the inventory count. The
large crate above the catalogue is a separate source selector. These are
structural references, not artwork
to copy and not approval of the Little Leaf candidate's appearance.

## Reuse and interaction

- Keep the existing Little Leaf wood shelf, cards, thumbnails, category
  rail/picker, horizontal paging, placement preview and whole-session controls.
- Shop and Storage are two sources in that same shelf and share the existing
  Decorate categories, cards and responsive layout. Storage shows only owned
  furniture pictures, with a small Little Leaf-style crate and plain count at
  the upper-right. No All, text input, visible item title, `Owned`, `×N`, price
  or `Place · free` copy. An empty category remains explicit. One shared card
  represents each catalogue kind, not each stored physical item. The filter
  and badge reuse one ownership count per kind per refresh. This bounded UI
  projection is rebuilt on refresh, never saved or used as a second inventory.
- Store and Sell remain separate. Store transfers the existing identity into
  Storage without payment or refund. Selecting it again uses the same placement
  planner, original rotation and identity, without buying another item.
- Dining sets retain both physical members, variant and recorded purchase basis.
  The original bench set is owned-only and never a new Shop product.
- Cancel restores the complete Decorate baseline, including stock, wallet,
  identity counter and purchase receipts. Apply retains existing save/retry and
  service-hold reconciliation. Invalid or repeated placement cannot duplicate stock.
- Mobile reuses the existing category-only picker when space requires it, and
  the category rail/arrows otherwise. Short landscape does not stack two44px
  rows inside a96px board. Storage controls and clipped item content must fit
  inside the actual26px/23px nine-slice wood interior, not merely the viewport.

## One ownership and persistence model

Save payload17 adds `storage_format: little_leaf.storage.v1` and
`storage: {items, dining_sets}`. One physical identity is placed or stored, never
both; held service hosts are non-owning references. Known paid cost is preserved,
and absent historical individual cost is not invented. Existing register,
legacy-sale and wallet rules stay intact.

The browser accepts payload17 inside existing envelope1/2 and uses the unchanged
ordinary CAS save path. It does not enroll mail protection, add envelope3, a
second inventory or wallet, backend rules, Functions, role grants or activation.
Untouched ordinary saves can remain15, or16 while held. New purchases with an
explicit acquisition basis and Storage usage require17. Old clients fail closed
instead of dropping that state. Existing byte limits still bound saves.

The later mail PR owns Inbox/composer/Claim, public UID/admin audience dispatch
and protected mail-save integration. None is delivered by this dependency.
Wall-topology/migration work is also excluded.

## Proportionate quality and acceptance

This affects UI/UX, gameplay-reference interaction and persistence. It reuses
existing art/audio and service behavior. Catalogue counts are computed during
existing UI refresh from owned records; no new per-frame process, network poll,
asset cache or per-owned-item control is introduced. Large-stock performance is
not certified by the synthetic ownership tests.

Existing focused fixtures cover purchase/store/place-back, stable identity and
cost, Cancel, duplicate/corrupt records, held-work markers, categories,105 owned items and
desktop/portrait/short-landscape control bounds. The revised native UI fixture
checks painted board insets, plain crate counts, no redundant text/input,
actual category/source/Store clicks and paired Shop/Storage captures. Browser
tests cover payload17 validation and actual ordinary adapter CAS with synthetic
SDK/journal boundaries, preserving envelopes1/2 and rejecting envelope3.

Source tests do not accept the pixels. The first native candidate was explicitly
rejected for crowded/out-of-board controls, the oversized All selector, text input
and redundant copy. Its screenshots and test evidence are retained, not accepted
or relabelled as the revision. Actual full-asset desktop/portrait/short-landscape
revision captures, place-back/Cancel interaction and the user's visual decision
remain required. Current revision status belongs in the roadmap and PR.
Browser/device, broader full UI, atlas/source closure and exact-head CI remain
separate gates. No release or deployment is implied by this design or draft PR.
