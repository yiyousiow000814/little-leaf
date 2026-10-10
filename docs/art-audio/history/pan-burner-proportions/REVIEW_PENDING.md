# Pan proportions and simplified cooking presentation

The centered pan and burner are wider, and the projected rim is deeper. The range cabinet, countertop, one-tile footprint, food-contact center and cooking height remain unchanged. The unused worktop plate and staged plating gesture are removed; ingredients remain in the pan until the existing ready-meal handoff, then travel with the chef to the counter.

This implements the accepted larger-pan/no-empty-worktop-plate preview. Run `python3 tests/run_integration_candidate.py --output /absolute/new/evidence --only test_simple_kitchen test_chef_fire test_food_contact`. Coverage includes absence of the plate, unchanged handoff, base/upgraded meals and no duplicate food ownership. Integrated native cooking and handoff sequences subsequently passed on this same production logic.

No new animation state, recipe delay, ownership state, save behavior, source asset or license is introduced. The handle-direction correction is a separate following issue.
