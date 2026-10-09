# Placement feedback follow-on

Base: PR103 source `bf0288265e81cdc80f943c2bcce5cfb8461542b3`.

The stroke action board shows quantity, existing coin artwork and numeric total.
The accessible price still names coins. Error and refund explanations remain in
the existing details. Ordinary single-target transaction text is unchanged.

Furniture availability and active placement use opaque mint/red colors with
contrasting outlines. They do not alpha-blend with installed flooring. Active
previews also use a check/cross marker. Tiles browsing still suppresses the
availability layer. Tile-paint previews show the selected finish at full color,
with a single fine outer perimeter instead of per-tile borders, checkmarks or a green/red material tint. Adjacent preview tiles reuse the installed floor palette, seams and oak grain so they join naturally.

Model validation, ownership, prices, revisions, atomic commit and cancel behavior
are unchanged. All captures use synthetic cafes and suppressed player saves.

Focused verification: 2,677 native checks across7 suites pass (feedback colors20,
stroke price layout62, tile perimeter156, stroke UI36, floor inspection180,
build/tiles UI2144, editing feedback79). Native color counts are compared across all3 installed
floor styles, and the real four-tile preview is captured before committing.

Centering checks cover390×844,440×700,566×360,844×390 and1360×880. The board is horizontally centered; quantity, coin, price and Cancel share a vertical center, with balanced left/right padding. Native portrait and landscape captures confirm the same four-tile,40-coin preview.

Optical follow-on: the actual painted inset is2.5px below the action board's
rectangular center. Visible Nunito/coin ink was3–3.5px high in the user crop.
Only the active stroke content row moves down3px. Native desktop/portrait/
landscape verification measures quantity, price, coin and Cancel ink within1px
of the inset center:24 pixel checks pass. All62 responsive geometry checks still
pass. `qa/verify_action_board_ink.py` reproduces the measurement from native PNGs
and the capture helper's recorded control bounds; no screenshot is resized.
