# Supplied music source preservation

This is the GitHub preservation entry point for the music materials supplied in
the current Little Leaf conversation. It preserves editable source without
changing gameplay or activating a recording. The earlier Sunlit Table study in
this PR remains intact and is separate from this intake.

| Supplied package | Preserved material | Rendered audio |
| --- | --- | --- |
| Music Skills v2 Corrected | [Production skill](../../../../.agents/skills/game-music-production/SKILL.md), [review skill](../../../../.agents/skills/game-music-review/SKILL.md), [companion source](../../reference-studies/music-skills-v2/README.md), reference case/register and analysis scripts | Private RC reference is excluded |
| Corner Cafe Harmony Study A/B | [Original MIDI, lead sheets, events, scripts, metrics and notices](original-harmony-study/) | Original A/B and comparison MP3s remain private |
| 04 Reference Rearrangement | [Original fourth-track MIDI, lead sheet, events, scripts, validation and notices](original-reference-rearrangement/) | Master MP3/FLAC and four stems remain private |
| 112 BPM Loop Package | [Exact supplied loop MIDI, lead sheet, events, mix settings, scripts, validation and notices](source/supplied-fourth-loop/) | Loop WAV/FLAC/OGG, audition MP3s and four stems remain private |
| Main Street and Shop Rhythm Fix | [Both editable track sources and shared authoring material](../mainstreet-shop-rhythmfix/) | Both masters, loops, previews and supplied stems remain private |

The [member-to-path manifest](SOURCE_PRESERVATION_MANIFEST.json) records the five
archive hashes and each public member's SHA256. The 75 original source/document
members are preserved; 72 have exact supplied bytes. Three Music Skills metadata
files replace only the private RC recording checksum. The exact originals and
all full ZIPs are retained locally. A/B technical loop derivatives, their
derivation receipts and authoring scripts are separate from the original study.
Lead sheets remain labelled as lead sheets, not complete orchestral scores.

Original package checksum lists and validation/approval records retain their
creation-time meaning. They may name withheld audio or the unredacted original
metadata. They do not certify that the public subset reconstructs a whole ZIP.
Later explicit user directions accept the fourth arrangement and request Street
as a selectable theme and Shop while Decorate is open. Preserving their source
does not activate those behaviors or assert new listening acceptance.

## Exact audio still awaiting public preservation

The manifest enumerates 40 rendered members withheld from the supplied archives,
plus the five exact proposed runtime OGG identities. No master, stem, comparison,
RC recording, SoundFont, synthesizer binary or font binary is added here.
The [recording distribution status](RECORDING_DISTRIBUTION_STATUS.md) identifies
the remaining TimGM question and the two concrete rights/compliance routes.
Do not delete the local audio, stems, full original ZIPs or dependencies while
these materials are not preserved remotely.

The original three game MP3s and their GeneralUser notices already exist under
`game/assets/audio/`. Their historical editable source/bank gaps remain recorded;
they are not replaced or relabelled by this source preservation.

## Reconstruction boundaries

The source preserves instruments, tempo, note events, delays/gates, mixing and
export parameters as supplied. Required authoring libraries and dependency
identity remain in the original scripts/requirements/notices. No supplied
producer script was executed for this preservation. The exact TimGM bank is a
separate dependency and is not committed; its GPL text is retained under
[source/licenses](source/licenses/GPL-2.0.txt), without relicensing the recordings.

The private frozen integration candidate remains at local `7c3de91`; its actual
native Web analogue/context/decoder checks passed 150/0. That proof covers its
exact local source and the declared native scope. This preservation commit has
no runtime change, browser qualification, canonical atlas adoption, audio
distribution clearance, deployment or release claim.
