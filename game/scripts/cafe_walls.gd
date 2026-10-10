extends RefCounted
## Pure grid-edge geometry shared by placement, routing, save validation and art.
## A segment starts at (x,z), extends one tile along axis x or z, and has a
## centered .16-tile physical thickness. Half walls block bodies just like full.
const THICKNESS := 0.16
const BODY_RADIUS := 0.23
const HEIGHTS := ["half", "full"]
const MATERIALS := ["sage_panels", "cream_stripe", "leaf_print"]
const PRICES := {"half": 35, "full": 55}
const HEIGHT_PIXELS := {"half": 58.0, "full": 128.0}

static func key(axis: String, x: int, z: int) -> String:
	return "%s:%d:%d" % [axis, x, z]

static func make(axis: String, x: int, z: int, height: String = "full", material: String = "sage_panels") -> Dictionary:
	return {"axis": axis, "x": x, "z": z, "height": height, "material": material}

static func key_of(wall: Dictionary) -> String:
	return key(str(wall.axis), int(wall.x), int(wall.z))

static func endpoints(wall: Dictionary) -> Array[Vector2]:
	var a := Vector2(float(wall.x), float(wall.z))
	return [a, a + (Vector2.RIGHT if wall.axis == "x" else Vector2.DOWN)]

static func adjacent_cells(wall: Dictionary) -> Array[Vector2i]:
	var cell := Vector2i(int(wall.x), int(wall.z))
	var result:Array[Vector2i]=[cell + (Vector2i.UP if wall.axis == "x" else Vector2i.LEFT), cell]
	return result

static func edge_between(a: Vector2i, b: Vector2i) -> String:
	if absi(a.x-b.x) + absi(a.y-b.y) != 1:
		return ""
	return key("z", maxi(a.x,b.x), a.y) if a.x != b.x else key("x", a.x, maxi(a.y,b.y))

static func nearest_edge(point: Vector2, preferred_axis: String = "") -> Dictionary:
	var axis := preferred_axis
	if axis not in ["x","z"]:
		axis = "x" if absf(point.y-roundf(point.y)) <= absf(point.x-roundf(point.x)) else "z"
	return make(axis, floori(point.x) if axis == "x" else roundi(point.x), roundi(point.y) if axis == "x" else floori(point.y))

static func body_touches(wall: Dictionary, point: Vector2, radius: float = BODY_RADIUS) -> bool:
	var ends := endpoints(wall)
	return Geometry2D.get_closest_point_to_segment(point, ends[0], ends[1]).distance_to(point) < radius + THICKNESS*.5 - .00001

static func crosses(wall: Dictionary, a: Vector2, b: Vector2) -> bool:
	# Exact segment/barrier crossing, including its solid thickness. Both
	# ordinary grid moves and short working/retreat moves share this test.
	var low_x:=float(wall.x)-(THICKNESS*.5 if wall.axis=="z" else 0.0)
	var high_x:=float(wall.x)+(THICKNESS*.5 if wall.axis=="z" else 1.0)
	var low_z:=float(wall.z)-(THICKNESS*.5 if wall.axis=="x" else 0.0)
	var high_z:=float(wall.z)+(THICKNESS*.5 if wall.axis=="x" else 1.0)
	if maxf(a.x,b.x)<=low_x+.000001 or minf(a.x,b.x)>=high_x-.000001 or maxf(a.y,b.y)<=low_z+.000001 or minf(a.y,b.y)>=high_z-.000001:return false
	var delta:=b-a
	var t_min:=0.0
	var t_max:=1.0
	if absf(delta.x)>.000001:
		var t0:=(low_x-a.x)/delta.x
		var t1:=(high_x-a.x)/delta.x
		t_min=maxf(t_min,minf(t0,t1));t_max=minf(t_max,maxf(t0,t1))
	if absf(delta.y)>.000001:
		var t0:=(low_z-a.y)/delta.y
		var t1:=(high_z-a.y)/delta.y
		t_min=maxf(t_min,minf(t0,t1));t_max=minf(t_max,maxf(t0,t1))
	return t_min<t_max-.000001 and t_max>.000001 and t_min<1.0-.000001

static func valid_shape(raw: Variant, max_width: int, max_depth: int) -> bool:
	if not raw is Dictionary:return false
	if raw.get("axis") not in ["x","z"] or raw.get("height") not in HEIGHTS or raw.get("material") not in MATERIALS:return false
	for field in ["x","z"]:
		var number=raw.get(field)
		if not (number is int or number is float) or not is_finite(float(number)) or float(number)!=floorf(float(number)):return false
	var x:=int(raw.x);var z:=int(raw.z)
	return x>=0 and z>=0 and (x<max_width and z<=max_depth if raw.axis=="x" else x<=max_width and z<max_depth)
