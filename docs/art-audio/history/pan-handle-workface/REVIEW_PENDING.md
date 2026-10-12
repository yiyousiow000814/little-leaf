# Chef-facing pan handle

The pan has one handle on the same rotated workface used by the chef. It attaches to the existing rim and is drawn behind or in front of the bowl according to depth. Its endpoint includes clearance for the moving head outline and the renderer's antialiasing envelope.

Run `python3 tests/run_integration_candidate.py --output /absolute/new/evidence --only test_pan_handle_workface test_simple_kitchen test_chef_fire test_food_contact`. The handle fixture checks orientation, attachment, layering and the entire cooking cycle's skull/muzzle clearance. Matched native normal/zoom front-view sequences show no new cheek overlap across 288 frames on the integrated source. `tests/check_pan_handle_pixels.py` supplies the pixel-comparison check.

This narrowly corrects the reported backward-facing handle. Separate final-image user acceptance is not claimed. Only `scripts/illustrated_furniture.gd` changes in production. Pan proportions, contact anchors, flame, character art, simulation, handoff and saves remain unchanged. No assets or licenses are added.
