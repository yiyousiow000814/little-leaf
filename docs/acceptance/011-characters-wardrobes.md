# 0.1.11 character and wardrobe acceptance

Extends the earlier [design contract](https://github.com/yiyousiow000814/little-leaf/pull/112) with complete species, identity, customization and attachment outcomes. Earlier [head study](https://github.com/yiyousiow000814/little-leaf/pull/100), [scale study](https://github.com/yiyousiow000814/little-leaf/pull/94) and [art contact standard](https://github.com/yiyousiow000814/little-leaf/pull/93) remain independent review references. Rejected body-stretch studies are not approved source. The 3D authoring workflow must preserve the original 2D isometric in-game appearance.

## Status and evidence rules

This is an acceptance/design contract only. It does not implement the requirements below, and unchecked boxes mean acceptance has not been established here. Existing candidate source remains in its original PR; this document does not duplicate or promote it. A source-bound implementation PR, exact-head tests and visual review are required before completion. Use generated disposable profiles only. No live saves, account credentials, security settings, merge, release, tag or deployment are included.

## 01 Character foundation and six species

- [ ] 01.01: Unified 3D character authoring and game-sprite import pipeline; preserve the original 2D isometric game style.
- [ ] 01.02: Support bear, rabbit, fox, cat, dog and red panda with species-correct silhouettes.
- [ ] 01.03: Head, torso and clothes face the same direction through movement, turns and task transitions.
- [ ] 01.04: Shoulders, sleeves, arms, legs and shoes join naturally without detached or floating parts.
- [ ] 01.05: Use one coherent character/furniture scale rather than stretching body parts independently.
- [ ] 01.06: Provide a coherent expression system with readable, natural faces.
- [ ] 01.07: Natural idle and role-specific small motions, with stable task contacts and pause behavior.
- [ ] 01.08: Rabbit ears have soft/asymmetric droop, pink inner ears and natural motion.
- [ ] 01.09: Individual natural fur palettes/patterns fit each species and remain stable across directions and the character lifecycle.

## 02 Staff identity and customization

- [ ] 02.01: Provide trousers for all four staff roles.
- [ ] 02.02: Redesign chef clothing; do not treat the earlier rejected outfit as approved.
- [ ] 02.03: Role-identifying accessories cannot be removed, but compatible variants and colors can be chosen.
- [ ] 02.04: Use a rotating white ring exclusive to staff, with consistent ground contact.
- [ ] 02.05: Support male/female appearance choices.
- [ ] 02.06: Allow clothing and color combinations without losing role identity.
- [ ] 02.07: Dedicated customization window with true preview, explicit confirm and full cancellation.

## 03 Random customer wardrobe

- [ ] 03.01: Generate genuinely modular outfits rather than choosing fixed prebuilt sets.
- [ ] 03.02: Keep each customer's appearance stable and restore it faithfully after save/load.
- [ ] 03.03: Combine upper/lower clothing including trousers/skirts and color choices.
- [ ] 03.04: Combine shoes and stockings/socks; show them cleanly from every direction.
- [ ] 03.05: Support compatible glasses, hats, ribbons and back bows; clips remain flat and hat/headband geometry avoids ear collisions.
- [ ] 03.06: Fit clothes and head accessories to every supported species and check clipping through idle, walking, seating and work poses.

## Acceptance matrix

Review all six species at useful normal and close zoom, each supported direction, idle/walk/seated/task transitions, accessories on/off where allowed, and the full preview-confirm-cancel cycle. A selected appearance must not reroll on turn, re-entry or restore. Natural fur identity and outfit identity need explicit persistence compatibility tests across every save consumer before a schema change is accepted. No migration/version is assigned by this document.
