# Audio Bible

Draft Audio Direction foundation, 2026-10-11. The [canonical roadmap](../roadmap.md#current-state) owns framework priorities, owners and approval status. This document defines the proposed production workflow; it does not accept a soundtrack or authorize a runtime change. **This foundation does not approve any playable pilot.** Existing direction and listening acceptance follow the latest explicit user decision for the exact audio; final mastering, derived-loop and runtime qualification remain separate. This foundation does not revoke an already accepted recording.

## Existing baseline and evidence

The audit used source `50dd65f5de1d476019497966206f88cf38cd9c96`; its audio inputs and relevant playback code are unchanged at this document's base `5cfa2f8632592d022b25c9f99c4191f1ce1cefb4`. The three existing MP3s retain their [recorded hashes and provenance](../../game/assets/audio/MUSIC_PROVENANCE_ADDENDUM.json). Offline Godot 4.6.3 decoding measured a 76.8-second repeat for each, without full-scale sample clipping. This establishes neither listening approval nor browser/device output quality; LUFS and true peak were not measured.

Editable compositions, MIDI, stems, lossless masters and the original SoundFont remain absent from the audited repository. Historical filenames are not recovered sources. Preserve the [music notices](../../game/assets/audio/README.md) and [licensing assessment](README.md); GeneralUser GS supplier permission for rendered music is documented, with uncertainty about some historical sample origins and an unverified historical bank checksum.

## Direction and pilot decision

Aim for a warm neighbourhood cafe, space for foreground feedback and comfortable repetition. Compose original material. Do not copy or transcribe Restaurant City melodies, recordings or loops, or substitute a final recording for editable source.

The following **untested alternatives** are dated audit proposals, not mandatory directions or replacements for subsequently accepted music:

| Direction | Original pilot brief |
| --- | --- |
| Window-box morning | Nylon guitar, short clarinet answers, upright bass and sparse brushes; 96 BPM, 4/4, proposed 32-bar / 80-second loop. Brief calls and rests leave room for play; a later busy variation could add rhythm on the same phrase grid. |
| Rain beneath the awning | Gentle piano, woody marimba, bass clarinet and plucked bass; 6/8 at dotted-quarter 72 BPM, proposed 48-bar / 80-second loop. A sheltered, reflective mood with a contrasting middle phrase. |

For new creative work, agree the direction and scope, establish a usable permitted toolchain, then produce an editable pilot and review its actual audio. Follow later explicit user authorization when continuing accepted source, loop adaptation or integration; do not reopen creative approval merely because historical metadata remains pending. Instrument names describe intent, not licensed assets already available. Timing, arrangement and mix values are proposals, not automatic final standards.

## BGM and SFX production

For BGM, record its intended state, tempo/meter/key, phrase structure and exact loop sample boundaries. Author one coherent theme first; proposed intensity variants should share an intentional musical relationship. Render aligned stems with their release/reverb tails and retain a lossless master before encoding a runtime derivative.

For each SFX, record the actual UI/game event, trigger timing, foreground priority, duration, overlap/voice limit and repeat-rate behavior. Retain the editable synthesis/recording source, parameters and any random seed needed to reproduce it. Review rapid clicks, placement and coin feedback together with music, including whether one event cuts another off. Avoid adding new event sounds as part of a documentation or mastering change.

Each accepted source package must contain:

- Stable asset ID/revision, author/owner, intended state/event and approved brief.
- Reopenable DAW/notation project or deterministic source; MIDI for note-based work, or an explicit reason it is inapplicable; aligned stems and lossless masters where applicable.
- Exact render/export commands, tool/plugin versions and settings; every instrument, SoundFont or sample dependency with source, licence text and checksum.
- Master/runtime hashes, import settings and loop boundaries, plus a recoverable archive location and restore/reopen/export verification. Keep measured, producer-reported and missing evidence distinct.

Do not replace an unknown historical SoundFont hash with a fresh download's hash. Preserve licence notices in exports and the existing historical records. A future replacement needs its own provenance; supplier permission does not establish blanket clearance of the game.

## Score and arrangement review

Include a score review before audition handoff. Preserve the native editable composition and, where feasible, MusicXML, a readable score export and MIDI in the coordinated repository source location, separate from runtime audio. Bind each revision to its rendered audio SHA256, author, source/tool versions, settings and export command. A score from another trial must never stand in for the current recording.

Inspect melody and harmony, bass movement, exact note/rest durations, ties and legato, beat/accent placement, voice ranges, instrument roles, phrase handoffs, accompaniment continuity, repetition and cadence against the approved brief. Record bar numbers and corresponding audio timestamps, specific findings and the proposed correction. Preserve intended releases and the ending's decay when rendering; a notated duration does not guarantee that generated or sampled audio sustains naturally. A syntactically valid score or in-key note list does not establish a coherent arrangement, convincing performance or a good mix.

Native composition data is authoritative. For audio-only generation, explicitly record absent score, MIDI and stems; a stereo clip project is not a multitrack composition. Any automatic transcription must be labelled **automatically transcribed, unverified**, with source audio hash, excerpt offset, method/model version, settings, confidence/uncertainty and manual corrections. Keep uncertain notes, missing voices and instrument attribution explicit; transcription mistakes are not established composition defects. Compare corrected notation and its playback with the original before relying on it. For example, [Basic Pitch's official guidance](https://github.com/spotify/basic-pitch) says it works best on one instrument at a time; mixed stereo output needs additional review. Missing tools or an unverified transcription must remain a capability gap rather than a fabricated score.

## Music loop production and QA

Apply this source-aware workflow to any permitted music source or tool. First
decide whether the asset should loop; a one-shot jingle need not loop. These
production rules do not approve new audio, revoke an accepted recording or reopen
creative approval for already authorized source, loop adaptation or integration.

1. Source review: identify exact original and approved revisions, hashes, intended
   use, available editable events/MIDI/MusicXML/DAW/stems or mixed audio, tool
   parameters and provenance/licences. Record missing source and listening access.
2. Musical structure: map phrases/bars, harmony, melodic ending or pickup, accents,
   transitions and sounding releases. An inferred transcription is not original
   session evidence.
3. Loop arrangement: justify a track-specific end/start relationship. Preserve
   approved melody, tempo, instrumentation and major arrangement unless the scoped
   change is authorized.
4. Boundary processing: implement exact sample/region boundaries and inspect
   attacks, decay, silence, truncation, level/phase continuity and rhythmic integrity.
5. Loop master: retain an identified lossless result, parameters, dependency/tool
   versions and audible original/before/after comparison. No universal mastering
   target or mandatory new derivative is implied.
6. Runtime export: reuse the supported codec/import path, preserve the master and
   compare the actual decoded export, including padding and resampling effects.
7. Listening QA: compare the exact original, master and decoded candidate across
   repeated complete loops, seams, phrases and tails; keep perception and objective
   measurements distinct.
8. In-game QA: use the existing Godot runtime, default BGM level and actual SFX in
   disposable profiles; verify affected controls, switching and background recovery
   on the relevant target platform without changing playback policy.

Prefer deliberate structural edits and rerendering when editable events exist.
With stems, change the affected part while retaining alignment and mix identity.
For mixed WAV/FLAC/MP3, identify musical boundaries and state what cannot be
isolated or reconstructed. Separation/transcription does not recover an original
session by itself.

Choose whole bars, ending rearrangement, transition bars, an authored loop region,
structure-aware crossfade, tail wrap or stem remix according to the actual track.
Methods may be combined when justified. There is no universal BPM, bar count,
crossfade duration, fade length or sample rate. Distinguish a surviving release
tail from a new closing-note attack: wrapping an outro attack into the intro is
not merely preserving reverb. A click-free splice is not musical acceptance.
An already suitable authored loop may be reused. Scripts reproduce a chosen
process and its provenance; they do not replace musical judgement.

### Loop acceptance and evidence

Record Musical Loop and Technical Loop separately as pass, revise or unassessed.
Musical review covers harmony, melodic ending/pickup, phrase/rhythm, transitions
and repeated naturalness. Technical review covers actual decoded boundaries,
silence/clicks, truncation, level/phase/tails, crossfade rhythm and codec/import
behavior. Neither waveform statistics nor CI establish that anyone heard a loop.

For a loop-listening acceptance claim, actually hear at least three consecutive
complete loops and every intervening seam, with a longer repeat-comfort check
appropriate to intended use. Record reviewer/capability, date, exact files and
hashes, seam timestamps, output device or audio-model scope, playback levels,
findings and limits. An audition file proves its contents, not that it was heard;
do not hide the seam behind an unrelated presentation fade.

Keep default-volume/SFX balance and affected runtime controls, switching in both
directions, rapid changes and focus/background recovery distinct from offline
listening. Mark missing listening or target-platform coverage unassessed, retain
the user's existing exact-recording approval, and continue authorized technical
work. A new derivative still needs its relevant listening and runtime checks.

Retain originals, loop master, runtime export, editable sources/stems where
available, method/parameters, licences and source-bound evidence. Start any
newly authorized pilot with one existing approved source rather than batch
remaking a catalog. No new audio framework, all-project test suite, paid tool,
runtime redesign, gameplay/save change or publication is authorized here.

## Tools and export

The 2026-10-11 Windows audit verified existing Godot 4.6.3 for offline decoding and Python 3.14 for hashes/PCM calculations. Scoped PATH, installation and registry checks did not find usable REAPER, MuseScore, Audacity, FluidSynth, FFmpeg/ffprobe or SoX. OBS libraries were present, but no mastering CLI or editable music workflow was verified. Recheck the actual workstation before selecting tools; this is not a claim of universal absence. No purchase, installation or account change is authorized here.

A 48 kHz, 24-bit stereo lossless BGM working master is a **proposed pilot format**. Choose mono/stereo and rate for SFX according to its use; do not automatically convert the existing 22,050 Hz procedural effects. Choose runtime compression through the current import/export path after comparing the decoded result. Preserve existing MP3s, import UIDs and notices until an exact replacement is approved.

Measure decoded duration, clipping, loop join, channel/mono behavior and whole-file/short-term levels. Label PCM RMS and sample peaks accurately; use a verified LUFS/true-peak meter before making mastering claims. The audit suggested 1 dB true-peak headroom and roughly 1 LU between comparable service/busy variants as **unvalidated starting points**. The user-approved in-game mix must determine final targets; these suggestions must not trigger automatic normalization.

## Runtime boundaries and cost

Reuse [main.gd](../../game/scripts/main.gd), [cafe_settings.gd](../../game/scripts/ui/cafe_settings.gd) and the [CrazyGames music pack adapter](../../game/scripts/platform/crazygames_music.gd). Preserve BGM/SFX buses, independent preferences, ordinary browser activation, platform mute and save-write fences. Audio changes must not change jobs, economy or save schema.

Current states are `service`, `busy` and `decorate`; editing currently keeps the current soundtrack and does not select `decorate`. **Whether Decorate mode should use a dedicated BGM track remains an unresolved product decision.** The current implementation does not establish the approved final audio direction. Zero volume mutes the bus, while disabling stops playback. Track selection uses a 15-second state age and a 1.2-second fade. Activating unused music or changing fade/resume/control semantics requires an explicit scoped decision. The audit identified the fade's possible level dip and shared SFX stream interruption as listening questions, not accepted runtime defects.

Prepare/cache audio once, keep voice/resource ownership bounded and retire inactive decoders. Avoid per-frame synthesis or redundant players. Measure startup, CPU and retained-memory impact when the proposed change affects them, following the existing [performance](../testing/rendering-performance.md) and [memory](../testing/memory-regression.md) contracts. Decoder success is not an FPS or memory qualification.

## Internal musical review before audition

The producer owns whole-track diagnosis before asking the user to approve a candidate. User timestamps are useful hints, not the primary defect-finding method. Review independently where an actual listening reviewer is available; record who or what examined the audio and its demonstrated capability. Text-only peer review and waveform measurements do not count as listening.

Record a concrete finding, timestamp/bar, severity and correction or a justified pass for each of these areas:

- Composition and arrangement: motif, harmony, phrase direction, balance of musical roles, intentional repetition and a suitable cadence.
- Timbre and performance: instrument credibility, attack and sustain, phrasing, dynamics, groove and vitality; performance energy must support the intended emotion. A sunny composition played with listless instruments requires review even when its notes are correct.
- Mix and artifacts: masking, foreground space, stereo/mono balance, noise, harshness, smearing, clicks, distortion and transitions.
- Reference comparison: use permitted, named references for tone and production goals, without copying their music. Record playback level/device and compare the lossless source with the decoded delivery at comparable listening levels; distinguish composition, performance, mix, encoding and playback causes.

Use pass, revise or unassessed with evidence; do not manufacture musical-quality scores from RMS, sample peaks or correlation. Independently inspect the complete track and then relevant excerpts. Technical findings guide listening but cannot certify timbre or emotional coherence. If genuine audio perception is unavailable, mark listening judgement unassessed and identify the capability gap. Continue authorized source, signal and technical work, preserving the user's existing acceptance of the exact recording; those checks must not be presented as listening. The producer remains responsible for technical defect finding and arranging the appropriate review capability. The user decides creative acceptance through actual audition; a new derivative still needs its relevant listening and runtime checks. Keep technical, imported-runtime, merge and release results separate.

## Listening and acceptance

Review several consecutive joins, first-bar energy, phrase repetition, quiet/default-volume play, mono playback and foreground SFX on a named output device. For affected transitions, listen in both directions and during rapid event overlap. Evaluate comfort, intelligibility and unwanted clicks/dips by ear; a playing flag or successful decode cannot approve them.

Verify the actual imported runtime derivative and affected ordinary-Web/CrazyGames path using disposable profiles: normal activation, enabled/disabled/zero controls, re-enable and platform mute. Reuse existing focused checks for changed behavior. The roadmap records successful welcome functional checks; paused PR114 diagnostics must not be revived without a specific authorized regression question. Preserve original saves and failed evidence.

Keep source recovery, offline measurements, imported/browser playback, listening approval, merge and release as separate results. Retain a compact review receipt with source/tree and asset hashes, source archive, engine/import/meter versions, measured results, listener/date/device/build, accepted direction, concerns and approved next scope. Framework/document approval does not approve unheard audio or authorize production publication.
