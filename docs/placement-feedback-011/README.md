# Placement feedback follow-on

Base: PR103 source `bf0288265e81cdc80f943c2bcce5cfb8461542b3`.

The stroke action board shows quantity, existing coin artwork and numeric total.
The accessible price still names coins. Error and refund explanations remain in
the existing details. Ordinary single-target transaction text is unchanged.

Furniture availability and active placement use opaque mint/red colors with
contrasting outlines. They do not alpha-blend with installed flooring. Active
previews also use a check/cross marker. Tiles browsing still suppresses the
availability layer. Tile-paint previews show the selected finish at full color,
with a border/check/cross instead of a green/red material tint.

Model validation, ownership, prices, revisions, atomic commit and cancel behavior
are unchanged. All captures use synthetic cafes and suppressed player saves.

Focused verification: 2,496 native checks across6 suites pass (feedback colors20,
stroke price layout37, stroke UI36, floor inspection180, build/tiles UI2144,
editing feedback79). Native color counts are compared across all3 installed
floor styles, and the real four-tile preview is captured before committing.
