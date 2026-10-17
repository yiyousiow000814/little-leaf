# Owned Storage in Decorate

This is the Storage-only dependency for the later mail integration. Current
delivery and review status belong in the [canonical roadmap](../roadmap.md).

## Recorded direction and reference

The user asked to keep purchased furniture without selling it, use the same
interface as Shop inside Decorate, and show only owned items, inspired by
Restaurant City. Preserved Restaurant City inventory, editor-menu and sale-dialog
screenshots were inspected on 17 October 2026. They show an inventory source tab
inside the editor catalogue, shared item categories, ownership counts and paging,
with selling as a separate action. These are structural references, not artwork
to copy and not approval of the Little Leaf candidate's appearance.

## Reuse and interaction

- Keep the existing Little Leaf wood shelf, cards, thumbnails, category picker,
  search, horizontal paging, placement preview and whole-session Decorate controls.
- Shop and Storage are two sources in that same shelf. Storage shows owned
  furniture only, with All and existing categories, `Owned ×N`, no coin-price
  icon, and explicit empty/no-match states. It creates one card per catalogue
  kind, not one control per stored physical item.
- Store and Sell remain separate. Store transfers the existing identity into
  Storage without payment or refund. Selecting it again uses the same placement
  planner, original rotation and identity, without buying another item.
- Dining sets retain both physical members, variant and recorded purchase basis.
  The original bench set is owned-only and never a new Shop product.
- Cancel restores the complete Decorate baseline, including stock, wallet,
  identity counter and purchase receipts. Apply retains existing save/retry and
  service-hold reconciliation. Invalid or repeated placement cannot duplicate stock.
- Mobile reuses the category/search popup and the existing short-landscape shelf
  rather than enlarging the panel over the café. Painted fit remains to be checked.

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
cost, Cancel, duplicate/corrupt records, held-work markers, category/search,
105 owned items and desktop/portrait/short-landscape control bounds. Browser
tests cover payload17 validation and actual ordinary adapter CAS with synthetic
SDK/journal boundaries, preserving envelopes1/2 and rejecting envelope3.

Source tests do not accept the pixels. Required next review is actual full-asset
Little Leaf at1360×880,390×844 and844×390: Storage, open category/search and distinct
Store/Sell, then place-back/Cancel interaction and the user's visual decision.
Current-main full UI, browser/device qualification, canonical atlas/source
closure and exact-head CI remain separate gates. No release or deployment is
implied by this design or its draft PR.
