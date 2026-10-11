# Audio Bible

Draft Audio Direction foundation, 2026-10-11. The [canonical roadmap](../roadmap.md#current-state) owns framework priorities, owners and approval status. This document defines the proposed production workflow; it does not accept a soundtrack or authorize a runtime change. **No playable pilot has been produced or approved.** Direction, listening and final mastering decisions remain open.

## Existing baseline and evidence

The audit used source `50dd65f5de1d476019497966206f88cf38cd9c96`; its audio inputs and relevant playback code are unchanged at this document's base `5cfa2f8632592d022b25c9f99c4191f1ce1cefb4`. The three existing MP3s retain their [recorded hashes and provenance](../../game/assets/audio/MUSIC_PROVENANCE_ADDENDUM.json). Offline Godot 4.6.3 decoding measured a 76.8-second repeat for each, without full-scale sample clipping. This establishes neither listening approval nor browser/device output quality; LUFS and true peak were not measured.

Editable compositions, MIDI, stems, lossless masters and the original SoundFont remain absent from the audited repository. Historical filenames are not recovered sources. Preserve the [music notices](../../game/assets/audio/README.md) and [licensing assessment](README.md); GeneralUser GS supplier permission for rendered music is documented, with uncertainty about some historical sample origins and an unverified historical bank checksum.

## Direction and pilot decision

Aim for a warm neighbourhood cafe, space for foreground feedback and comfortable repetition. Compose original material. Do not copy or transcribe Restaurant City melodies, recordings or loops, or substitute a final recording for editable source.

Two **untested alternatives** from the audit await user selection or revision:

| Direction | Original pilot brief |
| --- | --- |
| Window-box morning | Nylon guitar, short clarinet answers, upright bass and sparse brushes; 96 BPM, 4/4, proposed 32-bar / 80-second loop. Brief calls and rests leave room for play; a later busy variation could add rhythm on the same phrase grid. |
| Rain beneath the awning | Gentle piano, woody marimba, bass clarinet and plucked bass; 6/8 at dotted-quarter 72 BPM, proposed 48-bar / 80-second loop. A sheltered, reflective mood with a contrasting middle phrase. |

The gate is: approve one direction and scope, establish a usable permitted toolchain, then produce one editable pilot and review it by ear. Do not create final variants or integrate a pilot before that review. Instrument names describe intent, not licensed assets already available. Timing, arrangement and mix values are proposals, not automatic final standards.

## BGM and SFX production

For BGM, record its intended state, tempo/meter/key, phrase structure and exact loop sample boundaries. Author one coherent theme first; proposed intensity variants should share an intentional musical relationship. Render aligned stems with their release/reverb tails and retain a lossless master before encoding a runtime derivative.

For each SFX, record the actual UI/game event, trigger timing, foreground priority, duration, overlap/voice limit and repeat-rate behavior. Retain the editable synthesis/recording source, parameters and any random seed needed to reproduce it. Review rapid clicks, placement and coin feedback together with music, including whether one event cuts another off. Avoid adding new event sounds as part of a documentation or mastering change.

Each accepted source package must contain:

- Stable asset ID/revision, author/owner, intended state/event and approved brief.
- Reopenable DAW/notation project or deterministic source; MIDI for note-based work, or an explicit reason it is inapplicable; aligned stems and lossless masters where applicable.
- Exact render/export commands, tool/plugin versions and settings; every instrument, SoundFont or sample dependency with source, licence text and checksum.
- Master/runtime hashes, import settings and loop boundaries, plus a recoverable archive location and restore/reopen/export verification. Keep measured, producer-reported and missing evidence distinct.

Do not replace an unknown historical SoundFont hash with a fresh download's hash. Preserve licence notices in exports and the existing historical records. A future replacement needs its own provenance; supplier permission does not establish blanket clearance of the game.

## Tools and export

The 2026-10-11 Windows audit verified existing Godot 4.6.3 for offline decoding and Python 3.14 for hashes/PCM calculations. Scoped PATH, installation and registry checks did not find usable REAPER, MuseScore, Audacity, FluidSynth, FFmpeg/ffprobe or SoX. OBS libraries were present, but no mastering CLI or editable music workflow was verified. Recheck the actual workstation before selecting tools; this is not a claim of universal absence. No purchase, installation or account change is authorized here.

A 48 kHz, 24-bit stereo lossless BGM working master is a **proposed pilot format**. Choose mono/stereo and rate for SFX according to its use; do not automatically convert the existing 22,050 Hz procedural effects. Choose runtime compression through the current import/export path after comparing the decoded result. Preserve existing MP3s, import UIDs and notices until an exact replacement is approved.

Measure decoded duration, clipping, loop join, channel/mono behavior and whole-file/short-term levels. Label PCM RMS and sample peaks accurately; use a verified LUFS/true-peak meter before making mastering claims. The audit suggested 1 dB true-peak headroom and roughly 1 LU between comparable service/busy variants as **unvalidated starting points**. The user-approved in-game mix must determine final targets; these suggestions must not trigger automatic normalization.

## Runtime boundaries and cost

Reuse [main.gd](../../game/scripts/main.gd), [cafe_settings.gd](../../game/scripts/cafe_settings.gd) and the [CrazyGames music pack adapter](../../game/scripts/crazygames_music.gd). Preserve BGM/SFX buses, independent preferences, ordinary browser activation, platform mute and save-write fences. Audio changes must not change jobs, economy or save schema.

Current states are `service`, `busy` and `decorate`; editing currently keeps the current soundtrack and does not select `decorate`. **Whether Decorate mode should use a dedicated BGM track remains an unresolved product decision.** The current implementation does not establish the approved final audio direction. Zero volume mutes the bus, while disabling stops playback. Track selection uses a 15-second state age and a 1.2-second fade. Activating unused music or changing fade/resume/control semantics requires an explicit scoped decision. The audit identified the fade's possible level dip and shared SFX stream interruption as listening questions, not accepted runtime defects.

Prepare/cache audio once, keep voice/resource ownership bounded and retire inactive decoders. Avoid per-frame synthesis or redundant players. Measure startup, CPU and retained-memory impact when the proposed change affects them, following the existing [performance](../testing/rendering-performance.md) and [memory](../testing/memory-regression.md) contracts. Decoder success is not an FPS or memory qualification.

## Listening and acceptance

Review several consecutive joins, first-bar energy, phrase repetition, quiet/default-volume play, mono playback and foreground SFX on a named output device. For affected transitions, listen in both directions and during rapid event overlap. Evaluate comfort, intelligibility and unwanted clicks/dips by ear; a playing flag or successful decode cannot approve them.

Verify the actual imported runtime derivative and affected ordinary-Web/CrazyGames path using disposable profiles: normal activation, enabled/disabled/zero controls, re-enable and platform mute. Reuse existing focused checks for changed behavior. The roadmap records successful welcome functional checks; paused PR114 diagnostics must not be revived without a specific authorized regression question. Preserve original saves and failed evidence.

Keep source recovery, offline measurements, imported/browser playback, listening approval, merge and release as separate results. Retain a compact review receipt with source/tree and asset hashes, source archive, engine/import/meter versions, measured results, listener/date/device/build, accepted direction, concerns and approved next scope. Framework/document approval does not approve unheard audio or authorize production publication.
