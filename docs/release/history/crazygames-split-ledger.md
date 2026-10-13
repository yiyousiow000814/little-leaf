# Latest-source CrazyGames slice

Source: frozen local `08af6a1`, exact tree `f5e0be2`; remote PR66 `b3dc6da`.
Base: recovery/log slice `2138c07` on main `f2f1e8ae`. Old PR55/56 heads are not merged.

## Included
- Exact latest SDK Data adapter and embedded platform shell, including durable receipt projections, account availability/scope invalidation, stale writes, byte limits, and honest platform acceptance without cloud acknowledgement.
- Authority codec export in standalone vault and ordinary embedded vault. No change to ordinary vault storage routes.
- Controller platform acknowledgement, revision validation, dirty-generation protection and platform wording. Inbox snapshot validation remains shared with recovery slice.
- Five-second dirty platform submission policy. Native and ordinary Web retain their prior cadence.
- Platform gameplay/viewport gating and deferred music pack with no double gzip decoding.
- Exact platform export presets and developer-preview build transformation, keys, notice, manifest provenance, failure guards and synthetic isolation suite.
- Shared first-render callback required to dismiss the latest platform loading layer; ordinary Web shell styling is unchanged.
- Separate CI export/artifact added to current main workflow without dropping its existing gates.

## Retained for independent later slices
- Ordinary Web branded loader, approved splash configuration and boot-presentation tests: startup slice. The platform copy of the loader is already preserved here.
- `main.gd` intro motion, live descent and first-arrival hooks; `cafe_intro.gd` and `minimal_start.gd`: startup/first-guest slice.
- Tutorial setup, pointer ownership and tutorial state/helpers: tutorial slice.
- Browser suspend/resume state, visibility lifecycle hook and preferences flush: Web performance slice. This includes the platform gameplay stop on hidden events, which must be retained when composing that slice.
- Controller `_confirmed_payload`, `_inflight_payload`, `skip_unchanged`, and ordinary Web `_autosave`: periodic deduplication performance slice. The preview source-contract test omits only these deferred cache-variable assertions; all SDK route and isolation assertions remain.
- Legacy 3D suppression, stable geometry/path caches, retained rendering/UI and music crossfade stopping: performance slices.
- Decoration session/refund hooks: decoration slice.
- Environment, parking, camera, cleaning and UI visual changes: their respective feature slices.
- Reviewed Firebase source is separate and is not present here.

The machine-readable residual hunk ledger compares this candidate with the frozen source; it is a retention checklist, not permission to drop or wholesale copy mixed files. Latest-source docs replace old checkpoint validation and time-limited authorization claims; no historical receipt is represented as a current test result.
