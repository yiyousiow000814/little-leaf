extends Node2D
## Opt-in ground layer. Caller supplies presentation foot anchors, never actor state.
## Add this layer after rugs and before solids; no gameplay renderer hook is installed.
const MAX_RINGS = 64
const RADIUS = Vector2(11.0, 4.5)
const PERIOD_SECONDS = 12.0
var enabled = false
var _rings: Dictionary = {}
var _arcs: Array = []
var _phase = 0.0

class Ring:
	extends Node2D
	var arcs: Array
	func _draw():
		for arc in arcs: draw_colored_polygon(arc, Color(1, 1, 1, .82))

func _init():
	# Unit annular arcs are built once. Rotation precedes isometric flattening.
	for half in range(2):
		var arc = PackedVector2Array()
		for i in range(33):
			var angle = half * PI + deg_to_rad(12.0 + 156.0 * i / 32.0)
			arc.append(Vector2(cos(angle), sin(angle)))
		for i in range(32, -1, -1):
			var angle = half * PI + deg_to_rad(12.0 + 156.0 * i / 32.0)
			arc.append(Vector2(cos(angle), sin(angle)) * .87)
		_arcs.append(arc)
	visible = false

func sync_staff(foot_anchors: Dictionary, visual_seconds: float, paused: bool = false, scale_factor: float = 1.0):
	visible = enabled
	if not enabled: return
	if not is_finite(visual_seconds) or not is_finite(scale_factor) or scale_factor <= 0.0: return
	if not paused: _phase = fposmod(visual_seconds, PERIOD_SECONDS) * TAU / PERIOD_SECONDS
	var accepted: Dictionary = {}
	for key in foot_anchors:
		if accepted.size() >= MAX_RINGS: break
		var anchor = foot_anchors[key]
		if not anchor is Vector2 or not anchor.is_finite(): continue
		accepted[key] = true
		if not _rings.has(key):
			var placement = Node2D.new()
			var ring = Ring.new()
			ring.arcs = _arcs
			placement.add_child(ring)
			add_child(placement)
			_rings[key] = placement
		var placement: Node2D = _rings[key]
		if placement.position != anchor: placement.position = anchor
		var projected = RADIUS * scale_factor
		if placement.scale != projected: placement.scale = projected
		var ring: Node2D = placement.get_child(0)
		if ring.rotation != _phase: ring.rotation = _phase
	for key in _rings.keys():
		if not accepted.has(key):
			var placement: Node2D = _rings[key]
			remove_child(placement)
			placement.free()
			_rings.erase(key)

func inventory() -> Dictionary:
	return {"rings": _rings.size(), "arc_arrays": _arcs.size(), "phase": _phase, "enabled": enabled}

func clear():
	for placement in _rings.values():
		remove_child(placement)
		placement.free()
	_rings.clear()
