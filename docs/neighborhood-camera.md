# Neighborhood camera

The manual camera can inspect the world-coordinate square `[-24, 40] × [-24, 40]`: 64 × 64 tiles. Its isometric projection is a diamond; the viewport remains rectangular. This is a camera target envelope, not additional purchasable or walkable land.

The earlier authored ground targets (parking, bus stop/approaches and the fully expanded café) span x = -13.65..18 and z = -8.7..18, or 31.65 × 26.7 tiles. The new square exceeds twice either dimension and approximately 4.85 times that target-envelope area. This comparison is not a claim about the area of any particular viewport screenshot.

Manual zoom-out goes below the previous .70 desktop/.35 compact floor. The new nominal floors are .35 and .25 respectively, and can fall further when needed to fit the neighborhood below the HUD in portrait or short windows. Minimum zoom derives from the projected neighborhood bounds and actual viewport; it does not use a fixed pixel canvas. Home/Fit still frames the café exactly as before. Play and Decorate share the manual camera range and preserve the current view on mode changes. A bounded horizontal allowance prevents the camera from locking at the exact scale where content width matches viewport width.

The original simulation street/pavement limits remain -84..84 and -82..82. Separate render-only coverage extends to -320..320 and -318..318 so the wider overview does not expose abrupt street ends. Existing grass, objects, ownership, furniture, customers and saves are unchanged. The original pavement mesh and stroke rebuild workload are retained; only visible extra background rows are drawn. Tiny overview polygons use normalized coordinates for triangulation, then submit the original vertices and retain their outlines.

## Verification

Run the focused suites with `tests/run_integration_candidate.py`: `test_square_neighborhood_camera`, `test_overview_triangulation`, `test_decorate_camera`, `test_environment_camera_access`, `test_fit_owned_cafe`, `test_background_cache`, `test_ambient_traffic_culling`, `test_render_visibility`, `test_environment`, `test_environment_scope`, and `test_bus_stop`.

These are headless engine checks. Native/browser visual review and GPU frame-time validation are separate acceptance gates. `qa/probe_overview_cpu.gd` reports CPU-side retained-background submission and zoom-stroke rebuild timings only, using generated fixtures and the usual `--visual-qa --fresh-review --skip-intro --skip-tutorial` flags.
