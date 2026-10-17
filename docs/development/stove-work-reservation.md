# Stove work-space reservations

The 0.1.9 candidate treats a stove's working front as required service floor.
Decorate shows that square in the same red floor map used for other required
spaces, even when the stove is not selected. Selecting or previewing a stove
keeps its own rotated working square red.

The reservation protects a usable work space, not an invisible wall. Staff and
customers can still walk through it, and walkable rugs remain allowed. Multiple
stoves may share an open work square; the existing runtime staff reservations
still arbitrate who uses it. Neither the background colors nor the selected
marker creates collision geometry.

## Authoring rules

- New furniture, moves and rotations cannot block an existing stove's front or
  cut off its connection to staff-accessible floor
- A new or moved stove needs an owned, reachable, unblocked working front
- Wall placement, wall moves and doorway edits cannot newly close the stove's
  working edge or route
- Furniture hover, drag confirmation and immediate R rotation use the existing
  atomic edit plan; invalid attempts do not charge, move actors or save
- The floor map remains cached by committed geometry, independent of hover
  selection; no full placement scan is added to rendering

## Older layouts

The save format is unchanged. Existing blocked stoves load and save intact;
there is no automatic deletion, movement or rearrangement. Unrelated edits and
partial repairs stay possible. Clearing a wall and furniture can be done in
either order. An existing issue does not permit creating a new obstruction or
moving the stove to a different blocked work tile. Service pause and recovery
continue to handle old blocked layouts without adding bottom notifications.

## Verification

Full headless suite:

    python3 tests/run_integration_candidate.py --output /tmp/little-leaf-qa

Focused model, controller and native GL screenshots:

    python3 tests/building/run_stove_work_reservation.py --output /tmp/stove-work-qa --native

Both commands use disposable projects and generated profiles. When a fresh
asset import is unavailable, the focused runner can use --import-cache followed
by a source project whose asset inputs and .import metadata match byte-for-byte.
It copies only imported assets and marks clean import unverified. The normal
fresh-import CI/build remains required before publication.

## Chef pass allocation follow-up (0.1.11 candidate)

The user authorized repairing the reproduced held-meal wait cycle and choosing
the nearest reachable available pass. Main's service ledger continues to own
the dish, guest/token and reservation; this is not a new navigation system.
Assignment uses one cardinal distance search with the actual staff rule x>=1,
owned floor, furniture and walls. Both chef rear and waiter front must connect.
Equal route lengths use the lower counter ID. This is a local greedy choice,
not a globally optimal multi-worker schedule.

Valid reservations stay pinned. Geometry/content changes invalidate runtime-only
validation, and an unassigned search retries when the chef cell, geometry or
reserved-counter set changes. A lost pre-contact target may be reselected while
the same chef still owns the meal; only the incomplete placing action restarts.
Cooking/plating, guest/token, food and movement are never recreated or teleported.
After placing contact transfers custody to the counter, allocation must leave
that counter identity alone through the remaining handoff.

All valid chef work endpoints, including stove preparation/cooking, take priority
over idle/fallback standing choices regardless of roster order. If no standing
alternative exists, fallback does not claim such an endpoint as real work. Chef
slots prioritize an already started action, then a valid in-flight endpoint owner,
then accumulated blocked-work waiting time with roster order as a deterministic
tie. An owner retains its endpoint while approaching and through the action;
waiting time resets only on action completion. Completion releases ownership so
waiting chefs arbitrate the next action. The per-staff runtime claim binds
guest/token, action step, target and face; a changed binding or invalid face
releases it, and acquisition checks the actual staff route. Geometry changes
revalidate that route while preserving a still-valid owner; unrelated edits
do not preempt travel. Idle staff never own
these claims. This fixes the reviewed idle-before-active obstruction and the
approaching-chefs framewise preemption, rather than relying on both chefs
already standing at the shared cell. Other role order and
complementary sink lanes remain unchanged. Actor pass-through and static collision
stay unchanged. The cached search keys
are runtime fields on each staff dictionary, omitted from the existing explicit
save projection and removed with the job/staff. No all-counter search runs for
an unchanged valid reservation; no grid map is retained between assignments.

Relevant pillars are Gameplay, Living World and existing Game Feel contacts.
Art, audio, economy, UI structure and publishing are unaffected. Targeted
old-fail/new-pass tests and actual runtime evidence remain required; this record
does not establish gameplay acceptance, merge authority or deployment.

The combined PR331/PR335 candidate uses one frame-local union after the existing
navigation refresh: valid chef workfaces and the chosen order endpoint protect
both ordinary idle choices and blocked-work fallback. If no alternative exists,
remaining in place does not turn that protected cell into a fallback work claim.
Only chef slots retain the incumbent/travel/wait arbitration above; waiter and
cleaner ordering and sink front-claim snapshots are unchanged. Both existing
ownership gates share PR335's nonrecursive current-target classifier, so a
retained cook with no pass target keeps its plate and job without owning an idle
fallback. Endpoint collection remains one bounded staff scan, with no retained
union, new reservation owner or recursive destination call. PR335's per-staff
positive/negative order-route cache and both candidates' cleanup stay intact.
This composition affects Gameplay, Living World and existing service contacts;
rendering, audio, economy and persisted state format are unchanged. The actual
combined source needs its own runtime checks, same-scene evidence, independent
review, CI and user acceptance; separate-head passes cannot qualify it.


## Shared task, resource and contact policy (item 30 candidate)

The approved Gameplay/Living World change replaces the floor-only role-pair
exception rather than adding more exceptions. Independent non-equipment jobs
may use the same stance: different tables, independent litter, and legacy
visit-owned floor work follow the same rule. Actors still pass through each
other; this does not change static route collision or allow furniture/wall
penetration. This section supersedes the earlier cook/order-only idle priority.

`CafeWorkClaims` derives three facts from the existing service state: task
identity, contact resource and exclusive/shared workspace. It owns no new
ledger. Guest meal/order jobs remain serial. Finished-visit table cleanup,
floor litter and payment are separate task domains; one task still has one
owner. Dish and independent-mess identities remain separately exclusive.
Actual stove, beverage, counter, register, sink and real-bin contacts remain
equipment work, even if an actor's role or historical action label says floor
cleanup. Only synthetic equipment-free disposal shares the floor task stance.
Distinct table resources share stance, not the same table resource or payload.

Main uses the descriptor for assignment, selected destinations, current-frame
snapshots and physical contact. A productive endpoint requires the current
real target, its authored contact geometry and a reachable staff route.
Targetless, layout-held and blocked fallback jobs are not productive claims.
One selected geometry-valid endpoint per real task protects it from idle
standing. Anonymous extra cell claims are never silently waived.

Shared-stance work cannot take an already selected exclusive equipment
workspace, including an in-flight later roster owner. Existing chef
incumbency/travel/wait ordering and the sink's one-washer/one-front-dropper
lanes remain authoritative. Sink drop body clearance, queue capacity, FIFO,
dish custody and the .75/20-second clocks are unchanged. Value snapshots keep
an earlier worker's contact through its completion frame; release is visible
on the next frame, without an idle/fallback ghost claim.

All nine jobs use these categories: order and table phases of brew, meal/drink
delivery and cleanup are table resources; cook, beverage preparation/pickup,
pass pickup/placement and payment use equipment; wash and sink drop use the
existing sink lanes; floor and legacy cleanup floor stages use their actual
floor task. Actual equipment selection and held-payload reservations remain
with their existing owners, not this stance policy.

The shared identity check also rejects duplicate ordinary restored service
jobs after existing legacy migrations and structural validation. No new saved
fields or format are introduced: this successor depends on item 31 service6
exactly once. Its checkout debt, booking, early-cleanup and older-reader fence
remain unchanged. Original-save byte preservation remains mandatory.

Cost is bounded by the staff roster and existing contact candidates. The
existing positive/negative route-length cache is reused for all real work,
not duplicated: at most 324 owned-floor entries per staff, invalidated by
start/topology changes and cleared with job/layout/staff lifetime. Frame claims
and the idle-protection union are local arrays/dictionaries discarded each
frame. No actor grid, retained reservation system, new assets or rendering
changes are added. This is not a global optimal scheduler or an FPS claim.

`test_work_claim_policy` is registered in the existing focused runner. It
observes the original endpoint denial, both roster orders, sweep/local
disposal/mop, distinct-table and legacy-floor sharing, actual custody,
assignment uniqueness, completion snapshots, exclusive equipment ownership,
geometry/fallback controls and generated-save roundtrips/duplicate rejection.
The existing sink, chef, order, floor and role/service suites cover the retained
contracts. Rendered same-scene body/contact separation, actual user gameplay
acceptance, production import/export qualification, CI, merge and publication
remain separate gates. No visual offsets or logical positions are altered by
this candidate.


### Presentation successor: bounded shared-contact stances

This source candidate follows the shared-policy packet above. It changes only
existing rendered stance offsets and the explanation of a proven equipment
hold; logical cells, routing, ownership, service timing and service6 are not
changed. Main retains the geometry prepass result only for its current frame.
An actual conflicting exclusive owner, including its completion snapshot, may
produce “Waiting for the work space” instead of a false Decorate fault. Real
geometry failure, duplicate task ownership and unidentified claims are not
silently classified as expected waits.

The renderer consumes the common task/resource descriptor without requesting
routes. Independent contacts in one selected cell use a fixed 25-point search
and two coordinate passes, not a combinatorial solver or a reservation ledger.
Candidates reuse the existing swept body/furniture/wall checks, original cell
margin and .30 body radius. The authored head ellipse supplies a conservative
separation metric, not proof of all silhouette/arm/prop pixels. Feet still use
stance_offsets and its existing 1.5-unit/s transition. Actual world contacts,
short-arm lengths and floor stroke extrema remain unchanged; candidate floor
handles cannot exceed their previous center-stance lengths. An already-visible
completed worker may retain its sidestep only while leaving that current cell.
It owns no task and cannot delay the next assignment.

A single current-group cache is keyed by model identity/revision, binding,
contact and authored stance. It is replaced each update, retires when the
nearby contact group dissolves, and retains no model nodes or reservation
history. Single-worker, actual-equipment, checkout and complementary-sink
stances stay with their existing owners. This adds bounded per-group geometry
work on a binding/layout change and swept validation during display movement;
it is not an FPS, native-pixel or memory-soak qualification.

Local equipment-free disposal explicitly keeps the pan attached to the paw;
it does not aim at the previous missing-item/table-height fallback. Real-bin
rim contact retains its existing pose. No bin trip or transfer-time change is
introduced.

The same focused presentation test fails before and passes after for sweep,
local finish, distinct-table sharing and the one-frame sink warning, in both
roster orders. A separate lifecycle fixture observes restore/release, cache
bounds and fixed local-pan attachment. Both are in the existing focused runner.
A known constraint is explicit: authored table wiping leans .55 toward the
low tabletop, but the conservative full-tile placement-body test allows only
.20. This candidate does not waive that collision rule or change short-arm
reach to force a shared wiping arrangement. Such constrained presentation
falls back to the unchanged authored pose while valid service still proceeds.
The actual same-scene native pixels, including arrival/release and props, must
be reviewed before visual acceptance; this source packet is not universally
qualified shared-stance presentation.
