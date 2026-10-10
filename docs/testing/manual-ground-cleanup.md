# Manual ground cleanup

Version 0.1.11 manual cleanup uses the existing ground-work identity and completion
API. A pending tap must begin and end on the same visible painted mess. Pan, zoom,
focus/device cancellation, modal UI, Decorate, Pause, recovery and generation
changes invalidate it. Completion grants no currency or XP. Automatic NPC cleanup
remains authoritative, and a spill beside garbage already carried by an employee
does not settle that employee's custody, disposal timer or reservations.

Successful completion creates at most 32 transient cream puffs, lasting 0.42
seconds in the existing illustration process and ground painter layer. Service or
floor restoration invalidates them; they are never serialized.

Character occlusion queries the current retained painter. It does not repaint a
character, solve a pose, change routing or allocate retained meshes, textures or
nodes. A draw-time projection stamp, matching pre/post draw state and current
state check protect the completed image. Visible stale characters and unsupported
ancestor presentation fail closed. The receipt hashes command arrays, so work is
O(character descendants + geometry content) per completed frame and per query;
this is not a constant-cost or FPS acceptance claim. Mesh resources are treated as
immutable renderer-owned inputs, matching the existing retained painter contract.

The integration runner executes `test_manual_ground_cleanup` against a disposable
profile. Headless runs check the shared custody, duplicate completion and save
API, and explicitly skip real-pointer checks. Native GL Compatibility runs execute
the full input checks after actual completed frames. `test_character_pick_geometry`
uses synthetic command/receipt fixtures and does not establish rendered pixels.
`test_direct_janitor_cleanup` protects the existing automatic path.

`capture_manual_cleanup.gd` requires a native renderer and isolated output. It
captures before, puff at 0.12 seconds and expired at 0.50 seconds at normal and
maximum camera zoom. Keep failed evidence and bind comparisons to exact source
hashes. Owner approval of the query adapter, performance qualification, composed
editor/routing acceptance and user visual acceptance are separate gates.
