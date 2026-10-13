# Cash and placement sound candidate

The two PCM24 WAV derivatives use the supplied recordings with only the gain
changes in [SFX_DERIVATION.json](SFX_DERIVATION.json). Original source files are
preserved separately; sample count, rate and channels are retained.

| Event | Source | Gain | Duration |
| --- | --- | --- | --- |
| Cash settlement | `cash_raw.wav` | -17 dB | 1.5 s |
| Successful placement | `SfxPlaceItem.mp3` | -13 dB | 0.418 s |

The existing successful-transaction hooks, SFX player, bus, voice limit and
enable/volume controls remain in place. UI clicks and music are unchanged.
There are no added voices, clocks, preferences or per-frame work.

Imported playback, rapid feedback overlap, listening comfort and user acceptance
remain separate qualification gates. Cooking/eating and their near-zoom behavior
are preserved for later work; level-up and watering await their future mechanics.
