# Customer-path litter and visible meal remnants

Dry litter follows eligible adjacent customer crossings on owned floor. Arrival, checkout walking and departure are eligible; stationary or withdrawn customers, wall crossings, unknown multi-cell jumps, kitchen neighborhoods and staff workfaces are excluded. One drop per visit, a 12-item new-litter cap and neighboring-tile spacing prevent crowding. Existing 24-entry saves and saved spill geometry remain supported.

Meal scraps are larger and darker against the pale floor. Banana and paper drawing is unchanged from the accepted art. Matched native normal/detail comparisons retain identical routes, scene and other pixels.

## Reproducible synthetic fixture

`tests/fixtures/build_litter_legacy_spill.gd` creates the complete `litter_legacy_spill.json` record without reading storage. It uses synthetic mess id 1, guest id 1, cell (4, 6), path step 3 and seed 60, replaying the first shape-generation attempt from frozen `litter_art_v2/cafe_floor_geometry.gd`. The fixture test JSON-roundtrips the generated record and requires full equality with every preserved legacy field and vertex. It includes no real player state.

The frozen v6 art is required for exact preservation and native before/after comparison. These source fixtures are retained; review-only screenshots stay outside the repository.

## Validation

Run `python3 tests/run_integration_candidate.py --output /absolute/new/evidence --only test_customer_litter test_litter_visibility test_role_release test_staff_relocation_service test_floor_availability test_furniture_worker_egress`.

The disposable-profile runner covers traffic, geometry, native-codec save roundtrips, legacy preservation, material boundaries and role/access compatibility. `tests/capture_litter_visibility.gd` is the native generated-scene fixture; use isolated HOME/XDG profiles, suppressed saves and `--skip-intro`.

Only floor tasks, floor geometry and floor mess art change in production. Their bytes match the integrated v7 source. Economy, recipe timing, cleanup roles, assets and license notices are unchanged.
