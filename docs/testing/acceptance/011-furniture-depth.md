# 0.1.11 furniture, occlusion and ground contact

Existing candidate references: [full-tile stove](https://github.com/yiyousiow000814/little-leaf/pull/85), [modular cabinets](https://github.com/yiyousiow000814/little-leaf/pull/91), [table flowers/head study](https://github.com/yiyousiow000814/little-leaf/pull/100), [direct pickup](https://github.com/yiyousiow000814/little-leaf/pull/104), and [scale/contact contract](https://github.com/yiyousiow000814/little-leaf/pull/93). These remain their source owners; this document collects the unclosed shared acceptance requirements.

## Status and evidence rules

This is an acceptance/design contract only. It does not implement the requirements below, and unchecked boxes mean acceptance has not been established here. Existing candidate source remains in its original PR; this document does not duplicate or promote it. A source-bound implementation PR, exact-head tests and visual review are required before completion. Use generated disposable profiles only. No live saves, account credentials, security settings, merge, release, tag or deployment are included.

## 04 Furniture details

- [ ] 04.01: Suitable furniture occupies the complete standard grid cell without silently changing logical footprints.
- [ ] 04.02: Counters are lower, floor-mounted and have no legs.
- [ ] 04.03: Stove/pot scale and chef hand/body contact work together through cooking and pickup.
- [ ] 04.04: Chairs have refined details, thin seat edges and no ground projection/shadow.
- [ ] 04.05: Refine tabletop flowers while preserving table and actor clearance.
- [ ] 04.06: Refine checkout display and button details while preserving cashier contact.
- [ ] 04.07: Refine the sink rim and occlusion during washing so hands/plates remain believable.

## 05 Shared occlusion and grounding

- [ ] 05.01: Use a coherent depth-ordering system for people and objects.
- [ ] 05.02: Layer bodies, chair backs and held objects correctly through transitions.
- [ ] 05.03: Align feet, floor markers and furniture ground contact consistently.

## Acceptance matrix

Use exact-source before/after native frames in all four furniture rotations, normal and useful close zoom, adjacent furniture and wall corners. Include standing/seated transitions, washing, checkout, cooking, chef yielding and actual waiter pickup. Sampled stills do not prove continuous motion. No QA-only pose may substitute for the production motion/contact path. Record footprint/pathing invariance and review integrated overlaps separately from individual candidate tests.
