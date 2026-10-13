# Restore the original shared camera range

The latest request is to use the existing normal Play-mode drag limits in
Decorate. It supersedes the earlier edge-centering and distant-material-endpoint
interpretations. Neither a new scene rectangle nor wider street/grass travel is
part of this change.

The known pre-change source is `0dd4db11`. Its `cafe_camera_bounds.gd` and the
`exterior_environment.gd::inspection_bounds` function are restored exactly.
Play and Decorate continue to share that function, at the same viewport and zoom.
The screenshot supplied with the clarification has no readable version number,
so it is not claimed to identify an exact live build commit.

Other fixes, including offscreen curved-pavement clipping, remain intact. The
rejected test that required distant material endpoints to be reachable is removed.
The replacement regression compares against the frozen pre-change range oracle,
checks Play/Decorate mode transitions, and verifies no road cutoff enters the
viewport at the tested original-Play zoom levels and drag extrema. Existing
cafe Fit, mouse/touch environment access, and model/save tests remain applicable.
