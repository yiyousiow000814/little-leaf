# Continuous Welcome descent (0.1.10)

The Welcome scene is an automatic, skippable 6.5-second presentation. There is no
separate Start button or waiting menu. Its opening 1.0-second title hold remains
frozen. From the existing descent boundary through arrival, the current frame's
live duration now advances customer/service movement, staff work, character
animation, street pedestrians, visible road traffic and visible bus-stop people.

`CafeIntro.motion_delta` clips the one frame crossing that boundary instead of
replaying the hidden title's elapsed time. Frame stalls greater than one second
produce no world catch-up; the existing intro interruption still lands the
camera immediately. Normal browser suspension and discarded resume deltas remain
in place. Pause, decorating, recovery and undersized-viewport guards still block
live service and ambient motion. Simulation speed applies once through the
normal service and staff update path, while the animation clock remains at its
existing presentation rate.

The intro keeps complete input/skip-gesture ownership and the original camera,
HUD fade, title artwork, timing and once-per-session behavior. Periodic save time
and autosave submission are deferred until the intro ends, including an
already-due periodic save. No save format, offline progression, prices, worker
routes or service rules change. CrazyGames continues reporting loading rather
than playable gameplay until the intro releases player input; lazy music also
keeps its existing gameplay gate.

The welcome headless test exercises the real controller and artist, with generated
visitor and active worker trips. It checks the frozen title, exact elapsed time,
people/traffic motion, guard states, speed, no double ticking or catch-up,
periodic-save deferral, completion and all existing skip/interruption/layout
checks. Run `python3 tests/run_welcome_intro.py` in an isolated test profile, or
include these tests in `tests/run_integration_candidate.py`.

Headless checks establish simulation and presentation-state behavior. They do not
establish rendered smoothness, browser first-paint timing or device performance.
The separate branded boot presentation is documented in `branded-startup-010.md`.
