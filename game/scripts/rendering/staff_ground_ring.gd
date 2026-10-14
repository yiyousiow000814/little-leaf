extends Node2D
## Opt-in ground layer. Caller supplies presentation foot anchors, never actor state.
## Add this layer after rugs and before solids; no gameplay renderer hook is installed.
const MAX_RINGS = 64
# A floor cell has world side1. The circle's INTERNAL diameter is that side;
# its stroke grows outward before the usual ground-plane isometric projection.
const TILE_WORLD_SIDE = 1.0
const INNER_FRACTION = .82
const INNER_RADIUS_WORLD = TILE_WORLD_SIDE * .5
const OUTER_RADIUS_WORLD = INNER_RADIUS_WORLD / INNER_FRACTION
const WORLD_X = Vector2(39.0, 19.5)
const WORLD_Z = Vector2(-39.0, 19.5)
# Projected ellipse half axes are diagnostics only, not the sizing definition.
const RADIUS = Vector2(39.0, 19.5) * 1.4142135623730951 * OUTER_RADIUS_WORLD
const PERIOD_SECONDS = 12.0
var enabled = false
var _rings: Dictionary = {}
var _arcs: Array = []
var _phase = 0.0
static var _geometry: Array = _make_geometry()

class Ring:
	extends Node2D
	var arcs: Array
	func _draw():
		for arc in arcs: draw_colored_polygon(arc, Color(1, 1, 1, .82))

static func _make_geometry() -> Array:
	var geometry: Array = []
	# Unit annular arcs are built once. Rotation precedes isometric flattening.
	for quarter in range(4):
		var arc = PackedVector2Array()
		for i in range(17):
			var angle = quarter * PI * .5 + deg_to_rad(12.0 + 66.0 * i / 16.0)
			arc.append(Vector2(cos(angle), sin(angle)))
		for i in range(16, -1, -1):
			var angle = quarter * PI * .5 + deg_to_rad(12.0 + 66.0 * i / 16.0)
			arc.append(Vector2(cos(angle), sin(angle)) * INNER_FRACTION)
		geometry.append(arc)
	return geometry

func _init():
	_arcs = _geometry
	visible = false

static func _ground_transform(foot_anchor: Vector2, scale_factor: float) -> Transform2D:
	var outer_scale = OUTER_RADIUS_WORLD * scale_factor
	return Transform2D(WORLD_X * outer_scale, WORLD_Z * outer_scale, foot_anchor)

static func placement(foot_anchor: Vector2, visual_seconds: float, scale_factor: float) -> Transform2D:
	var angle = fposmod(visual_seconds, PERIOD_SECONDS) * TAU / PERIOD_SECONDS
	return _ground_transform(foot_anchor, scale_factor) * Transform2D(angle, Vector2.ZERO)

static func paint(artist):
	# For the existing native retained-object painter: static unit geometry,
	# flattened/rotated only by placement, outside all character paint callbacks.
	for arc in _geometry: artist.art_draw_colored_polygon(arc, Color(1, 1, 1, .82))

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
		var projected = _ground_transform(anchor, scale_factor)
		if placement.transform != projected: placement.transform = projected
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
