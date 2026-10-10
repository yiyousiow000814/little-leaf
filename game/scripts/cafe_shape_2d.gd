extends Node2D
## A procedural shape keeps Godot's original rasterization and cached _draw.
## Moving its parent or changing its transform does not rebuild its geometry.
static var aa_materials = {}
static var aa_shader: Shader
static var contour_shader: Shader
var contour_material: ShaderMaterial
var contour_scale = -1.0
var draw_method: StringName
var draw_arguments: Array = []


func configure(method: StringName, arguments: Array, placement: Transform2D) -> void:
	if method == &"retained_aa_mesh":
		var geometry_changed = (
			draw_method != method or draw_arguments.is_empty() or draw_arguments[0] != arguments[0]
		)
		var width = float(arguments[1]) if arguments.size() > 1 else .7
		if not aa_materials.has(width):
			if aa_shader == null:
				aa_shader = preload("res://shaders/retained_aa_geometry.gdshader")
			var created = ShaderMaterial.new()
			created.shader = aa_shader
			created.set_shader_parameter("stroke_width", width)
			aa_materials[width] = created
		# CanvasItem.set_material does not skip an unchanged resource: it queues
		# a render-tree update and a property-list notification on every call.
		if material != aa_materials[width]:
			material = aa_materials[width]
		if geometry_changed:
			var bounds = arguments[0].get_aabb()
			RenderingServer.canvas_item_set_custom_rect(
				get_canvas_item(),
				true,
				(
					Rect2(
						Vector2(bounds.position.x, bounds.position.y),
						Vector2(bounds.size.x, bounds.size.y)
					)
					. grow(5.0)
				)
			)
	elif method == &"scaled_contours":
		var geometry_changed = (
			draw_method != method or draw_arguments.is_empty() or draw_arguments[0] != arguments[0]
		)
		if contour_material == null:
			if contour_shader == null:
				contour_shader = preload("res://shaders/retained_contours.gdshader")
			contour_material = ShaderMaterial.new()
			contour_material.shader = contour_shader
		if material != contour_material:
			material = contour_material
		var scale_changed = contour_scale != arguments[1]
		if scale_changed:
			contour_scale = arguments[1]
			contour_material.set_shader_parameter("geometry_scale", contour_scale)
		if geometry_changed or scale_changed:
			var bounds = arguments[0].get_aabb()
			var rect = (
				Rect2(
					Vector2(bounds.position.x, bounds.position.y) * contour_scale,
					Vector2(bounds.size.x, bounds.size.y) * contour_scale
				)
				. grow(5.0)
			)
			RenderingServer.canvas_item_set_custom_rect(get_canvas_item(), true, rect)
		arguments = [arguments[0]]
	elif material != null:
		material = null
		RenderingServer.canvas_item_set_custom_rect(get_canvas_item(), false)
	if transform != placement:
		transform = placement
	if draw_method != method or draw_arguments != arguments:
		draw_method = method
		# Callers close outlines by appending to the same packed vertex array
		# after submitting its fill. Own the array snapshot, or the cached fill
		# changes too and appears dirty on every following frame. Godot's deep
		# array copy preserves Resource identities while isolating packed arrays.
		draw_arguments = arguments.duplicate(true)
		queue_redraw()
	show()


func _draw() -> void:
	if draw_method in [&"scaled_contours", &"retained_aa_mesh"]:
		draw_mesh(draw_arguments[0], null)
	elif draw_method == &"scalable_polyline":
		draw_polyline(draw_arguments[0], draw_arguments[1], draw_arguments[2], true)
	elif draw_method == &"scalable_line":
		draw_line(draw_arguments[0], draw_arguments[1], draw_arguments[2], draw_arguments[3], true)
	elif draw_method == &"ordered_triangles":
		RenderingServer.canvas_item_add_triangle_array(
			get_canvas_item(), draw_arguments[0], draw_arguments[1], draw_arguments[2]
		)
	elif draw_method != &"":
		callv(draw_method, draw_arguments)
