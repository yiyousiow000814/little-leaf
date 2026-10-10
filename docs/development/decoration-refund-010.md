# Decoration session refunds (0.1.10 candidate)

Entering Decorate begins a memory-only purchase receipt ledger. Successful furnishing purchases in that session refund their actual charge in full through Sell selected, until Done decorating. Selecting either dining-set member sells the whole group and consumes its receipt once. Included zero-cost furniture has no session refund. Old furnishings keep normal resale; a historical 140-coin oak set retains its 70-coin resale, while a new 280-coin oak set retains its 280 paid basis and has 140 resale after Done.

Moves, rotations, selection/gesture cancellation, previews, category changes and autosaves do not finish the session or create another receipt. Failed purchases, failed sales and duplicate planner commits do not transfer money. Done clears receipts before requesting a save, even if the save later fails. Reentry cannot restore eligibility. Successful reload (including reload into an existing model) finalizes an interrupted session; failed load leaves the live session intact. Closing/restarting the process therefore restores saved purchases at normal resale, without refund or wallet correction. A new profile also clears receipts.

The existing save schema remains unchanged: receipts are not serialized, existing dining paid_cost values are not repriced, and old versions can still read these saves. Legacy loose table/chair groups can mix old and new members: only the current purchase receives the extra refund (old100 table + new40 chair sells for90). Floor replacement, wall/opening removal, parcel prices, upgrades and staff transactions retain their existing rules.

The planner copies the session ledger into its isolated model, then publishes it only with a validated purchase. Its stamp includes session state so Done rejects stale previews. Existing Sell labels already read logical_refund and display the eligible value.

Focused verification: tests/test_decoration_refund.gd exercises actual model transactions and the controller Decorate/Done boundary. The baseline mode runs identical purchase/move/sale cases against v0.1.9. All fixtures use generated saveguard profiles; the player save is never read.

## Scope remaining from the broader wording

This PR implements the furnishing Sell selected route because it shares stable item IDs and the atomic furniture planner. It does not claim that every purchase under Decorate has full refund support. Build products use separate wall/opening identities and replacement ledgers; sharing furniture receipts with those routes without their own transaction tests would be unsafe.

| Decorate purchase | Existing disposal transaction | This PR |
| --- | --- | --- |
| Tables, Kitchen, Drinks, Cleaning, Decor furnishings | Sell selected removes physical item or complete dining set | Full actual-charge refund before Done; old items normal |
| Player-built half/full walls | remove_wall refunds half current wall price; attachments must be removed first | Excluded; broader rule still needs implementation/tests |
| Doors/windows | remove_wall_attachment refunds half stored paid_cost | Excluded; broader rule still needs implementation/tests |
| Floor tiles | replace_floor quotes half previous paid_cost against new tile cost; no standalone sell action | Excluded; session replacement semantics remain to define/test |
| Shell wall height/finish and wallpaper | replacement/upgrade ledger; free wallpaper finish | Excluded; replacement semantics remain separate |
| Land parcels | buy_parcel only; no resale action found | Excluded; no current resale rule to change |
| Stove levels and staffing | Upgrade/hire/payroll, not furnishing sale receipts | Excluded; upgrade cost is not refunded by this rule |

If newly purchased items includes Build products, this is a partial implementation of that broader request. Wall and door/window removals clearly have resale actions requiring follow-up. Tile replacement credits may also need the rule, but must preserve net-cost accounting and distinguish replacement from sale.
