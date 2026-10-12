---
name: game-music-production
description: Produce or adapt Little Leaf music and loops from editable source, stems or mixed audio, using musical structure, source review and actual listening. Preserve approved identity and separate musical, technical and runtime acceptance; not a generic SFX or runtime redesign workflow.
---

# Little Leaf music production

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

## Read and establish the task

Read the repository's `AGENTS.md`, current roadmap and
[Audio Bible](../../../docs/art-audio/AUDIO_BIBLE.md). Follow the current Audio owner;
do not create a competing document or revive paused work. Read the applicable owner-approved source/reference record and retrieve its actual
audio/source assets before relying on it. Keep durable principles here and dated
examples, measurements and user decisions in their existing source records.

Record the actual input file/revision/hash, listening capability, approved scope,
retained musical idea and one question this iteration should answer. A title, link,
waveform or score is not proof of having listened. Without audio access, restrict the
claim to symbolic/source analysis and report the missing capability honestly.

Use existing permitted local tools and sounds with no additional fees. Code-based
composition and rendering are allowed; a DAW GUI is not a quality requirement.
Do not buy tools, use paid APIs, rent a GPU or make the user draw/compose by default.
Retain editable events/MIDI/project, instrument configuration and provenance. Recheck
actual tool availability; do not turn an old workstation inventory into a permanent ban.

## Listen, diagnose, then change

1. Listen to the complete short control and reference, then replay the relevant
   phrase. Record what is heard separately from what is measured or inferred.
2. Separate **tempo**, **subdivision/swing**, **note density**, **accent placement**,
   **articulation/envelope**, **register**, **timbre** and **mix balance**. "Too fast"
   does not necessarily mean higher BPM; "strange note" does not prove a pitch error.
3. For uncertain BPM, compare more than one passage, check half/double-time readings
   and align pulse with repeated musical phrases. Report rounded estimates and
   method limits; do not reproduce a tracker's decimal output as authored tempo.
4. Identify instrument *roles and families* before exact instruments. Do not claim
   a specific plugin, SoundFont patch or acoustic instrument from mixed stereo alone.
5. State a concrete hypothesis tied to a timestamp/bar. Keep alternatives alive when
   the evidence does not distinguish harmony, register, articulation or sound source.

## Compose for this piece, not a recipe

- Keep a recognizable motive and design a question/answer, arrival and release.
  Let some phrases rest. A fixed bar count or a hummability score is not a universal rule.
- Audition melody alone, bass plus harmony, then the full arrangement. Inspect sustained
  notes across chord changes, voice leading, register crowding and audible resolutions.
- Chromatic approaches, ninths/thirteenths, repeated ostinatos and bass on beats 1/3
  are allowed. Choose them for audible purpose; do not ban them or insert them by formula.
  In particular, do not automatically fill every bar with "next root minus a semitone".
- Give every layer a role: lead, harmonic support, bass, pulse or occasional answer.
  First make the main parts work; add a layer only when its audible contribution helps.
  A mute comparison is diagnostic, not proof that fewer instruments are always better.
- Shape performance intentionally: phrase-level dynamics, selective legato, real rests,
  appropriate note lengths and clear handoffs. Respect ties and release tails.
  Random timing/velocity jitter is not a substitute for phrasing or a coherent groove.
- Choose timbre in the working register and full mix. Patch labels do not guarantee
  a pleasant attack, sustain or balance. Change instrumentation separately when diagnosing.

## Build a bounded comparison

Start with a short playable phrase appropriate to the question (often 8-16 bars).
Preserve the accepted control. Do not extend a weak idea into a full soundtrack first.

For a **tempo test**, retain pitches, beat positions, instruments, roles and mix chain;
change only the tempo map. Prefer re-rendering from editable events/MIDI; retain intended
millisecond articulations and document treatment of tails. Label any MP3 time-stretch as
an approximate preview because it may change transients. Do not use pitch-shifting rate
changes as a tempo comparison.

For harmony, density or timbre tests, isolate that dimension when practical. When several
changes are combined, label it a bundled comparison and do not claim a single cause.
Use the same phrase and comparable integrated/perceived levels, with peak headroom.
Loudness matching is an audition control, not a universal mastering target. Keep source,
notation and performance MIDI consistent, and identify lead sheets versus full scores.

Apply [game-music-review](../game-music-review/SKILL.md) before user handoff. Provide the
actual audio, source revision, changed dimensions, technical caveats and one focused
choice. Do not claim that an internal textual review or successful export proves taste.

## Loop production for the actual source

Apply the [canonical loop pipeline](../../../docs/art-audio/AUDIO_BIBLE.md#music-loop-production-and-qa):
Source Review → Musical Structure Analysis → Loop Arrangement → Audio Boundary
Processing → Loop Master → Runtime Export → Listening QA → In-game QA.

Before processing, determine whether the asset should loop at all; one-shot
jingles can remain one-shots. Review the actual source and identify phrase/bar,
harmony, melody ending, rhythmic pickup/downbeat, transitions and release tails.
For MIDI/MusicXML/DAW sources, prefer deliberate structural edits and rerendering;
with stems, work on the affected part while retaining alignment/mix identity.
For mixed WAV/FLAC/MP3, identify musical boundaries and state what cannot be
separated or reconstructed. Transcription/separation is estimated evidence.

Choose and justify a method per track: whole bars, ending rearrangement,
transition bars, an authored loop region, structure-aware crossfade, tail wrap
or stem remix. Do not apply a fixed crossfade length, BPM, fade or bar count to
all music. Inspect closing note attacks separately from surviving phrase decay:
wrapping an outro attack into the intro is not merely retaining a reverb tail.
Crossfades must retain rhythm, accents, phrase clarity and phase/level coherence.
A click-free sample join does not make an ending musically compatible.

Preserve immutable originals and approved versions. Do not change approved
melody, tempo, instrumentation or major arrangement without scoped authority.
Necessary structural edits need a separately identified derivative, exact source
and parameters, a recorded change map and an audible original/before/after
comparison. If the existing authored loop needs no edit, reuse it and say so;
creating another version is not mandatory. Scripts may reproduce/batch a chosen
process, but cannot replace per-track musical judgement.

Retain original, lossless loop master, runtime export, editable sources/stems,
method/parameters, dependency/tool versions, provenance/licences and evidence.
Validate actual decoded/exported boundaries rather than assuming container tags
or a DAW marker control the game. Apply both musical and technical acceptance,
then obtain the [required listening/runtime evidence](../../../docs/art-audio/AUDIO_BIBLE.md#loop-acceptance-and-evidence).
Start with one existing owner-approved pilot; do not batch remake or roll out
other tracks before that pilot is verified. Reuse existing permitted tools and
Godot audio runtime; this workflow does not authorize a runtime redesign.

## Retain learning and finish

Record both positive and negative feedback with exact candidate and scope. If the user
likes both A and B, retain both; do not invent a winner or a rule inferred from the
combined changes. Never silently overwrite previously accepted auditions.

Only after a short direction is accepted, extend it, inspect musical joins, listen over
repeated play and test the delivered mix with actual game SFX. Short-excerpt approval,
long-form approval, game integration and publication remain separate decisions.
Follow existing licensing, save, performance and deployment boundaries.

Deliver: listening candidate(s), editable source/MIDI, score where applicable, instrument
manifest, concise change/measurement/listening record and remaining decision. Preserve
originality: use reference groove, role balance and sound character as study inputs,
not its distinctive melody or recording as the new Little Leaf composition.
