# Manual ground cleanup

## Current completion candidate (2026-10-14)

The requested outcome is one satisfying cleanup: retain the accepted V4 real
3D coin, its short outward arc and two diminishing bounces, then lift the coin
upward at its unchanged proportions before it disappears. First ground contact
and each later true landing play the supplied `SfxCoinDrop.mp3` once each,
with per-contact gains of 0, -4 and -8 dB; pickup/ascent starts the supplied
`SfxCoinPickUp.mp3` once. The old immediate cash-settlement sound is not emitted
by manual cleanup. Successful cleanup still awards exactly one coin once.

### Proportionate Feature Design Quality Gate

- Reuse the original V4 GLB/texture and rigid mesh transform, the shared ground
  work transaction, pointer receipt and current SFX bus/preferences. Preserve
  PR260's cash and placement sounds. No save-schema or model-RNG changes.
- Art/Technical Art/Game Feel: preserve normal coin proportions, contacts,
  painter order and camera; only the final pickup trajectory changes. Audio:
  use the two exact supplied MP3s without conversion or asset-byte edits;
  attenuation belongs to individual runtime impact voices. Gameplay:
  preserve litter identity, NPC custody, wallet cap and +1 idempotence. UI and
  Living World mechanics are unaffected.
- Cost: bounded 32 cosmetic records and mesh slots; one shared transparent
  viewport, allocated lazily and disabled when idle. Event checks run only for
  active effects. The game scene owns/releases the viewport and its children.
  No timers or saved cosmetic state. One lazy scene-owned polyphonic SFX player
  retains at most 128 voices (32 cosmetic coins × four cues), retires finished
  voices and stops when idle. Restore and scene exit stop/release playback. It
  uses the existing SFX preference bus without changing cash/place voices.
  Two scene-owned frame
  callbacks are connected only for the world artist and disconnected on exit.
- Evidence: fresh focused cleanup, picking, SFX and carried-trash/save checks;
  real native pointer/mesh tests and actual normal/detail-scale gameplay clip.
  Explicitly test all three true contacts, decreasing per-voice gain, slow-frame
  overlaps, ascent, repeated ticks, idle retirement and generation restore.
- Status: the user accepted the actual per-impact gameplay recording and
  authorized merge on 2026-10-14. The accepted runtime, tests and supplied assets
  are preserved byte for byte in the current-main composition. The recording
  contains all three diminishing landing sounds and one pickup cue; all 480
  video frames remain identical to the preceding rigid-coin recording.
  Focused native checks passed 201/201, and final cleanup/SFX headless checks
  passed 145/145. Original-three qualification passed on exact source 3604b106
  in run 38587911724, attempt 1 (QA 61a102c5). Authenticated content verifies
  all 1257 raw inputs/modes, 73 dependencies and unchanged generated/imported/
  READY/direct/saved RGBA; nine original/runtime/regenerated PNG decodes match.
  Current-main composition and final exact-head CI are tracked separately on
  PR88. The first-contact-only clip was rejected
  for missing later bounce sounds; its source and evidence remain preserved.
  No release or deployment is established by this note.

Version 0.1.11 manual cleanup uses the existing ground-work identity and completion
API. A pending tap must begin and end on the same visible painted mess. Pan, zoom,
focus/device cancellation, modal UI, Decorate, Pause, recovery and generation
changes invalidate it. Following the explicit user decision on 2026-10-13, a successful certified player cleanup grants exactly one Leaf Coin, once only. XP, served totals and automatic NPC rewards are unchanged. A full existing save-contract wallet (1,000,000,000) rejects the player transaction before removing litter. Automatic NPC cleanup
remains authoritative, and a spill beside garbage already carried by an employee
does not settle that employee's custody, disposal timer or reservations.

Hover adds gentle brightness and a 6% visual lift using the original painted hit silhouette. Successful completion settles the original ownership API, then animates a detached snapshot: 50% pop/shrink over 0.58s and one overlapping fluffy smoke ring.

The coin is an actual editable GLB model: three indexed mesh surfaces (front/back/bevel+edge), 1,536 triangles, diameter 2 and thickness 0.32 model units. MeshInstance3D nodes rotate through real Basis transforms under Camera3D in one isolated transparent SubViewport. The existing floor painter composites that viewport texture; it does not calculate or paint coin-face polygons. Lighting and StandardMaterial3D surfaces produce the coin's shading. Per-slot material duplicates apply fade once and work with the Compatibility renderer. The model pool is bounded to 32; the viewport is lazy, resolution-capped, and stops updating/submitting when no coin is active. Model source/generator and original embedded texture are retained for editing.

The initial emergence/landing and two diminishing bounces retain their previous timing and heights. Each successful emission samples a dedicated cosmetic RNG once for bounded world-space direction/travel, kept only in the transient effect. A bounded path search redirects or shortens near walls/furniture. The moving ground shadow paints below every coin. Ground support is computed from actual mesh vertices after real 3D rotation. The three true contacts emit `coin_drop` once each at effect ages 1.15s, 1.59s and 1.91s, with individual gains 0, -4 and -8 dB. Monotonic threshold crossings retain every actual contact even when one slow frame passes several; independent bounded playback voices preserve overlapping tails. Resting on the floor never retriggers a cue. After the second rebound and a short settle, `coin_pickup` starts once at 2.05s while the same rigid mesh translates upward and fades. Source identities are recorded in [coin feedback provenance](../../game/assets/audio/sfx/COIN_FEEDBACK_PROVENANCE.json). Exactly +1 once remains; no model RNG or save schema change. Effects expire after 2.55s and restoration invalidates them before delayed sound can play.


## Painted floor-hit candidate (2026-10-16)

Purpose: exposed litter must remain clickable beside/behind furniture. The old
cleanup guard combined a real litter silhouette with `hit_item` rectangles and
full wall-host faces, incorrectly rejecting empty portions of those masks. PR337
addressed Decorate's different clicked-cell policy; it did not fix this play-mode
visibility guard. Keep that accepted cell-selection behavior and GUI/camera input
ownership unchanged. No customer/staff click-to-serve route is introduced.

Proportionate Feature Design Quality Gate:

- Gameplay/UI: keep original litter hit geometry, identity, cancellation, custody
  and exactly-once +1 completion. Press/hover nominate a candidate only. Hover is
  provisional cosmetic paint in the existing floor pass, so solids naturally
  cover it; it is not an authorization or a geometry query. Release alone asks
  the renderer to certify visibility before the shared transaction can run.
- Renderer owner: extend the existing bounded retained-command query (historical
  `cafe_character_pick_geometry.gd` name) to the half-open painter span after floor
  litter/effects and before editing overlays. The same actual furniture parts,
  doorway panels, actor poses, transforms, triangles and texture alpha determine
  coverage. Do not infer silhouettes from model footprints, host boxes or another
  pose/art replay. Ground rugs/rings and cosmetic litter/coins are below the span.
- Cost/ownership: two span integers on the scene artist and two scalar repaint
  revision counters on each existing native draw/shape node. No new nodes,
  mesh cache, timer, routing state, saved field or wall-slice preparation.
  Revisions advance only on changed commands/appearance and record completion in
  the existing native draw. A hidden subtree keeps its identity/visibility marker
  but skips inactive geometry hashing; showing it still invalidates the receipt.
  Geometry hashing/traversal and non-atlas image readback run only during a
  released query. The existing 250 ms admission deadline and maximum two
  certification frames are not a hard CPU execution-time budget. Traversal is
  O(world commands + relevant geometry), not constant cost or an FPS qualification.
- Measured-cost correction: the existing furniture atlas owner prepares one
  level-zero LA8 image during asset loading (or reuses the CPU image from runtime
  baking). Native conversion retains exact 8-bit alpha and unchanged bilinear
  sampling without a per-pixel GDScript loop. At 1280×3216 this costs 8,232,960
  retained bytes, half a duplicate RGBA image; it also moves one image acquisition
  and conversion into loading, including sessions that never click litter. This
  is one fixed owner resource, not a growing texture cache. Texture replacement,
  content-change signals and dimension checks prevent stale reuse, and the alpha
  revision participates in the presentation receipt. Replacement/owner destruction
  releases the image; other textures retain per-query fallback. Scene-owned nodes
  release their counters; temporary query arrays/images are not retained.
- Evidence boundary: fixed-coordinate command fixtures cover clear table-leg
  gaps, solid neighbors, doorway holes, transformed objects, paint revisions,
  painter-span exclusion and polygon/mesh texture alpha. The native cleanup test
  also defines authored round-table exposed/covered paper points at normal,
  detail and first-frame zoom/pan, without searching `hit()` for a passing point.
  That generated fixture is not the unidentified object in the user's crop.
  Headless tests cannot establish native pointer or pixel acceptance. Exact alpha
  conversion, bilinear/edge samples, texture invalidation, hidden-to-visible
  transitions and snapshot ownership have focused deterministic checks. Native
  source-bound before/after capture, composed renderer cost and visual acceptance
  remain required; this candidate does not change merged/released status.

### Current-main integration and atlas qualification (2026-10-16)

The existing painted-floor candidate `64e4da79bc331c6cba0dbcd70886aeb22c4f832f`
was reconciled once with settled main
`63642fdd453b1581e94f283e14aa9842e0021fc6`, without text conflicts.
At that integration, the delta against main retained the same twelve candidate
paths; the automatic
`illustrated_cafe.gd` merge retains both the main wall preparation and cleanup
painter span. Main's PR331/339 custody, PR340/341 optimizations and PR330 UID
remain present. The transitive producer closure has 80 inputs. The six formerly
stale cleanup renderer rows are adopted from the exact native-qualified source
below; the other 74 rows, all atlas asset records, reference PNGs and imports
remain unchanged.

Focused disposable checks pass 1,485 assertions with zero engine diagnostics:
manual cleanup 155, painted picking 72, retained shapes 18, imported atlas/alpha
34, automatic janitor 39, Decorate picking 41, layout reconciliation 808 and
centered walls 318. These headless checks do not certify native pointer/pixel
acceptance or performance of the composed source.

One bounded actual native regeneration on exact source
`ff2c3f5eea0889520ac2784cbe01ed9fee3c7678` / tree
`9061786ec01494e1e6ce10ccaf998e3da5adf87a` passes the current repository's
original-three exact-RGBA gate. Verified official Godot 4.6.3 runs X11 GL
Compatibility on Mesa 25.0.7 / llvmpipe LLVM 19.1.7. Fresh procedural output,
unchanged imported references, runtime READY/prebaked textures, direct original
PNG decodes and saved PNG decodes all match the fixed ba615/6dc/d16 RGBA hashes.
Native receipt SHA256 is
`a6fa783ed56e42bc39a3a3f7e9dd1a574de60715a5062596b81e84da1a19468a`;
summary SHA256 is
`a4f0ef6b1e68cdb9304e3ccc31d20fe1a52e4fdaa7785eb7b7db9cbf25e42792`;
closure SHA256 is
`0f0d6012c6dcd35c20115d22a1f8a7e45a20e3b2fdb4495879992a362efe268f`.
Independent review verified the exact remote rows/assets and decoded native
receipt, log, driver and unchanged components before this authorized
six-row/provenance adoption. No runtime postimage changes in this successor;
all historical provenance remains intact. The strict 80-source/three-atlas guard,
release metadata validation and 23 related fast unit checks pass on the adoption
source. Final-head CI, user gameplay/visual
acceptance, browser/performance qualification and release remain separate.

Historical limitation and failure evidence remain preserved: the first attempt
stopped before regeneration by applying the historical Car158 wrapper's scoped
Mesa 25.2.8 / LLVM 20.1.2 fingerprint to this different candidate. That was an
over-broad prerequisite; the current general contract has no Mesa pin. The
Car158 wrapper was neither modified nor executed by the new invocation.
The earlier workflow lookup returned `Forbidden`, and no dispatch/retry followed.
Automatic [CI38917981817](https://github.com/yiyousiow000814/little-leaf/actions/runs/38917981817)
for ff2c3f5 failed preflight at `verify_prebaked_atlases.py:79` with
`Atlas procedural dependencies changed: regenerate and verify RGBA before updating manifest`;
release metadata had passed, later checks did not run, and mandatory aggregation
failed. That source-closure failure is retained as history, not a new runtime
regression or a successful final-head CI result.

### Bounded stalled-release recovery (R2, 2026-10-16)

This is a separate correction to admission timing, not proof that the newest
user screenshot was caused by furniture occlusion. Native control source
`0698eb3b5cf388955780653d808041c195abe6a9` / tree
`d43fc1ce098fba298948f49a505b79653bd8b429` reproduced an exposed-paper click lost
after a controlled 300 ms presentation stall. R2 changes only
`cafe_manual_cleanup.gd`; tested script SHA256 is
`0ee60a42e007a81cb94ab230d96976c1a35b0afcebcd28ad1a8a4cd09baed58c`, patch SHA256
`1bfff2d375a135a79b5aa72c33b8954c514fab5f58c0130e575839db87f457a4`.

One unpresented expired query may request a fresh completed receipt. It retains
unused attempts from the original two-frame budget and an absolute 750 ms
intent deadline. A second expiration, exhausted attempts or an expired completed
receipt refuses cleanup. Duplicate release cannot renew either bound. The same
record object, identity, ground custody/shape, model revision and projection must
remain current; ordinary guest/meal/waiter progress is outside that ground-mess
semantic snapshot. No expired pixels authorize completion, and no timer, saved
field, new rendering resource or atlas change is introduced.

Actual native synthetic-scene evidence uses official Godot 4.6.3, X11 GL
Compatibility, Mesa 25.0.7 / llvmpipe LLVM 19.1.7 at 1360×880. It reuses the
existing synthetic mouse-event interaction handlers and actual completed-frame
callbacks; it is not physical-device or browser qualification. Control passes
38 diagnostic assertions, reproducing the stalled loss; R2 passes 107 assertions:
normal/delayed exposed-paper taps settle exactly +1, duplicates cannot reward
again, camera/layout/custody/shape/record replacement refuses, guest progress
allows the fresh receipt, true table coverage still refuses, and a second stall
or total deadline refuses. For the delayed R2 tap, completed frame 11 observes
expiration and rearms with two unchanged attempts; frame 12 submits fresh paint
and settles once. A separate 26-check capture pass inspects real before/after
and final-cleared images after the existing cosmetic effect lifetime; frozen
feedback at age zero is not mistaken for persistent authoritative litter.

The original R2 cleanup headless suite passes 155 assertions. These results bind
to the named base plus exact R2 script, not a new whole-tree native qualification
or performance measurement. The existing suite now retains scalar admission,
semantic invalidation and duplicate/budget regressions, plus native delayed-frame
checks. The expanded ordinary headless suite passes 200 assertions with zero
engine diagnostics; the full tracked native suite was not rerun for this
source-preservation successor. The first exploratory native harness had an unfinished startup cover and
an invalid empty-dining guest fixture; those failed logs remain preserved. The
corrected control/candidate runs have no script errors; their unsupported VSync
warning is recorded. No new user screenshot root-cause proof, user visual
approval or release is claimed. The separate exact ff2c3f5 original-three atlas
pass and bounded six-row/provenance adoption are recorded above; reference assets
and the strict guard remain unchanged. Final-head CI is pending; do not retry
the denied workflow lookup as part of this candidate preservation.

The read-only query never repaints, solves a pose or changes routing. A draw-time
projection stamp, matching pre/post draw state, completed repaint revisions and
current state check protect the completed image. Visible stale commands and
unsupported presentation fail closed. A frame using immediate painting instead of
native command retention leaves the span invalid, never an apparently clear empty
range. No receipt or an expired window grants cleanup. Mesh resources remain immutable renderer-owned inputs, as required by
the existing retained painter contract. Unknown commands do not silently grant a
click. Full wall hosts and furniture rectangles are no longer cleanup vetoes.

The integration runner executes `test_manual_ground_cleanup` against a disposable
profile. Headless runs check the shared custody, duplicate completion and save
API plus the actual retained table commands at fixed points; they explicitly skip
real-pointer certification and pixels. No completed-frame receipt is fabricated. Native GL Compatibility runs execute
the full input checks after actual completed frames. `test_character_pick_geometry`
uses synthetic command/receipt fixtures and does not establish rendered pixels.
`test_direct_janitor_cleanup` protects the existing automatic path.

`capture_manual_cleanup.gd` requires a native renderer and isolated output. It
captures baseline, hover, pop, ring, emergence, three ground contacts, two diminishing bounce peaks, rigid pickup ascent, fade and cleared state at normal/detail/maximum camera zoom. Each fixed age is held across three rendered frames to avoid the old one-frame capture lag. The optional --cleanup-motion path records actual native frames at a fixed 60Hz simulation for a bounded review clip; this is not a realtime performance claim. Keep failed evidence and bind comparisons to exact source
hashes. Owner approval of the query adapter, performance qualification, composed
editor/routing acceptance and user visual acceptance are separate gates.
