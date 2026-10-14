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

The original comparison capture remains technically failed on 13 GL shader-cache
save errors in its long disposable Windows profile. The separate corrected
qualification passed 19 feedback and 12 ordinary native GL checks with no engine
diagnostics, observed mixer retirement and eight valid cache files in a short
isolated profile. It recorded no media and retains the original failed evidence.
Four other existing CI fixtures now have the same bounded test-only teardown
repair; their source-bound checks and final current-main/canonical CI are pending.

This focused evidence does not qualify whole-game performance or extended rapid
feedback overlap. Cooking/eating and their near-zoom behavior are preserved for
later work; level-up and watering await their future mechanics.
