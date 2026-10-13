# Supplied music and production source preservation

This is the GitHub preservation entry point for the five music packages supplied
in the current Little Leaf conversation. Exact original audio and editable
production material are preserved through the existing PR228. The earlier Sunlit
Table study stays unchanged and remains separate from this intake.

| Supplied package | Preserved source and audio |
| --- | --- |
| Music Skills v2 Corrected | [Production skill](../../../../.agents/skills/game-music-production/SKILL.md), [review skill](../../../../.agents/skills/game-music-review/SKILL.md), [companion material](../../reference-studies/music-skills-v2/README.md), analysis, case/register; private RC reference excluded |
| Harmony Study A/B | [Exact original MP3s/comparison, MIDI, lead sheets, events, scripts, metrics and notices](original-harmony-study/) |
| 04 Reference Rearrangement | [Exact original master MP3/FLAC, four stems, MIDI, lead sheet, events, scripts and notices](original-reference-rearrangement/) |
| 112 BPM Loop Package | [Exact supplied loop WAV/FLAC/OGG, auditions, four stems, MIDI, lead sheet, events, mix settings and scripts](source/supplied-fourth-loop/) |
| Main Street and Shop Rhythm Fix | [Exact original masters, loops, previews, stems and complete editable source](../mainstreet-shop-rhythmfix/) |

The [member-to-path manifest](SOURCE_PRESERVATION_MANIFEST.json) identifies all
five original ZIP hashes, 75 supplied non-audio members and all 40 supplied audio
members. Every audio byte is unchanged. Of the 75 non-audio members, 72 retain
exact original bytes; three metadata copies redact only the private RC recording
checksum. Full ZIPs and exact originals remain local. Public mapped files are
not a claim that the original ZIP container bytes were uploaded.

The existing A/B-v3 technical derivatives are separate from the original study:
[masters, WAV/OGG, auditions and stems](technical-AB-v3/), matching their preserved
derivation receipts. Five exact runtime OGG aliases are under
`game/assets/audio/`; all other production audio stays outside `game/`.
Lead sheets remain labelled as lead sheets, not full scores. Original approval,
validation and checksum records retain their creation-time meaning. Later user
decisions take precedence and are reflected in the canonical reference register.

## Provenance and excluded dependencies

[Recording provenance and licence scope](RECORDING_DISTRIBUTION_STATUS.md)
corrects the earlier blanket hold. The bank notice does not state a prohibition
on original recordings. Production use is recorded per file; it does not by
itself establish automatic GPL inheritance or an unconditional legal clearance.
The actual TimGM notice and full GPL text for that dependency are retained.
No new licence is imposed on the user's music or the game.

Private RC audio/checksum, raw SoundFont/font binaries and authoring executables
are excluded. No local original is deleted or overwritten. The original three
game MP3s and their GeneralUser records remain unchanged, with their historical
editable-source/bank gaps still recorded separately.

## Storage and reconstruction

The largest supplied audio file is 13,608,044 bytes (about13 MiB). Existing regular
Git asset storage is used; no LFS is introduced. Audio aliases share identical
Git blobs. Source preserves tempo, notes, instruments, performance delays/gates,
mix and export parameters. No producer, encoder, decoder, engine or model is run
for preservation. Rebuilding requires the separately identified lawful local
bank and authoring dependencies; these are not embedded in the source archive.

The frozen local integration candidate7c3de91 and its actual150/0 native outcome
remain intact. This preservation adds assets/provenance only: Main, Settings,
catalog, platform playback code, import controls, export settings and source
guards are unchanged. Runtime activation, canonical qualification, browser,
actual audition, export acceptance, merge, deployment and release remain separate.
