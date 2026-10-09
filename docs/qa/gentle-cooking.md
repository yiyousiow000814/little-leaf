# Gentle covered-pot cooking review

This rendering-only candidate reads the existing cooking job clock and ownership.
It does not alter recipes, service timing, ownership handoffs, or player saves.
The stove-pickup feature independently owns finished-plate placement and removal.
The requested fuller stove top occupies exactly one logical grid tile; the lower
cabinet retains its small edge bevel. Pot/lid proportions and actual hand-grip
contact are coordinated with a .32-tile presentation inset. Logical routing and
collision cells are unchanged.

## Automated checks

Run `tests/test_gentle_cooking.gd`, `tests/test_chef_fire.gd` and
`tests/test_pan_handle_workface.gd` with Godot 4.6.3 in an isolated HOME and
XDG_DATA_HOME. The first two generate their own restaurants and suppress saves.
The existing integration runner includes the chef/fire and pan suites.

## Visual acceptance (pending)

`tests/capture_gentle_cooking.gd` requires native GL, rejects headless mode,
and creates only generated, save-suppressed scenes. Set GENTLE_CAPTURE_OUTPUT
and run `godot --path PROJECT --script tests/capture_gentle_cooking.gd
--audio-driver Dummy --rendering-method gl_compatibility` in an isolated profile.
Run the identical fixture against settled-live baseline2173e827a29b58cdc508bfb4435ee1eddf501a7e
and this candidate, with separate output folders. Review all four rotations,
normal/max zoom, and three work-clock moments. No montage or video is required.
Use the existing CI runner's Xvfb if needed; this cloud workspace has no display.
The current browser CI renders unrelated tutorial/save flows, so its screenshots
are not cooking visual acceptance. Earlier captures lacking live motion updates are invalid for stance acceptance.
The fixture now advances motion every0.1s, asserts the work inset, records logical
and rendered positions, and verifies identical paired camera origins. Three
clock samples are still frames, not realtime/continuous-motion acceptance.

Check hand/shoulder subtlety, lid and pot opposing motion, no exposed ingredients,
no clipping or duplicate foreground lid, and pause/reduced-motion rest. Review
ready-plate appearance and pickup again with the independent pickup feature.
