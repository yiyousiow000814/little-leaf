# Directional chef hat fit

Chef hats use an asymmetric soft crown, curved fitted band, lower contact edge, and directional front/profile/rear construction. Rabbit ear tips keep their exact coordinates and emerge from two explicit openings with inset shadows and a foreground fabric rim. Head bounds include the crown so thought bubbles stay clear.

Only `scripts/directional_character_art.gd` changes in production. Non-chef heads, cache layout, pan, food, spatula, staff behavior, saves and engine configuration are unchanged. This issue is the fitted hat geometry repair; additional rendering clarity when zooming is a separate issue.

Run `python3 tests/run_integration_candidate.py --output /absolute/new/evidence --only test_chef_hat test_chef_fire test_food_contact`. The 182 hat assertions cover exact non-chef preservation, species/views, blinking/blocked variants, ear tips/openings, head bounds, gutter and cache keys. Native all-view/species stills and integrated chef motion were inspected. This does not claim separate final-image user acceptance or resolution of the later zoom-quality report.

`tests/fixtures/chef_hat_before.gd` is a required source fixture: the exact directional-character implementation before this repair, used to assert unrelated heads remain identical. SHA-256: `c3b6bf8713ced6972094eff3fc420e5a630e64cebc0111ca04c3028fc074b308`. The capture and painter scripts use that fixture for reproducible comparisons.

Geometry is original procedural source, with no new external image, font, sound or license. Existing assets and individual license notices are preserved.
