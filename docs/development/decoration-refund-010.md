# Decoration session transactions and refunds

The current candidate follows the user's whole-session requirement: the top X cancels every change since entering Decorate and exits; the checkmark applies every change, including furniture sales. Selection cancellation, Escape and right click remain tool/gesture cancellation. The top X stays enabled throughout the session, including after selling the last selected furnishing.

One memory-only baseline owns the model state, wallet, layout identities, Build products, parking, staffing and paused service snapshot. Entry is idempotent. X restores that baseline and reconstructs the existing runtime so moved staff and guest custody agree with the restored layout; stale planner receipts are invalidated. No undo money is calculated: restoring the baseline avoids duplicate sale credits and rounding errors.

During Decorate, the existing native and Web save paths serialize the baseline through the unchanged save validator and writer. Autosave, tab hide, recovery protection and update therefore cannot make an unaccepted draft durable. A reload before Apply restores the baseline. Apply clears the baseline and temporary refund receipts before requesting the ordinary save. A persistence failure after Apply leaves applied changes in memory under the existing unsaved/retry behavior; it does not claim durable success. Repeated Apply/Cancel callbacks cannot apply a second refund. Successful load or fresh profile replacement clears the session; failed load retains it. No save-format or account/profile/revision/lease guard changes are included.

This is a pending implementation, with generated regression cases and actual native/browser interaction acceptance still required. No live player recovery is performed.

## Actor-independent editing follow-up (requirements 25/26)

The user approved moving, rotating, placing and selling furniture independently
of present actors. Apply must preserve existing customers, orders, payloads,
job/meal progress and payment state, prefer surviving compatible bindings, and
wait with frozen progress when equipment or floor is unavailable. Cancel must
restore the complete existing baseline, including confirmed external credits
exactly once. This approval does not authorize deletion, forced departure,
invented completion or payment.

The candidate extends the existing EditPlan with explicit Runtime/Decorate
contexts and typed furniture, wall and opening actions. UI and execution share
the cached quote, including price, refund and stale-state validation. Each
Decorate domain adapter uses a geometry-only shadow; normal Model/runtime
collision remains strict. Existing flooring quotes keep their own decorative
layer rules. No placement tooltip is restored.

Draft edits change geometry and purchase/refund ledgers without refreshing
service, clearing staff routes or publishing actor changes. Autosave still writes
the complete session baseline. Apply constructs a read-only reconciliation over
existing service identities, preserves surviving bindings before replacements,
and validates its complete native serialization before publishing or clearing
Cancel. Encoding/reconciliation failure leaves the draft and baseline intact.
After successful Apply the ordinary writer retains its existing unsaved/retry
behavior on persistence failure. Confirmed external credits still update both
wallet and baseline once through the existing credit boundary.

The bounded `service.layout_hold` registry identifies existing visits by ID/token,
workers by stable index, dishes by ID and floor tasks by ID/token. It does not own
actors or orders. Only invalid host references detach to `-1`; typed historical
host descriptors are validation evidence, never furniture, stock, obstacles or
refundable items. Valid actual payload hosts remain occupied. Native validation
resolves these descriptors in a private projection and reuses the full existing
custody/payment/job validator before accepting the detached representation.
Held meal, patience, movement and job clocks freeze. An unassigned visit also
waits when unfinished service needs unavailable equipment, so a sold stove cannot
turn into an automatic patience departure. Checkout keeps FIFO tickets and paid
flags; a held head never allows a later ticket to settle ahead of it.

Snapshots with the registry use outer version16 plus matching outer/runtime/hold
markers. Normal snapshots remain version15 in the existing profile namespace.
Native building/checkout/runtime readers and both embedded browser authority
codecs accept the explicit newer format. Legacy clients reject its version;
foreign markers cannot be disguised as older saves. Authority/profile identity,
archive retention, leases, CAS and compensation receipts remain unchanged.

Feature Design Quality Gate: reuse EditPlan, the domain adapters, full-session
baseline, Main service records, dish/floor ledgers and ordinary save writer.
Living World identity/custody, Gameplay Reference rules, UI/UX actions and QA are
affected; art assets, Technical Art, audio and animation assets remain unchanged.
No new actor, order or endpoint allocator exists. The hold registry is bounded
by existing service limits; derived membership maps are replaced at registry
changes. Apply/retry performs bounded component/reachability work. A cheap
geometry/capacity signature excludes clocks and ordinary revision changes;
unchanged held layouts do not run reconciliation or BFS each frame. Existing
coordinator endpoint and chef-priority algorithms retain only narrow held-owner
exclusions. Their `_service_target` lookup is unchanged.

Focused disposable verification covers natural cooking, counter payload, occupied
dining, queued/partly washed dishes and in-progress payment; replacement/reload,
unusable floor, corruption rejection, repeated Apply/Cancel, confirmed external
credit and save/encoding failure. Native matched source-bound captures show the
actual Sell behavior and held/rebound work. Exact receipts and source identities
belong in the principal Draft PR. They do not establish browser rendering,
physical-device performance or user acceptance.

Composition boundary: based on the frozen combined PR331/335 coordinator source
`9d6893d`. Preserve PR337's accepted picker/hidden-object changes when composing
with main; this delta does not alter those hunks. PR329's Gift Apply confirmation,
Cancel baseline, stock quote and protected-save codec additions require coherent
integration by the parent coordinator. The performance owner's idle-scan work
must retain the three held-worker skips in `_refresh_idle_homes`; this candidate
does not change `_staff_idle_cell`, `_standby_cell_static` or `_idle_cell_clear`.
No independent merge, tag, deployment, live grant or original player-save access.

## Historical 0.1.10 refund contract

The following dated refund rules retain their price/entitlement scope. Their interrupted-session persistence behavior is superseded by the whole-session transaction above.

Entering Decorate begins a memory-only purchase receipt ledger. Successful furnishing purchases in that session refund their actual charge in full through Sell selected, until Done decorating. Selecting either dining-set member sells the whole group and consumes its receipt once. Included zero-cost furniture has no session refund. Old furnishings keep normal resale; a historical 140-coin oak set retains its 70-coin resale, while a new 280-coin oak set retains its 280 paid basis and has 140 resale after Done.

Moves, rotations, selection/gesture cancellation, previews, category changes and autosaves do not finish the session or create another receipt. Failed purchases, failed sales and duplicate planner commits do not transfer money. Done clears receipts before requesting a save, even if the save later fails. Reentry cannot restore eligibility. Successful reload (including reload into an existing model) finalizes an interrupted session; failed load leaves the live session intact. Closing/restarting the process therefore restores saved purchases at normal resale, without refund or wallet correction. A new profile also clears receipts.

The existing save schema remains unchanged: receipts are not serialized, existing dining paid_cost values are not repriced, and old versions can still read these saves. Legacy loose table/chair groups can mix old and new members: only the current purchase receives the extra refund (old100 table + new40 chair sells for90). Floor replacement, wall/opening removal, parcel prices, upgrades and staff transactions retain their existing rules.

The planner copies the session ledger into its isolated model, then publishes it only with a validated purchase. Its stamp includes session state so Done rejects stale previews. Existing Sell labels already read logical_refund and display the eligible value.

Focused verification: tests/building/test_decoration_refund.gd exercises actual model transactions and the controller Decorate/Done boundary. The baseline mode runs identical purchase/move/sale cases against v0.1.9. All fixtures use generated saveguard profiles; the player save is never read.

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
