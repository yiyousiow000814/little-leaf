extends RefCounted
## Distance-driven short steps. Foot ground positions are persistent projected
## shoe centers, including lateral spacing. Body facing cannot move a planted
## shoe. The painter consumes these samples without blending toward the torso.
## Model positions, service clocks and movement speeds are untouched.
const CharacterGeometry=preload("res://scripts/directional_character_art.gd")

# The floor is drawn at 2:1. A stride is 20 pixels across it or 10 in
# depth, avoiding a tall body bounce on nearly vertical screen travel.
const STRIDE_PIXELS := 20.0
const STANCE_FRACTION := 0.5
const FOOT_LIFT := 1.0
const SETTLE_SECONDS := 0.15
const MAX_SUPPORT_DROP := 0.75
const MIN_SUPPORT_NEED := -5.5
const EPSILON := 0.000001
const TELEPORT_DISTANCE := 2.0

var _actors: Dictionary = {}

static func project(world: Vector2) -> Vector2:
	return Vector2((world.x - world.y) * 39.0, (world.x + world.y) * 19.5)

static func _shoe_axis(heading: Vector2) -> Vector2:
	var direction := project(heading)
	return Vector2(direction.x, direction.y * 0.96).normalized()

static func _rest_center(side: float, heading: Vector2) -> Vector2:
	var axis := _shoe_axis(heading)
	var direction := project(heading).normalized()
	var depth := clampf(direction.x * direction.y * 2.5, -1.0, 1.0)
	return Vector2(side * 3.7, -1.75 - side * depth * 0.75) + axis * 1.5

func update(key: Variant, world_pos: Vector2, delta: float) -> void:
	if not world_pos.is_finite(): return
	if not _actors.has(key):
		_actors[key] = _new_actor(world_pos)
		return
	if delta <= 0.0 or not is_finite(delta): return
	var actor: Dictionary = _actors[key]
	var old_pos: Vector2 = actor.position
	var travel := world_pos - old_pos
	var distance := travel.length()
	if distance > TELEPORT_DISTANCE:
		_actors[key] = _new_actor(world_pos)
		return
	actor.position = world_pos
	actor.speed = distance / delta
	if distance > EPSILON:
		var direction := travel / distance
		if not actor.has_heading:
			actor.heading = direction
			actor.has_heading = true
			actor.phase = 0.25
			for foot in [actor.left, actor.right]:
				foot.ground = project(old_pos) + _rest_center(foot.side, direction)
				foot.axis = _shoe_axis(direction)
		else:
			var angle := lerp_angle((actor.heading as Vector2).angle(), direction.angle(), 1.0 - exp(-12.0 * delta))
			actor.heading = Vector2.from_angle(angle)
		actor.blend = lerpf(float(actor.blend), smoothstep(0.015, 0.30, float(actor.speed)), 1.0 - exp(-14.0 * delta))
		var turning: bool = actor.was_moving and (actor.travel_direction as Vector2).dot(direction) < 0.75
		if not actor.was_moving or turning:
			# Fit the remaining support interval to its real contact, especially
			# when reversing after a stop. Restarting at an arbitrary half-step
			# would drag a trailing foot beyond the short leg's reach.
			if actor.distance > EPSILON: _align_contact_phase(actor, project(old_pos), direction)
			for foot in [actor.left, actor.right]: foot.settling = false
			_rebase_swing(actor.left, actor.phase, project(old_pos), direction, actor.heading)
			_rebase_swing(actor.right, _wrap_phase(actor.phase + 0.5), project(old_pos), direction, actor.heading)
		_advance_feet(actor, project(old_pos), project(travel), direction)
		actor.distance += distance
		actor.travel_direction = direction
		actor.was_moving = true
		_exchange_support(actor)
		_raise_return_feet(actor)
	else:
		actor.speed = 0.0
		actor.blend = float(actor.blend) * exp(-12.0 * delta)
		if actor.has_heading: _settle_feet(actor, delta)
		actor.was_moving = false
		if actor.has_heading: _raise_return_feet(actor)
		if actor.blend < 0.0001: actor.blend = 0.0

func sample(key: Variant) -> Dictionary:
	return _pose(_actors[key] if _actors.has(key) else _new_actor(Vector2.ZERO))

func remove(key: Variant) -> void:
	_actors.erase(key)

func clear() -> void:
	_actors.clear()

func _new_actor(position: Vector2) -> Dictionary:
	return {"position":position, "speed":0.0, "heading":Vector2.DOWN, "travel_direction":Vector2.DOWN, "has_heading":false,
		"phase":0.0, "distance":0.0, "blend":0.0, "was_moving":false, "support_exchanges":0,
		"left":_new_foot(project(position), -1.0), "right":_new_foot(project(position), 1.0)}

func _new_foot(position: Vector2, side: float) -> Dictionary:
	return {"side":side, "ground":position, "axis":_shoe_axis(Vector2.DOWN), "swing_start":position, "plant":0,
		"swing_axis":_shoe_axis(Vector2.DOWN), "lift":0.0, "lift_start_phase":STANCE_FRACTION,
		"lift_start_height":0.0, "settling":false, "settle_elapsed":0.0,
		"settle_start":position, "settle_target":position, "settle_lift":0.0}

func _pose(actor: Dictionary) -> Dictionary:
	var floor := project(actor.position)
	var left_ground: Vector2 = actor.left.ground - floor
	var right_ground: Vector2 = actor.right.ground - floor
	var phase: float = actor.phase
	return {"speed":actor.speed, "heading":actor.heading, "phase":phase, "distance":actor.distance,
		"blend":actor.blend, "grounded_feet":actor.has_heading,
		"support_exchanges":actor.support_exchanges,
		"left_rest":_rest_center(-1.0,actor.heading), "right_rest":_rest_center(1.0,actor.heading), "rest_axis":_shoe_axis(actor.heading),
		"left_ground":left_ground, "right_ground":right_ground,
		"left_foot":left_ground - Vector2(0.0, actor.left.lift),
		"right_foot":right_ground - Vector2(0.0, actor.right.lift),
		"left_axis":actor.left.axis, "right_axis":actor.right.axis,
		"left_lift":actor.left.lift, "right_lift":actor.right.lift,
		"left_plant":actor.left.plant, "right_plant":actor.right.plant,
		"left_phase":phase, "right_phase":_wrap_phase(phase + 0.5),
		"left_stance":not actor.left.settling and actor.left.lift < EPSILON and (not actor.was_moving or phase < STANCE_FRACTION - EPSILON),
		"right_stance":not actor.right.settling and actor.right.lift < EPSILON and (not actor.was_moving or _wrap_phase(phase + 0.5) < STANCE_FRACTION - EPSILON)}

func _advance_feet(actor: Dictionary, start: Vector2, travel: Vector2, direction: Vector2) -> void:
	var advance := Vector2(travel.x, travel.y * 2.0).length() / STRIDE_PIXELS
	var remaining := advance
	var elapsed := 0.0
	while remaining > EPSILON:
		var left_phase: float = actor.phase
		var right_phase := _wrap_phase(left_phase + 0.5)
		var step := minf(remaining, minf(_until_event(left_phase), _until_event(right_phase)))
		elapsed += step
		var position := start + travel * minf(elapsed / advance, 1.0)
		_step_foot(actor.left, left_phase, step, position, direction, actor.heading)
		_step_foot(actor.right, right_phase, step, position, direction, actor.heading)
		actor.phase = _wrap_phase(left_phase + step)
		remaining -= step

func _until_event(phase: float) -> float:
	return STANCE_FRACTION - phase if phase < STANCE_FRACTION - EPSILON else 1.0 - phase

func _swing_target(foot: Dictionary, phase: float, position: Vector2, direction: Vector2, heading: Vector2) -> Vector2:
	return position + _stride_vector(direction) * (1.0 - phase + STANCE_FRACTION * 0.5) + _rest_center(foot.side, heading)

static func _stride_vector(direction: Vector2) -> Vector2:
	var screen := project(direction)
	return screen * STRIDE_PIXELS / maxf(Vector2(screen.x, screen.y * 2.0).length(), EPSILON)

func _align_contact_phase(actor: Dictionary, position: Vector2, direction: Vector2) -> void:
	var left_support := float(actor.phase) < STANCE_FRACTION
	if maxf(actor.left.lift, actor.right.lift) > 0.02: left_support = actor.left.lift < actor.right.lift
	var support: Dictionary = actor.left if left_support else actor.right
	var other: Dictionary = actor.right if left_support else actor.left
	var support_gap := ((support.ground as Vector2) - position - _rest_center(support.side, direction)).length()
	var other_gap := ((other.ground as Vector2) - position - _rest_center(other.side, direction)).length()
	var stride := _stride_vector(direction).length()
	if (actor.travel_direction as Vector2).dot(direction) < 0.75 and support_gap > stride * 0.25 and other_gap < support_gap:
		# A tight pivot can finish the short airborne step where its shoe
		# already is, then release the old support. Do not ask an old-facing
		# contact to support another half-stride across the new direction.
		# Only the remaining (at most 1px) lift lands; the shoe never slides.
		other.lift = 0.0
		other.plant += 1
		actor.phase = 0.75 if left_support else 0.25
		return
	var along := ((support.ground as Vector2) - position - _rest_center(support.side, direction)).dot(project(direction).normalized())
	var contact_phase := clampf(STANCE_FRACTION * 0.5 - along / stride, 0.0, STANCE_FRACTION - 0.04)
	actor.phase = contact_phase + (0.0 if left_support else 0.5)

func _step_foot(foot: Dictionary, phase: float, advance: float, position: Vector2, direction: Vector2, heading: Vector2) -> void:
	var end_phase := phase + advance
	if phase < STANCE_FRACTION - EPSILON:
		foot.lift = 0.0
		if end_phase >= STANCE_FRACTION - EPSILON:
			foot.swing_start = foot.ground
			foot.swing_axis = foot.axis
			foot.lift_start_phase = STANCE_FRACTION
			foot.lift_start_height = 0.0
		return
	var progress := clampf((end_phase - STANCE_FRACTION) / (1.0 - STANCE_FRACTION), 0.0, 1.0)
	var eased := smoothstep(0.0, 1.0, progress)
	foot.ground = (foot.swing_start as Vector2).lerp(_swing_target(foot, end_phase, position, direction, heading), eased)
	foot.axis = Vector2.from_angle(lerp_angle((foot.swing_axis as Vector2).angle(), _shoe_axis(heading).angle(), eased))
	var lift_span := 1.0 - float(foot.lift_start_phase)
	var lift_progress := clampf((end_phase - float(foot.lift_start_phase)) / maxf(lift_span, EPSILON), 0.0, 1.0)
	var start_height: float = foot.lift_start_height
	foot.lift = start_height * (1.0 - smoothstep(0.0, 1.0, lift_progress)) + maxf(0.0,FOOT_LIFT - start_height) * minf(lift_span / (1.0 - STANCE_FRACTION), 1.0) * pow(sin(lift_progress * PI), 2.0)
	if progress >= 1.0 - EPSILON:
		foot.lift = 0.0
		foot.plant += 1

func _ground_support_needs(actor: Dictionary) -> Array:
	# Required torso drop for each complete ground contact, with the same
	# fixed leg length and covered hip sockets used by the painter.
	var floor := project(actor.position)
	var feet := [actor.left,actor.right]
	var ankles := []
	var hips := []
	var low := -INF
	var high := INF
	var rest_axis := _shoe_axis(actor.heading)
	var length: float = CharacterGeometry.LEG_LENGTH
	for foot in feet:
		var ankle: Vector2 = foot.ground-floor-foot.axis*1.5
		var hip := Vector2(foot.side*3.7,_rest_center(foot.side,actor.heading).y-rest_axis.y*1.5-length)
		ankles.append(ankle);hips.append(hip)
		low=maxf(low,ankle.x-hip.x-7.5);high=minf(high,ankle.x-hip.x+7.5)
	var body_x := clampf(0.0,low,high) if low<=high else (low+high)*0.5
	var result := []
	for index in range(2):
		var dx: float = ankles[index].x-hips[index].x-body_x
		dx-=clampf(dx,-2.0,2.0)
		var required: float = ankles[index].y-sqrt(maxf(0.0,length*length-dx*dx))-hips[index].y-CharacterGeometry.HIP_COVER
		result.append(required)
	return result

func _exchange_support(actor: Dictionary) -> void:
	# A contact lasts only while its short leg can support the body naturally.
	# This is geometric, not a phase/frame-specific exception: if a trailing
	# support would pull the body down, first land the other shoe at its own
	# already reachable ground point, then release and lift the trailing shoe.
	# Never slide a stance point or exchange onto an ungrounded shoe.
	var needs := _ground_support_needs(actor)
	var feet := [actor.left,actor.right]
	for index in range(2):
		var phase := _wrap_phase(float(actor.phase)+index*0.5)
		if phase>=STANCE_FRACTION-EPSILON or (needs[index]>=MIN_SUPPORT_NEED and needs[index]<=MAX_SUPPORT_DROP):continue
		var other: Dictionary = feet[1-index]
		if needs[1-index]<MIN_SUPPORT_NEED or needs[1-index]>MAX_SUPPORT_DROP or other.lift>FOOT_LIFT+EPSILON:continue
		other.lift=0.0
		other.plant+=1
		other.settling=false
		var released: Dictionary = feet[index]
		# The incoming shoe may land halfway through a short step. Give it
		# only the support distance its actual placement permits, not a new
		# full half-cycle which could leave its partner tucked into the torso.
		var direction:Vector2=actor.travel_direction
		var along:=((other.ground as Vector2)-project(actor.position)-_rest_center(other.side,direction)).dot(project(direction).normalized())
		var contact_phase:=clampf(STANCE_FRACTION*.5-along/_stride_vector(direction).length(),0.0,STANCE_FRACTION-.04)
		actor.phase=contact_phase+(STANCE_FRACTION if index==0 else 0.0)
		_rebase_swing(released,_wrap_phase(actor.phase+index*.5),project(actor.position),direction,actor.heading)
		actor.support_exchanges+=1
		return

func _raise_return_feet(actor: Dictionary) -> void:
	# A returning foot is free to lift. Do not lower the whole rigid body to
	# reach an airborne shoe trailing behind a tight corner, especially when
	# a coarse frame crosses both touchdown and toe-off. Stance anchors never
	# change here; any extra clearance is explicitly exposed as foot lift.
	var needs := _ground_support_needs(actor)
	var feet := [actor.left,actor.right]
	for index in range(2):
		var foot: Dictionary = feet[index]
		var phase := _wrap_phase(float(actor.phase)+index*0.5)
		if not foot.settling and (not actor.was_moving or phase<STANCE_FRACTION-EPSILON):continue
		foot.lift=maxf(foot.lift,needs[index])

func _rebase_swing(foot: Dictionary, phase: float, position: Vector2, direction: Vector2, heading: Vector2) -> void:
	if phase < STANCE_FRACTION - EPSILON: return
	var eased := smoothstep(0.0, 1.0, (phase - STANCE_FRACTION) / (1.0 - STANCE_FRACTION))
	var target := _swing_target(foot, phase, position, direction, heading)
	foot.swing_start = ((foot.ground as Vector2) - target * eased) / maxf(1.0 - eased, EPSILON)
	foot.swing_axis = foot.axis
	foot.lift_start_phase = phase
	foot.lift_start_height = foot.lift

func _settle_feet(actor: Dictionary, delta: float) -> void:
	var active: Dictionary = {}
	for foot in [actor.left, actor.right]:
		if foot.settling: active = foot
	if active.is_empty():
		# Finish the airborne foot first; the other shoe supports the body.
		var first: Dictionary = actor.left if actor.left.lift > actor.right.lift else actor.right
		var second: Dictionary = actor.right if first == actor.left else actor.left
		for foot in [first, second]:
			var target := project(actor.position) + _rest_center(foot.side, actor.heading)
			if (foot.ground as Vector2).distance_to(target) < 0.01 and foot.lift < 0.01: continue
			active = foot
			active.settling = true
			active.settle_elapsed = 0.0
			active.settle_start = foot.ground
			active.settle_target = target
			active.settle_lift = foot.lift
			active.swing_axis = foot.axis
			break
	if active.is_empty(): return
	active.settle_elapsed += delta
	var t := clampf(active.settle_elapsed / SETTLE_SECONDS, 0.0, 1.0)
	var eased := smoothstep(0.0, 1.0, t)
	active.ground = (active.settle_start as Vector2).lerp(active.settle_target, eased)
	active.axis = Vector2.from_angle(lerp_angle((active.swing_axis as Vector2).angle(), _shoe_axis(actor.heading).angle(), eased))
	active.lift = float(active.settle_lift) * (1.0 - eased) + FOOT_LIFT * 0.65 * pow(sin(t * PI), 2.0)
	if t >= 1.0:
		active.lift = 0.0
		active.settling = false
		active.plant += 1

static func _wrap_phase(phase: float) -> float:
	var result := fposmod(phase, 1.0)
	return 0.0 if result < EPSILON or result > 1.0 - EPSILON else result
