# Starter-wall grid implementation: local review candidate

Historical source-bound implementation review, based on shipped 0.1.8 commit `9110ebd`. The independent design review is retained in [starter-wall-design-review.json](starter-wall-design-review.json). Candidate, branch, publication and deployment statements below describe the source revisions recorded here; they do not establish current readiness or integration instructions. Use the [canonical roadmap](../roadmap.md) for current implementation, ownership and acceptance state.

A starter-wall click now selects one floor-grid edge. Its preview, style/height quote and confirmation apply to that edge only. A new full-height tile costs 55 coins, rather than replacing all nine west-wall tiles for 495. Quotes and cancellation do not charge. Existing shell boundaries, thickness, geometric root order, opening identities and offsets remain intact.

The version-15 payload now writes wall sub-format 2 and an additive 21-entry segment ledger. Format 1 remains readable. Older 0.1.8 clients reject format 2 through their existing guarded recovery path. Each inherited record retains its deterministically allocated paid amount and refund credit, including the 495-paid/247-refund rounding case. Production validation accepts exact inherited records or recognized ordinary purchases; arbitrary 62-coin values or new 55-coin purchases with a 28-coin refund are rejected. Historical 35/55 prices remain explicit constants for old payments. The validator requires one coherent historical eight- or nine-unit allocation per root across every inherited record; it never reallocates payments when current geometry changes. Ordinary purchases may coexist with that same historical basis.

## Consumer audit

- Model save/load validates the segment ledger before publishing state or writing files. Root snapshots remain historical metadata
- Opening placement, move and replacement validation check the complete aperture span against authoritative segment heights, including openings crossing two or three cells
- Floor collision and egress keep the two original geometric hosts. Half and full walls have the same blocking footprint; no host origin, thickness or root order changes
- Furniture planning clones carry the ledger; edit-plan and availability signatures include it
- Unit hit testing expands only the selection view of the roots. Attachments retain root host IDs and root-relative offsets
- The renderer keeps the original homogeneous draw path. Mixed runs keep root-relative texture coordinates and aperture clipping; end faces appear only at exposed ends and height steps
- The shell corner cap reads the adjacent segment-zero heights, including a valid preview, rather than inherited root height
- The old whole-shell material setter and replacement quote reject ambiguous root edits, preventing stale snapshots from overwriting segment state
- The unused legacy `_wall` art helper still refers to the legacy finish field but has no render call sites

## Completed evidence

At corrected runtime commit `40b3c5a7c4e14240ba1bf482f5b4d499072f8031`:

- 217,822 aggregate assertions across 44 engine processes passed
- Production ledger, model and UI cases include exact payments, refund preservation, unchanged neighbors, unit hit targets, confirmation/cancel, wide-opening support and mixed save/reload
- A separately reproduced extension-removal save failure was corrected. Removing or moving the retained extension now preserves every ledger record and exact totals, even after a prior neighbor purchase; the ninth tile remains free. Subsequent purchase/save/reload and incompatible-basis rejection also pass
- The actual frozen 0.1.8 reader passed 27,219 guard/design assertions
- Independent exact old-controller checks passed 16 assertions: new-format rejection enters paused recovery with writes suppressed and zero bridge writes
- Independent synthetic transaction checks passed 16 assertions: stale old writes conflict, then remain not ready; authority, prior record, digest, compensation receipts and legacy bytes remain unchanged
- Eight unchanged legacy scenes matched pixel-for-pixel at the same native viewport and camera, including inherited finishes, a half-height back wall, a retained west extension with a wide paid door, and remove/move-extension save/reload for both 495-paid full and 315-paid half roots
- Actual native hover changed from whole-root 495-coin preview to one-cell 55-coin preview; both wallets stayed at 10,000 until confirmation. Mixed styles and heights were visually reviewed
- 42 CI utility unit tests and 172 synthetic legacy-byte checks passed

All evidence uses synthetic profiles. Local engine tests reuse only byte-verified imported assets because fresh local editor import is resource-limited. No player profile, source import or authoritative browser record was modified.

## Complete wall product preview refinement

The later visual candidate at `be809ec0c0a93486a5b391c19201f5a35f1ef106` treats height and style as one wall product. Its selection follows the real front, top-cap and side-return coordinates, rather than tinting only a flat front rectangle. The front fill was removed, so selection cannot paint over a doorway aperture. These temporary edges do not create new gaps or permanent interior faces between neighbors. The picker says “Wall style · included.”

This refinement changes no model, save, payment, refund, host or opening geometry code: six core scripts were verified byte-identical to the validated grid-wall candidate. Its affected UI/geometry tests pass 336 assertions, and model transaction tests pass 1,169. Actual native full- and half-height previews were inspected; all eight unchanged legacy/extension scenes remain pixel-identical. The current preview has 22 native PNGs. The earlier 217,822-check aggregate applies to the validated migration/core revision; the full final integrated build still needs the release gates below.

## Final accepted outline

The accepted selection and preview use an antialiased dark-gray `#444744` outline at 0.35 display-pixel width, with no fill on the cap, wall or opening. The complete front, top-cap and side-return geometry stays visible at every zoom. The earlier palette and stroke revisions are superseded. The regression fixture checks passive, valid and invalid previews without changing payment or save state.

## Historical remaining release gates

Real browser execution was pending in this recorded review. The [actual Web wall-save compatibility gate](../testing/wall-web-compatibility.md) specifies actual IndexedDB, stale-tab, new-client reload, failed durable write and old-client recovery checks. Native-controller and synthetic transaction evidence do not replace that gate; use the roadmap for its current status.

Integrate with the accepted Build action strip, door-jamb correction, stove reservations, dishwashing and other 0.1.9 work; run combined regressions and fresh import/export CI against the final source before publication. Keep the existing outer save version 15 and receipt authority unchanged.
