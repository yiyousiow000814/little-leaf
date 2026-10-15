# Parking visitor parties

This PR158 successor composes the existing party/traffic repair with pinned main
`83e20a1b2cf03a833ea4306d07d756b3c07c3bd6` and the PR243 delivery-phase bridge.
It is a source candidate. Current-head engine, atlas, natural journey and user
acceptance remain pending; historical evidence does not qualify this composition.

## Scope and ownership

Parking remains a fixed four-bay upgrade bought through Decorate for 50,000.
The current model purchase guard, same-session full refund, later half-paid-cost
refund and occupied-lot sale refusal are retained. The old branch's normal-play
For Sale sign, purchase modal and independent curb seam changes are excluded.
Current Ring/rug rendering, selected furniture footprint and oak painter ordering
remain intact. Bus rendering synchronizes only the model-owned controller reference;
the existing model service tick advances traffic and bus progress.

The implementation follows the [Living World contract](../design/living-world.md)
and [Feature Design Quality Gate](../design/README.md#feature-design-quality-gate).
It reuses the bounded eight-car pool, four bays and one-to-four-member parties.
No extra customer/background clock, economy rule, private reception capability,
generic route codec change or global save-version promotion is introduced.

## Identity, custody and restore

The parking subsystem uses `little_leaf.parking.v2`. Every original member retains
`id == member_id == appearance_sequence`, its original car/bay, species and original
appearance recipe. Queue/admitted guests carry the same parking bindings.
`Parking.admitted` transfers that exact guest; `Parking.start_return` consumes the
exact guest ID and actual exit position. Dirty table records may retain cleanup
custody after the visible person returns. Departure requires every original member
to be boarded and retirement requires the physical car to reach its route endpoint.

The v2 reader checks actual guest/queue custody, route/index/body continuity,
membership, bays/slots and the bounded saved road pool before atomic publication.
Valid historical v1 records retain strict legacy multiple-driving refusal before
migration. A validated straight pre-turn approach may progress while a different
car owns the exclusive maneuver; two actual maneuvers or unsafe spacing reject.
Older v2 binaries can reject these newly concurrent snapshots: unchanged format
does not establish acceptance by older clients. Generic save, body and service
validation remains authoritative.

Successful restore deep-copies saved road state and recreates only the transient
bus offscreen. Failed restore changes no live state. Rendering never advances a
second bus/traffic clock. Pause, Decorate and background suspension retain their
existing simulation gates.

## Finite departure and service completion

At the final straight leg of the existing 35-point departure, only physically
forward road cars constrain the departing car. Earlier legs, arrivals and ordinary
road followers keep cyclic following. A real forward blocker still stops the car;
speed 2.8, gap 4.5, merge arbitration and the existing endpoint remain unchanged.
The derived street-versus-maneuver predicate prevents an approaching car and the
exclusive departure from permanently blocking each other without weakening body,
lane, bus or merge clearance.

The PR243 Main/Model bridge is included once. Final matched meal delivery consumes
that guest's cooking phase on the next eligible positive live tick. Contact alone,
pause, Decorate, zero time and load do not promote it. Recipe, physical cooking,
abandonment, payload, job IDs, payment and subsequent phase clocks remain unchanged.

## Evidence and remaining gates

Historical exact-source finite/save checks, canonical atlas runs and PR158 CI
remain attached to their original commits. The retained images in
`docs/testing/history/parking-parties/` are synthetic historical checkpoints,
not natural current-head payment or visual acceptance. Rejected recordings stay
historical; this closeout does not create or encode new video.

The next focused checks must observe the new current-source import, party/save
contracts, Decorate transaction and delivery bridge. Fresh source-bound atlas
qualification must precede manifest adoption; the complete accepted main manifest
is retained until matching proof exists. No old 127-row manifest is transplanted.

The separately admitted natural observer must use actual Main at 1x in a generated
no-save profile. Initial fixture purchases use normal Decorate APIs; after setup it
must not reserve/admit members, force positions/routes/clocks/payment or extend the
approved cap. Track the first naturally dispatched party's immutable member/car
IDs through service, per-member payment, return, all-member boarding and physical
departure/retirement. Report cap/unreached states explicitly. One member paying
does not establish all members paid or that the whole party departed. Queue
admission, inspected pixels, user acceptance, publication, merge and release are
separate gates.
