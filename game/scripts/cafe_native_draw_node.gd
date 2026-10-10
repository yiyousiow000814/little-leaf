extends Node2D
const Outline = preload("res://scripts/ordered_pocket_triangles.gd")
static var use_merged_native_geometry = true
const Strokes = preload("res://scripts/retained_aa_strokes.gd")
static var rigid_meshes = {}
static var body_meshes = {}
static var unsupported_body_shapes = {}
const BodyGeometry = preload("res://scripts/scalable_body_geometry.gd")
static var rigid_hits = 0
static var rigid_builds = 0
## Godot owns this node's cached draw list. Translation never queues a redraw.
var artist: Node2D
var paint: Callable
var appearance: Array = []
var generation: int = -1
var draw_order: int = 0
var paint_opacity: float = 1.0
var draw_count: int = 0
var contacts: Array = []
var resources: Array[Resource] = []
const CafeShape = preload("res://scripts/cafe_shape_2d.gd")
var shapes: Array[Node2D] = []
var shape_cursor: int = 0


func _child_at_cursor(script: Script) -> Node2D:
	if shape_cursor == shapes.size():
		shapes.append(null)
	if shapes[shape_cursor] == null or shapes[shape_cursor].get_script() != script:
		if shapes[shape_cursor] != null:
			shapes[shape_cursor].hide()
			remove_child(shapes[shape_cursor])
			shapes[shape_cursor].queue_free()
		var child = script.new()
		add_child(child)
		move_child(child, shape_cursor)
		shapes[shape_cursor] = child
	return shapes[shape_cursor]


func submit_shape(method: StringName, arguments: Array, placement: Transform2D) -> void:
	var shape = _child_at_cursor(CafeShape)
	shape.configure(method, arguments, placement)
	shape_cursor += 1


func submit_group(source: Node2D, callback: Callable, next: Array, placement: Transform2D) -> void:
	var group = _child_at_cursor(get_script())
	group.configure(source, callback, next, placement)
	# The character node already inherits the artist's self modulation.
	group.modulate = Color.WHITE
	shape_cursor += 1


func configure(source: Node2D, callback: Callable, next: Array, placement: Transform2D) -> void:
	artist = source
	paint_opacity = source.opacity
	if transform != placement:
		transform = placement
	if modulate != source.self_modulate:
		modulate = source.self_modulate
	if light_mask != source.light_mask:
		light_mask = source.light_mask
	if visibility_layer != source.visibility_layer:
		visibility_layer = source.visibility_layer
	if appearance != next:
		appearance = next.duplicate(true)
		paint = callback
		contacts.clear()
		queue_redraw()
	show()


func _draw() -> void:
	if uses_scalable_body() and body_meshes.has(appearance):
		draw_count += 1
		rigid_hits += 1
		_apply_body_segments(body_meshes[appearance])
		return
	if _rigid_key_supported() and rigid_meshes.has(appearance):
		draw_count += 1
		rigid_hits += 1
		resources.clear()
		resources.append(rigid_meshes[appearance])
		draw_mesh(rigid_meshes[appearance], null)
		for child in shapes:
			child.hide()
		return
	draw_count += 1
	resources.clear()
	shape_cursor = 0
	if is_instance_valid(artist) and paint.is_valid():
		artist.paint_native_object(self, paint)
	if uses_scalable_body():
		var segments = BodyGeometry.build(shapes, shape_cursor)
		if not segments.is_empty():
			if body_meshes.size() >= 128:
				body_meshes.erase(body_meshes.keys()[0])
			body_meshes[appearance] = segments
			rigid_builds += 1
			_apply_body_segments(segments)
			return
		# Reject the whole optimized body before showing any of its commands.
		# Repaint through the original raster rules, and include scale in future
		# invalidation keys for this unsupported appearance.
		unsupported_body_shapes[appearance[0].duplicate(true)] = true
		resources.clear()
		shape_cursor = 0
		artist.paint_native_object(self, paint)
	var merged = _draw_merged_geometry()
	for index in range(shapes.size()):
		if shapes[index].visible != (index < shape_cursor and not merged):
			shapes[index].visible = index < shape_cursor and not merged


func _draw_merged_geometry() -> bool:
	if not _rigid_key_supported():
		return false
	# Preserve the object's complete painter sequence in one engine triangle list.
	# Reject unsupported commands before emitting anything, so the original
	# child CanvasItems remain an all-or-nothing fallback.
	var combined = Outline.new()
	for index in range(shape_cursor):
		var shape = shapes[index]
		if shape.get_script() != CafeShape:
			return false
		var arguments = shape.draw_arguments
		var part = Outline.new()
		if (
			shape.draw_method == &"draw_colored_polygon"
			and arguments[2].is_empty()
			and arguments[3] == null
		):
			var triangles = Geometry2D.triangulate_polygon(arguments[0])
			if triangles.is_empty():
				return false
			var colors = PackedColorArray()
			colors.resize(arguments[0].size())
			colors.fill(arguments[1])
			part.append_triangles(arguments[0], colors, triangles)
		elif (
			shape.draw_method == &"draw_polyline"
			and arguments[3]
			and arguments[2] > 0
			and arguments[0].size() > 3
			and arguments[0][0].is_equal_approx(arguments[0][-1])
		):
			part.append_closed_outline(arguments[0], arguments[1], arguments[2])
		elif (
			shape.draw_method == &"draw_mesh"
			and arguments[1] == null
			and arguments[2] == Transform2D.IDENTITY
			and arguments[3] == Color.WHITE
			and arguments[0].get_surface_count() == 1
		):
			var arrays = arguments[0].surface_get_arrays(0)
			if arrays[Mesh.ARRAY_TEX_UV] != null and not arrays[Mesh.ARRAY_TEX_UV].is_empty():
				return false
			var vertices = PackedVector2Array()
			for point in arrays[Mesh.ARRAY_VERTEX]:
				vertices.append(Vector2(point.x, point.y))
			part.append_triangles(vertices, arrays[Mesh.ARRAY_COLOR], arrays[Mesh.ARRAY_INDEX])
		elif shape.draw_method == &"draw_line" and arguments[4] and arguments[3] > 0:
			var stroke = Strokes.new()
			stroke.add_line(arguments[0], arguments[1], arguments[2], arguments[3])
			part.append_triangles(stroke.vertices, stroke.colors, stroke.indices)
		else:
			return false
		combined.append_triangles(shape.transform * part.vertices, part.colors, part.indices)
	if combined.indices.is_empty():
		return false
	var arrays = []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = combined.vertices
	arrays[Mesh.ARRAY_COLOR] = combined.colors
	arrays[Mesh.ARRAY_INDEX] = combined.indices
	var mesh = ArrayMesh.new()
	mesh.add_surface_from_arrays(
		Mesh.PRIMITIVE_TRIANGLES, arrays, [], {}, Mesh.ARRAY_FLAG_USE_2D_VERTICES
	)
	if rigid_meshes.size() >= 128:
		rigid_meshes.erase(rigid_meshes.keys()[0])
	rigid_meshes[appearance] = mesh
	rigid_builds += 1
	resources.append(mesh)
	draw_mesh(mesh, null)
	return true


func _rigid_key_supported() -> bool:
	if uses_scalable_body() or appearance.size() == 2:
		return false
	return (
		use_merged_native_geometry
		and not appearance.is_empty()
		and not appearance[0].is_empty()
		and appearance[0][0] in ["torso", "apparel", "bus", "shelter-back", "shelter-front"]
	)


func uses_scalable_body() -> bool:
	return appearance.size() == 2 and can_retain_scalable_body(appearance[0])


static func can_retain_scalable_body(shape: Array) -> bool:
	return (
		use_merged_native_geometry
		and not shape.is_empty()
		and shape[0] in ["torso", "apparel"]
		and not unsupported_body_shapes.has(shape)
	)


func _apply_body_segments(segments: Array):
	shape_cursor = 0
	resources.clear()
	for segment in segments:
		resources.append(segment[0])
		submit_shape(&"retained_aa_mesh", segment, Transform2D.IDENTITY)
	for index in range(shape_cursor, shapes.size()):
		shapes[index].hide()
