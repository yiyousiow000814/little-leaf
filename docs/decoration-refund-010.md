# Decoration session refunds (0.1.10 candidate)

Entering Decorate begins a memory-only purchase receipt ledger. Successful furnishing purchases in that session refund their actual charge in full through Sell selected, until Done decorating. Selecting either dining-set member sells the whole group and consumes its receipt once. Included zero-cost furniture has no session refund. Old furnishings keep normal resale; a historical 140-coin oak set retains its 70-coin resale, while a new 280-coin oak set retains its 280 paid basis and has 140 resale after Done.

Moves, rotations, selection/gesture cancellation, previews, category changes and autosaves do not finish the session or create another receipt. Failed purchases, failed sales and duplicate planner commits do not transfer money. Done clears receipts before requesting a save, even if the save later fails. Reentry cannot restore eligibility. Successful reload (including reload into an existing model) finalizes an interrupted session; failed load leaves the live session intact. Closing/restarting the process therefore restores saved purchases at normal resale, without refund or wallet correction. A new profile also clears receipts.

The existing save schema remains unchanged: receipts are not serialized, existing dining paid_cost values are not repriced, and old versions can still read these saves. Legacy loose table/chair groups can mix old and new members: only the current purchase receives the extra refund (old100 table + new40 chair sells for90). Floor replacement, wall/opening removal, parcel prices, upgrades and staff transactions retain their existing rules.

The planner copies the session ledger into its isolated model, then publishes it only with a validated purchase. Its stamp includes session state so Done rejects stale previews. Existing Sell labels already read logical_refund and display the eligible value.

Focused verification: tests/test_decoration_refund.gd exercises actual model transactions and the controller Decorate/Done boundary. The baseline mode runs identical purchase/move/sale cases against v0.1.9. All fixtures use generated saveguard profiles; the player save is never read.
