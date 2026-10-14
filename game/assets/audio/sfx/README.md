# Cash and placement sound candidate

Cash uses the exact supplied `SfxCash.mp3` selected by the user on 2026-10-14,
with no conversion or gain change. Placementv02 raises only the prior PCM24 candidate by4dB at the user's request. [SFX_DERIVATION.json](SFX_DERIVATION.json) records
both identities; original supplied files and previous candidate evidence remain
preserved separately.

| Event | Source | Gain | Duration |
| --- | --- | --- | --- |
| Cash settlement | `SfxCash.mp3` | unchanged | supplied MP3; measured decode 1.620 s |
| Successful placement | `SfxPlaceItem.mp3` | -9 dB cumulative (+4 dB from v01) | 0.418 s |

The existing successful-transaction hooks, SFX player, bus, voice limit and
enable/volume controls remain in place. UI clicks and music are unchanged.
There are no added voices, clocks, preferences or per-frame work.

The selected cash MP3 and placementv02 were imported and triggered by the actual
game fixture: all 11 functional checks passed. The user accepted the exact
placement +4 dB comparison on 2026-10-14. Both comparison windows use actual
game PCM at BGM70/SFX55 without additional gain or processing; no samples clip.
The accepted placement runtime SHA256 is
`c4efec5d7489b902e81e26669834fdec0de4f4f35101041699390dced2ef2098`.

The capture remains technically failed because its disposable Windows profile
reported 13 GL shader-cache save errors. Cache-path qualification and the five
CI shutdown-resource diagnostics remain open. Hearing acceptance does not waive
those checks or authorize a release.

Imported playback, rapid feedback overlap and listening comfort remain separate
qualification gates. Cooking/eating and their near-zoom behavior
are preserved for later work; level-up and watering await their future mechanics.
