# Recording distribution status

The five proposed game recordings are original mixed performances rendered with
TimGM6mb.sf2, SHA256
`c5378b62028c920cb11e4803327983fee2f2cdff5dc89c708e39da417e51c854`.
The bank, extracted sample libraries and authoring binaries are not committed.
This does not by itself resolve the copyright scope of samples in a recording.

The [official Debian bank notice](https://metadata.ftp-master.debian.org/changelogs/main/t/timgm6mb-soundfont/timgm6mb-soundfont_1.3-5_copyright)
identifies GPL-2 and Tim Brechbill/David Bolton. The bank's metadata and notice
do not map the nine used presets to self-created, public-domain or GPL sample
origins, and contain no explicit recording exception. Presets are bank 0
programs 4/24/32/33/12/8/108 and bank 128 programs 0/40, all zero-based.

[GPL-2 section 0](https://www.gnu.org/licenses/old-licenses/gpl-2.0.en.html)
does not license all output automatically; coverage depends on the output's
content. No distribution prohibition was identified, but neither automatic
recording GPL inheritance nor an unconditional recording exception is claimed.
The [author's MIDI-to-WAV/MP3 page](https://www.timbrechbill.com/saxguru/Timidity.php)
supports intended musical use without establishing permissions for every sample.
The [upstream font/document exception](https://raw.githubusercontent.com/musescore/musescore-old/90c33ef9d87b3f5ff92efd3b07d89eb455fb1fef/mscore/COPYING)
does not expressly address TimGM recordings. GeneralUser permission stays scoped
to the existing three game MP3s and cannot be transferred to TimGM.

Before public preservation of the rendered files, complete one specific route:

1. Obtain scoped output-rights clarification covering the exact bank/used
   presets, original mixed recordings in free/commercial games, and any
   underlying GPL sample contributor's applicable conditions.
2. Explicitly choose an audio-specific GPL-2 compliance route where applicable:
   contribution rights, retained notices/full licence, adaptation dates, the
   preferred modification source and qualifying source access for non-source
   distribution. The appropriate source package is not established merely by a
   bank hash or unrelated upstream link. This does not silently license all
   music, source or the whole game under GPL.

The same question applies to the supplied TimGM masters, stems and audition
files, not only the runtime OGGs. Their exact versions/hashes and excluded status
are preserved in the [manifest](SOURCE_PRESERVATION_MANIFEST.json). The user's
musical approval remains intact and distinct from this distribution question.
No rightsholder contact was sent, bank substituted, music regenerated or licence
imposed for this preservation.
