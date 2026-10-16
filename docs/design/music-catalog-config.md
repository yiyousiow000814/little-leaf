# Authoring the music catalog

Edit `game/data/music_catalog.json`, not filenames or music-panel code. This is
project configuration, not an in-game editor, remote service or player save.
The user requested one row per named song with its recordings/versions together.

## Add or edit a song

- Each `songs` entry has a stable `id`, a clean player-facing `title`, and an
  ordered `recordings` list. Change the title here to rename the displayed song.
- Add a version under the existing song, including when its source filename or
  tempo differs. Do not add a second song row with the same title.
- Add a genuinely new song as another entry. Song order and recording order are
  the displayed order. Put the ordinary Default before Premium A/Premium B.
- Every recording has a unique stable `id`, `edition_label`, `edition_key`,
  `tier` (`Default` or `Premium`), `audio_path`, boolean `selectable`, and `source`.
  Existing recording IDs are saved preferences: never rename or recycle them.
  The ID `automatic` is reserved for the runtime in both songs and recordings.
- `edition_label` is the visible version text. `edition_key` is the internal
  next/previous-song preference: current matching classes are `default`, `1nd`
  and `2nd`. These strings are configured metadata, never inferred from a
  filename or ID. Several ordinary versions can share the `default` key.
- Use a real imported file under `res://assets/audio/`. Adding its catalog row
  does not create, regenerate, license, or qualify the audio. Keep its source
  path/import identity and provenance intact.
- `source.title` and `source.loop_qualification` preserve original metadata.
  They are not the displayed song name. Do not turn pending listening evidence
  into an approval by editing a label.
- `selectable: false` keeps a contextual recording visible but unavailable as a
  saved listening choice; it does not disable runtime playback. To retire a song
  entirely, remove its catalog entry and update any contextual reference while
  preserving its assets and provenance. Automatic, service/busy switching and
  Decorate ownership still belong to the runtime.

Harmony contains both original recordings with Version 1/Version 2 labels.
Sunshine Skip contains the original176 Default and150 premium recordings. The
user requested that its sole premium choice display **Premium A**. Only the
`edition_label` changes: the `sunshine-skip-150-r6-2nd` ID, `2nd` navigation key,
audio path, source metadata and stored preference remain intact. This label
does not imply that a second premium recording was found or generated.
The subsequent requested removals are recorded below.
Premium remains currently free with the existing future-charging disclosure.
The retained23-recording metadata is pinned by the catalog fixture's projection
hash; deliberate future catalog changes must update that regression evidence
without silently replacing an existing recording or source asset.

## First-use rendering and volume follow-up (2026-10-16)

The release2752 native baseline reproduced the visible `100%` label on two
lines (37.63px allocation versus44px ink). The value now uses a single line,
allowing the existing container to reserve its actual text width.

That same bounded synthetic baseline measured audio loads of3.123–11.281ms,
while the first visible Default-to-Premium switch included a371.527ms frame.
The following process was substantially lighter; caches were not purged, so
these observations do not prove a cold-driver or Web performance result.
The narrow candidate reuses the existing startup readiness cover to draw the
already-owned Default and Premium Music materials once before Welcome. It
restores the hidden panel and actual presentation state without selecting a
recording, adding an audio cache, flushing preferences or starting its poll
timer. Gate teardown also restores the panel. Separately, the user reported
the visual reveal felt too fast: the board and hero now share a one-second
sine ease-in/out, replacing the half-second linear reveal. Artwork, bounded
interruption/reversal, reduced-motion behavior and audio timing remain intact.
Source-bound candidate tests, pixels and performance
evidence are required before claiming the reported stall is resolved.

Independent review of the bd12 candidate found two omitted cold draw paths:
the gilded control palette/rims and the click ripple's shader. The correction
uses the real palette during each covered pose and temporarily displays one
existing wave at a nonzero age. It emits no touch, advances no wave cursor or
audio envelope, and restores the wave's shader value, position, visibility and
input/processing flags before restoring the actual saved Default/Premium UI.
No new wave, shader, callback or audio resource is created. Existing readiness
regressions now check both saved editions and exact ripple-state restoration.
This follows Godot's [Compatibility loading guidance](https://docs.godotengine.org/en/4.6/tutorials/performance/pipeline_compilations.html):
materials must actually draw in view during loading. These are confirmed
coverage omissions, not proof that they caused the measured stall. The prior
bd12 CI/native results remain bound to bd12; corrected-source CI, rendered
coverage, performance and user acceptance must be reported separately.

Downloads contains eight of the nine live catalog song families. Harmony's
Version1/Version2 OGG files remain present in the repository and catalog; their
absence from Downloads does not remove them from the game. No new candidate
song or source file is imported by this follow-up.

## Verify a config change

Run the existing focused integration fixture from the repository root:

```sh
python3 tests/run_integration_candidate.py --only test_music_transport --output /tmp/little-leaf-catalog-review
```

It validates schema/duplicates, stable original metadata, all real recording
availability, config-only authoring, family navigation and the two main export
include filters. The ordinary Web and CrazyGames presets include the JSON; the
separate CrazyGamesMusic payload contains exactly the catalog recording paths.
The main CrazyGames payload excludes only exact catalog audio paths, never a
folder-wide wildcard that could hide SFX. Existing GeneralUser and TimGM notices
remain included. This retains the existing delayed
pack loader and bounded retry behavior. The focused fixture checks membership
and the unchanged loader contract; exported platform packaging remains pending. Native import
and these checks do not establish an exported/browser/audio-listening pass.

## Scope and cost

This small UI/audio-metadata change reuses Catalog's existing API, Main's audio
ownership and the current music window. Only JSON parsing/validation at script
load is new; it creates metadata, no streams, players, timers or persistent files.
Runtime queries read the bounded in-memory list; there is no polling/hot reload.
Malformed documents produce an explicit catalog error, not partially accepted
recordings. No gameplay, save-policy, SFX or art asset change is included.
Actual composed UI review, final platform qualification and user acceptance remain
with the music owner; technical catalog checks do not approve the presentation.

## Historical listening-room motion candidate (2026-10-13, cancelled)

The prior vine/motion approach below was rejected and cancelled. A newly
authorized reference-based art implementation is pending with the visual owner;
this historical evidence does not approve that new art.

The owner requested continuous seedling-to-vine growth, individual music-led leaf
responses, sparse falling leaves, a local luminous air-touch wave, and a deliberate
landscape edition layout. The unaccepted successor retains the exact original
wood board source and fixed board geometry. Default paint is unchanged.

Two rooted, tapered retained mesh arms advance through authored curved paths over
4.6 seconds. Branch arrival triggers curled leaf unfolding. Thin phone rails carry
stems rather than tiny leaf clutter; controls retain clear border-only ink bounds.
Actual BGM bus left/right peak meters drive smoothed energy, delayed leaf response
and sparse transient-triggered falls. There is no per-track BPM timer. Authored
pose curves and fall trajectories remain procedural; the record-label rotation is
a conventional playback cue, not claimed beat synchronization. Pause settles over
0.32 seconds; hidden/reduced-motion state stops frame processing immediately.

Touch input emits into four retained clipped quads without consuming controls.
Soft transparent-centred layered light crests decay in 0.95 seconds; BGM energy
subtly modulates their strength. This is luminous SDR artwork, not a true HDR or
screen-space refraction pipeline. Four bounded foliage touch impulses share the
existing process. No new audio stream, microphone capture or gameplay/save change.

Phone landscape allocates a wider player bay, artwork/title row and full-width
three-edition row. The 844x390 board uses 796x358 available space; the compact
566x360 variant prioritizes title and edition controls. Existing 44px hit areas
and smaller painted control faces remain.

Native Godot 4.6.3 GL Compatibility evidence includes a 24.15-second, 1,449-frame
movie with actual mixed soundtrack, two tracks, three transient-triggered falls,
touch response, silence, pause, resume and reduced motion. Board/decoration bounds
checks pass throughout. Exact phone-aspect renders are simulated native viewports,
not physical phones or Safari. The cloud renderer is llvmpipe and fixed-FPS capture
is not a real-time performance qualification. Per-frame work is bounded retained
material/transform updates and bus reads; no unchanged geometry is rebuilt.

Native footage and aspect-ratio images remain acceptance candidates. No merge,
release, browser/audio-device listening or mobile performance claim is made.

## Requested soundtrack removal (2026-10-13)

The user explicitly rejected Main Street and Shop Rhythm for repeated listening
and requested their removal. All six recordings of those two songs are removed
from the existing runtime catalog. Their original audio, import settings, source
records and licenses remain intact. No UI-specific blacklist or second catalog
is introduced. The remaining nine songs contain23 selectable recordings
(10 Default,13 Premium), plus Automatic.

The Decorate context now uses the existing `decorate` recording, Quiet Table,
which remains selectable. Existing stored IDs for removed recordings use the
existing invalid-selection fallback to Automatic (`service`/`busy`). Loading such
a preference does not rewrite it or migrate player saves. Normal explicit future
preference changes retain the existing persistence behavior.

This scoped Audio/UI behavior change reuses Catalog, settings normalization and
Main's bounded playback ownership. It adds no per-frame work, new streams or
retained resources; art, gameplay, SFX and save policy are unchanged. Focused
Godot4.6.3 generated-profile context and imported-decoder transport suites passed
397 and183 checks respectively. Tests cover every removed saved ID, unchanged
preference bytes on load, refusal to create removed players, remaining row/tier
counts, Decorate/restore, navigation, pause, seek, visibility and stream retirement.
The retained metadata projection and original asset blobs were verified.

Implementation and these580 technical checks do not establish listening, browser,
visual acceptance, merge or deployment. The visual owner is updating preview
selections to a remaining song independently.

## Reference-directed static candidate (2026-10-13, awaiting review)

The user supplied the cream/gold botanical reference and then authorized implementation. The previous procedural green-vine composition is rejected. The current Premium candidate uses separate original generated RGBA board and botanical layers, retained native player/list/transport controls, and four uniform-scale botanical quadrants. Compact landscape uses a single bounded header ornament; narrow portrait omits it rather than compressing leaves into the control rim. The Default edition retains the original four-corner decoration. No new botanical motion has been qualified or accepted.

Asset hashes and provenance are in `game/assets/ui/music_botanical/PROVENANCE.json`. The ornament alpha-cell inventory is geometry-only evidence; it does not alter source raster pixels. Explicit opaque list, transport and header surfaces cover underlying decoration. Single-line text audits measure the drawn aligned text width, not empty layout allocation. All controls retain their full hit rectangles in overlap checks. Decorative nodes ignore input and allocate retained textures once; layout changes only reposition existing nodes. There is no new per-frame geometry construction.

The source-only recovery retains the original four-corner rollback and all audio/license dependencies. Main Street and Shop Rhythm remain removed from the catalog, including automatic selection. Static tests do not constitute aesthetic acceptance or release approval.

## Current source integration (2026-10-14, visual acceptance pending)

The current candidate is the independent desktop/portrait/landscape Music panel,
with the r27 ornamental foliage restored after the rejected plain r26 frame.
Original retained raster assets are unchanged; a source-UV rounded frame mask
removes unwanted outer seams without replacing intended corner ornament. Phone
composition positions existing ornament nodes independently rather than shrinking
the desktop layout. Track selection, pause, seek, dismiss, repeated open/close and
edition transitions remain owned by the existing native panel and Main BGM state.
No payment, entitlement, remote catalog, player-save migration or service is added.

The relevant pillars are Art, Technical Art, UI/UX and Audio. Gameplay, economy,
world rendering and save policy are unchanged. Existing retained controls/textures
are created once per panel; responsive layout changes transforms and bounded
shader parameters. Transport snapshots do not load streams. At most incoming and
outgoing BGM players are owned; replaced streams are stopped and released. Hidden
or reduced-motion decoration does not keep frame processing active. Real browser
performance, listening, final packaging and user visual acceptance remain open.

Integration is selective against current main, preserving accepted ring artwork,
current Help/Settings behavior, PR280 delayed-pack retries, and the existing
Decorate transaction functions. PR308 owns all dirty-save scheduling and save
hooks. Its unmerged changes are not copied or replaced by this music addition.
Historical native r27 screenshots remain bound to their original candidate, not
relabelled as proof of this current-main composition. Neither tests nor Draft PR
publication constitute visual approval, merge or deployment.


## Cloud continuation: rejected composition aliases (2026-10-16, candidate)

The latest user correction rejects the Corner Café composition and its Harmony,
Main Street and Shop aliases/arrangements. Earlier short-reference approval
remains historical evidence. The runtime catalog candidate removes Harmony
Version 1/2 and Corner Café, in addition to the six already excluded Main
Street/Shop recordings. Seven families retain20 recordings (7 Default,
13 Premium), plus Automatic. Every original audio, import, production source,
licence and recovery record remains preserved. The existing unknown-selection
fallback handles excluded stored IDs without writing preferences on load.

This is a source-family exclusion, not a judgement from filenames or distinct
hashes. Preserved event data shows41 identical opening melody performance events
between Harmony B and Corner Café; Main Street's parent has the same514 events
as the supplied Corner Café loop; Shop preserves all123 theme pitch/onset/duration
events. Actual decoded runtime Harmony A/B and Corner Café PCM each match their
preserved technical derivatives (756000/756000/2268000 stereo44100Hz frames).
No listening or new recording approval is claimed.

The change reuses the authored catalog and existing normalization, playback and
CrazyGames packaging owners. It adds no per-frame cost, stream/cache ownership,
audio processing or save policy. Context/transport fixtures use retained tracks,
including a42-second Petal decoder in place of the excluded51-second Corner
loop, retaining seek/pause/visibility/retirement and invalid-ID byte-preservation
checks. Initial context368 checks passed; initial transport206 checks exposed
that the first replacement Cloverlight is29.28 seconds and cannot satisfy the
unchanged longer-than30-second decoder assertion. The corrected fixture uses
Petal, without weakening that assertion. Corrected transport206 checks pass with zero diagnostics; together with the
unchanged context368 result this gives574 focused checks. Actual UI/browser/audio
acceptance remains pending.

## Panel-edge botanical correction candidate (2026-10-16)

The user's annotated follow-up requires the existing foliage on the actual panel
upper/left inner edges, rather than a centered smaller-aspect frame crossing the
gramophone and playback copy. The isolated cloud candidate starts from verified
handoff `8b5261ae5a1066b964361d572162c324bb3c7ef6`; that transfer is source
provenance, not visual acceptance. Fresh native Before/After captures reproduce
the issue at1882x831 and include1360x880 and the annotated1917x867 viewport.

Eight retained corner/edge regions reuse the original continuous botanical PNG.
Corners retain uniform proportions; intervening edge strips span the available
panel dimensions. Adjacent slices use level-zero linear sampling to avoid seams
from differing mip levels. The original gramophone source, meshes, UVs, placement,
controls and PNG/import bytes are preserved. The desktop quiet region now covers
actual status/title/edition/fee/context text ink, rather than only the song title.
All raised frame islands, finials and emboss layers receive the same actual mask;
the explicit ink inventory reflects those masks. Source masks update with layout,
without per-frame resource allocation. Four additional desktop edge nodes and
four added raised-ornament mask materials remain owned by the existing frame.

The focused engine suite passes49,875 assertions for panel-edge placement,
adjacency, masks after resize, repeated material identity and material release
on teardown. It is registered in the ordinary integration runner. The unchanged
79-source/three-atlas guard passes. Fresh inspected Godot4.6.3 native captures use
Mesa llvmpipe software rendering in disposable synthetic profiles; no original
saves or production services were used. Earlier source-transfer tests/screenshots
are not relabelled as this candidate's proof. Intermediate broad-mask clipping
and mip-seam attempts remain retained outside source and are not the final
candidate. Actual browser/device performance, integrated Music regression,
user acceptance, merge and publication remain open; PR321 stays the sole
principal Music review. No remote branch or PR write accompanies this candidate.


### Music toolbar image candidate (2026-10-16)

The user requests a designed Music image alongside the existing brush, chef,
pause and gear. An original transparent sage/wood musical-note raster reuses
those assets as style references; prompt and exact source hash are preserved
with the existing HUD provenance. The existing HUD texture owner bounds the
retained texture to 320px and crops alpha bounds; the44px native action, tooltip,
accessibility name, focus, popup ownership and existing press motion remain.
Responsive arrangements keep the same Music hit rectangles and render the
picture inside them. No player-state/save/audio path changes. The generated
raster and prompt are recoverable; layered GUI/vector authoring is unavailable
for this generated source and no new Golden approval is claimed. Actual native
normal-scale toolbar inspection and focused responsive checks remain pending.
# Gramophone toolbar candidate (2026-10-16)

The user rejected the paired musical-note Music entry and explicitly requested a
gramophone. This scoped candidate replaces only the toolbar raster and its alpha
crop, using an original brass-horn, vinyl-record and wooden-cabinet illustration.
The inspected existing Decorate/Settings art informed the style. The successful
built-in generation used a text prompt, retained beside the unchanged generated
RGBA source; it is not a layered editable illustration or a new Golden Reference.

The existing native Music button, tooltip, accessible name, input, focus/press
feedback, retained texture loading and panel behavior remain. Source
resolution stays 1254x1254, and the same loader limits the cached texture to 320px;
there is no new frame callback, animation, resource owner or invalidation path.
This is an intentional appearance change awaiting the user's actual game-pixel
acceptance. Desktop/mobile-size paired fixture captures and narrow toolbar checks
are recorded in the candidate PR; native emulated touch does not qualify a phone
browser, performance or release. Hat/steam reference work remains separate.

The user subsequently requested balanced icon proportions, vertical centering
and equal spacing across the toolbar. The revised candidate keeps the same
generated gramophone PNG and tight alpha crop. It draws the gramophone at44px
height on the desktop rail,34px on phone layouts, and uses
the same retained material treatment as Decorate/Staff/Settings. This replaces
the earlier32px square fit and stronger lightening that reduced its visible
width and weight. It adds no texture, material variant or frame callback.

Desktop actions share a painted centerline and equal18px gaps (8px at the
compact breakpoint), including both sides of Pause and Music-to-Decorate. Phone
actions use equal44x44 native cells and6px gaps; wrapped rows retain aligned
columns. Original asset aspects,44px minimum targets, focus order and actions
remain. Actual pixels and existing responsive/input suites must confirm this
candidate; numeric geometry alone does not establish visual acceptance.

PR330 at09bbd6d4 owns Settings UID footer/clipboard changes in
`cafe_compact_ui.gd`, `cafe_cloud_settings.gd` and the Web adapter. This candidate
changes the separate `cafe_hud.gd` layout and its existing layout tests. The
shared Roadmap receives only the scoped status update; no PR330 runtime delta
is copied, changed or claimed integrated.

Mobile button-padding refinement: the user requested a little more space
between artwork and button edges. Phone artwork now fits30px for brush/gear,
30px high for the chef, and34px high for the gramophone's taller silhouette.
Every illustrated action has at least5px internal clearance while retaining
native aspect,44px hit cells,6px gaps and the existing centerline. The already
inset Pause glyph and wallet coin retain their spacing. The desktop path and
its44px gramophone remain unchanged; actual paired desktop pixels verify this.
