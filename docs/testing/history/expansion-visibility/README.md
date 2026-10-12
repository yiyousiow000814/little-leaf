# Expansion rings, sale signs and prices

The entire first geometric ring remains visible in Decorate, including the initially purchase-locked diagonal corner. Later plots appear when the existing stage and adjacency rules unlock them. Owned ground and its camera bounds remain intact.

A shared geometric-ring helper measures the right/front distance from the starter footprint. The existing 10,000 / 18,000 / 30,000 schedule now uses that ring for every direction. Only corner_1 changes price: it is in the second geometric ring even though its storage row is zero, so its displayed and charged price is 18,000. Saved wallets and ownership are not recomputed or charged retroactively.

Procedural scenery trees on visible sale plots are temporarily hidden while Decorate shows the plots. They return on unowned land outside Decorate. Signs and hit testing use each plot's center. This does not remove player furniture or mutate save data.

## Verification

Run `python3 tests/run_expansion_visibility_native.py` with Godot 4.6.3 installed. The runner imports and tests a disposable project with isolated user directories. The synthetic checks cover all 24 parcel identities, unchanged progression and ownership, initial/expanded camera bounds, tree visibility, centered signs, all quoted/charged prices and historical wallet round trips.

The accepted initial and progressed native comparisons were reviewed separately. No image payload or player data is included here. Browser rendering remains unverified.
