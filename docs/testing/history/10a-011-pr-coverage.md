> Historical coverage index, frozen before the all-version roadmap migration. This document preserves review provenance and original constraints, not current implementation/merge/release status. Read the [current roadmap](../../roadmap.md).

# 0.1.10a / 0.1.11 PR coverage index

## How to read this index

This records **12 groups and 76 deduplicated player-visible 0.1.11 outcomes**, plus four additional acceptance gates. It is a coverage index, not a completed-feature count. A PR link means there is a durable review/acceptance home. It does not mean the feature is implemented, tested, approved or released.

All outcome checkboxes remain open here because this index does not establish integrated exact-source acceptance. The 50 routing cases are tests, not 50 additional features. Species/palette/pattern variants and accessory refinements do not increase the total. Already released 0.1.10 tutorial/save-status work and separate 10a save/session/startup/audio work are excluded from 76.

## Review homes

- [#117](https://github.com/yiyousiow000814/little-leaf/pull/117): character/staff/customer acceptance, **documentation only**, 22 outcomes; extends [#112](https://github.com/yiyousiow000814/little-leaf/pull/112).
- [#118](https://github.com/yiyousiow000814/little-leaf/pull/118): furniture and shared depth/contact acceptance, **documentation only**, 10 outcomes; links existing source studies.
- [#119](https://github.com/yiyousiow000814/little-leaf/pull/119): land/reception/navigation acceptance, **documentation only**, 15 outcomes; extends [#112](https://github.com/yiyousiow000814/little-leaf/pull/112) and links [#103](https://github.com/yiyousiow000814/little-leaf/pull/103).
- [#120](https://github.com/yiyousiow000814/little-leaf/pull/120): starter-bin/street/interface acceptance, **documentation only**, 16 outcomes.
- [#103](https://github.com/yiyousiow000814/little-leaf/pull/103) and [#106](https://github.com/yiyousiow000814/little-leaf/pull/106): existing editor/feedback implementation candidates, 11 outcomes; separate exact-head acceptance still required.
- [#104](https://github.com/yiyousiow000814/little-leaf/pull/104): existing direct stove-pickup candidate, two outcomes.
- [#121](https://github.com/yiyousiow000814/little-leaf/pull/121): four additional cross-release gates, **documentation only**, outside the 76-item count.

No duplicate runtime source is introduced by these acceptance drafts. In-progress character/shoe, camera, FPS and hidden-progression work must be linked to frozen reviewed implementation PRs when available. A document-only PR cannot substitute for that implementation.

## 01. Character foundation and six species (9)

- [ ] **01.01** Unified 3D character authoring and game-sprite import pipeline; preserve the original 2D isometric game style. Review home: [#117](https://github.com/yiyousiow000814/little-leaf/pull/117). Existing reference: [#112](https://github.com/yiyousiow000814/little-leaf/pull/112).
- [ ] **01.02** Support bear, rabbit, fox, cat, dog and red panda with species-correct silhouettes. Review home: [#117](https://github.com/yiyousiow000814/little-leaf/pull/117).
- [ ] **01.03** Head, torso and clothes face the same direction through movement, turns and task transitions. Review home: [#117](https://github.com/yiyousiow000814/little-leaf/pull/117). Existing reference: [#100](https://github.com/yiyousiow000814/little-leaf/pull/100), [#112](https://github.com/yiyousiow000814/little-leaf/pull/112).
- [ ] **01.04** Shoulders, sleeves, arms, legs and shoes join naturally without detached or floating parts. Review home: [#117](https://github.com/yiyousiow000814/little-leaf/pull/117). Existing reference: [#112](https://github.com/yiyousiow000814/little-leaf/pull/112).
- [ ] **01.05** Use one coherent character/furniture scale rather than stretching body parts independently. Review home: [#117](https://github.com/yiyousiow000814/little-leaf/pull/117). Existing reference: [#93](https://github.com/yiyousiow000814/little-leaf/pull/93), [#94](https://github.com/yiyousiow000814/little-leaf/pull/94).
- [ ] **01.06** Provide a coherent expression system with readable, natural faces. Review home: [#117](https://github.com/yiyousiow000814/little-leaf/pull/117). Existing reference: [#112](https://github.com/yiyousiow000814/little-leaf/pull/112).
- [ ] **01.07** Natural idle and role-specific small motions, with stable task contacts and pause behavior. Review home: [#117](https://github.com/yiyousiow000814/little-leaf/pull/117). Existing reference: [#112](https://github.com/yiyousiow000814/little-leaf/pull/112).
- [ ] **01.08** Rabbit ears have soft/asymmetric droop, pink inner ears and natural motion. Review home: [#117](https://github.com/yiyousiow000814/little-leaf/pull/117).
- [ ] **01.09** Individual natural fur palettes/patterns fit each species and remain stable across directions and the character lifecycle. Review home: [#117](https://github.com/yiyousiow000814/little-leaf/pull/117).

## 02. Staff identity and customization (7)

- [ ] **02.01** Provide trousers for all four staff roles. Review home: [#117](https://github.com/yiyousiow000814/little-leaf/pull/117).
- [ ] **02.02** Redesign chef clothing; do not treat the earlier rejected outfit as approved. Review home: [#117](https://github.com/yiyousiow000814/little-leaf/pull/117).
- [ ] **02.03** Role-identifying accessories cannot be removed, but compatible variants and colors can be chosen. Review home: [#117](https://github.com/yiyousiow000814/little-leaf/pull/117).
- [ ] **02.04** Use a rotating white ring exclusive to staff, with consistent ground contact. Review home: [#117](https://github.com/yiyousiow000814/little-leaf/pull/117).
- [ ] **02.05** Support male/female appearance choices. Review home: [#117](https://github.com/yiyousiow000814/little-leaf/pull/117).
- [ ] **02.06** Allow clothing and color combinations without losing role identity. Review home: [#117](https://github.com/yiyousiow000814/little-leaf/pull/117).
- [ ] **02.07** Dedicated customization window with true preview, explicit confirm and full cancellation. Review home: [#117](https://github.com/yiyousiow000814/little-leaf/pull/117).

## 03. Random customer wardrobe (6)

- [ ] **03.01** Generate genuinely modular outfits rather than choosing fixed prebuilt sets. Review home: [#117](https://github.com/yiyousiow000814/little-leaf/pull/117).
- [ ] **03.02** Keep each customer's appearance stable and restore it faithfully after save/load. Review home: [#117](https://github.com/yiyousiow000814/little-leaf/pull/117).
- [ ] **03.03** Combine upper/lower clothing including trousers/skirts and color choices. Review home: [#117](https://github.com/yiyousiow000814/little-leaf/pull/117).
- [ ] **03.04** Combine shoes and stockings/socks; show them cleanly from every direction. Review home: [#117](https://github.com/yiyousiow000814/little-leaf/pull/117).
- [ ] **03.05** Support compatible glasses, hats, ribbons and back bows; clips remain flat and hat/headband geometry avoids ear collisions. Review home: [#117](https://github.com/yiyousiow000814/little-leaf/pull/117).
- [ ] **03.06** Fit clothes and head accessories to every supported species and check clipping through idle, walking, seating and work poses. Review home: [#117](https://github.com/yiyousiow000814/little-leaf/pull/117).

## 04. Furniture details (7)

- [ ] **04.01** Suitable furniture occupies the complete standard grid cell without silently changing logical footprints. Review home: [#118](https://github.com/yiyousiow000814/little-leaf/pull/118). Existing reference: [#91](https://github.com/yiyousiow000814/little-leaf/pull/91).
- [ ] **04.02** Counters are lower, floor-mounted and have no legs. Review home: [#118](https://github.com/yiyousiow000814/little-leaf/pull/118). Existing reference: [#91](https://github.com/yiyousiow000814/little-leaf/pull/91).
- [ ] **04.03** Stove/pot scale and chef hand/body contact work together through cooking and pickup. Review home: [#118](https://github.com/yiyousiow000814/little-leaf/pull/118). Existing reference: [#85](https://github.com/yiyousiow000814/little-leaf/pull/85), [#104](https://github.com/yiyousiow000814/little-leaf/pull/104).
- [ ] **04.04** Chairs have refined details, thin seat edges and no ground projection/shadow. Review home: [#118](https://github.com/yiyousiow000814/little-leaf/pull/118).
- [ ] **04.05** Refine tabletop flowers while preserving table and actor clearance. Review home: [#118](https://github.com/yiyousiow000814/little-leaf/pull/118). Existing reference: [#100](https://github.com/yiyousiow000814/little-leaf/pull/100).
- [ ] **04.06** Refine checkout display and button details while preserving cashier contact. Review home: [#118](https://github.com/yiyousiow000814/little-leaf/pull/118).
- [ ] **04.07** Refine the sink rim and occlusion during washing so hands/plates remain believable. Review home: [#118](https://github.com/yiyousiow000814/little-leaf/pull/118).

## 05. Shared occlusion and grounding (3)

- [ ] **05.01** Use a coherent depth-ordering system for people and objects. Review home: [#118](https://github.com/yiyousiow000814/little-leaf/pull/118). Existing reference: [#93](https://github.com/yiyousiow000814/little-leaf/pull/93).
- [ ] **05.02** Layer bodies, chair backs and held objects correctly through transitions. Review home: [#118](https://github.com/yiyousiow000814/little-leaf/pull/118). Existing reference: [#93](https://github.com/yiyousiow000814/little-leaf/pull/93).
- [ ] **05.03** Align feet, floor markers and furniture ground contact consistently. Review home: [#118](https://github.com/yiyousiow000814/little-leaf/pull/118). Existing reference: [#93](https://github.com/yiyousiow000814/little-leaf/pull/93).

## 06. Editor operation and feedback (11)

- [ ] **06.01** Clear the original red placement cell while moving an item. Review home: [#103](https://github.com/yiyousiow000814/little-leaf/pull/103).
- [ ] **06.02** Make selected objects, particularly doors, visually clear. Review home: [#103](https://github.com/yiyousiow000814/little-leaf/pull/103).
- [ ] **06.03** Select scene objects across shop categories, including a wall while browsing Tables. Review home: [#103](https://github.com/yiyousiow000814/little-leaf/pull/103).
- [ ] **06.04** Show true floor colors without red/cyan preview tint. Review home: [#103](https://github.com/yiyousiow000814/little-leaf/pull/103).
- [ ] **06.05** Temporarily hide scene objects to inspect the floor. Review home: [#103](https://github.com/yiyousiow000814/little-leaf/pull/103).
- [ ] **06.06** Drag-paint floors in atomic batches. Review home: [#103](https://github.com/yiyousiow000814/little-leaf/pull/103).
- [ ] **06.07** Drag-paint walls in atomic batches. Review home: [#103](https://github.com/yiyousiow000814/little-leaf/pull/103).
- [ ] **06.08** Show batch quantity/price clearly with centered layout. Review home: [#106](https://github.com/yiyousiow000814/little-leaf/pull/106).
- [ ] **06.09** Keep furniture available/unavailable colors consistent across floor materials. Review home: [#106](https://github.com/yiyousiow000814/little-leaf/pull/106).
- [ ] **06.10** Use one natural continuous fine outline for floor selection. Review home: [#106](https://github.com/yiyousiow000814/little-leaf/pull/106).
- [ ] **06.11** Remove duplicate or unhelpful tooltips. Review home: [#103](https://github.com/yiyousiow000814/little-leaf/pull/103).

## 07. Doors, windows, walls and land (5)

- [ ] **07.01** Original and newly purchased doors/windows/walls support consistent buy, sell and move actions with correct ownership/payment provenance. Review home: [#119](https://github.com/yiyousiow000814/little-leaf/pull/119). Existing reference: [#103](https://github.com/yiyousiow000814/little-leaf/pull/103).
- [ ] **07.02** Doors have consistent one-grid-cell width and visual size. Existing 0.76-width historical doors are not already normalized by PR #103; compatibility and visual migration remain explicit gates. Review home: [#119](https://github.com/yiyousiow000814/little-leaf/pull/119). Existing reference: [#103](https://github.com/yiyousiow000814/little-leaf/pull/103).
- [ ] **07.03** Customers and staff enter/exit through actual doors or missing-wall openings. Review home: [#119](https://github.com/yiyousiow000814/little-leaf/pull/119).
- [ ] **07.04** Never route through unpurchased land. Review home: [#119](https://github.com/yiyousiow000814/little-leaf/pull/119).
- [ ] **07.05** Make door movement and the parking/land purchase entry point easier to discover. Review home: [#119](https://github.com/yiyousiow000814/little-leaf/pull/119).

## 08. Reception and waiting (5)

- [ ] **08.01** Customers enter the restaurant first to look for a dining seat. Review home: [#119](https://github.com/yiyousiow000814/little-leaf/pull/119). Existing reference: [#112](https://github.com/yiyousiow000814/little-leaf/pull/112).
- [ ] **08.02** When no dining place is available, customers wait near the entrance. Review home: [#119](https://github.com/yiyousiow000814/little-leaf/pull/119). Existing reference: [#112](https://github.com/yiyousiow000814/little-leaf/pull/112).
- [ ] **08.03** Unpaired chairs may serve as waiting chairs. Review home: [#119](https://github.com/yiyousiow000814/little-leaf/pull/119). Existing reference: [#112](https://github.com/yiyousiow000814/little-leaf/pull/112).
- [ ] **08.04** Customers may sit at dirty tables and wait for cleaning without receiving invalid service. Review home: [#119](https://github.com/yiyousiow000814/little-leaf/pull/119). Existing reference: [#112](https://github.com/yiyousiow000814/little-leaf/pull/112).
- [ ] **08.05** Handle vacancy refill, failure to enter and physical clearance after departure without stranded claims. Review home: [#119](https://github.com/yiyousiow000814/little-leaf/pull/119). Existing reference: [#112](https://github.com/yiyousiow000814/little-leaf/pull/112).

## 09. Eight-direction navigation (5)

- [ ] **09.01** Use consistent eight-direction routing for customers, staff and cashier flows. Review home: [#119](https://github.com/yiyousiow000814/little-leaf/pull/119). Existing reference: [#112](https://github.com/yiyousiow000814/little-leaf/pull/112).
- [ ] **09.02** Disallow diagonal corner cutting through walls, furniture or door frames. Review home: [#119](https://github.com/yiyousiow000814/little-leaf/pull/119). Existing reference: [#112](https://github.com/yiyousiow000814/little-leaf/pull/112).
- [ ] **09.03** Replan correctly after layout changes without stale reservations. Review home: [#119](https://github.com/yiyousiow000814/little-leaf/pull/119). Existing reference: [#112](https://github.com/yiyousiow000814/little-leaf/pull/112).
- [ ] **09.04** Use bounded soft person avoidance rather than hard mutual blocking. Review home: [#119](https://github.com/yiyousiow000814/little-leaf/pull/119). Existing reference: [#112](https://github.com/yiyousiow000814/little-leaf/pull/112).
- [ ] **09.05** Resolve chair/equipment task endpoints and seat ownership correctly. Review home: [#119](https://github.com/yiyousiow000814/little-leaf/pull/119). Existing reference: [#112](https://github.com/yiyousiow000814/little-leaf/pull/112).

## 10. Service and starter inventory (3)

- [ ] **10.01** Remove the new service flow's dependency on service counters while preserving existing ownership. Review home: [#104](https://github.com/yiyousiow000814/little-leaf/pull/104).
- [ ] **10.02** Chef finishes at the stove, yields space, and the waiter physically picks up the plate. Review home: [#104](https://github.com/yiyousiow000814/little-leaf/pull/104).
- [ ] **10.03** Do not give an unnecessary trash bin in a fresh start, but retain the item for optional shop purchase; preserve already-owned items and saved value. Review home: [#120](https://github.com/yiyousiow000814/little-leaf/pull/120).

## 11. Outdoors and traffic (7)

- [ ] **11.01** Hide buses and vehicles while in Decorate mode; restore correct live visibility on exit. Review home: [#120](https://github.com/yiyousiow000814/little-leaf/pull/120). Existing reference: [#103](https://github.com/yiyousiow000814/little-leaf/pull/103).
- [ ] **11.02** Buses arrive and depart in distinct trips. Review home: [#120](https://github.com/yiyousiow000814/little-leaf/pull/120).
- [ ] **11.03** Bus direction matches its lane. Review home: [#120](https://github.com/yiyousiow000814/little-leaf/pull/120).
- [ ] **11.04** Fix the fine white seam at the bus platform. Review home: [#120](https://github.com/yiyousiow000814/little-leaf/pull/120).
- [ ] **11.05** Refine bus-stop benches. Review home: [#120](https://github.com/yiyousiow000814/little-leaf/pull/120).
- [ ] **11.06** Refine bus-stop sign artwork. Review home: [#120](https://github.com/yiyousiow000814/little-leaf/pull/120).
- [ ] **11.07** Connect both road curbs and corridor grass naturally. Review home: [#120](https://github.com/yiyousiow000814/little-leaf/pull/120).

## 12. Menus and interface (8)

- [ ] **12.01** Settings orders Inbox, Updates and Help in that sequence. Review home: [#120](https://github.com/yiyousiow000814/little-leaf/pull/120).
- [ ] **12.02** Move Log into Help. Review home: [#120](https://github.com/yiyousiow000814/little-leaf/pull/120).
- [ ] **12.03** Use an X inside the panel's upper-right corner for close. Review home: [#120](https://github.com/yiyousiow000814/little-leaf/pull/120).
- [ ] **12.04** Center the Sign in panel. Review home: [#120](https://github.com/yiyousiow000814/little-leaf/pull/120).
- [ ] **12.05** Keep every label/text inside its panel at supported viewport sizes. Review home: [#120](https://github.com/yiyousiow000814/little-leaf/pull/120).
- [ ] **12.06** Make blurry text clear without changing its meaning. Review home: [#120](https://github.com/yiyousiow000814/little-leaf/pull/120). Existing reference: [#99](https://github.com/yiyousiow000814/little-leaf/pull/99).
- [ ] **12.07** Rearrange the top bar after removing speed controls. Review home: [#120](https://github.com/yiyousiow000814/little-leaf/pull/120).
- [ ] **12.08** Show shop imagery with price below and useful, nonduplicated tooltips. Review home: [#120](https://github.com/yiyousiow000814/little-leaf/pull/120). Existing reference: [#106](https://github.com/yiyousiow000814/little-leaf/pull/106), [#99](https://github.com/yiyousiow000814/little-leaf/pull/99).

## Four additional gates, outside the feature count

All four are captured in [#121](https://github.com/yiyousiow000814/little-leaf/pull/121) and remain pending:
- Google sign-in in the actual itch.io context; local and cloud/hosted origins are distinct.
- Progress while a page is hidden, excluding closed-page catch-up, while preserving ownership.
- Actual 60/120 FPS verification with device/display/source-bound evidence.
- Square 64 × 64 camera overview, useful minimum zoom and correct pan bounds.

## Separate 10a candidates and diagnostics

- [#101](https://github.com/yiyousiow000814/little-leaf/pull/101) / [#113](https://github.com/yiyousiow000814/little-leaf/pull/113): save/session/device handoff and combined startup candidate.
- [#114](https://github.com/yiyousiow000814/little-leaf/pull/114): audio QA **paused; tracking only**. This index does not resume or accept it.
- [#115](https://github.com/yiyousiow000814/little-leaf/pull/115): legacy pending-save migration QA.
- [#116](https://github.com/yiyousiow000814/little-leaf/pull/116): bounded request-renew race diagnostic.
- [#99](https://github.com/yiyousiow000814/little-leaf/pull/99): catalog OCR QA infrastructure; a test repair, not proof that all UI outcomes pass.
- Earlier rejected or superseded studies remain historical evidence, not an integration dependency. In particular, rejected body-stretch/HUD-import/startup candidates must not be promoted by their existence in open PRs.

## Integration and release gate

Preserve released source and recoverable evidence. All save consumers must remain compatible. Require exact-source integrated visual, performance and regression evidence after composing candidates; separate branch passes do not certify the combination. Do not merge all drafts as a bundle. Source/dependency review, approval and release authorization remain separate. No merge, release, tag, deployment, security change or live-player-save operation is performed by this documentation work.

## Inventory verification

- 12 group counts: 9 + 7 + 6 + 7 + 3 + 11 + 5 + 5 + 5 + 3 + 7 + 8 = 76.
- Every outcome has exactly one primary review home; additional links show relevant existing candidates/contracts.
- New acceptance files are documentation-only and make no implementation or test-pass claim.
