# Little Leaf Art Bible

**DRAFT — framework for user review, not final visual standards.** This is the
single visual-standard document. It preserves existing user direction while
proposing a production and review process. The Bus Stop is the single pilot;
its outcome must refine this Bible and the two skills before the user confirms
the system and pilot. No new Golden Reference is approved here.

Source audit: main `824a1aaee50e4e0a783054e400a8c46855cd3e9d`,
2026-10-11 UTC. The [roadmap](../roadmap.md#current-state) owns work allocation,
priorities and delivery status. The queue owns the root [AGENTS](../../AGENTS.md)
entrypoint. The [production skill](../../.agents/skills/game-art-production/SKILL.md)
and [review skill](../../.agents/skills/game-art-review/SKILL.md) route work here;
they do not maintain another style guide.

## Authority and existing contracts

Keep the original 2D isometric identity, palette, camera presentation and
gameplay contacts. A reference offers only its recorded approval scope; it does
not authorize copying another game's assets, changing footprints or redrawing
unrelated objects. Existing character/wardrobe work remains paused under its
own Blender/editable-source direction. This framework does not mandate Blender
for static props or reopen that lane.

Reuse these maintained contracts rather than restating their implementation:

- [Assets, licenses and provenance](README.md): permissions and existing notices.
- [Character source contract](../design/cute-staff-accessories-011.md): the
  separate character pipeline and its current roadmap gate.
- [Rendering and performance](../testing/rendering-performance.md): retained
  resources, pixel correctness and completed-frame measurement.
- [Memory regression](../testing/memory-regression.md): lifecycle evidence when
  the change affects allocations, caches or teardown.
- [Development](../development/README.md) and [release](../release/README.md):
  Godot **4.6.3**, GL Compatibility, matching templates, import/source/atlas
  qualification and publication gates. Existing guards are not weakened here.

Historical studies under this directory retain their dates and approval limits.
Where they conflict with newer explicit user direction, record the discrepancy
and obtain the scoped evidence; do not treat an old document as new approval.

The renderer owner is preparing `docs/development/depth-occlusion.md`, the
World Depth & Occlusion Contract. Its architecture is **Pending validation**;
add a navigable link only after the actual file and source have been verified.
It will own anchors/world projection, footprint versus occlusion region,
deterministic depth and part order, Play/Decorate/Preview agreement and cache
consistency. Initial actor/tree continuous paths and Decorate table/chair drag
cases in four directions precede rollout. Do not invent blanket YSort rules,
magic offsets or a renderer rewrite here. Art approval cannot excuse depth
regressions. Any diagnostic anchor/order overlay stays developer-only.

## Two different visual gates

| Change | Required comparison | Reference decision |
| --- | --- | --- |
| Behavior-preserving performance optimization | Pixel Parity against the retained, source-bound control, including geometry, color/alpha, detail, timing, painter order and first frames after movement/zoom. Follow the existing exact-RGBA atlas and runtime comparison contracts. | Investigate differences; do not refresh expected pixels to make an optimization pass. Fix or withdraw a rendering regression. |
| Intentional art upgrade | Declare the intended visual difference, then inspect actual same-scene, same-scale Before/After and representative performance evidence. Retain unaffected behavior and import/atlas integrity checks. | Pixel difference is expected only within the declared scope. User approval is required before updating a Golden Reference; a matching atlas or successful test cannot provide it. |

A technically qualified atlas records which source produced pixels. A Golden
Reference records which visible result the user accepted. Neither substitutes
for the other. Documentation, reviewer recommendation, user approval, merge and
release are separate facts.

## Reference and evidence registry

**Approved** means only the explicitly listed user-approved aspect.
**Rejected** means preserve the example and rejection; do not promote it.
**Pending** means an unresolved decision or missing evidence. **Uninspected**
describes inspection coverage independently of those decisions.

The four originals below were visually inspected for this documentation audit.
Their PNG sizes and hashes were read from the actual files. Library IDs identify
the retained originals; they are not public download URLs. Request the original
by ID and verify its hash if unavailable. Do not substitute a similar screenshot.
No images, player profiles or private operational paths are copied into this PR.

| ID / decision | Original and identity | What it establishes / limits |
| --- | --- | --- |
| R1 — **Rejected** | Actual empty Bus Stop capture, `LittleLeaf-PR162-45f7cd3-bold-text.png`; Library `libfile_ca38bec963d48191a92da64075173f54`; 1654×951. Source `45f7cd3b57ec2c93c2105b00747819c8540ec2f2`, tree `7f44bcade0b572ee75026f5f3cdc6bb0164d3b7e`; [PR162](https://github.com/yiyousiow000814/little-leaf/pull/162). | User rejected this procedural shelter/road-lettering result. Actual frame shows the empty stop in the world scene. Earlier geometry and text-difference checks do not reverse rejection. Retain as a failure example, never an approved baseline or Golden Reference. |
| R2 — **Approved: shelter style only** | User-circled shelter reference, `image(20261011-055942).png`; Library `libfile_e2c94668c8f88191a819abc7445e3443`; 1207×723. | Circled cream canopy, supports/glazing and wooden bench provide the shelter direction. This enlarged reference is not an integrated candidate, a scale contract, or permission to copy its yellow road markings/background. No game-source identity or final Golden approval is established. |
| R3 — **Approved: white road/bay direction; cadence Pending** | Annotated road reference, `image(20261011-054901).png`; Library `libfile_fb67eae619b88191b3f0f08d4b94d10a`; 1309×805. | White drawn road/bay strokes communicate placement direction. Their rough, varying gaps are not a measured dash-ratio specification. Preserve the lettering center opposite the shelter; do not slide it sideways simply to expose it beneath a bus. Exact spacing remains a pilot decision. |
| R4 — **Approved: bounded Settings layout only** | Actual `settings-390x844.png`; Library `libfile_eb60624c73948191956a2469911bbc74`; 390×844. Source `cc8d64bbc7333f1e882e00b30472aec6ff329d6d`, runtime-equivalent published `1f7c331905b4ce4f743512416894a7553f1dc536`; [PR135](https://github.com/yiyousiow000814/little-leaf/pull/135). | Recorded user acceptance covers this Settings arrangement, entries and X. The inspected wood/cream panel is a bounded UI example, not approval of Help/Updates, later fonts, all UI or world art. |
| R5 — **Pending** | New software-authored Bus Stop pilot; no candidate identity or approved capture yet. | Shelter/bench are proposed first Golden References only after the pilot refines this framework and the user approves both. |

| Original | SHA256 |
| --- | --- |
| R1 | `a3e895b8b52f32a9b4202fab73a6bebd33637636cc0929a219a99a67ac6924df` |
| R2 | `e7d4abc730d44250f8e3df9d3888b732f605245f2095542eaed36a9e2ecb1da8` |
| R3 | `9cfbf71b5f471e673710f38fc8b9ea7c313c365f2649cdcf121b94bb0948944a` |
| R4 | `41f4d2660e274df80b091f585552da4d0c87612d49963846a2141afece6fba5d` |

R1–R3 differ in source, framing, scale and scene state. They are **not paired
Before/After**. R2/R3 are direction references, not new game captures. R1 may be
a labeled rejected comparison, but the pilot still needs a newly pinned real
control/candidate pair. No collection of these images is a final Golden set.

## World units and normal-scale calibration

At the audited main source, [illustrated_cafe.gd](../../game/scripts/illustrated_cafe.gd)
uses base `tile = Vector2(39,19.5)`. One logical ground tile is a **78×39**
diamond, with projected axes **(39,19.5)** and **(-39,19.5)**. Before current
origin/scale, `(x,z)` maps to `((x-z)*39,(x+z)*19.5)`; height projects upward
separately. These are existing renderer facts, not proposed aesthetic tolerances
or an inferred physical camera angle. Current UI scale, zoom and wall-detail
projection still apply.

For a new asset, display a labeled unit grid in the authoring/review artifact,
mark its logical footprint, pivot, ground contacts and layer anchors, then
compare them with the actual game at recorded normal play zoom and viewport.
Show the grid calibration and a clean view. Use close-ups only to explain a
finding after the normal-scale view. Do not change camera, picking, collision
or world dimensions to make the picture fit.

Existing [ground source](../../game/scripts/illustrated_ground.gd) samples are
warm oak `#edd5ab`, cream tile `#ece8d4`, sage tile `#cbd7ba`, bare floor
`#cbbfa8`, and pavement `#dfe0c8`/`#d7dcc2`; illustration ink is `#6d7859`.
These identify current materials, not a universal new palette. Any new palette,
stroke width, ratio, detail-density limit or other numeric aesthetic tolerance
is a **proposal requiring user approval** after actual normal-scale inspection.

## Draft visual review criteria

| Aspect | Inspect in the actual scene |
| --- | --- |
| Structure and silhouette | Roof/support joins, leg/seat construction, openings and negative spaces remain readable. Details must not disguise a weak primary shape. |
| Proportion and contact | Compare footprint, height and neighboring objects on the unit grid. Feet/posts meet their intended support; seat, hand and service contacts remain aligned. |
| Palette and material | Preserve the muted original identity and coherent top/side planes. Wood, glass, metal and fabric remain distinguishable. Do not flatten useful material shading or infer universal colors from one reference. |
| Detail and typography | Inspect edges, plank/trim detail, counters and visible glyph ink at normal scale. Center signs/UI content in the painted inset. Road type lies on the road plane and remains legible without the bus present. |
| Depth and occlusion | Check empty/occupied states and transitions, world depth plus local part ordering/masks, and relevant rotations. A parked bus naturally hiding road type differs from type that is unreadable in an empty scene. |
| UI and motion | Preserve hierarchy, optical alignment and relevant responsive states; inspect first frames after pan/zoom and neighboring animation. The Settings example does not approve other layouts. |

Retain the existing no-chair-ground-shadow/no-duplicate-seated-oval direction
while preserving material-plane shading. A **source discrepancy remains**:
`illustrated_cafe.gd::_chair` still contains a broad ellipse and four contact
ellipses, and the [historical chair note](history/chair-ground-contact.md)
describes them. Actual current basic-chair/atlas pixels across empty/occupied
states need a scoped audit. Their presence is not new approval; this framework
does not silently remove them or claim the pixel audit completed.

## Initial six-category inventory

This is a source/reference inventory, not an all-game visual pass. Entry points
are examples to follow into actual assets and atlas regions, not a complete
asset count. Retain existing scoped receipts without promoting a whole category.

| Category | Verified source entry points | Coverage and next evidence |
| --- | --- | --- |
| Outdoor | [exterior](../../game/scripts/exterior_environment.gd), [stop pedestrians](../../game/scripts/bus_stop_pedestrians.gd) | R1 rejected; R2/R3 direction inspected. Other exterior art **Uninspected** for this audit. Single Bus Stop pilot needs editable/export and actual scene evidence. |
| Building | [wall painter](../../game/scripts/illustrated_walls.gd), [openings](../../game/scripts/cafe_wall_openings.gd) | **Uninspected** at asset level. Inspect shell/door/window scale, joins, alpha and people crossing the relevant boundaries. |
| Furniture | [illustration/chair](../../game/scripts/illustrated_cafe.gd), [dining styles](../../game/scripts/dining_style_art.gd), [atlas painter](../../game/scripts/furniture_atlas_painter.gd) | **Uninspected** at asset level; basic-chair source discrepancy above is Pending pixel audit. Include empty/occupied contact and rotations; do not start an unsolicited fix. |
| Equipment | [furniture/kitchen](../../game/scripts/illustrated_furniture.gd), [checkout](../../game/scripts/cafe_checkout_art.gd), [sink](../../game/scripts/cafe_sink_wash_art.gd) | **Uninspected** here. Review real service phases, hand/plate contact and rim/local occlusion using the owning candidate. |
| Characters/animals | [directional art](../../game/scripts/directional_character_art.gd), [heads](../../game/scripts/character_head_painter.gd) | **Uninspected** for a new system audit; character/wardrobe authoring and activation remain paused. Preserve the separate existing Blender direction. |
| UI | [compact UI](../../game/scripts/cafe_compact_ui.gd), [HUD](../../game/scripts/cafe_hud.gd), [asset provenance](../../game/assets/ui/wood_hud/PROVENANCE.json) | R4 has bounded approval. Other screens/fonts/viewport combinations are **Uninspected**, not implicitly accepted. |

When an asset is actually audited, attach its source/tree, reference IDs,
editable/export/import identities, actual image/scene/scale, inspected states,
specific finding, reviewer and user decisions, and missing evidence. Prioritize
demonstrated defects and scene readability with the roadmap owner; estimates of
effort/runtime cost are not measurements or assignments to redraw all categories.

## Tool choice and editable production

| Route | Evidence and boundary at this draft |
| --- | --- |
| Inkscape for static props | Preferred proposed route for the Bus Stop. The bus owner's bounded installation/GUI audit has not proved editable save, reopen or transparent export. Qualify the actual executable/version and supported GUI before claiming readiness. No installation is authorized by this document. |
| Browser vector editor | Bus phase-one report records real Method Draw GUI creation/editing and pixel inspection; save/reopen and transparent PNG attempts yielded no retrievable files, and the exact app version is unknown. The graphical production pipeline is not operationally proven. This is partial capability evidence, not a production asset. |
| Figma | Account research reports View/Starter, not proven agent-write access. The [official write-to-canvas documentation](https://developers.figma.com/docs/figma-mcp-server/write-to-canvas/) checked 2026-10-11 requires a Full seat and appropriate edit permission. This does not authorize an upgrade, promise production access, or equate UI capture with the requested authoring proof. Recheck exact capabilities if this route is later selected. |
| Blender | Preserve the separate paused character lane. Do not impose it on all six categories or reopen characters to demonstrate this system. |
| Existing painters / other suitable art software | Keep existing editable GDScript and simple procedural tiles/markings where appropriate. Other user-approved software can be qualified for its asset type. The Bus Stop request specifically requires genuine drawing-software authoring; more generated polygon/SVG code does not demonstrate that workflow. |

For new or changed visual assets or an authoring/export toolchain change,
prove the selected workflow with a small disposable GUI-authored sample: save
its native editable document, close/reopen it, edit a named layer/path/text
element, and export the intended transparent output. Inspect the saved source,
alpha edges, colors, bounds and dimensions, then a normal-scale Godot import.
Record tool/version and source/export hashes. A screenshot, installed executable,
generated SVG string or advertised export button is insufficient proof.

For code-only performance optimization with unchanged artwork and authoring/
export toolchain, preserve the existing editable sources and calibration;
prove Pixel Parity under the existing contracts. No new disposable GUI asset
or grid-authoring exercise is required for that path.

Retain useful layers, editable typography or licensed outlines, pivots and the
reproducible export settings. Follow existing notices/import/atlas contracts;
do not convert a reference image into an unlicensed flattened game asset.

## Bus Stop pilot and refinement

Use the existing [PR162](https://github.com/yiyousiow000814/little-leaf/pull/162)
owner and current roadmap authorization. The phase-one inventory is pinned to
45f7cd3, not automatically current main: its [exterior source](https://github.com/yiyousiow000814/little-leaf/blob/45f7cd3b57ec2c93c2105b00747819c8540ec2f2/game/scripts/exterior_environment.gd)
splits `_draw_shelter_back` and `_draw_shelter_front` around under-roof people.
Reconfirm the target source before integration. Preserve **shelter back → people
→ shelter front**, the separate sign/bench elements, matching pivots and existing
obstacle/contact anchors. A single flattened shelter PNG is not a substitute for
this depth contract. Art changes alone do not authorize traffic, routes, saves
or collision changes.

The proposed sequence is tool proof and unit-grid calibration; editable shelter,
wooden bench, separate sign and clean road type; design review; retained-source
export and minimal integration; actual empty/occupied/parked and transition
review; then representative performance evidence. Keep both the unapproved
candidate and the existing control identified. Respect the pilot owner's phase
authorization; publishing this framework does not start runtime work.

After the pilot, revise this Bible and the skills with demonstrated lessons and
unresolved choices. Present the system and pilot to the user. Only explicit
approval of both permits a Golden record, containing the approved Bible revision,
pilot commit/tree, editable/export/import/capture hashes, normal scale and state,
user decision, performance surface and known limits. Preserve rejected records;
approval of one asset is not a mass-migration instruction.

## Review evidence and decision

Retain actual same-scene **Before/After at normal play scale**, matched camera,
viewport, zoom, fixture and animation phase; include relevant first-frame,
occupied and occlusion states. Inspect the real files before writing a visual
conclusion. Close-ups and concepts supplement these views, never replace them.

For an art/rendering change, record representative performance on the actual
candidate and matched control: source/export, engine/browser/device, viewport,
scene load, sample method, completed-frame timings and first-use/transition
behavior. Identify per-frame work, retained resources, invalidation and release
ownership. Apply the existing performance/memory contracts proportionately;
missing surface evidence stays Pending. A cap/high average or desktop capture
does not certify stable Web/phone performance.

Keep receipts and failed experiments in the task's evidence destination. Report
source/integration, targeted tests, inspected visuals, measured performance,
reviewer recommendation, user approval, merge and release separately. Automated
checks never grant visual approval. Record a specific finding and smallest next
action rather than declaring an entire category acceptable from one frame.
