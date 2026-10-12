# Audio Bible

Draft Audio Direction foundation, 2026-10-11. The [canonical roadmap](../roadmap.md#current-state) owns framework priorities, owners and approval status. This document defines the proposed production workflow; it does not accept a soundtrack or authorize a runtime change. **This foundation does not approve any playable pilot.** Existing direction and listening acceptance follow the latest explicit user decision for the exact audio; final mastering, derived-loop and runtime qualification remain separate. This foundation does not revoke an already accepted recording.

For executable music work, use [game-music-production](../../.agents/skills/game-music-production/SKILL.md)
and [game-music-review](../../.agents/skills/game-music-review/SKILL.md). Dated track
choices belong in their existing source/owner records, not in universal rules.

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

## Tools and export

The 2026-10-11 Windows audit verified existing Godot 4.6.3 for offline decoding and Python 3.14 for hashes/PCM calculations. Scoped PATH, installation and registry checks did not find usable REAPER, MuseScore, Audacity, FluidSynth, FFmpeg/ffprobe or SoX. OBS libraries were present, but no mastering CLI or editable music workflow was verified. Recheck the actual workstation before selecting tools; this is not a claim of universal absence. No purchase, installation or account change is authorized here.

A 48 kHz, 24-bit stereo lossless BGM working master is a **proposed pilot format**. Choose mono/stereo and rate for SFX according to its use; do not automatically convert the existing 22,050 Hz procedural effects. Choose runtime compression through the current import/export path after comparing the decoded result. Preserve existing MP3s, import UIDs and notices until an exact replacement is approved.

Measure decoded duration, clipping, loop join, channel/mono behavior and whole-file/short-term levels. Label PCM RMS and sample peaks accurately; use a verified LUFS/true-peak meter before making mastering claims. The audit suggested 1 dB true-peak headroom and roughly 1 LU between comparable service/busy variants as **unvalidated starting points**. The user-approved in-game mix must determine final targets; these suggestions must not trigger automatic normalization.

## Music loop production and QA

This standard applies to any music source or permitted production tool. Determine
whether the intended asset is looping music or a one-shot jingle first; a one-shot
need not loop. Preserve approved identity and exact versions. Start with one
existing owner-approved pilot, then verify it before batch remaking or rolling out
other tracks. The workflow and its documentation do not themselves approve audio.

Source Review → Musical Structure Analysis → Loop Arrangement → Audio Boundary
Processing → Loop Master → Runtime Export → Listening QA → In-game QA.

| Stage | Required result |
| --- | --- |
| Source Review | Identify original/approved revisions and hashes, intended use, actual available MIDI/MusicXML/DAW/stems/mixed audio, parameters and provenance/licences; record missing source and listening capability. |
| Musical Structure Analysis | Map harmony, melodic ending/pickup, phrase/bar structure, accents/rhythm, transition intent and sounding releases. Source notation and inferred transcription have different authority. |
| Loop Arrangement | Choose a track-specific method and justify the musical end/start relationship; retain approved melody, tempo, instrumentation and major arrangement unless a scoped change is authorized. |
| Audio Boundary Processing | Implement the approved arrangement at exact sample/region boundaries; inspect attacks, decay, silence, clicks/truncation, level/phase and any crossfade's effect on rhythm. |
| Loop Master | Retain an identified lossless result with chosen rate/channels, boundaries, parameters, original/before/after comparison and source dependency/tool versions. No universal normalization target is implied. |
| Runtime Export | Use the existing supported codec/import path, preserve the master, and compare the actual decoded export and loop behavior; account for encoder padding, resampling and platform behavior. |
| Listening QA | Compare the original, master and decoded runtime candidate; listen to at least three consecutive full loops and every seam, phrase/rhythm/tail, plus longer repeat comfort. Record actual perception separately from objective measures. |
| In-game QA | Use the existing Godot4.6.3 runtime with default BGM volume and actual SFX; verify loop/control/switch/background recovery and applicable target-platform behavior in disposable profiles. |

Prefer structure edits and rerendering when MIDI/MusicXML/DAW material exists.
With stems, revise only the affected parts while keeping alignment, effects and
mix identity explicit. For mixed WAV/FLAC/MP3, locate musical boundaries first
and transparently state limits on isolated-note/instrument/tail repair. Automatic
transcription or source separation does not recover an original session by itself.

| Possible method | Selection question |
| --- | --- |
| Whole bars | Do the phrase, harmony and rhythmic pickup already return naturally at the chosen boundary? |
| Ending rearrangement | Is an intentional cadence/outro incompatible with return? Preserve identity and obtain scoped authority for changed musical events. |
| Transition bars | Does a named connective passage solve a phrase/energy transition better than forcing a sample splice? |
| Authored loop region | Can intro/outro remain separate while a defined internal region repeats naturally? |
| Structure-aware crossfade | Are overlapping harmony/accents compatible, and does the overlap retain pulse, phase and levels? |
| Tail wrap | Are only valid releases/reverb being folded, rather than new closing attacks or an incompatible phrase? |
| Stem remix | Can an affected part be repaired while unchanged parts and the approved mix remain aligned? |

Methods may be combined when justified. There is no mandatory crossfade duration,
BPM, fade length, bar count or master sample rate. A technical sample join cannot
replace musical arrangement. Necessary structural changes require a separately
identified derivative and audible before/after; an already suitable authored loop
may be reused without manufacturing a new version. Reproduction/batch scripts
assist execution and provenance, not per-track judgement.

### Loop acceptance and evidence

Record **Musical Loop** and **Technical Loop** acceptance separately, with pass,
revise or unassessed for each relevant observation. Musical acceptance covers
harmony, melodic ending, phrase/rhythm, transitions and repeated naturalness.
Technical acceptance covers actual decoded sample boundaries, silence/clicks,
truncation, levels/phase/tails, rhythm-preserving crossfade and decode/import
verification. No waveform statistic, correlation, CI run or playing flag proves
that a listener heard a natural musical loop.

Each candidate requires the exact original comparison, at least three actual
consecutive listening loops and every seam encountered, phrase/rhythm/tail
review, default in-game volume with SFX, longer repeat comfort and target-platform
runtime playback. Record reviewer capability/identity, time, device or model
scope, levels, exact hashes, seam/bar timestamps, findings and limits. Presentation
clips must not hide the tested seam behind an unrelated outer fade. If a needed
listening or target-platform capability is absent, retain completed technical
work and explicitly mark the corresponding acceptance unassessed.

Keep original, loop master, runtime export, editable source/stems, method and
parameters, provenance/licences and objective/subjective evidence recoverable.
Reuse existing audio players, buses, preferences, switching/fade policy and
background recovery; music production does not authorize redesigning that
runtime or changing jobs, economy or save schema. New local engine/browser work
uses the existing coordinated finite QA lane and must not delay urgent diagnosis.

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
