# Starter-wall grid segments: migration design for review

Status: independently reviewed design, now implemented as a local candidate. See `starter-wall-implementation-review.md` for validation and remaining release gates. The original review is bound to commit `5a0f151`. Base: `9110ebd9a2d6cbf4d2af303be0e244e660c0f7fc` (shipped 0.1.8). This work is separate from the completed Build/Tiles UI branch.

## Intended interaction

Clicking a starter wall selects the one floor-grid edge under the pointer. Preview, style/height change, quote, and commit concern that segment only. The selected segment receives a one-grid outline. Unchanged adjacent walls remain visually continuous; permanent new seam lines are not necessary to make selection local. This phase does not add shell removal, move its boundaries, or change entrances.

The current whole-west-wall quote is nine units × 55 = 495 coins. The existing model already represents player-built walls as one-grid edges; only the starter shell requires this migration.

## Preserve the geometric roots

Keep `shell:back` and `shell:west`, their order, axes, coordinate origins, and 0.26-tile thickness. Do not convert them into player-built walls, which have different 0.16-tile geometry. Existing collision code indexes the two root hosts by order, so a new flat list of segment hosts cannot replace that API.

Keep every door/window ID, `host_id`, offset, width, paid value, and sequence counter unchanged. Attachment geometry continues to resolve against its original root host. Segment appearance/payment records are an additive layer. An aperture may cross several segment boundaries; it is not split into new attachments.

Retain the current special player-built west extension at z=8. When it exists, the shell ends at z=8 and the player wall remains authoritative there. The new ledger holds the canonical 12 back + 9 west identities, with the inactive ninth shell entry carrying zero paid/refund value. Removing the legacy extension later can reveal that included entry without moving another wall or inventing value.

The existing narrowly scoped free starter-door migration remains separate. Compare new migration output against the validated 0.1.8 load result, not against a raw old fixture before that existing migration. This proposal introduces no additional opening narrowing, movement, or ID rewrite.

## Proposed data contract

Use existing root snapshots plus:

- `wall_format: 2`
- `shell_segment_format: "little_leaf.shell_segments.v1"`
- `shell_segment_products`: canonical keys such as `shell:west#5`
- Each segment: `height`, `material`, `paid_cost`, `refund_credit`

The retained `shell_products` root snapshots describe the inherited base and preserve historical metadata. Once format 2 is active, segment records are authoritative for current appearance and refundable value. No old whole-shell mutator may update only a root snapshot and leave the segment layer inconsistent. Route the active UI to a dedicated segment quote/replace operation; reject ambiguous whole-root replacement with “Select one wall tile” unless a separately designed explicit batch operation is introduced later.

### Compatibility guard without a blind vault version bump

Keep the outer save version 15, checkout/movement formats, storage identity, revision handling, and campaign receipts unchanged. The browser vault currently hard-requires version 15. The existing wall sub-format already provides a strict compatibility guard: shipped 0.1.8 accepts only `wall_format == 1`.

The focused test writes a generated version-15 payload with `wall_format: 2` and proves the unmodified 0.1.8 loader rejects it without changing the live model or the original file. An older tab opened before a new commit remains subject to the existing authoritative profile/revision conflict checks. An older client opening afterward must enter its existing write-suppressed recovery path rather than flatten the new wall layer.

Production integration must add browser tests for that complete chain; the prototype does not claim to have exercised IndexedDB or an actual old-client browser. Keep wall format 1 readable for migration, and reject any format-1 payload that unexpectedly contains format-2 segment fields rather than silently ignoring them.

## Exact paid-value and refund preservation

Naively setting nine 55-coin segments to a 27-coin refund loses value: 9 × 27 = 243, while the old whole-wall refund is floor(495 / 2) = 247. An explicit refund credit is required.

For each inherited root:

1. Preserve its exact total paid amount P
2. Allocate deterministic integer paid shares along increasing root coordinates
3. Allocate each refund as floor(cumulative paid / 2) minus floor(previous cumulative paid / 2)
4. Therefore segment paid shares sum to P and segment refund credits sum to floor(P / 2)

For P=495 across nine units, paid shares are all 55 and credits are `[27, 28, 27, 28, 27, 28, 27, 28, 27]`, totaling 247. These extra alternating coins preserve a pre-existing aggregate entitlement; they are not new awards.

Special legacy cases:

- A paid eight-unit west wall extended to nine included units keeps its value in the first eight segments. The ninth remains free with zero refund
- A retained player-built extension leaves eight active shell segments
- The current reader also accepts a nine-unit paid amount with an eight-unit active shell. Do not reject or discard that previously accepted value: prorate it deterministically over the eight active segments (61/62 paid shares for 495), with the same exact cumulative-refund rule
- Free inherited shells keep zero paid/refund value regardless of material

After a new single-segment purchase, that segment records the ordinary current unit cost and floor(unit cost / 2) as its future refund. Every neighbor's appearance, paid amount, and refund credit stays byte-for-byte unchanged. A first edit does not reallocate credits across the remaining wall. Removing or moving a retained extension also leaves the historical allocation unchanged. Validation must find one coherent historical eight- or nine-unit basis for all inherited records in each root, rather than deriving history from its current extent; ordinary purchased records can coexist with that basis. Same-style selection is a no-op. Invalid support, insufficient coins, cancellation, and failed validation cannot charge or mutate anything.

Validate complete canonical key coverage, active/inactive geometry, enumerated styles/heights, finite integer costs/credits, per-segment credit limits, and aggregate credit ≤ floor(total paid / 2). Normalize JSON numeric fields to integers on decoding. The prototype's numeric bounds are deliberately tied to the unchanged 0.1.8 prices and accepted legacy records; no economy change is proposed.

## Opening support and rendering

An opening needs every segment intersecting its complete half-open aperture interval at full height. Exact grid-boundary contacts do not claim the neighboring segment. Examples covered by tests:

- Door centered at 5.5, width 1.0: segment 5
- Legacy door centered at 5.5, width 1.5: segments 4, 5, 6
- Moved door centered at 5.0, width 0.76: segments 4, 5
- Window centered at 4.0, width 0.70: segments 3, 4

A material-only edit remains local and does not change the aperture. Lowering any supporting segment is rejected until the opening is moved or removed through the existing validated workflow. Existing player-built spanning hosts retain their existing validation.

Keep the old renderer verbatim for a homogeneous inherited root. For mixed appearances, group consecutive equal segments into runs while retaining the original root origin, normal, and world-aligned texture coordinates. Clip solid panels around the existing apertures in root coordinates. Draw end faces only at genuine exposed ends or height steps, not at every segment/run join. Segment selection/hit testing is separate from render batching.

The prototype proves root extent/thickness/ordering and homogeneous-render eligibility. It does not prove final raster equivalence: before/after native pixel captures remain a required implementation gate.

## Focused evidence completed

`tests/run_shell_segment_contract.py` runs a disposable, asset-free headless project. No editor import, copied asset cache, player profile, or browser storage is involved.

The current pass has 27,219 assertions covering:

- Both root hosts, two heights, all four inherited materials, zero/eight/nine-unit paid values, and extension present/absent
- Exact total paid/refund preservation and the 495 → 247 rounding case
- Contiguous unit geometry, unchanged root identities and thickness
- Every one-cell edit with all other 20 ledger records unchanged
- Included/dormant ninth-row rules and retained extension authority
- Full aperture-span support checks, including exact boundaries and legacy wide openings
- Atomic invalid/insufficient-funds paths, same-style no-op, and normalized JSON round-trip
- Real unmodified v15 model rejection of wall format 2 without live-model mutation or original-file writes

Files: `tests/fixtures/shell_segment_contract.gd`, `tests/test_shell_segment_contract.gd`, and `tests/run_shell_segment_contract.py`.

## Review and implementation gates

Before production edits, approve the wall-format-2 guard and explicit refund-credit representation. Then implement in this order:

1. Pure segment codec/validation and atomic model quote/replace
2. Root-preserving geometry, complete opening support, and unit hit testing
3. Homogeneous fast-path and mixed-run renderer; compare unchanged legacy scenes pixel-for-pixel
4. Build UI one-segment target/preview/confirmation, integrated with the separate stable-title/price fix
5. Save/load and browser authority tests: old-tab conflict, old-client recovery, new-client reload, failed writes, receipt preservation, and no reset or automatic rewrite of original import files
6. Focused engine/native review, then the complete regression suite and clean import/export CI

The stove owner may edit placement validation in `cafe_model.gd`; keep this work in shell-specific methods and coordinate integration rather than copying the entire file. Door-jamb art changes in `illustrated_openings.gd` must be preserved when adding mixed-run rendering. No merge, deployment, or repository publication is authorized by this design checkpoint.
