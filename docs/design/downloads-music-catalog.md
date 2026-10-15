# Downloads music candidate

Historical source/provenance record. The initial 29-recording scope below is not
the current catalog: the user later removed Main Street and Shop Rhythm. The
current configuration has nine songs and 23 selectable recordings; Decorate uses
Quiet Table. See [the current catalog contract](music-catalog-config.md). The
original recordings, notices and rejected candidates remain preserved.

## Initial implementation record

This isolated candidate implements the user's requested groups in an independent
Music window opened from the HUD. The rejected Settings selector is removed.
Default contains unmarked versions; Premium contains the exact
1nd/2nd versions and is currently free. Its tooltip explains future charging.
There is no entitlement, payment or locked selection. The29-entry catalog keeps
the existing Harmony Study A/B and unmarked Decorate-only Shop behavior;28 tracks
are gameplay choices, plus Automatic. Masters, stems and ZIPs are not songs.

## Reuse and state

Reuse `game/scripts/ui/cafe_music_catalog.gd` and the existing music backend and
Settings preference setters from private7c3de91, originally composed onto
main08bcf651. The new `cafe_music_panel.gd` is presentation only. Existing stable
preference IDs remain; each full-name row carries its catalog ID, so
Default/Premium tabs do not alter saved IDs. Missing, malformed and unknown
preferences
default to Automatic. Only `audio/music_track` is added to the independent
preferences file. Stats strict-bool/default-Off, frame-rate controls, Help,
existing styles/insets and restaurant save/economy/model behavior are preserved.

Automatic retains service/busy timing. Decorate overrides the effective track
with Shop, then restores the previous state/position/age unless the user changed
their choice inside Decorate. Selection, volume, mute and browser suspension
continue using the existing BGM bus and1.2-second transition. Incoming/outgoing
streams are loaded on demand; retired streams are stopped and detached before
their nodes are queued for deletion. A fade generation protects rapid A-B-A
changes. The availability table is populated once per pack arrival, with no
resource loading/catalog scan in the per-frame tick. Real lifecycle bounds and
audible fades remain pending runtime evidence.

## Source and musical limits

[Runtime source mapping](../../game/assets/audio/DOWNLOADS_RUNTIME_SOURCES.json)
binds26 exact supplied audio copies to preservation heade2436be. The21 newly
introduced MP3s are unchanged full recordings for this private comparison;
replaying them is **not** accepted seamless-loop processing. The five existing
OGG aliases retain their source identities. Originals stay separate from any
future marked loop master/derivative. GeneralUser permissions remain scoped to
the original three MP3s; supplied TimGM source notices/recording assessment are
in PR228, and marked sources' unrecovered authoring provenance is not invented.

The proposed marked Main Street1nd pilot has no matching editable events/stems.
Its138.767-second mixed source cannot inherit the unmarked51.429-second score.
One CPU source/pulse analysis and exact three-cycle lossless repetition control
are prepared privately; they do not establish a musical region or hearing pass.
The failed3874-byte OGG encoding attempt is retained and not adopted. No fixed
crossfade, blind outro-tail wrap, trimming or other16-track batch is performed.
An audible source review must select the deliberate region/ending before its
arranged-loop candidate is qualified. The existing Audio Bible and Music Skills
remain the workflow; no new production framework is added.

## Feature Design Gate and qualification

Relevant pillars: Audio and UI/UX, with Technical Art resource ownership.
Gameplay/economy, Art, Living World and character rendering are unaffected.
Source/hash/ownership checks and the adapted existing music-context fixture
support review; no new broad test framework is introduced. Dated Godot
import/compile, preference/context and ownership results are recorded
below. The independent window has separate responsive navigation and actual-frame
checks; source-bound results must follow the final panel revision. Three-cycle
musical listening, game/SFX comfort and target-browser playback remain pending.
Synthetic disposable profiles
only; no original player save is used.

Release presets/helpers, platform storage, CI/atlas guards and deployment
resources are unchanged. CrazyGames readiness uses catalog availability rather
than counting retained players. Its existing three-track pack is insufficient
for this catalog, so the full new platform catalog is explicitly unqualified
until the Release owner coordinates the separate membership delta. No engine
grant, browser export, publication, merge or deployment is inferred here.

## Cloud technical continuation — 2026-10-13

The frozen candidate `a70fb7d354bc9b1be6f9af8f3f49afa67f3d158c`, tree
`50ea4989a4e01381f96db6ddf781c2df8f2082e6`, was restored exactly before this
focused continuation. All26 introduced audio files still match its recorded
hashes; no recording or import setting was changed.

Focused failures exposed interrupted-transition issues. The correction preserves
an active same-target fade, leaves the effective Shop transition alone when a
saved preference changes inside Decorate, retains the playing gameplay position
at Decorate entry if a subsequent mute prevents normal retirement capture, and
retries an enabled selection deferred while the browser was suspended. General
mute semantics, volume/buses, stable preferences and player data guards remain.

The music fixture's original29 preference failures were caused by review-mode
flags intentionally rejecting writes. Its runner exception now uses only the
already isolated generated profile, synthetic startup and zero-I/O save override;
an ordinary-player-save filename tripwire remains enforced. Production review
and save guards were not relaxed. The focused fixture also observes real
AudioStreamPlayer positions through the Dummy device, held-completion context
restoration and weak-reference release of retired nodes and compressed streams.
Those observations are controller/ownership evidence, not hearing. A verbose
exit diagnostic identified an intermittent retained OGG decoder in the earlier
fixture shutdown. The strengthened fixture observes release of the actually
played decoder across deferred node/audio cleanup before it permits exit; the
earlier warning and diagnosis remain retained, not suppressed.

Godot4.6.3 import/compile and the focused music-context, existing Settings
navigation and Web-performance ownership fixtures pass. The16 existing runner
infrastructure tests pass. Final exact-source counts and source hashes are in
the retained aggregate receipts. Actual sound output, timed audible fades,
real-browser lifecycle/codec behavior and sustained resource soak remain
unqualified. This cloud runtime denied display/browser socket creation, so no
actual interface pixels or playable preview were produced; headless layout
checks do not establish visual or touch acceptance. CrazyGames pack membership,
canonical guard qualification, complete CI, user acceptance, merge and release
remain separate pending gates.

## Independent Music window — 2026-10-13

The user rejected putting track selection in Settings. Music now has its own HUD
entry and themed framed window, reusing `CafeHud`, the 29-entry catalog, Settings
setters and the existing BGM runtime. Default shows 12 rows including visibly
unavailable Decorate-only Shop; Premium shows 17 currently free choices. Its exact
future-charge wording is available in wrapped content and bounded tooltips, with
no payment or entitlement behavior. The 22px title, 44px X, full-name track rows,
Automatic action, group tabs and BGM mute/volume retain the existing popup input
policy, safe-area helpers and focus return. Settings remains the sole preference
persistence owner; no audio player, polling timer or restaurant save is added.

The initial independent panel passed 254 focused headless assertions, but actual
short-landscape inspection exposed an overview occupying the whole list viewport.
The correction keeps current playback in the short header, combines Automatic
and both tabs into one 44px row, and starts the track list immediately. Redundant
short status paragraphs are omitted; full Premium terms remain reachable after
the list. Portrait and desktop retain their prior composition. The focused test
now requires an initially fully visible track and reachable group controls in
both groups at 844x390 and 566x360. The refined panel passed 266 focused headless
assertions with no engine warnings or errors. The duplicate selection click sound was removed
because the existing button entrypoint already supplies it.

Final source-bound headless and actual refined-window frames, real pointer
interaction, user visual acceptance, audible/browser qualification, current-main
composition and release gates remain separate. Earlier source-bound evidence and
failed frames are preserved; this correction authorizes no merge or publication.

## Large listening player candidate — 2026-10-13

The latest request supersedes the narrow window and separate Default/Premium tabs
above. The requested player uses roughly 80% of the game viewport, centered within
safe areas, with a library and Now Playing area. Portrait stacks these sections;
short viewports retain the 80% target with bounded detail/list scrolling.
Related recordings appear together in one song card: Default is the base edition,
with supplied Premium 1nd/2nd variants alongside. The eight evidenced families
are paired by catalog metadata; unmatched recordings are never made into a false
family. All 29 IDs and their full accessible recording names remain unchanged.

The candidate reuses CafeHud's original framed wood, leaves, cream faces, hanging
sign, fonts and native controls. Premium variants use warm gold-tinted instances
of the existing painted face, with an explicit Premium label and the exact
currently-free/future-charge notice. No new art, service account, payment,
entitlement or Spotify branding is introduced. This is a requested functional
reference, not a copied service skin.

Main owns pause/resume, family-aware previous/next, true stream position/duration
and supported seek. The panel consumes its snapshot. Settings still owns BGM
volume, mute and selected-track persistence; SFX and restaurant saves are
unaffected. A single panel-owned 0.25-second timer runs only while visible and
stops on hide/teardown. Song cards are built once, and selection/status changes
update retained controls. No fabricated elapsed timer or per-frame catalog
rebuild is used. Decorate, browser suspension/loading and unsupported seek have
visible state/reasons, with keyboard focus, dismissal and world-input behavior
reused from the existing popup path.

Relevant pillars are Audio, UI/UX and Technical Art resource ownership. World
art, camera, gameplay, economy, progression and save policy are unaffected.
Focused synthetic-profile geometry, dispatch, transport presentation and timer
lifecycle checks plus actual responsive frames are required for this candidate.
Implementation, source-bound tests, inspected frames, hearing/browser behavior,
user acceptance and release remain separate; the preceding narrow-window
results cannot qualify this replacement.

The focused 305-assertion native-engine/Dummy-audio fixture passed without
diagnostics on the first frozen large-player source. Its layout measurements
are 1088×704 at 1360×880 and 675.2×312 at 844×390, exactly 80% on both axes.
Portrait 390×844 uses 366×675.2: 93.8% width preserves the 44px targets and
readable three-edition cards, while height stays 80%. At 566×360, native control
minimums require 477×288 (84.3% width and 80% height). All are centered in the
safe viewport, with at least one complete initial song card. Short layouts show
a compact free-now/future-paid note above the library and retain the complete
exact Premium disclosure at its end. These geometry checks do not replace
actual native pixels or physical touch acceptance.

Visibility ownership was tightened after this first frozen candidate: hiding an
ancestor also stops the same timer, revealing it resumes that timer, and hiding
the panel or freeing the scene still stops/releases it. No new timer or catalog
controls are allocated on reopen. Focused follow-up verification is recorded
separately from the first capture's source identity.

Actual first-candidate inspection found the 566×360 right-side details viewport
showing only the first word of a long title. Its focused correction moves the
current song title and edition into the spare header column only on short,
narrow viewports. The complete identity remains visible alongside the fixed
transport, without enlarging the window; desktop, portrait and 844×390 retain
their previous composition. A long-title bounds assertion guards this case.

The added 360px portrait safe-area capture exposed a second concrete issue: the
300px player left a 22px library viewport at 360×680. Shorter portraits therefore
use a 240px player and the compact Premium notice, while retaining the complete
disclosure in the scrollable library. Native measured card height sets the
library's minimum, so one complete family and its 44px actions are reachable.
Only the real combined minimum may exceed the 80% height target, centered within
the safe viewport. Focused cases include 360×600 and 360×680 with 8/20/8/16 insets;
desktop, 390×844 and both existing landscape layouts remain unchanged.

The combined preview uses main3a5c8553 runtime with the docs-only bef5b763
roadmap, the accepted normal HUD placement from PR256 ef7f6f5, and the accepted
text-only Saving source from PR25815dfeca. The wallet-notice implementation is
unchanged from main; PR256's separate long-amount edge patch is not included.
Music stays before the adjacent Pause/Settings pair. Below378 usable pixels it
uses a44px musical-note entry and a66px business-status target in the first row,
preserving the accepted two-row height, ordinary wage clearance and supported
360×600 safe-inset viewport. An earlier third-row candidate failed that exact
support boundary and is preserved as failed evidence, not accepted behavior.

Final scoped receipts establish334 panel,446 context,117 transport,678 HUD,
4898 mobile-toolbar and36 Saving assertions on their recorded matching sources.
Native actual frames cover1360×880,390×844,844×390,566×360 and360×600/680 safe
areas. Actual own-cloud pointer checks exercised open, pause, seek, resume,
next/previous, volume, mute, edition selection, close/reopen and resize; Escape
was not observed before the bounded fixture exited. These checks used synthetic
cafés with intercepted/no-I/O save routines. Dummy audio is not listening
acceptance. User approval, Web/audio listening, canonical atlas closure,
CrazyGames membership and complete current-source CI remain pending. No merge
or deployment is established by this preview.

## Independent Music polish after visual rejection — 2026-10-13

The user rejected the large split-player presentation, particularly on landscape
phones, and clarified that an independent Music screen does not need to resemble
Spotify. Those previous captures and technical receipts remain historical
evidence, not accepted pixels. This revision uses one full-width song library
above a compact unified playback dock. It removes the large competing Now Playing
column, decorative sign, duplicate library heading and scroll-trapped current
song identity. Song rows keep their full titles and related edition choices
together; portrait stacks only the row contents and playback controls.

The user's latest naming direction is Premium A / Premium B everywhere visible,
and one Harmony Study family with Study 1 / Study 2. Catalog display helpers own
those names while the original 29 IDs, source titles, file mappings and playback
variant keys remain unchanged. There are now 12 displayed families. The existing
cream/wood/leaf surfaces, gold Premium treatments and exact free-now/future-charge
disclosure are retained. No additional art or UI framework is introduced.

The dock keeps actual controller-owned position/duration, transport, BGM mute and
volume. It has no scrolling title pane; exceptional playback/context reasons
remain visible. The existing visible-only timer, focus cycle, close behavior and
Settings/backend ownership are unchanged. An 80% centered safe-viewport target
retains measured minimum fallback for a complete song row and 44px touch controls.
Responsive engine checks and new actual captures must qualify this revision; the
previous source's passing checks cannot establish its visual acceptance.

The polished source passed372 focused panel assertions plus446 context and166
catalog/transport assertions without diagnostics. The first polish fixture
exposed an initial desktop minimum-height cache; invalidation now follows the
retained track body's minimum-size change. Failed evidence is retained. Actual
native inspection covered17 generated frames across desktop, portrait, both
landscape sizes and360px safe-area cases. The final capture aligns the selected
whole family after layout; all playback positions remain decoder-derived.
The reviewer found no further blocking layout defect in those frames. This is
an inspected candidate awaiting the user's visual judgement, not an accepted
replacement, canonical renderer qualification, hearing pass or release.

## Listening folio redesign — 2026-10-13, pending visual acceptance

The user rejected both recent music layouts for layout, occupancy and usability,
particularly phone landscape. The frozen `f62ee96d` tree is retained as rejected
visual evidence, not a target. This additive candidate changes only the music
presentation and its focused fixture. Catalog, Main, Settings, audio bytes,
preference IDs, save policy and release configuration remain separately owned.

The player task is choosing a song, comparing its recordings and controlling
playback while still recognizing the café. A single paper song shelf therefore
replaces the repeated three-button cards. Selecting a family starts its last
chosen recording (or first selectable recording); the one fixed recording pane
shows its title and Default/Premium A/Premium B choices. Harmony keeps its
explicit Study 1/Study 2 pair. The disabled Shop Default remains visible beside
its selectable Premium recordings. Selection during Decorate is explicitly
identified as the service choice while the backend's Shop explanation remains.

Wide views place the recording and shelf beside one another; portrait stacks
them. A shared transport stays below both. Small landscape uses two-line Premium
labels to recover shelf width without hiding the A/B distinction. Existing wood
frame, type and palette anchor the music surface in Little Leaf; lighter local
paper/sage controls reduce repeated bevel weight. The static record mark and
speaker glyph are original retained UI geometry, not replacement world art.
The record ornament is omitted where it would compete with song choices.

Keyboard order is Close, Automatic, song shelf, visible editions and transport.
The shelf is one Tab stop: Up/Down and Home/End browse; Enter selects. It is still
scrollable by pointer/touch. All active controls retain at least44px targets,
including seek and volume. Repeated song/edition selection, focus restoration,
Escape, safe areas, ancestor hiding, interrupted playback and scene destruction
remain part of the fixture. Long names remain wrapped and fully readable.

This affects UI/UX and retained Technical Art only. The Audio backend is reused;
no listening, seamless-loop, world art, gameplay, economy or production save
claim follows. One scene-owned timer polls the live playback snapshot at4Hz
while visible; hidden panels stop it. Song/edition nodes are allocated once.
Record/speaker geometry redraws only for size/state changes. Layout work is
invalidated by viewport, minimum-content or state changes, not elapsed time.
The smallest applicable checks are the music-panel fixture and actual native
frames at1360×880,844×390,566×360,390×844 and safe360px portraits. Final source
hashes, exact check results, runtime limitations and captures are recorded in
the separate candidate evidence receipt. User visual approval, canonical atlas
qualification, real-device touch/browser playback, listening, integration and
release remain separate pending gates. No publication or merge is authorized.

Candidate verification: the final focused music-panel run passed344 assertions
with no diagnostics, including all29 catalog identities, all28 selectable
recordings, one visible edition chooser, remembered family choice, roving-keyboard
navigation, repeated selection, safe-area and interrupted-state bounds, canceled
seek handling, shorter-duration refresh without accidental seek, automatic
edition focus transfer, hidden-panel input refusal and timer teardown. Eighteen
actual Godot4.6.3 native frames were rendered and inspected. The runtime used
X11/GL Compatibility, llvmpipe LLVM19.1.7/Mesa25.0.7 and Dummy audio following
ALSA failure. This establishes the captured interface pixels and controller
checks only; it is not canonical atlas, hearing, physical-touch, performance or
browser qualification. No player data or restaurant save I/O was used. The native Decorate-exit
scenario invokes one instrumented `_save()` override, which only increments a
fixture counter and returns; it does not call the production save writer.
The code-health review stayed within the presentation owner: bounded node and
family-choice retention, event-driven layout, no duplicate audio owner, no new
asset imports, focused lifecycle fixes and no remote/source integration changes.
The UI remains a private visual candidate pending the user's decision.

Parent visual review refined the candidate before user delivery: header and
transport content share a10px inner inset, the desktop recording cluster sits
directly on the retained wood with a bounded300px edition strip, and Premium
editions have restrained cream/gold faces with a darker gold selected edge.
Short-landscape disclosure is one lower-hierarchy line. This parent review is
not user acceptance. Final post-refinement evidence is source-bound separately.

The post-review fixture also observes release of every exercised audio player
and stream after scene teardown, with a bounded1-second wait. This follows an
intermittent ObjectDB exit warning in the retained earlier run; it does not
suppress diagnostics or change the production backend. The final verbose run
passed344 assertions without diagnostics. All327 tracked production game files
in the native staging directory match the candidate; only the isolated
`project.godot` profile/capture entry is intentionally different.


## Board-interior foundation correction — 2026-10-13, pending review

The user rejected the delivered folio pixels as overflowing the board and too
flat. The `afa6fc1` source and r4 frames remain frozen rejected evidence. The
previous outer-panel checks were insufficient: the compact shared frame margins
were only20/16/20/8px, while the original512×158 artwork's inner bevel is about
32px from either side,26px from the top and20px from the bottom. Its64px corner
caps remain unscaled, including at phone sizes. Music now owns one conservative
40/36/40/32px inner-face envelope for the entire body, including curved corners.
The shared HUD and original assets remain unchanged. Header, cards and transport
use this same envelope; overflow is not concealed by clipping the whole body.

Cream and sage buttons reuse the existing painted face textures for shallow
material depth; Premium uses the same bevel with restrained gold tint. There
are no new shadows, raster assets, gameplay features or animations in this
foundation correction. The short landscape shelf keeps two complete44px songs
and a scroll cue, while a safe360px portrait uses a narrower but still44px-or-
larger Play/Pause control. Native pixels and independent painted-bound checks,
including style expansion and clipped shelf descendants, must qualify the result.

The user requested this order: finish board containment, layout, clean song
names and usability, then enrich the music-themed visual presentation. These
foundation changes do not constitute acceptance of the eventual richer visual
experience. Name cleanup is coordinated through the Catalog owner; immutable
recording IDs, audio mappings and all29 recordings remain intact.


The earlier foundation clean-name audit used an explicit presentation map, leaving the original
`TRACKS` block byte-identical (all29IDs, source titles, paths, entitlement groups,
loop notes and the Decorate-only exclusion). Displayed songs are Doorway
Sunshine, Lively Lunch, Quiet Table, Harmony, Corner Café, Main Street, Shop
Rhythm, Cloverlight, Fiesta en Flor, Petal Promenade and Sunshine Skip. Harmony
retains both recordings through Default A/B selectors. Premium A/B selectors
keep their original source mapping. The two source-distinct Sunshine Skip
families initially shared the clean base title but remained separate. This
intermediate decision is superseded by the user’s explicit same-name grouping
direction below; both original recordings remain intact.
Main's snapshot title and Decorate explanation use the same display mapping;
this is a text-only change to the playback owner's response. A pre-existing
context fixture assertion was corrected to inspect the actual full tooltip and
short visible disclosure, rather than expecting the tooltip's old prose in the
label. The new panel fixture also checks every visible title, selector, tooltip,
accessible title and each effective playback status for production markers.

Song titles contain only the clean base name. Default A/B and Premium A/B are
separate version controls and metadata lines, never suffixes appended to the song
title. Accessible version buttons announce both the clean song name and the
separate edition so identical recordings remain distinguishable without sight.


## Requested control polish — 2026-10-13, pending visual review

After reviewing the contained foundation, the user requested visible Auto,
a better X button, icon-only playback/track controls, and Version1/Version2
for the paired Harmony recordings. This bounded candidate is separate from
unreviewed illustration experiments. Base song names remain clean; a single
ordinary Default and Premium A/B labels remain unchanged. Native retained vector
marks replace text glyphs for close, previous track, play/pause and next track.
Their tooltip/accessibility names keep the full actions. The close face is a
quiet44px circle with a centered X and an inset keyboard-focus ring. All control
hit targets remain at least44px inside the established wooden-face envelope.
Pricing text, catalog identities, audio, saves and behavior ownership are unchanged.
The already requested richer artwork/motion stage remains separately in progress.


## Premium listening artwork and motion candidate — 2026-10-13

The user explicitly requests a visibly richer Premium edition experience. The
separate candidate keeps Default functional feedback and gives Premium its own
warm-gold record label/selected row, six retained leaf silhouettes on desktop
(two in small artwork slots), a bounded selection unfurl with up to three gold
motes, and a short spring/bevel glint on the activated edition. The unchanged
44px button target does not scale. Short layouts without artwork keep the gold
selection and button response rather than borrowing control space.

The record, tonearm and wood plinth are original native vector artwork within
the listening slot; no world art, texture, camera or pricing copy changes. Only
retained transforms/opacity animate. No geometry is rebuilt by time and no FFT
or invented audio-level display is added. Artwork owns six leaves, three motes
and at most four bounded tweens; one shared edition-feedback layer owns one
replacement tween. Source geometry changes only on layout/palette changes.

Continuous motion is playback-linked, not beat-synchronized: it requires a
visible panel, the shown recording to be effective and playing, and no mute,
zero volume or suspension. A new Premium selection can run its finite selection
flourish even when queued or paused. Pause/mute ease leaves to rest in250ms;
reduced motion and hidden ancestry stop motion immediately. Reduced motion keeps
the completed static Premium illustration and suppresses spring/glint/motes.
Scene teardown releases panel-owned art and tweens; playback remains Main-owned.

Verification must include transformed decorative ink inside both its allocated
artwork slot and the unchanged40/36/40/32 wooden-face envelope, plus label/control
exclusions, repeated selection and hide/reopen, all responsive breakpoints and
actual native motion frames. Headless checks alone do not accept visual quality.
Native Dummy audio supports playback-state evidence only; this candidate does
not establish listening, beat synchronization, real-device touch, canonical
renderer qualification, performance acceptance or publication.


### Composed project configuration

The user's subsequent explicit direction is source audio → editable project
configuration → display, with no in-game administration UI. The composed
[data catalog](music-catalog-config.md) is now the sole source for song names,
song grouping, version labels, tier and audio mapping. Both Sunshine Skip
recordings share one song row with Default/Premium B controls. All29 original
playback IDs and source metadata remain unchanged, including the Decorate-only
recording. There are11 named songs; the visible shelf count is data-derived.
Harmony uses Version1/Version2 and Premium A/B remain separate edition labels.
Future recordings need config entries rather than filename-specific branches.


## Selected Pearlwood prototype — 2026-10-13, not accepted

The user rejected frozen9088e55 as insufficiently Premium and preferred the
ivory/floral Concept2 direction. This authorizes a bounded native prototype,
not exact mockup fidelity, true3D, a new Golden Reference or publication.
The whole board crossfades from the ordinary wood into pearlwood/ivory with
restrained gold edging. A separately layered painted cabinet, five petals,
four leaves, record and native tonearm share a440×360 logical art canvas.
Premium unfolds petals and changes the record into a fixed projected ellipse;
only the circular center label turns. Mesh shaders bend leaf tips while their
roots remain planted. A separate inner-frame vine/leaf layer never covers
controls. Native icons, clean catalog configuration,11songs/all29recordings,
playback ownership and saved preferences remain unchanged.

The paint consists of separate generated transparent PNGs, not a flattened UI
mockup or editable3D model. Named Godot layers and crop/root coordinates remain
editable; the source paint is raster. A small actual Inkscape named-path proof
was saved, reopened, node-edited, saved and exported to transparent PNG, then
imported by Godot4.6.3. That proves the tool route, not graphical authorship of
the whole new composition. PNG identities and sampling limits are recorded in
assets/ui/music_pearlwood/PROVENANCE.json.

The initial native r3 pass produced16 actual frames, all without geometric
content/perimeter overlap. Earlier failed material-property and painter-order
passes are retained. Desktop shows the intended material/flower departure;
short landscape art and perimeter foliage still need stronger presence.
Adapted focused lifecycle/input tests are source-ready but not yet executed for
this checkpoint. Actual transition video, native motion review, mobile/Web
performance and final user visual acceptance remain open. Dummy audio and the
noncanonical llvmpipe renderer cannot establish hearing, beat synchronization
or canonical visual/performance qualification. Existing future-charging copy
was inherited; this art change makes no new pricing decision.


### Corrective refinement after the first native prototype

The user asked to restore the earlier Default color, remove four guide-like
perimeter strokes, add substantial foliage, and slow the transformation. The
orange Default was a confirmed integration regression: moving the original
StyleBoxTexture into a new draw owner omitted the existing HUD soft-material
shader. A dedicated ordinary paint layer now retains that exact shader and
texture treatment, without choosing a replacement tint. It stays opaque below
Premium paint during the blend, avoiding the previous transparency dip.

Content now reserves more foliage space on large screens: desktop insets
64/52/64/46; wide short landscape48/36/48/32; narrow layouts keep40/36/40/32.
Both tiers use the same allocation, so switching tiers never moves controls.
The short landscape player places artwork beside the title/edition column
rather than treating it as a tiny badge. Twenty-eight retained perimeter leaves
form paired curved sprigs within the reserved bands; the four uninterrupted
near-straight edge strokes are removed. The record cabinet appears first, then
petals unfold in stages over1.7seconds; the frame leaves unfold over1.8seconds.
Playback-linked leaf-tip flex leaves roots fixed. Mipmapped filtering is scoped
to the new painted layers; Default keeps its exact existing filter/material.

Current checks and actual corrected native pixels must be recorded against the
next frozen checkpoint. The first5.55-second actual mechanics clip remains
evidence of the earlier translucency/sparse-foliage version, not this correction.

### Continuous original wood successor — 2026-10-13, pending acceptance

The user rejected the two-silhouette board swap and metallic appearance, asked
for smaller visible phone buttons with usable hit targets, and specified physical
retraction of the four original corner clusters before new Premium foliage.
This successor keeps one original 512×158 source StyleBoxTexture and its64px
nine-patch geometry continuously drawn. Default at reveal0 uses the exact
original HUD material and source. Premium applies a matte honeywood stain to
that same source grain; the generated board painting is no longer drawn.

Four source-derived corner meshes share one retained323-vertex grid. Shader
vertices curl toward fixed roots and retract under the opaque rim without
changing leaf opacity. Tiny foliage-hidden source bevel depressions are
reconstructed locally from adjacent original texels during retraction; the
unoccluded rim and Default path stay unchanged. Inset Premium vines/leaves
emerge only after the old clusters have fully retracted at reveal0.64.
Body allocation, original style identity and alpha stay fixed throughout.
Phone control faces/glyphs are smaller while their native44px hit boxes remain.

Ownership: the board owns one original draw control, one wood material, four
corner material/mesh instances and one shared immutable mesh; its finite tween
updates shader parameters, not mesh arrays. Geometry changes only with layout.
Hidden/reduced-motion/paused states settle transitions; interrupted changes
replace the same owner's tween. Existing record/frame ownership remains.

Native evidence is retained outside source in wood-morph-native and
wood-morph-motion checkpoints, with hashes and generated saveguard profiles.
The earlier rim-notch checkpoint remains preserved rather than relabelled.
Focused test results, final inspected pixels and delivery versions are recorded
in the final external handoff. No user acceptance, merge, Web/physical-phone
qualification, canonical performance measurement or release is claimed.
