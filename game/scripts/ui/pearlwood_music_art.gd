extends Control
## Experimental, bounded 2.5D art study for the selected ivory/floral concept.
## The supplied PNGs remain untouched. Native editable-source GUI proof, actual
## runtime pixel acceptance, and Web/phone performance are separate pending gates.
## Presentation only: no playback, persistence, network, or resource-loading API.

const SPRIG_TEXTURE: Texture2D = preload("res://assets/ui/music_botanical/gold_flowering_stem.png")
const SUPPORT_TEXTURE: Texture2D = preload("res://assets/ui/music_pearlwood/petal_support.svg")
const BASE_TEXTURE: Texture2D = preload("res://assets/ui/music_pearlwood/base.png")
const PETAL_TEXTURE: Texture2D = preload("res://assets/ui/music_pearlwood/petal.png")
const PETAL_FRONT_TEXTURE: Texture2D = preload("res://assets/ui/music_pearlwood/petal-cupped-front-r22.png")
const PETAL_BACK_TEXTURE: Texture2D = preload("res://assets/ui/music_pearlwood/petal-curled-back-r22.png")
# Source regions align each new painted root with the unchanged mesh UV hinge.
# Transparent padding outside the PNG clamps to alpha <= 1/255 and is discarded.
const PETAL_FRONT_CROP := Rect2(46.8525,61.9,991.362766587678,1376.91578181818)
const PETAL_BACK_CROP := Rect2(46.1925,87.515,1082.90518364929,1334.78626909091)
const LEAF_TEXTURE: Texture2D = preload("res://assets/ui/music_pearlwood/leaf.png")
const RECORD_TEXTURE: Texture2D = preload("res://assets/ui/music_pearlwood/record.png")
const CABINET_RIM_SHADER: Shader = preload("res://assets/ui/music_pearlwood/cabinet_rim_mask.gdshader")
const CROP_SHADER: Shader = preload("res://assets/ui/music_pearlwood/pearlwood_crop.gdshader")
const LEAF_SHADER: Shader = preload("res://assets/ui/music_pearlwood/pearlwood_leaf.gdshader")
const RECORD_SHADER: Shader = preload("res://assets/ui/music_pearlwood/pearlwood_record.gdshader")
const DESIGN_SIZE := Vector2(440.0, 360.0)
const TRANSITION_SECONDS := 1.0
const LEAF_BEND_LIMIT := 0.035
const ARM_MUSIC_DEGREES := 0.85
const ARM_LANDING_DEGREES := 0.9
const ARM_PIVOT := Vector2(348,110)
const BASE_CROP := Rect2(86.0, 276.0, 1277.0, 547.0)
const PETAL_CROP := Rect2(100.0, 53.0, 865.0, 1392.0)
const LEAF_CROP := Rect2(179.0, 85.0, 746.0, 1331.0)
const RECORD_CROP := Rect2(62.0, 54.0, 1130.0, 1130.0)
const PETAL_ROOT := Vector2(422.0 / 865.0, 1375.0 / 1392.0)
const LEAF_ROOT := Vector2(361.0 / 746.0, 1315.0 / 1331.0)
const PETAL_ROOTS: Array[Vector2] = [
	Vector2(207, 267), Vector2(215, 268), Vector2(227, 268),
	Vector2(237, 273), Vector2(205, 281), Vector2(225, 276),
]
const PETAL_ANGLES: Array[float] = [-24.0, -2.0, 4.0, 43.0, -48.0, 82.0]
const PETAL_HEIGHTS: Array[float] = [230.0, 258.0, 260.0, 198.0, 125.0, 140.0]
const PETAL_LIGHT: Array[Color] = [
	Color(0.95,0.97,0.94), Color(1.0,0.995,0.96), Color(0.96,0.98,0.94),
	Color(0.91,0.95,0.88), Color(1.0,0.99,0.94), Color(1.0,0.99,0.93),
]
# Width, rounded-tip compression and lateral curl, baked once into each blade.
# The original painted source stays intact. These retained profiles are shared
# by the original and calibrated r22 paints, with no live vertex animation.
const PETAL_PROFILES: Array[Vector3] = [
	Vector3(1.25, 0.28, -0.10), Vector3(1.13, 0.31, -0.08),
	Vector3(1.20, 0.32, 0.06), Vector3(1.26, 0.25, 0.03),
	Vector3(1.18, 0.30, 0.08), Vector3(1.25, 0.30, -0.07),
]
const REAR_PETAL_COUNT := 4
const LEAF_ROOTS: Array[Vector2] = [
	Vector2(135, 284), Vector2(171, 232), Vector2(296, 198), Vector2(302, 284),
	# New leaves are planted on the retained right/back sprig curves.
	Vector2(387.72,235.32), Vector2(399.48,201.65), Vector2(407.75,158.62),
	Vector2(322.30,156.44), Vector2(335.24,124.55), Vector2(346.68,89.91),
]
const LEAF_ANGLES: Array[float] = [-58.0, -35.0, 15.0, 63.0, 62.0, -34.0, 24.0, -32.0, 56.0, -24.0]
const LEAF_HEIGHTS: Array[float] = [112.0, 102.0, 176.0, 110.0, 44.0, 42.0, 31.0, 44.0, 49.0, 48.0]

const BUD_CROP := Rect2(1767,188,101,94)
const BUD_ROOT := Vector2(0.16,0.97)
const BUD_ROOTS: Array[Vector2] = [Vector2(355,50),Vector2(413,102),Vector2(407,231)]
const BUD_HEIGHTS: Array[float] = [30.0,32.0,23.0]
const BUD_ANGLES: Array[float] = [-15.0,-28.0,36.0]

# Public, deterministic inspection surface. Assigning this property samples the
# composition; set_reveal() additionally cancels a running state transition.
var reveal: float = 0.0:
	set(value):
		var next_reveal := clampf(value, 0.0, 1.0)
		if is_equal_approx(reveal, next_reveal):
			return
		reveal = next_reveal
		if is_instance_valid(_canvas):
			_apply_reveal()

var _canvas: Node2D
var _base: Node2D
var _support: MeshInstance2D
var _record: MeshInstance2D
var _arm: Node2D
var _sprigs: Node2D
var _bud_blades: Array[MeshInstance2D] = []
var _petals: Array[Node2D] = []
var _petal_blades: Array[MeshInstance2D] = []
var _leaves: Array[Node2D] = []
var _leaf_blades: Array[MeshInstance2D] = []
var _leaf_materials: Array[ShaderMaterial] = []
var _record_material: ShaderMaterial
var _ink_meshes: Array[MeshInstance2D] = []
var _ink_bounds: Array[Rect2] = []
var _transition: Tween
var _playing_requested := false
var _premium := false
var _reduced := false
var _identity := ""
var _leaf_phase := 0.0
var _label_angle := 0.0
var _bgm_bus := -1
var _audio_peak_db := -100.0
var _audio_envelope := 0.0
var _audio_average := 0.0
var _leaf_music := PackedFloat32Array()
var _settled_bends := PackedFloat32Array()
var _settling := false
var _arm_motion := 0.0
var _settled_arm_motion := 0.0


class HeroSprigs extends Node2D:
	# Static, named attachment curves, baked once. Each begins in the cabinet
	# recess and terminates at a bud root; petals/cabinet cover the lower joins.
	var paths: Array[PackedVector2Array] = []
	var highlights: Array[PackedVector2Array] = []
	var shadows: Array[PackedVector2Array] = []
	var bake_count := 0
	const INK := Rect2(284,47,146,249)

	func _init() -> void:
		_add_curve(Vector2(332,291),Vector2(389,268),Vector2(407,204),Vector2(413,102))
		_add_curve(Vector2(377,251),Vector2(402,250),Vector2(405,243),Vector2(407,231))
		_add_curve(Vector2(287,239),Vector2(310,178),Vector2(346,118),Vector2(355,50))
		bake_count = 1

	func _add_curve(a:Vector2,b:Vector2,c:Vector2,d:Vector2) -> void:
		var path := PackedVector2Array()
		var light := PackedVector2Array()
		var shade := PackedVector2Array()
		for index in 33:
			var t := index / 32.0
			var point := a*pow(1.0-t,3.0)+b*3.0*pow(1.0-t,2.0)*t+c*3.0*(1.0-t)*t*t+d*t*t*t
			path.append(point); light.append(point+Vector2(-0.55,-0.55)); shade.append(point+Vector2(0.7,0.7))
		paths.append(path); highlights.append(light); shadows.append(shade)

	func _draw() -> void:
		for index in paths.size():
			draw_polyline(shadows[index],Color("977040"),3.3,true)
			draw_polyline(paths[index],Color("d5aa58"),2.4,true)
			draw_polyline(highlights[index],Color("fff0b6"),0.8,true)


class Tonearm extends Node2D:
	# Small retained native-vector fallback. Replace with a painted arm only as
	# an explicit art change; the current illustration assets have no arm layer.
	func _draw() -> void:
		var pivot := Vector2(348, 110)
		var tip := Vector2(303, 205)
		var path := PackedVector2Array([pivot, Vector2(341, 175),
			Vector2(339, 180), Vector2(309, 201), tip])
		draw_circle(pivot + Vector2(1, 2), 12.0, Color("8d5928"))
		draw_circle(pivot, 10.8, Color("c58c38"))
		draw_circle(pivot + Vector2(-1, -2), 8.4, Color("e9ba61"))
		draw_circle(pivot + Vector2(-2, -4), 5.3, Color("fff0bc"))
		draw_circle(pivot + Vector2(0, -13), 3.4, Color("c58c38"))
		draw_circle(pivot + Vector2(-1, -14), 2.1, Color("ffe9a3"))
		draw_polyline(path, Color("94632e"), 7.5, true)
		draw_polyline(path, Color("e2ad51"), 5.5, true)
		var highlight := PackedVector2Array()
		for point in path:
			highlight.append(point + Vector2(-1.3, -0.8))
		draw_polyline(highlight, Color("ffedb1"), 1.7, true)
		# The stylus ends inside the record's right/lower quadrant. The whole arm
		# sits behind the foreground petals, so it cannot rest on their paint.
		var cartridge := PackedVector2Array()
		for index in 17:
			var t := float(index) / 16.0
			cartridge.append(tip + Vector2(-14.0 + t * 19.0, 10.0 - t * 15.0)
				+ Vector2(-4, -5) * sin(t * PI))
		for index in range(16, -1, -1):
			var t := float(index) / 16.0
			cartridge.append(tip + Vector2(-14.0 + t * 19.0, 10.0 - t * 15.0)
				+ Vector2(4, 5) * sin(t * PI))
		draw_colored_polygon(cartridge, Color("f4d287"))
		cartridge.append(cartridge[0])
		draw_polyline(cartridge, Color("9f6b31"), 1.1, true)
		draw_line(tip + Vector2(-12, 8), tip + Vector2(3, -3), Color("fff4c9"), 1.3, true)


func _init() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	clip_contents = true
	texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS
	set_process(false)
	_leaf_music.resize(LEAF_ROOTS.size())
	_settled_bends.resize(LEAF_ROOTS.size())
	_build_layers()
	_apply_reveal()


func _ready() -> void:
	_arrange()
	_refresh_processing()


func _exit_tree() -> void:
	_kill_transition()
	set_process(false)


func _notification(what: int) -> void:
	if not is_instance_valid(_canvas):
		return
	if what == NOTIFICATION_RESIZED:
		_arrange()
	elif what == NOTIFICATION_VISIBILITY_CHANGED:
		if not is_visible_in_tree():
			_kill_transition()
			_reset_audio()
			reveal = 1.0 if _premium else 0.0
		_refresh_processing()


func _build_layers() -> void:
	_canvas = Node2D.new()
	_canvas.name = "PearlwoodLayerCanvas"
	# Keep local back layers above the containing board's background. Negative
	# child Z values alone otherwise escape behind a sibling panel material.
	_canvas.z_index = 10
	add_child(_canvas)
	_support = _make_layer("SculptedIvorySupport", SUPPORT_TEXTURE, Rect2(0,0,440,84),
		CROP_SHADER, _make_grid(440.0/84.0,Vector2.ZERO), _canvas)
	_support.position = Vector2(4,268)
	_support.scale = Vector2(82.0,92.0)
	_support.z_index = -6
	_track_ink(_support,Rect2(0,0,440.0/84.0,1))
	_base = Node2D.new()
	_base.name = "BaseCabinet"
	_canvas.add_child(_base)
	# Complementary masks split the untouched source along its painted curved
	# front lip. This removes the straight horizontal cut across foreground petals.
	var base_scale := Vector2(292.0 / BASE_CROP.size.x, 0.28)
	for front_side in [false,true]:
		var cabinet := _make_layer("BaseFrontFascia" if front_side else "BaseTopRecess",
			BASE_TEXTURE, BASE_CROP, CABINET_RIM_SHADER,
			_make_grid(BASE_CROP.size.x / BASE_CROP.size.y, Vector2.ZERO), _base)
		cabinet.position = Vector2(74,190)
		cabinet.scale = BASE_CROP.size.y * base_scale
		cabinet.z_index = 4 if front_side else -4
		cabinet.material.set_shader_parameter("front_layer",1.0 if front_side else 0.0)
		_track_ink(cabinet,Rect2(Vector2.ZERO,Vector2(BASE_CROP.size.x / BASE_CROP.size.y,1)))

	_sprigs = HeroSprigs.new()
	_sprigs.name = "CabinetRootedHeroSprigs"
	_sprigs.z_index = -3
	_canvas.add_child(_sprigs)
	var bud_mesh := _make_grid(BUD_CROP.size.x / BUD_CROP.size.y,BUD_ROOT)
	for index in BUD_ROOTS.size():
		var bud := _make_layer("SprigBud%d"%index,SPRIG_TEXTURE,BUD_CROP,CROP_SHADER,bud_mesh,_canvas)
		bud.position = BUD_ROOTS[index]
		bud.rotation = deg_to_rad(BUD_ANGLES[index])
		bud.z_index = -3
		_bud_blades.append(bud)
		_track_ink(bud,_mesh_rect(bud_mesh))

	var leaf_ratio := LEAF_CROP.size.x / LEAF_CROP.size.y
	var leaf_mesh := _make_grid(leaf_ratio, LEAF_ROOT, 16)
	for index in LEAF_ROOTS.size():
		var stem := Node2D.new()
		stem.name = "Leaf%dStem" % (index + 1)
		stem.position = LEAF_ROOTS[index]
		stem.rotation = deg_to_rad(LEAF_ANGLES[index])
		stem.z_index = -3
		_canvas.add_child(stem)
		var blade := _make_layer("LeafBlade", LEAF_TEXTURE, LEAF_CROP, LEAF_SHADER, leaf_mesh, stem)
		_leaves.append(stem)
		_leaf_blades.append(blade)
		_leaf_materials.append(blade.material as ShaderMaterial)
		_track_ink(blade, Rect2(-LEAF_ROOT * Vector2(leaf_ratio, 1), Vector2(leaf_ratio, 1)).grow_individual(LEAF_BEND_LIMIT, 0, LEAF_BEND_LIMIT, 0))

	for index in PETAL_ROOTS.size():
		var hinge := Node2D.new()
		hinge.name = "Petal%dHinge" % (index + 1)
		hinge.position = PETAL_ROOTS[index]
		hinge.z_index = -2 if index < REAR_PETAL_COUNT else 3
		_canvas.add_child(hinge)
		var petal_mesh := _make_petal_grid(PETAL_PROFILES[index])
		var paint: Texture2D = PETAL_TEXTURE
		var crop: Rect2 = PETAL_CROP
		if index == 1 or index == 2:
			paint = PETAL_BACK_TEXTURE; crop = PETAL_BACK_CROP
		elif index >= REAR_PETAL_COUNT:
			paint = PETAL_FRONT_TEXTURE; crop = PETAL_FRONT_CROP
		var blade := _make_layer("PaintedPetal", paint, crop, CROP_SHADER, petal_mesh, hinge)
		blade.texture_repeat = CanvasItem.TEXTURE_REPEAT_DISABLED
		blade.modulate = PETAL_LIGHT[index]
		_petals.append(hinge)
		_petal_blades.append(blade)
		_track_ink(blade, _mesh_rect(petal_mesh))

	_record = _make_layer("RecordProjection", RECORD_TEXTURE, RECORD_CROP, RECORD_SHADER,
		_make_grid(1.0, Vector2(0.5, 0.5)), _canvas)
	_record.z_index = 0
	_record_material = _record.material as ShaderMaterial
	_track_ink(_record, Rect2(-Vector2.ONE * 0.5, Vector2.ONE))
	_arm = Tonearm.new()
	_arm.name = "Tonearm"
	_arm.z_index = 2
	_arm.position.y = -18
	_canvas.add_child(_arm)


# Twelve immutable meshes (support, two cabinet pieces, six petals, shared leaf,
# shared bud, record) and bounded paint materials belong to this subtree.
# All mesh arrays are built once and remain immutable after submission.
func _make_petal_grid(profile: Vector3) -> ArrayMesh:
	var mesh := _make_grid(PETAL_CROP.size.x / PETAL_CROP.size.y, PETAL_ROOT, 24)
	var arrays := mesh.surface_get_arrays(0)
	var vertices: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
	var uvs: PackedVector2Array = arrays[Mesh.ARRAY_TEX_UV]
	for index in vertices.size():
		var y := uvs[index].y
		var shoulder := (y + profile.y * pow(1.0 - y, 3.0) - profile.y) / (1.0 - profile.y)
		vertices[index].x = vertices[index].x * profile.x + profile.z * pow(1.0 - y, 2.0)
		vertices[index].y = shoulder - PETAL_ROOT.y
	arrays[Mesh.ARRAY_VERTEX] = vertices
	mesh.clear_surfaces()
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	return mesh


func _mesh_rect(mesh: ArrayMesh) -> Rect2:
	var bounds := mesh.get_aabb()
	return Rect2(Vector2(bounds.position.x, bounds.position.y), Vector2(bounds.size.x, bounds.size.y))


func _make_grid(ratio: float, anchor: Vector2, rows: int = 1) -> ArrayMesh:
	var vertices := PackedVector3Array()
	var uvs := PackedVector2Array()
	var indices := PackedInt32Array()
	for row in range(rows + 1):
		var y := float(row) / rows
		for column in 2:
			var uv := Vector2(float(column), y)
			vertices.append(Vector3((uv.x - anchor.x) * ratio, uv.y - anchor.y, 0.0))
			uvs.append(uv)
	for row in rows:
		var first := row * 2
		indices.append_array(PackedInt32Array([first, first + 1, first + 2, first + 1, first + 3, first + 2]))
	var arrays: Array = []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = vertices
	arrays[Mesh.ARRAY_TEX_UV] = uvs
	arrays[Mesh.ARRAY_INDEX] = indices
	var mesh := ArrayMesh.new()
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	return mesh


func _make_layer(layer_name: String, paint: Texture2D, crop: Rect2, shader: Shader,
		mesh: ArrayMesh, parent: Node2D) -> MeshInstance2D:
	var layer := MeshInstance2D.new()
	layer.name = layer_name
	layer.texture = paint
	layer.mesh = mesh
	var material := ShaderMaterial.new()
	material.shader = shader
	var source_size := paint.get_size()
	material.set_shader_parameter("source_region", Vector4(crop.position.x / source_size.x,
		crop.position.y / source_size.y, crop.size.x / source_size.x, crop.size.y / source_size.y))
	layer.material = material
	parent.add_child(layer)
	return layer


func _track_ink(layer: MeshInstance2D, bounds: Rect2) -> void:
	_ink_meshes.append(layer)
	_ink_bounds.append(bounds)


func _arrange() -> void:
	var fit := maxf(0.0, minf(size.x / DESIGN_SIZE.x, size.y / DESIGN_SIZE.y))
	_canvas.position = (size - DESIGN_SIZE * fit) * 0.5
	_canvas.scale = Vector2.ONE * fit


func _apply_reveal() -> void:
	var amount := smoothstep(0.12, 0.72, reveal)
	_support.visible = reveal > 0.0
	_support.modulate.a = smoothstep(0.12,0.44,reveal)
	_base.visible = reveal > 0.0
	_base.modulate.a = smoothstep(0.12, 0.44, reveal)
	_arm.visible = reveal > 0.0
	_arm.modulate.a = smoothstep(0.52, 0.66, reveal)
	_sprigs.visible = reveal > 0.0
	_sprigs.modulate.a = smoothstep(0.26,0.60,reveal)
	for index in _bud_blades.size():
		var amount_bud := smoothstep(0.40+index*0.03,0.80+index*0.03,reveal)
		_bud_blades[index].visible = amount_bud > 0.0
		_bud_blades[index].modulate.a = amount_bud
		_bud_blades[index].scale = Vector2.ONE*BUD_HEIGHTS[index]*lerpf(0.20,1.0,amount_bud)
	_apply_arm_pose()
	for index in _petals.size():
		var hinge := _petals[index]
		# All roots stay fixed in the cabinet while their own blades open.
		var start := 0.24 + index * 0.06 if index < REAR_PETAL_COUNT else 0.44 + (index - REAR_PETAL_COUNT) * 0.08
		var finish := 0.60 + index * 0.04 if index < REAR_PETAL_COUNT else 0.76 + (index - REAR_PETAL_COUNT) * 0.08
		var petal_amount := smoothstep(start, finish, reveal)
		hinge.visible = petal_amount > 0.0
		hinge.modulate.a = petal_amount
		hinge.rotation = deg_to_rad(lerpf(PETAL_ANGLES[index] * 0.12, PETAL_ANGLES[index], petal_amount))
		_petal_blades[index].scale = Vector2(lerpf(0.16, 1.0, petal_amount),
			lerpf(0.07, 1.0, petal_amount)) * PETAL_HEIGHTS[index]
	for index in _leaves.size():
		var leaf_start := 0.36+index*0.035 if index<4 else 0.40+(index-4)*0.025
		var leaf_end := 0.76+index*0.035 if index<4 else 0.78+(index-4)*0.025
		var leaf_amount := smoothstep(leaf_start,leaf_end,reveal)
		_leaves[index].visible = leaf_amount > 0.0
		_leaves[index].modulate.a = leaf_amount
		_leaf_blades[index].scale = Vector2.ONE * LEAF_HEIGHTS[index] * lerpf(0.18, 1.0, leaf_amount)
	_record.position = Vector2(220, lerpf(180.0, 165.0, amount))
	_record.scale = Vector2(lerpf(248.0, 254.0, amount), lerpf(248.0, 254.0 * 0.74, amount))
	# No scene-node rotation is ever applied to the record's ellipse.


func _apply_arm_pose() -> void:
	if not is_instance_valid(_arm):return
	var arm_settle:=smoothstep(0.52,0.82,reveal)
	var landing:=clampf((reveal-0.80)/0.20,0.0,1.0)
	var rebound:=sin(landing*TAU)*(1.0-landing)*ARM_LANDING_DEGREES
	var music_motion:=rad_to_deg(_arm_motion)*smoothstep(0.88,1.0,reveal)
	_arm.rotation=deg_to_rad(lerpf(-12.0,0.0,arm_settle)+rebound+music_motion)
	# Rotate around the planted pivot, never translate the complete tonearm.
	_arm.position=ARM_PIVOT-ARM_PIVOT.rotated(_arm.rotation)+Vector2(0,-18)


func set_state(playing: bool, premium: bool, reduced: bool = false, identity: String = "") -> void:
	var edition_changed := _premium != premium
	var was_playing := _playing_requested
	_playing_requested = playing
	_premium = premium
	_reduced = reduced
	_identity = identity
	var target := 1.0 if premium else 0.0
	if reduced or not is_inside_tree() or not is_visible_in_tree():
		_kill_transition();reveal=target;_reset_audio()
	elif edition_changed:
		_kill_transition()
		if not playing:_reset_audio()
		_transition=create_tween()
		_transition.tween_property(self,"reveal",target,TRANSITION_SECONDS*maxf(0.2,absf(target-reveal))).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
		_transition.finished.connect(_transition_finished)
	elif was_playing and not playing:
		# Stop audio-driven movement without snapping an active edition reveal.
		if active_tweens()>0 and not _settling:_reset_audio()
		elif premium:_begin_rest()
		else:_reset_audio()
	elif playing and _settling:
		_kill_transition()

	_refresh_processing()


func _begin_rest() -> void:
	_settling = true
	_settled_arm_motion = _arm_motion
	for index in _leaf_materials.size():
		var bend: Variant = _leaf_materials[index].get_shader_parameter("tip_bend")
		_settled_bends[index] = 0.0 if bend == null else float(bend)
	_transition = create_tween()
	_transition.tween_method(_apply_rest, 0.0, 1.0, 0.32).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_OUT)
	_transition.finished.connect(_transition_finished)


func _apply_rest(amount: float) -> void:
	_arm_motion=_settled_arm_motion*(1.0-amount)
	_apply_arm_pose()
	for index in _leaf_materials.size():
		_leaf_materials[index].set_shader_parameter("tip_bend", _settled_bends[index] * (1.0 - amount))
	if amount >= 1.0:
		_reset_audio()


func _reset_audio() -> void:
	_audio_peak_db = -100.0
	_audio_envelope = 0.0
	_audio_average = 0.0
	_leaf_music.fill(0.0)
	_arm_motion=0.0
	_apply_arm_pose()
	for paint in _leaf_materials:
		paint.set_shader_parameter("tip_bend", 0.0)


func set_reveal(value: float) -> void:
	_kill_transition()
	reveal = value


func _transition_finished() -> void:
	_transition = null
	_settling = false


func _kill_transition() -> void:
	if _transition != null and _transition.is_valid():
		_transition.kill()
	_transition = null
	_settling = false


func _refresh_processing() -> void:
	set_process(_playing_requested and not _reduced and is_inside_tree() and is_visible_in_tree())


func _process(delta: float) -> void:
	# The printed record label is a conventional constant-speed playback cue,
	# not an audio-reactive effect. Its fixed ellipse never rotates as a node.
	_label_angle = fposmod(_label_angle + delta * TAU / 20.0, TAU)
	_record_material.set_shader_parameter("label_angle", _label_angle)
	if reveal <= 0.0:
		return
	_sample_music(delta)
	# Actual musical energy drives both the decorative phase and amplitude.
	# The authored shape vocabulary stops and relaxes when the signal is silent.
	_leaf_phase = fposmod(_leaf_phase + delta * _audio_envelope * 1.7, 86400.0)
	# Existing BGM energy drives a sub-degree compliant nod. Low-pass damping
	# avoids rigid random jitter; no new audio player, clock or geometry resource.
	var arm_wave:=sin(_leaf_phase*4.8)*0.72+sin(_leaf_phase*8.3)*0.28
	var arm_target:=deg_to_rad(ARM_MUSIC_DEGREES)*arm_wave*clampf(_audio_envelope*1.7,0.0,1.0)
	_arm_motion=lerpf(_arm_motion,arm_target,1.0-exp(-delta*14.0))
	_apply_arm_pose()
	for index in _leaf_materials.size():
		var offset := float(index) * 1.73
		var rate := 1.25 + float(index) * 0.147
		var breath := 0.63 + 0.37 * sin(_leaf_phase * (0.34 + float(index % 3) * 0.07) + offset)
		var bend := (sin(_leaf_phase * rate + offset) * 0.72
			+ sin(_leaf_phase * (rate * 1.83) + offset * 0.61) * 0.28) * breath
		var target := clampf((_audio_envelope - _audio_average * 0.64) * 1.8, 0.0, 1.0)
		_leaf_music[index] = lerpf(_leaf_music[index], target,
			1.0 - exp(-delta * (5.9 + float(index) * 1.7)))
		var nod := _leaf_music[index] * (0.76 if index % 2 == 0 else -0.65)
		_leaf_materials[index].set_shader_parameter("tip_bend",
			clampf(bend * 0.62 * _audio_envelope + nod, -1.0, 1.0) * LEAF_BEND_LIMIT)


func _sample_music(delta: float) -> void:
	# Read the existing BGM mix. Never install an effect or synthesize a beat.
	if _bgm_bus < 0 or _bgm_bus >= AudioServer.bus_count:
		_bgm_bus = AudioServer.get_bus_index("BGM")
	var loudness := 0.0
	_audio_peak_db = -100.0
	if _bgm_bus >= 0 and not AudioServer.is_bus_mute(_bgm_bus):
		_audio_peak_db = maxf(AudioServer.get_bus_peak_volume_left_db(_bgm_bus, 0),
			AudioServer.get_bus_peak_volume_right_db(_bgm_bus, 0))
		# Restore the game's -17dB player trim to a useful bounded visual range.
		loudness = clampf(db_to_linear(_audio_peak_db) * 7.08, 0.0, 1.0)
	var rate := 13.0 if loudness > _audio_envelope else 4.0
	_audio_envelope = lerpf(_audio_envelope, loudness, 1.0 - exp(-delta * rate))
	_audio_average = lerpf(_audio_average, _audio_envelope, 1.0 - exp(-delta * 1.5))


func audio_motion_state() -> Dictionary:
	return {"audio_peak_db": _audio_peak_db, "audio_envelope": _audio_envelope,
		"leaf_music": _leaf_music.duplicate(), "leaf_phase": _leaf_phase,
		"settling": _settling, "processing": is_processing(),
		"label_angle": _label_angle, "label_rotation_seconds": 20.0,
		"tonearm_motion_degrees":rad_to_deg(_arm_motion),"tonearm_limit_degrees":ARM_MUSIC_DEGREES,
		"tonearm_pivot":_arm.get_global_transform()*ARM_PIVOT}


func ink_rects() -> Array[Rect2]:
	var result: Array[Rect2] = []
	if not is_visible_in_tree() or _canvas.scale.x <= 0.0:
		return result
	for index in _ink_meshes.size():
		var layer := _ink_meshes[index]
		if layer.is_visible_in_tree():
			result.append(layer.get_global_transform() * _ink_bounds[index])
	if _sprigs.is_visible_in_tree():
		result.append(_sprigs.get_global_transform()*HeroSprigs.INK)
	if _arm.is_visible_in_tree():
		result.append(_arm.get_global_transform() * Rect2(288, 92, 74, 125))
	return result


func active_tweens() -> int:
	return 1 if _transition != null and _transition.is_valid() and _transition.is_running() else 0
