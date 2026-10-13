# Basic chair ground contact

The basic wooden chair's four leg tips use the same floor-height projection as
four small 2:1 contact shadows. Only the tip height changes from 1 to 0 art pixels;
the seat remains at height 18 and the leg tops remain at height 17.

All contacts are emitted in the existing chair-local pass, before its legs.
A whole-chair presentation transform therefore carries its legs and shadows
along together. No model cell, route, collision footprint, save field, character
pose, furniture style, or table height is changed.

The existing broad 6%-opacity chair shadow remains. Each foot adds a restrained
14%-opacity patch with radii (2.2, 1.1). Their antialiased bounds fit the existing
static chair atlas; there is no extra world-space shadow or stale anchor.

## Verification

- `tests/test_chair_ground_contact.gd` checks four rotations, local offsets,
  floor contact, unchanged seat/upper-leg geometry, atlas bounds, zoom and
  translated whole-chair alignment, and absence of duplicate rail-pass shadows.
- `qa/capture_chair_ground_contact.gd` captures a generated isolated restaurant
  in four directions with empty and occupied chairs. It settles render motion
  before pausing, prevents save writes and verifies zero save calls. Run it with
  an isolated HOME/XDG profile and an OUTPUT directory on a native display.
- Compare the same fixture and cameras on the unmodified parent source and the
  candidate. Native captures do not use or modify an original player profile.

This correction is independent of the separately reviewed natural-dining
prototype; its chair-docking source is not included in the preview baseline.
