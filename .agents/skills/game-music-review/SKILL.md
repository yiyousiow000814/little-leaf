---
name: game-music-review
description: Review Little Leaf music and loops through actual listening, source analysis and controlled original/candidate comparisons. Record musical-loop and technical-loop acceptance separately, including repeated seams and game/SFX context; never certify hearing or taste from CI alone.
---

# Little Leaf music review

## Reference identity and latest feedback come first

Use the exact owner-approved source/control and the applicable reference register
or dated case record where available. Match actual file hashes and excerpt boundaries.
A liked excerpt does not approve its parent composition, other renders, or a ZIP
with a similar name. Preserve the exact approved-control bytes. Never mark a new
candidate accepted merely because it was rendered after reference analysis.

Keep dated track choices, positive/rejected references and excerpt boundaries in
the applicable owner record. Do not turn one track, source service, sound library,
BPM, crossfade or accepted comparison into a permanent rule for other music.

A revision must state what was deliberately preserved: the recognizable phrase,
working instrumentation, groove and/or register. Do not discard those features
merely to make the reference influence stronger. If changing several dimensions,
retain an audible control and call the experiment bundled. Missing original
control audio blocks claims of successful matched-reference review, not useful
source analysis. Private external reference recordings remain study inputs outside game assets.

Read the [Audio Bible](../../../docs/art-audio/AUDIO_BIBLE.md), current task authority
and the applicable owner-approved source/reference record.
Use the exact supplied control/candidate audio and composition source, not a similarly
named render or a recreated file presented as the same recording.

## Establish the evidence boundary

Record which reviewer actually perceived which audio segment. An audio-capable model may
supply listening observations; a text-only peer, notation engine, waveform graph or meter
may not claim it listened. Do not invent a listening device or physical-speaker test.
Without genuine audio perception, mark musical judgement unassessed, preserve useful
technical work, and identify the actual listening capability/reviewer needed.

The producer remains responsible for internal defect finding. The user chooses creative
direction; do not ask the user to locate every broken note before doing any review.

## Review in three passes

**Pass 1: the whole audible phrase.** At a comfortable, recorded comparison level, listen
for immediate tone, musical direction, intrusive accents and the sense of motion.
Do not start with the score's complexity or instrument count as a quality proxy.

**Pass 2: local diagnosis.** Revisit the timestamp/bar, using available stems or deliberate
mutes of our own arrangement. Check the relevant source events and identify which layer
is contributing. For mixed references, separated stems or transcriptions are estimates,
not original session evidence. Confirm suspected note faults against audio before editing.

**Pass 3: context.** Compare with the retained control and legitimate style reference at
comparable loudness. Check phrase handoffs and multiple joins. For a full-track or
in-game claim, actually inspect those longer/contextual conditions; do not transfer a
20-second audition to a 20-minute comfort claim.

## Diagnostic questions, not rigid musical laws

| Complaint | Check before changing | Suitable bounded comparison |
| --- | --- | --- |
| Too fast / restless | BPM and half-time reading, note density, constant high subdivisions, loud accents, short gates | Same-source tempo-only render, OR density-only render; state which |
| Strange / forced notes | Audible melodic intent, tension/resolution, chord transition, register, doubled tones, instrument envelope | Replay melody and harmonic bed separately; revise the identified event, not all chromatic notes |
| Mechanical | Phrase dynamics, articulation, complementary timing, variation at phrase boundaries | Purposeful articulation/groove change at fixed pitch and tempo |
| Thin / cheap / harsh | Actual patch in used register, attack, sustain, band balance, clipping and masking | Timbre-only or mix-only comparison with level control |
| Repetitive | Whether the loop is pleasant, phrase shape, listener fatigue, lack of meaningful contrast | Retain stable groove; change one phrase response or register, not randomize every bar |
| Too busy | Competing foreground parts, fills over the lead, excessive transient density | Mute/reduce specific competing layer; preserve a control |

Simple harmony, repeated accompaniment, bass on beats 1/3, complex harmony and chromatic
approaches are neither automatic passes nor failures. Judge how they sound in context.
There is no rule that the reference tempo must be slower when it feels more relaxed.

## A/B controls and records

Match the musical passage, instrumentation and source as required by the tested variable.
Keep gain-only audition alignment distinct from creative compression/EQ. Check peak
headroom; document any limiting or time-stretch that might confound the comparison.
For our own events, source/MIDI tempo is stronger evidence than an MP3 estimator.
For a mixed reference, check multiple windows and half/double tempo before reporting BPM.

Use a concise record, not an automatically computed "music quality" score:

- Candidate/control IDs + audio hashes; actual scope and observed timestamps.
- What changed, what stayed fixed, and whether this was single-variable or bundled.
- Measurement(s), method and uncertainty; keep metrics distinct from perception.
- For each relevant issue: concrete observation, bar/time, consequence and smallest fix.
- Reviewer recommendation: proceed / revise / unassessed.
- Exact user feedback and scope: positive direction / preferred comparison / final mix /
  in-game acceptance. Do not invent a winner, infer approval from silence or overwrite history.

## Musical and technical loop acceptance

Use the [canonical loop pipeline and acceptance](../../../docs/art-audio/AUDIO_BIBLE.md#music-loop-production-and-qa).
Record two separate conclusions, each pass/revise/unassessed with its evidence:

- Musical Loop: end/start harmony, melodic ending/pickup, phrase and rhythm,
  transitions, intended tension/resolution and repeated naturalness. A source
  chart helps diagnosis; actual repeated listening establishes the audible result.
- Technical Loop: exact decoded sample/loop regions, unwanted silence, clicks,
  truncation, level/phase continuity, attack/release/reverb tails, rhythmic integrity
  of any crossfade, and runtime codec/import decode behavior. Metrics and listening
  findings remain distinct; a finite waveform or low seam step is not a full pass.

Compare the exact original and candidate, then actually listen to at least three
consecutive full loops and every end/start seam encountered. Inspect phrases,
accents and tails; include a longer repeat-comfort check appropriate to intended
use. Record listener/capability, dates, exact files, seam timestamps, output device
or audio-model scope, playback levels, findings and limitations. A rendered
three-cycle audition file proves its contents, not that anyone heard it.

Review default game BGM volume with real SFX and target-platform playback,
including looping, volume/enable/zero, switching in both directions, rapid
changes, focus/background recovery and applicable platform mute. Reuse the
existing Godot runtime and focused QA with disposable profiles. Do not infer
in-game or cross-platform acceptance from offline decode or silent headless flags.
Keep unresolved actual listening separate from useful completed source/signal work.
Do not claim a longer comfort result from a short audition or a one-shot jingle.

## Gates

Check decode, finite samples, obvious clipping/clicks, tails/joins, sample rate and source
identity with existing tools. Follow the existing pipeline for licensing and runtime
control/SFX interaction. Do not create a new all-project audio CI suite.

A technical pass cannot prove groove, pleasure, timbre realism or emotional fit. Likewise,
"I like it" does not establish the final loop, safe mix, performance or publication.
Keep short positive reference excerpts accessible to the working agents; a hash without
retrievable audio is not an effective listening reference.

If both alternatives are liked, preserve both as scoped positive references and identify
the remaining question. Update dated evidence, not the permanent musical rules, from
that one comparison. New music still needs a fresh relevant audition.
