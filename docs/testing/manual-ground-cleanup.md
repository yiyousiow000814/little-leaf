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
  passed 145/145. Original-three canonical qualification and final exact-source
  CI remain required before merge. The first-contact-only clip was rejected
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


Character occlusion queries the current retained painter. It does not repaint a
character, solve a pose, change routing or allocate retained meshes, textures or
nodes. A draw-time projection stamp, matching pre/post draw state and current
state check protect the completed image. Visible stale characters and unsupported
ancestor presentation fail closed. The receipt hashes command arrays, so work is
O(character descendants + geometry content) only during a bounded cleanup query;
ordinary rendering does not traverse geometry. A valid release queues one painted
frame instead of changing the model immediately. Its query expires after 250 ms
and allows at most two submission/completion certifications; cancellation closes
it. Settlement rechecks input guards, identity, projection and current geometry
against the completed receipt. No receipt or an expired window grants no cleanup.
This is not a constant-cost or FPS acceptance claim. Mesh resources are treated as
immutable renderer-owned inputs, matching the existing retained painter contract.

The integration runner executes `test_manual_ground_cleanup` against a disposable
profile. Headless runs check the shared custody, duplicate completion and save
API, and explicitly skip real-pointer checks. Native GL Compatibility runs execute
the full input checks after actual completed frames. `test_character_pick_geometry`
uses synthetic command/receipt fixtures and does not establish rendered pixels.
`test_direct_janitor_cleanup` protects the existing automatic path.

`capture_manual_cleanup.gd` requires a native renderer and isolated output. It
captures baseline, hover, pop, ring, emergence, three ground contacts, two diminishing bounce peaks, rigid pickup ascent, fade and cleared state at normal/detail/maximum camera zoom. Each fixed age is held across three rendered frames to avoid the old one-frame capture lag. The optional --cleanup-motion path records actual native frames at a fixed 60Hz simulation for a bounded review clip; this is not a realtime performance claim. Keep failed evidence and bind comparisons to exact source
hashes. Owner approval of the query adapter, performance qualification, composed
editor/routing acceptance and user visual acceptance are separate gates.
