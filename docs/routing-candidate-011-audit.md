# Eight-direction candidate: audit and compatibility boundary

Source: public main `b8b80eea57ac3cb141cb5c771b375207a284436a`.
Design reviewed: PR112 head `8114fc32845ba7c4f4b34a98c1ffc1a3640880fc`,
`rc-inspired-routing-011.md` and its 50-case QA plan. All open PR titles and
branches were inspected on 2026-10-09. No tracked AGENTS.md exists on this base.

## Consumers found before implementation

| Authority | Current consumers and constraints | Candidate boundary |
| --- | --- | --- |
| Guest geometry | `cafe_model.path_between`, `guest_access_for`, `reroute_guest`, `service_cell_for`; owned floor, furniture, chair egress and external approach | Explicit snapshot adapter only; old planners stay cardinal |
| Staff | `main._staff_route`, `_static_service_path`, `_staff_route_invalid`, `_animate_staff`; destination claims separate from transit | Same candidate planner/follower for synthetic staff; no task or service mutation |
| Checkout | `cafe_checkout.path`, `_route_to`, `depart`, placement reachability; separate front/back, tickets, payment token | Same candidate geometry; existing claim authority must approve endpoint |
| Layout | `cafe_furniture_motion.route_to/seat_route/layout_error`, `cafe_staff_relocation`; proposed-layout shadows, cardinal relocation | No default diagonal edit routes; proposed geometry must be frozen explicitly |
| Validation | model remaining-route and placement checks, wall reachability, `cafe_runtime_codec` mobility and staff/guest state validation | No relaxation of historical assertions |
| Cost consumers | model service-cell choice, checkout seated egress; main table/bin/service face selection; dishwashing and floor geometry compare `.size()` | Integration must switch these to route cost/length together; candidate returns both |
| Native persistence | `cafe_save_contract` v15, service v5; runtime and layout-motion codecs; save profiles and migration | Unchanged; candidate plans are transient objects and never inserted into runtime |
| Platform persistence | `cafe_web_save`, web/CG bridges, Firebase build contract and cloud pending/conflict/recovery | Unchanged; no capability/version assigned, journal or cloud writes |
| Reception/departures | PR112 references local `f70affce` and core/sink `7983d614`; these are absent from public remotes | Integration blocked on shared frozen source and owner API decision |

`edge_between` accepts cardinal neighbors only. The candidate must check all
four cardinal edges for a diagonal, then sweep the center segment against
wall rectangles expanded by body clearance. A blocked goal never becomes a
transit exception. Existing public/parking lanes, furniture docking and task
contacts remain separate from ordinary floor navigation.

## Stage delivered here

An original bounded A* and immutable snapshot adapter, plus a common transient
follower. Synthetic callers representing guest, staff and cashier use the same
rules. Endpoint permission is supplied by the existing authority as a callback;
there is no second claim ledger. Plans retain a task token and endpoint callback
and reject stale claims. People only reduce speed to a positive lower bound,
without side shifts or hard occupancy. Geometry changes validate remaining legs;
invalid plans replan only at a safe center, otherwise stop without snapping.

The module is explicitly imported by synthetic tests; no production caller is
changed. This is stage 2 of PR112, not completed gameplay integration. It cannot
create diagonal native/Web/CG saves. Old cardinal readers, point order, economy,
role ownership, service timing, reception and appearance are unchanged.

## Remaining gates

Obtain shared reception/departure baseline; adapt task endpoints and existing
claim tokens in the actual state machines; update all cost consumers; preserve
cardinal historical in-flight routes; coordinate save capability and reverse
rejection across native/Firebase/Web/CG; validate proposed edits and body sweeps;
run business regression, native pixels, browser storage and timed hardware QA.
No native visual, browser, FPS, migration, release or deployment claim is made.

Parent coordination attempted; the desktop API returned `thread not found`.
Heavy tests are deferred to avoid
competing with the parent's FPS task. No branch push or PR creation is performed
here; parent owns Draft PR coverage.
