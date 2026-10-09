# Little Leaf 0.1.11 — cute staff accessories and 3D character authoring

Original design freeze: 2026-10-09, 12:03 UTC. Import review cutoff: 2026-10-09, 12:13 UTC. The latest trousers, chef-outfit and expression requirements are recorded below; implementation and acceptance are pending. Later art revisions need a separately source-bound follow-up. Scope: the approved design direction and its current implementation boundaries. This is a local design handoff, not a release or visual-acceptance certificate.

## Approved direction

The user approved 3D character authoring on 2026-10-09 at 11:03 UTC. The intended result is the same friendly Little Leaf bear, with head, torso, clothing and limbs sharing one orientation. Blender is our editable authoring choice. It is not a claim about Restaurant City's original authoring software, and it does not authorize a whole-engine or world-renderer rewrite.

After the shoulder and shoe corrections, the user asked for more cuteness. Their clarification rejected the interpretation of simply making the body fuller. At 11:48 UTC they approved the proposed cute-element direction: Little Leaf pocket details, recognizable role accessories, and restrained personality through small expressions and natural motions.

At 12:10:33 UTC the user requested “加上裤子” in response to the four-role study. All four roles require trousers that follow their established uniform palette, with continuous knee/ankle, cuff and shoe connections. This is a requested addition, not full approval of the earlier four-role study. The art owner is implementing it separately; no trouser model, export, native import or visual acceptance is established by this document.

At 12:12:14 UTC the user said the chef clothes did not look right; that outfit remains unaccepted. The pending revision is a clearer warm-ivory double-breasted short coat, a smaller neckerchief/Leaf accent, defined fitted cuffs and darker sage trousers. The latest expression feedback calls for a subtle smile, blink, focused look and happy greeting. These are approved design targets only: a static model/render study does not establish animated expressions or native acceptance.

### Preserve

- The connected structural baseline: continuous torso–shoulder–upper-arm anatomy, a fitted sleeve following that volume, bent/tapered forearms and attached paws.
- Shaped shoes with ankle entry, heel, toe, thin sole and relaxed stance. Do not revert to oval discs on rods.
- Baseline proportions, friendly face, original palette family and soft stylized material treatment. No additional fullness changes.
- Shared 3D facing for body, head, clothing and attachments. Accessories belong to the model, not a camera-facing layer.
- Clear employee-versus-customer distinction. The existing slow white ground ring remains a separate ground-render component; it is not baked into sprite images.
- Existing role definitions. Cleaner is the existing dishes/floor-cleaning role; no new janitor gameplay job is introduced.

### Explicitly excluded

The body-fullness study at `25ab703c81fe8632016ad8fe33a1d06697ee22c8` is unapproved and is not the accessory-study base. Initial 3D pilot arm/foot quality and the earlier 2D arm-facing repair were not accepted as final. Their histories remain available without being promoted into the accepted structural baseline.

## Four-role accessory specification

| Existing role | Established palette | Readable shape cue | Little Leaf detail |
| --- | --- | --- | --- |
| Chef | Warm ivory/cream, sage accents and darker sage trousers | Soft toque, double-breasted short coat, small neckerchief and defined fitted cuffs; revision pending | Small sage leaf pocket |
| Waiter | Warm brown, cream apron | Apron straps and a compact order pad | Leaf pocket on the apron |
| Cleaner | Muted teal | Wrapped headband, overalls, tucked cloth | Teal leaf-shaped front pocket |
| Cashier | Mauve and ivory | Short visor, vest, bow and badge | Small leaf pocket mark |

Use silhouette/accessory plus color, never color alone. At ordinary play size, the main hat/headband/apron cue takes priority over tiny decoration. Pocket veins, buttons and badges may simplify with resolution. Preserve an unobstructed face and visible shoulder connection. Do not add a large floating prop that suggests an unconnected hand.

## Implementation and approval states

| Surface | State at this document freeze | Acceptance boundary |
| --- | --- | --- |
| 3D authoring route | User approved | Does not approve every rendered model |
| Connected shoulder and shaped feet | Implemented; structural direction accepted as the base for continued work | Final overall aesthetic remains open |
| Leaf pocket and role-personality concept | User approved | Exact accessory models are still review candidates |
| Four-role accessory study | Locally authored in Blender; eight front/rear model renders generated; visual cleanup/review in progress | Not yet frozen as an accepted asset; not a Godot screenshot |
| Four-role trousers | User requested at 12:10:33 UTC; implementation pending in the separate art worktree | Preserve uniform palettes and cuff/shoe continuity; model review, exports and native acceptance remain pending |
| Chef outfit revision | User rejected the earlier clothes; revised short coat, cuffs, neckerchief and darker trousers are pending | Earlier chef appearance remains unaccepted; model review and native evidence required |
| Subtle expressions and natural microanimation | Approved targets: subtle smile, blink, focus and happy greeting; motion plan below | Model study pending; actual animated expressions are not implemented, rigged or runtime-verified |
| Current accessory native import | Not run | Must be source-bound after model review and engine-slot coordination |
| Full production draw-loop integration | Pending | Must test actual drawing, occlusion, work poses and performance |
| Release / live publication | Not performed | No save or live-service changes |

## Post-cutoff addendum: modular customer wardrobes (12:14–12:15 UTC)

The user requested genuinely random, modular wardrobe combinations for male/female customer variants. This is future customer scope, separate from the staff study: do not substitute a small selection of fixed complete outfits. Mix compatible clothing (including skirts), colors, shoes, hats, head ribbons, large back bows, glasses and expressions. Compatibility restrictions should prevent clipping, intersecting accessories or invalid attachments, rather than arbitrarily reduce the wardrobe to predetermined sets.

Choose a coherent appearance once for each customer and keep it stable through walking, turning, sitting and other animation states. All body-facing attachment slots must rotate with the same connected model; a back bow must remain attached behind the body, not face the camera independently. Preserve clear silhouettes and foot/cuff connections. Define reusable, bounded cached variants rather than promising unconstrained per-frame generation or unmeasured performance.

Implementation, exact meshes/materials, random selection rules, caching limits, clipping tests and native/browser acceptance are all pending. Stable appearance across save/load requires a separately reviewed identity/seed or appearance representation and native/Firebase/Web/CrazyGames contract decision; this document assigns no field or version and does not write wardrobe data into existing saves. Four-direction staff renders cannot qualify an eight-direction customer wardrobe. Model review, all required facings/turns/sitting transitions, actual production rendering and per-target persistence remain separate gates.

This addendum records feedback through 12:15:05 UTC. It does not approve the earlier chef outfit, body-fullness study or staff study as finished, and later art handoffs need their own immutable source/evidence update.

## Natural expression and motion plan

These are bounded design targets, not claims of completed animation:

1. Common: a subtle readable smile, occasional blink and a tiny breathing/weight-settle movement with planted feet. Avoid synchronized looping across employees.
2. Chef: a brief attentive glance or small satisfied nod at the end of a completed cooking action; keep work timing authoritative.
3. Waiter: a restrained head tilt/acknowledgment while waiting, and a stable carrying pose. Do not swing a loaded tray or change collision space.
4. Cleaner: a short focused look toward the cleaning target, with wrist, forearm, upper arm and shoulder moving as a continuous chain.
5. Cashier: a small greeting nod while available, with hands resting coherently near the counter/task pose.

A neutral, readable face is the default. No exaggerated grin, constant bounce, oversized gesture or constant sparkle. Expressions and accessories must remain compatible with all required directions and work poses. Animation cannot substitute for pathfinding, task completion or occupancy logic.

## Immutable source authorities

- Structural implementation: `b025811e1fa62be6bc8948eb0d66e66d0f7192c9`.
- Structural evidence freeze: `1a91d0894d4110cc2c858f08247524bbb1e217ea`, tree `cef997a0292cec3e812e02f3cde5e624b075a510`.
- Supporting structural review artifacts are retained privately.
- Connected baseline Blender source SHA-256: `631720cc4bddbeef13d23fcd34e2aa445214781ae367a76c4e9044c4a10b047a`.
- Palette/outfit authority: staff identity `2ac186e282cb27f84d6458a1ab26d986104e6759`.
- The newer accessory study is a separate mutable candidate, not an immutable dependency of this document; its later commit and manifest must accompany any integration handoff.

Shoulder and foot model-review renders and a 48-view turntable are retained privately. Structural revision native qualification is pending; the old pilot's native capture cannot certify this newer source.

## Editable asset and render contract

Keep editable `.blend` files, source scripts, named role meshes/materials, transparent exports, a palette record, source/export hashes, actual-render logs and a review receipt. All role models begin from the same connected baseline. The authoring script must verify unchanged core body geometry and transforms before/after accessory generation.

The current study uses Blender 4.3.2, orthographic projection at 26.565 degrees elevation, flat/toon color bands, transparent background, no floor, cast shadow or ambient-occlusion clutter. It uses an 80×80 logical sprite cell exported at 640×640 (8× density), pivot (40,73), to provide padding for the chef hat. Padding must not be confused with body rescaling. The final engine export contract remains subject to native review.

Authorship/licensing: the bear, role shapes and leaf detail are original Little Leaf project work, derived from its own authorized sources. No Restaurant City code, meshes, textures or extracted art are included. Blender is an external authoring tool; its GPL license does not make the output models third-party game assets. Preserve the project's existing asset rights; no new external asset license is being granted by this document. Any future imported font, texture or mesh needs its own source and license entry before inclusion.

## Required gates before integration

1. Model review: consistent front/rear and all four intended directions at the same camera, scale and foot anchor; include ordinary 1× size alongside enlarged details. Inspect hat/pocket/vest surfaces for clipping and rear coverage.
2. Geometry check: core proportions unchanged; shoulders, elbows, wrists, knees, ankles and footwear remain connected and coherent. No disconnected cap or accessory hides an anatomical gap.
3. Native import: import exact hashed exports into a synthetic Godot fixture. Verify filtering, pivot, scale, alpha, facing and visual identity. Label genuine runtime captures separately from Blender renders.
4. Production draw loop: check carrying, cooking, cleaning and cashier poses; adjacent furniture and front/rear occlusion; seated transitions where relevant; employee ring grounded under feet and solids; no ring on customers.
5. Animation: test transition frames, shared rig facing, foot contact, held props and all four directions. Report static-only models honestly until these gates pass.
6. Performance: measure representative runtime if claiming smoothness. No measured-performance or production acceptance claim follows from an isolated render.
7. Source/release: record exact commit, tree, assets, hashes, licenses and test receipt. Keep implementation, visual review, native verification and release status separate. No player saves or live services may be used as fixtures.
