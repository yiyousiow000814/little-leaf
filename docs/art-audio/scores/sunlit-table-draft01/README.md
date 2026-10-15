# Sunlit Table — original score draft 01

An original eight-bar C-major composition study in 4/4 at quarter = 84, lasting 22.857143 seconds. This is a score-first draft for a warm, bright neighbourhood café; no runtime state is assigned. It does not describe or replace V6, and does not approve either previously proposed Audio Bible direction.

Start with the [readable three-page staff score](sunlit_table_draft01_score.pdf), [editable MusicXML](sunlit_table_draft01.musicxml) and [exact note/rest ledger with bar timestamps](score_readme.txt). The four roles are melody, sparse chord replies, bass and soft wood clicks. Names and GM metadata express orchestration intent; no instrument bank, MIDI, stems or audio is supplied.

The original source package is preserved byte-for-byte here, including its [hash manifest](SHA256SUMS.txt), [authoring source](build_score.py), [event data](score_events.json), [validator](validate_score.py), [provenance](provenance_review.json), [independent symbolic review](independent_review.txt) and [revision history](REVISION_HISTORY.txt). The original ZIP SHA256 is `9c2ec476ab292d8736d27a1094443125098fdfdeeb7aafd9ff457d5a998f7520`. The manifest covers the 18 original payload files; this integration README and scoped `.gitattributes` are additional files. The latter prevents line-ending conversion from breaking source hashes across Windows/Linux checkouts.

## Actual verification and review

Local intake verified ZIP size/CRC, safe members and all 18 manifest hashes. Running the supplied structural validator in a disposable copy passed all 1,034 checks, including 150 event anchors; the archived source and producer evidence were unchanged. Local inspection also checked all three supplied pages and the ending detail. The [producer-supplied independent review](independent_review.txt) found no written-musical blocker and explicitly excludes audio quality.

Preserve the bar-4 D4–F4 accompaniment handoff, bar-5-to-6 descent, bar-6-to-7 tied D5 and final B4–C5 cadence. The last C5 is a half note on beat 1 tied to a quarter on beat 3, then a quarter rest on beat 4. All pitched parts release at 22.142857 seconds; written duration ends at 22.857143 seconds. Future audio must sustain ties and preserve natural release tails rather than hard-cutting to the notated end. This excerpt is not a verified seamless loop.

The bar-7 G5–B4 descending minor sixth remains a conspicuous, deliberate gesture for later performance review. No optional passing note or other compositional revision was made during integration. Authoring-time pending-review wording remains in the PDF/event/validation files; the later provenance and independent review state the completed symbolic-review result.

## Reproduction and remaining gates

Use the existing [Audio Bible](../../AUDIO_BIBLE.md); the producer reviewed its [exact score-review revision](https://github.com/yiyousiow000814/little-leaf/blob/17839b5dc4ce4c2767172d2cee6663d9e24cd0dd/docs/art-audio/AUDIO_BIBLE.md). Read [INTEGRATION.txt](INTEGRATION.txt) before changing or exporting the draft.

Run reproduction in a disposable copy: `python build_score.py`, then `python validate_score.py`. The builder regenerates event, XML, PDF and ledger outputs from its explicit musical data; direct event-file edits must be reconciled into that source before regeneration. Both scripts overwrite generated files, and the validator rewrites the manifest. Preserve the original packet before any revision.

The recorded PDF toolchain is Python 3.12.14 / ReportLab 4.4.9 with NotoMusic and DejaVu fonts at Linux system paths. The PDF is manually laid out staff notation, not a notation-engraver export. Font binaries and checksums are absent, and Windows PDF regeneration has not been verified. [Noto](licenses/Noto-font-license.txt) and [DejaVu](licenses/DejaVu-font-license.txt) licence notices accompany the embedded subsets. The superseded PDF bytes were overwritten during producer regeneration; only their hash and the limitation survive in revision history.

Notation-application import, an independently checked MIDI exporter, intended instrument sources/licences, performance, stems, genuine listening review, mixing and creative acceptance remain open. MIDI is applicable and deferred. A correct score cannot establish lifelike timbre or lively performance. Future sound production needs its own reviewed scope; no audio rendering, runtime asset activation, installation, merge or release is part of this source preservation.
