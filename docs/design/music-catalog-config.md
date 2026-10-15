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
