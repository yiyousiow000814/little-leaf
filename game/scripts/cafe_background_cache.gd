extends RefCounted
## Retained world geometry. The vertex shader scales centerlines,
## while preserving the reference renderer's screen-space antialias offsets.
const Original = preload("res://scripts/cafe_background_native.gd")
const Neighborhood = preload("res://scripts/exterior_environment.gd")
const Outline = preload("res://scripts/ordered_pocket_triangles.gd")
const Strokes = preload("res://scripts/retained_aa_strokes.gd")
var fallback = Original.new()
var canvas = RID()
var screen_canvas = RID()
var geometry_items: Array[RID] = []
var meshes: Array[ArrayMesh] = []
var material: ShaderMaterial
var signature = []
var rebuilds = 0
var command_count = 0
var used = false
var previous_scale = -1.0
var previous_grass: Mesh


class Painter:
	extends RefCounted
	var origin = Vector2.ZERO
	var tile = Vector2(39, 19.5)
	var zoom = 1.0
	var ui_scale = 1.0
	var opacity = 1.0
	var valid = true
	var full = Outline.new()
	var center = Outline.new()

	func iso(x, z, h = 0.0):
		return Vector2((x - z) * 39, (x + z) * 19.5 - h)

	func get_viewport_rect():
		return Rect2(-100000, -100000, 200000, 200000)

	func render_bounds_visible(_bounds):
		return true

	func col(value):
		var color = Color(value) if value is String else value
		color.a *= opacity
		return color

	func poly(points: Array, value):
		var vertices = PackedVector2Array(points)
		var valid_full = full.append_contour(vertices, col(value), .7)
		var valid_center = center.append_contour(vertices, col(value), 0.0)
		valid = valid and valid_full and valid_center

	func line(a: Vector2, b: Vector2, value, width = 1.0):
		var solid = Strokes.new()
		var zero = Strokes.new()
		solid.add_line(a, b, col(value), width)
		zero.add_line(a, b, col(value), 0.0)
		full.append_triangles(solid.vertices, solid.colors, solid.indices)
		center.append_triangles(zero.vertices, zero.colors, zero.indices)

	func multiline(points: PackedVector2Array, value, width: float):
		for index in range(0, points.size(), 2):
			line(points[index], points[index + 1], value, width)

	func mesh() -> ArrayMesh:
		if not valid or full.vertices.size() != center.vertices.size():
			return null
		var offsets = PackedVector2Array()
		for index in range(full.vertices.size()):
			offsets.append(full.vertices[index] - center.vertices[index])
		var arrays = []
		arrays.resize(Mesh.ARRAY_MAX)
		arrays[Mesh.ARRAY_VERTEX] = center.vertices
		arrays[Mesh.ARRAY_TEX_UV] = offsets
		arrays[Mesh.ARRAY_COLOR] = full.colors
		arrays[Mesh.ARRAY_INDEX] = full.indices
		var result = ArrayMesh.new()
		if not center.vertices.is_empty():
			result.add_surface_from_arrays(
				Mesh.PRIMITIVE_TRIANGLES, arrays, [], {}, Mesh.ARRAY_FLAG_USE_2D_VERTICES
			)
		# Vertex expansion happens in the shader. Culling must include all legal
		# camera scales rather than relying on the unscaled mesh AABB.
		result.custom_aabb = AABB(Vector3(-100000, -100000, -1), Vector3(200000, 200000, 2))
		return result


func _new_item(parent: RID, index: int) -> RID:
	var item = RenderingServer.canvas_item_create()
	RenderingServer.canvas_item_set_parent(item, parent)
	RenderingServer.canvas_item_set_draw_index(item, index)
	return item


func hide():
	fallback.hide()
	if canvas.is_valid():
		RenderingServer.canvas_item_set_visible(canvas, false)
	if screen_canvas.is_valid():
		RenderingServer.canvas_item_set_visible(screen_canvas, false)
	used = false


func release():
	fallback.release()
	for item in geometry_items:
		RenderingServer.free_rid(item)
	geometry_items.clear()
	meshes.clear()
	if canvas.is_valid():
		RenderingServer.free_rid(canvas)
		canvas = RID()
	if screen_canvas.is_valid():
		RenderingServer.free_rid(screen_canvas)
		screen_canvas = RID()
	signature = []
	used = false
	previous_scale = -1.0
	previous_grass = null
	material = null


func _notification(what):
	if what == NOTIFICATION_PREDELETE:
		for item in geometry_items:
			RenderingServer.free_rid(item)
		if canvas.is_valid():
			RenderingServer.free_rid(canvas)
		if screen_canvas.is_valid():
			RenderingServer.free_rid(screen_canvas)


func update(artist, landed_origin = null, presentation_offset = Vector2.ZERO) -> bool:
	if (
		artist.material != null
		or artist.use_parent_material
		or artist.self_modulate != Color.WHITE
		or artist.clip_children != CanvasItem.CLIP_CHILDREN_DISABLED
		or artist.light_mask != 1
		or artist.visibility_layer != 1
		or artist.y_sort_enabled
		or not artist.use_batched_ground
		or not artist.use_grass_mesh
		or artist.get_global_transform_with_canvas() != Transform2D.IDENTITY
		or artist._art_transform != Transform2D(0, presentation_offset)
	):
		hide()
		return fallback.update(artist, landed_origin, presentation_offset)
	fallback.hide()
	var size = artist.get_viewport_rect().size
	artist.prepare_grass(size)
	var key = [
		artist._parking_owned(),
		artist.ui_scale,
		artist.opacity,
		size,
		artist.grass_mesh,
		artist.ground_art.pavement_mesh
	]
	if not canvas.is_valid():
		canvas = _new_item(artist.get_canvas_item(), -1)
		RenderingServer.canvas_item_set_draw_behind_parent(canvas, true)
		screen_canvas = _new_item(artist.get_canvas_item(), -2)
		RenderingServer.canvas_item_set_draw_behind_parent(screen_canvas, true)
		var shader = preload("res://shaders/retained_contours.gdshader")
		material = ShaderMaterial.new()
		material.shader = shader
		for index in range(3):
			var item = _new_item(canvas, index)
			RenderingServer.canvas_item_set_material(item, material.get_rid())
			RenderingServer.canvas_item_set_custom_rect(
				item, true, Rect2(-100000, -100000, 200000, 200000)
			)
			geometry_items.append(item)
	if signature != key:
		var ground = Painter.new()
		ground.ui_scale = artist.ui_scale
		ground.opacity = artist.opacity
		Neighborhood.draw_ground(ground, artist._parking_owned())
		var paving = Painter.new()
		paving.ui_scale = artist.ui_scale
		for index in range(2):
			paving.multiline(
				artist.ground_art.pavement_edges[index],
				artist.ground_art.PAVEMENT_COLORS[index],
				.7
			)
		paving.multiline(artist.ground_art.pavement_grid, Color("c7cbae"), .7)
		var crossing = Painter.new()
		crossing.ui_scale = artist.ui_scale
		crossing.opacity = artist.opacity
		Neighborhood.draw_crossing(crossing, artist._parking_owned())
		var next_meshes: Array[ArrayMesh] = [ground.mesh(), paving.mesh(), crossing.mesh()]
		if null in next_meshes:
			hide()
			return fallback.update(artist, landed_origin, presentation_offset)
		meshes = next_meshes
		for index in range(3):
			RenderingServer.canvas_item_clear(geometry_items[index])
			if index == 1:
				RenderingServer.canvas_item_add_mesh(
					geometry_items[index],
					artist.ground_art.pavement_mesh.get_rid(),
					Transform2D.IDENTITY,
					Color.WHITE
				)
			if meshes[index].get_surface_count() > 0:
				RenderingServer.canvas_item_add_mesh(geometry_items[index], meshes[index].get_rid())
		RenderingServer.canvas_item_clear(screen_canvas)
		RenderingServer.canvas_item_add_rect(
			screen_canvas, Rect2(Vector2.ZERO, size), Color("c6d5ad")
		)
		signature = key.duplicate()
		rebuilds += 1
		command_count = 6
	var scale = artist.tile.x / 39.0
	if previous_scale != scale:
		material.set_shader_parameter("geometry_scale", scale)
	RenderingServer.canvas_item_set_transform(
		canvas, Transform2D(0, artist.origin + presentation_offset)
	)
	# Grass uses its original world-space tapered mesh, including its original
	# scale-dependent feather. Keep it outside the screen-width shader.
	if previous_scale != scale or previous_grass != artist.grass_mesh:
		RenderingServer.canvas_item_clear(canvas)
		RenderingServer.canvas_item_add_mesh(
			canvas,
			artist.grass_mesh.get_rid(),
			Transform2D(0, Vector2.ONE * scale, 0, Vector2.ZERO),
			Color.WHITE
		)
		previous_scale = scale
		previous_grass = artist.grass_mesh
	RenderingServer.canvas_item_set_visible(canvas, true)
	RenderingServer.canvas_item_set_visible(screen_canvas, true)
	used = true
	return true
