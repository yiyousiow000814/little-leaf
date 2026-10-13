# Gameplay sound candidates

These four PCM24 WAV derivatives reuse the supplied recordings with the gain
changes in [SFX_DERIVATION.json](SFX_DERIVATION.json). The original files remain
preserved separately. Sample count, rate and channel count are retained; there
is no trimming, EQ, compression, limiting, pitch shift or per-file normalization.

| Event | Source | Gain | Duration |
| --- | --- | --- | --- |
| Cash settlement | `cash_raw.wav` | -17 dB | 1.5 s |
| Successful placement | `SfxPlaceItem.mp3` | -13 dB | 0.418 s |
| Active cooking | `sizzling_hot_oil_in_raw_need_adjusting.wav` | -26 dB | 2.25 s |
| Seated eating | `SfxEating.wav` | -7 dB | 4.650 s |

Cash and placement reuse their existing successful-transaction hooks and SFX
player. UI clicks remain unchanged. Cooking/eating use one additional scene-owned
voice on the same SFX bus, with category-wide entry delays and sparse reminders.
They read service state rather than animation frames, and fade with the near end
of the existing camera range. Pause, Decorate, intro, recovery, background, mute
and zero-volume controls stop reminders and reset their unsaved clocks.

The gain, cue intervals and zoom thresholds are integration candidates requiring
actual in-game listening and user acceptance. Imported playback and platform
qualification are separate from measured PCM levels. Level-up and watering
remain reserved for their future mechanics. Existing music, music selection,
preferences and save formats remain with their current owners.
