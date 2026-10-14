# Recording provenance and licence scope

The user explicitly authorized GitHub preservation of the supplied original
music and complete production material (Sentinel_4819f712409c819180da6b347208ef8f).
The previous blanket hold on all40 audio members was an owner's conservative
assumption, not an identified prohibition in the supplied bank notice. It is
withdrawn as a publication precondition. Exact recording versions are preserved
without regenerating them or assigning a new licence to the songs or game.

## Actual production dependency

The A/B, fourth arrangement/loop, Street and Shop production records identify
TimGM6mb.sf2, SHA256
`c5378b62028c920cb11e4803327983fee2f2cdff5dc89c708e39da417e51c854`.
TimGM provides instrument sounds; the supplied MIDI/events contain the musical
writing and arrangement. The bank itself is not redistributed here.

Direct evidence is in A/B `source/metrics.json` and `source/make_study.py`, the
fourth `technical_validation.json`/`source/render_arrangement.py`, the loop
`evidence/loop_validation.json`/`source/build_loop.py`, and Street/Shop validation
and authoring scripts. Their exact file mappings are in the
[manifest](SOURCE_PRESERVATION_MANIFEST.json). Shop retains three original stems
and re-renders only kalimba/percussion. The before/after comparison has declared
V1/V2 provenance, with weaker code-level evidence than the production tracks.

The earlier nine-preset list omitted A's active vibraphone/flute parts. The actual
11 presets are bank0 programs4/8/11/12/24/32/33/73/108 and bank128 programs0/40,
all zero-based. A also contains separately generated shaker noise. Source/data
and individual mixed recordings are not all assigned one licence merely because
the same bank appears in a render chain.

## Bank terms and recording treatment

The [actual supplied notice](original-harmony-study/source/TimGM6mb_package_notice.txt)
and [official Debian source](https://metadata.ftp-master.debian.org/changelogs/main/t/timgm6mb-soundfont/timgm6mb-soundfont_1.3-5_copyright)
identify GPL-2 for `TimGM6mb.sf2` and name Tim Brechbill/David Bolton. Their sample
origin statement is not a per-preset ledger. Keep the notice and
[full bank licence text](source/licenses/GPL-2.0.txt). No notice clause found says
that original recordings must not be published or that separate permission is
always required solely because this bank was used.

[GNU output guidance](https://www.gnu.org/licenses/gpl-faq.en.html#WhatCaseIsOutputGPL)
distinguishes ordinary program output from copied licensed art/audio. Likewise,
[MuseScore's general ownership statement](https://musescore.org/en/node/20202)
concerns scores/exported output and is not a new TimGM-specific exception.
Neither statement justifies automatic GPL inheritance, nor a blanket legal
clearance for all sample content. If a particular copied element is subject to
applicable licence conditions, those remain relevant; this record does not
silently waive them or relicense the user's original contributions.

GeneralUser permission remains scoped to the three pre-existing game MP3s.
Private RC audio/checksum, bank/font binaries and sample libraries are excluded.
Preserved stems are musical production parts, not a repackaged raw SoundFont.
No rightsholder contact, licence election, bank substitution or new music
production occurred for this preservation.
