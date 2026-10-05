# Furniture edits during guest departure

An unrelated furniture edit preserves a valid guest route that has already reached the outside doorway. Validation still checks the remaining route against walls and the guest body sweep; it does not project a valid outside segment back onto an interior floor cell.

Run `python3 tests/run_integration_candidate.py --output /absolute/new/evidence --only test_departing_route_edit test_departing_route_service test_floor_availability test_furniture_worker_egress test_staff_relocation_service test_role_release`.

Tests use generated guests and disposable profiles. They cover boundary-adjacent positions, retained payment and route state, continuous next movement, blocked geometry, completion and cleanup ownership. Integrated native evidence also exercised the real edit controller at the west-boundary epsilon and confirmed one commit with unchanged guest and wallet state.

Only `scripts/cafe_model.gd` changes in production. No new assets, licenses, save contract or economy changes are introduced.
