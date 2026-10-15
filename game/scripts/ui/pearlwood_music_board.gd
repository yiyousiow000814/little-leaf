extends Control
## One original nine-patch silhouette, continuously opaque at every edition.
## Default uses the exact original StyleBoxTexture and shared HUD material.
## Four retained source-derived corner pieces keep their original placement;
## Premium changes the wood stain, never the board geometry or source bytes.

const WOOD_SHADER: Shader = preload("res://assets/ui/music_pearlwood/pearlwood_board_wood.gdshader")
const CORNER_SHADER: Shader = preload("res://assets/ui/music_pearlwood/original_corner_foliage.gdshader")
const INSETS := Vector4(40, 36, 40, 32)
const SOURCE_SIZE := Vector2(512, 158)
const CORNER_EXTENT := Vector2(72, 64)
const SOURCE_ORIGINS := [Vector2(0, 0), Vector2(440, 0), Vector2(0, 94), Vector2(440, 94)]
const SOURCE_ROOTS := [Vector2(43, 33), Vector2(477, 33), Vector2(36, 130), Vector2(480, 130)]
const SOURCE_TIPS := [Vector2(24, 3), Vector2(494, 5), Vector2(3, 137), Vector2(507, 126)]
signal reveal_changed(amount:float)
const TRANSITION_SECONDS := 0.5
const PALETTE_PARAMETERS := ["surface_kind", "treatment_strength", "wood_lift", "preserve_dark_details",
	"birch_ink", "birch_shadow", "birch_body", "birch_light",
	"cream_ink", "cream_shadow", "cream_body", "cream_light"]

var content_insets := INSETS
var original: StyleBoxTexture
var ordinary: OriginalSurface
var wood_material: ShaderMaterial
var corner_leaves: Array[MeshInstance2D] = []
var corner_materials: Array[ShaderMaterial] = []
var reveal: float = 0.0:
	set(value):
		var next := clampf(value, 0.0, 1.0)
		if reveal == next:
			return
		reveal = next
		_apply_reveal()
var reference_surface: OriginalSurface
var reference_style: StyleBoxTexture
var _original_material: Material
var _corner_canvas: Node2D
var _premium := false
var _transition: Tween


class OriginalSurface extends Control:
	var style: StyleBoxTexture
	var render_scale := 1.0
	var quiet_center: StyleBoxFlat
	var quiet_inset := 30.0

	func _draw() -> void:
		if style != null:
			draw_set_transform(Vector2.ZERO,0,Vector2.ONE*render_scale)
			draw_style_box(style, Rect2(Vector2.ZERO, size/render_scale))
		if quiet_center != null:
			draw_set_transform(Vector2.ZERO)
			draw_style_box(quiet_center, Rect2(Vector2.ZERO, size).grow(-quiet_inset))

	func _notification(what: int) -> void:
		if what == NOTIFICATION_RESIZED:
			if has_meta("folio_depth"):material.set_shader_parameter("surface_size",size)
			queue_redraw()


class FolioSurface extends Control:
	var layers: Array[StyleBoxFlat] = []
	var insets: Array[float] = []
	var page_light:=StyleBoxFlat.new()
	var compact_mode:=false
	var surface_kind:="library"
	func _init(kind: String = "library") -> void:
		surface_kind=kind
		mouse_filter = Control.MOUSE_FILTER_IGNORE
		var shade:=ShaderMaterial.new();shade.shader=preload("res://assets/ui/music_botanical/folio_depth.gdshader");shade.set_shader_parameter("beveled_frame",false);material=shade
		page_light.bg_color=Color.TRANSPARENT;page_light.border_color=Color("fff9e5");page_light.set_border_width_all(1);page_light.set_corner_radius_all(27 if kind=="library" else 45)
		var colors = [Color("73784f"), Color("f4dfaa"), Color("fff7e6")] if kind == "library" else [Color("a97838"), Color("fff2ce"), Color("f9edd5")]
		var edges = [Color("ae8b48"), Color("b8954f"), Color("ead9b2")] if kind == "library" else [Color("8c622f"), Color("d2a15d"), Color("e6cea0")]
		for index in 3:
			var layer := StyleBoxFlat.new()
			layer.bg_color = colors[index]; layer.border_color = edges[index]
			layer.set_border_width_all(2 if index < 2 else 1)
			layer.set_corner_radius_all(32-index*5 if kind == "library" else 58-index*5)
			if kind == "library":
				layer.corner_radius_bottom_left = 46-index*5
				layer.corner_radius_bottom_right = 52-index*5
			layers.append(layer); insets.append([0.0,5.0,11.0][index])
		resized.connect(_refresh_size)
	func set_compact(value:bool):
		if compact_mode==value:return
		compact_mode=value
		for index in layers.size():
			insets[index]=[0.0,2.0,5.0][index] if value else [0.0,5.0,11.0][index]
			layers[index].set_corner_radius_all((18-index*2 if surface_kind=="library" else 28-index*2) if value else (32-index*5 if surface_kind=="library" else 58-index*5))
			if not value and surface_kind=="library":
				layers[index].corner_radius_bottom_left=46-index*5;layers[index].corner_radius_bottom_right=52-index*5
		page_light.set_corner_radius_all(14 if value else 27 if surface_kind=="library" else 45)
		queue_redraw()
	func _refresh_size():
		material.set_shader_parameter("surface_size",size);queue_redraw()
	func _draw() -> void:
		for index in layers.size():
			draw_style_box(layers[index], Rect2(Vector2.ZERO,size).grow(-insets[index]))
		draw_style_box(page_light,Rect2(Vector2.ZERO,size).grow(-7 if compact_mode else -15))


func _init() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR
	_corner_canvas = Node2D.new()
	_corner_canvas.name = "OriginalCornerFoliage"
	_corner_canvas.show_behind_parent = true
	add_child(_corner_canvas)
	var mesh := _make_corner_mesh()
	for index in 4:
		var leaf := MeshInstance2D.new()
		leaf.name = "OriginalCorner%02d" % (index + 1)
		leaf.texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR
		leaf.mesh = mesh
		var paint := ShaderMaterial.new()
		paint.shader = CORNER_SHADER
		paint.set_shader_parameter("source_origin", SOURCE_ORIGINS[index])
		paint.set_shader_parameter("source_root", SOURCE_ROOTS[index])
		leaf.material = paint
		_corner_canvas.add_child(leaf)
		corner_leaves.append(leaf)
		corner_materials.append(paint)
	wood_material = ShaderMaterial.new()
	wood_material.shader = WOOD_SHADER
	ordinary = OriginalSurface.new()
	ordinary.name = "OriginalSoftWoodMaterial"
	ordinary.texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR
	ordinary.mouse_filter = Control.MOUSE_FILTER_IGNORE
	ordinary.show_behind_parent = true
	add_child(ordinary)
	var atlas := AtlasTexture.new()
	atlas.atlas = preload("res://assets/ui/music_botanical/cream_gold_board.png")
	atlas.region = Rect2(28,64,1482,884)
	reference_style = StyleBoxTexture.new()
	reference_style.texture = atlas
	for side in [SIDE_LEFT,SIDE_TOP,SIDE_RIGHT,SIDE_BOTTOM]:
		reference_style.set_texture_margin(side,180)
	reference_surface = OriginalSurface.new()
	reference_surface.name = "ReferenceCreamGoldSurface"
	reference_surface.style = reference_style
	reference_surface.render_scale = .42
	var reference_depth:=ShaderMaterial.new();reference_depth.shader=preload("res://assets/ui/music_botanical/cream_gold_frame_clip_r27.gdshader")
	reference_surface.material=reference_depth;reference_surface.set_meta("folio_depth",true)
	reference_surface.quiet_center = StyleBoxFlat.new()
	reference_surface.quiet_center.bg_color = Color("f7efd7")
	reference_surface.quiet_center.set_corner_radius_all(32)
	reference_surface.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(reference_surface)
	resized.connect(_arrange)
	_apply_reveal()


func make_ordinary_surface(style:StyleBoxTexture) -> Control:
	var surface:=OriginalSurface.new();surface.style=style;surface.mouse_filter=Control.MOUSE_FILTER_IGNORE
	add_child(surface);return surface


func make_reference_surface(kind:String) -> Control:
	var surface := FolioSurface.new(kind)
	add_child(surface)
	return surface


func _make_corner_mesh() -> ArrayMesh:
	# One immutable 18x16 grid shared by all four pieces. The 72px width includes
	# the original top-right leaf's five pixels inside the stretched center strip.
	# The shader maps that strip with the very same 64px nine-patch transform.
	var vertices := PackedVector3Array()
	var uvs := PackedVector2Array()
	var indices := PackedInt32Array()
	for row in 17:
		for column in 19:
			var uv := Vector2(float(column) / 18.0, float(row) / 16.0)
			vertices.append(Vector3(uv.x * CORNER_EXTENT.x, uv.y * CORNER_EXTENT.y, 0))
			uvs.append(uv)
	for row in 16:
		for column in 18:
			var first := row * 19 + column
			indices.append_array(PackedInt32Array([first, first + 1, first + 19,
				first + 1, first + 20, first + 19]))
	var arrays: Array = []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = vertices
	arrays[Mesh.ARRAY_TEX_UV] = uvs
	arrays[Mesh.ARRAY_INDEX] = indices
	var mesh := ArrayMesh.new()
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	return mesh


func set_content_insets(value: Vector4) -> void:
	if content_insets == value:
		return
	content_insets = value
	_arrange()


func set_original_material(style: StyleBoxTexture, paint: Material) -> void:
	original = style
	_original_material = paint
	ordinary.style = original
	for leaf in corner_leaves:
		leaf.texture = original.texture
		leaf.modulate = original.modulate_color
	if paint is ShaderMaterial:
		for parameter in PALETTE_PARAMETERS:
			var value = paint.get_shader_parameter(parameter)
			if value != null:
				wood_material.set_shader_parameter(parameter, value)
				for corner_material in corner_materials:
					corner_material.set_shader_parameter(parameter, value)
	ordinary.queue_redraw()
	_arrange()
	_apply_reveal()


func _arrange() -> void:
	if not is_instance_valid(ordinary):
		return
	ordinary.position = Vector2(-content_insets.x, -content_insets.y)
	ordinary.size = size + Vector2(content_insets.x + content_insets.z, content_insets.y + content_insets.w)
	reference_surface.position = ordinary.position
	reference_surface.size = ordinary.size
	_corner_canvas.position = ordinary.position
	for index in 4:
		corner_leaves[index].position = _board_point(SOURCE_ORIGINS[index])
		corner_materials[index].set_shader_parameter("board_size", ordinary.size)


func _apply_reveal() -> void:
	if not is_instance_valid(ordinary):
		return
	# The exact original draw path at zero guarantees Default pixel parity.
	# The split is immediate but lossless; subsequent change is vertex motion.
	var next_material: Material = _original_material if reveal == 0.0 else wood_material
	if ordinary.material != next_material:
		ordinary.material = next_material
	ordinary.visible = true
	ordinary.modulate.a = 1.0
	reference_surface.modulate.a = smoothstep(0.0,0.24,reveal)
	_corner_canvas.modulate.a = 1.0-smoothstep(0.0,0.24,reveal)
	_corner_canvas.visible = original != null and reveal > 0.0
	wood_material.set_shader_parameter("material_reveal", smoothstep(0.0, 0.24, reveal))
	wood_material.set_shader_parameter("rim_repair", 0.0)
	var retraction := 0.0
	for paint in corner_materials:
		paint.set_shader_parameter("retraction", retraction)

	reveal_changed.emit(reveal)


func set_state(premium: bool, reduced: bool, _playing: bool = true) -> void:
	var changed := _premium != premium
	_premium = premium
	var target := 1.0 if premium else 0.0
	if reduced or not is_visible_in_tree():
		set_reveal(target)
	elif changed:
		_kill_transition()
		_transition = create_tween()
		_transition.tween_property(self, "reveal", target,
			TRANSITION_SECONDS * maxf(0.2, absf(target - reveal))).set_trans(Tween.TRANS_LINEAR)
		_transition.finished.connect(_transition_finished)


func set_reveal(value: float) -> void:
	_kill_transition()
	reveal = value


func _transition_finished() -> void:
	_transition = null


func active_tweens() -> int:
	return int(_transition != null and _transition.is_valid() and _transition.is_running())


func _kill_transition() -> void:
	if _transition != null and _transition.is_valid():
		_transition.kill()
	_transition = null


func _notification(what: int) -> void:
	if what == NOTIFICATION_VISIBILITY_CHANGED and not is_visible_in_tree():
		set_reveal(1.0 if _premium else 0.0)
	elif what == NOTIFICATION_EXIT_TREE:
		_kill_transition()


func _board_axis(point: float, source_length: float, destination_length: float) -> float:
	if point <= 64.0:
		return point
	if point >= source_length - 64.0:
		return destination_length - source_length + point
	return 64.0 + (point - 64.0) * (destination_length - 128.0) / (source_length - 128.0)


func _board_point(point: Vector2) -> Vector2:
	return Vector2(_board_axis(point.x, SOURCE_SIZE.x, ordinary.size.x),
		_board_axis(point.y, SOURCE_SIZE.y, ordinary.size.y))


func _curled_point(source_point: Vector2, _index: int) -> Vector2:
	# Restored original corner decoration remains planted for both editions.
	return _board_point(source_point)


func material_state() -> Dictionary:
	return {"reveal": reveal, "material_mix": smoothstep(0.0, 0.24, reveal),
		"corner_retraction": 0.0, "rim_repair": 0.0,
		"body_rect": ordinary.get_global_rect(), "body_visible": ordinary.visible,
		"body_alpha": ordinary.modulate.a, "same_original_style": ordinary.style == original,
		"original_material_active": ordinary.material == _original_material,
		"corner_count": corner_leaves.size(), "mesh_vertices": 323}


func corner_motion_data() -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	for index in 4:
		result.append({"index": index,
			"source_region": Rect2(SOURCE_ORIGINS[index], CORNER_EXTENT),
			"root": ordinary.get_global_transform() * _board_point(SOURCE_ROOTS[index]),
			"tip": ordinary.get_global_transform() * _curled_point(SOURCE_TIPS[index], index),
			"alpha": corner_leaves[index].modulate.a,
			"mesh_id": corner_leaves[index].mesh.get_instance_id(),
			"material_id": corner_materials[index].get_instance_id()})
	return result
