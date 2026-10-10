extends RefCounted
## Retained native commands for the exact static prefix of IllustratedCafe._draw.
## No image baking, downsampling, geometry welding or reordered commands.
const Neighborhood = preload("res://scripts/exterior_environment.gd")
var server = RenderingServer
var canvas = RID()
var screen_canvas = RID()
var signature = []
var rebuilds = 0
var command_count = 0
var used = false


class NativeArtist:
	extends RefCounted
	var source
	var server = RenderingServer
	var canvas: RID
	var origin: Vector2
	var tile: Vector2
	var ui_scale: float
	var zoom: float
	var opacity: float
	var commands = 0
	var view_override = Rect2()

	func _init(artist, rid: RID):
		source = artist
		canvas = rid
		origin = artist.origin
		tile = artist.tile
		ui_scale = artist.ui_scale
		zoom = artist.zoom
		opacity = artist.opacity

	func iso(x, z, h = 0.0):
		return source.iso(x, z, h)

	func get_viewport_rect():
		return view_override if view_override.has_area() else source.get_viewport_rect()

	func render_bounds_visible(bounds):
		if view_override.has_area():
			return (
				not source.use_screen_culling
				or preload("res://scripts/cafe_render_visibility.gd").visible(
					bounds, view_override, 6.0
				)
			)
		return source.render_bounds_visible(bounds)

	func col(value):
		var color = Color(value) if value is String else value
		color.a *= opacity
		return color

	func art_transform(offset: Vector2, rotation: float = 0.0, scale: Vector2 = Vector2.ONE):
		server.canvas_item_add_set_transform(canvas, Transform2D(rotation, scale, 0.0, offset))
		commands += 1

	func draw_rect(rect: Rect2, color: Color):
		server.canvas_item_add_rect(canvas, rect, color)
		commands += 1

	func draw_mesh(
		mesh: Mesh,
		texture: Texture2D = null,
		placement: Transform2D = Transform2D.IDENTITY,
		tint: Color = Color.WHITE
	):
		var texture_rid = texture.get_rid() if texture != null else RID()
		server.canvas_item_add_mesh(canvas, mesh.get_rid(), placement, tint, texture_rid)
		commands += 1

	func draw_multiline(
		points: PackedVector2Array, color: Color, width: float = -1.0, antialiased: bool = false
	):
		server.canvas_item_add_multiline(
			canvas, points, PackedColorArray([color]), width, antialiased
		)
		commands += 1

	func poly(points: Array, color):
		var vertices = PackedVector2Array(points)
		var tint = col(color)
		server.canvas_item_add_polygon(canvas, vertices, PackedColorArray([tint]))
		commands += 1
		vertices.append(vertices[0])
		server.canvas_item_add_polyline(canvas, vertices, PackedColorArray([tint]), .7, true)
		commands += 1

	func line(a: Vector2, b: Vector2, color, width = 1.0):
		server.canvas_item_add_line(canvas, a, b, col(color), width, true)
		commands += 1


func release():
	if screen_canvas.is_valid():
		server.free_rid(screen_canvas)
		screen_canvas = RID()
	if canvas.is_valid():
		server.free_rid(canvas)
		canvas = RID()
	signature = []
	used = false


func _notification(what):
	if what == NOTIFICATION_PREDELETE:
		if canvas.is_valid():
			server.free_rid(canvas)
		if screen_canvas.is_valid():
			server.free_rid(screen_canvas)


func hide():
	if canvas.is_valid():
		server.canvas_item_set_visible(canvas, false)
	if screen_canvas.is_valid():
		server.canvas_item_set_visible(screen_canvas, false)
	used = false


func update(artist, landed_origin = null, presentation_offset = Vector2.ZERO) -> bool:
	# Nonstandard/inspection paths keep their existing helpers, including stroke
	# compensation under outer canvas transforms. Ordinary world art is identity.
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
		return false
	var size = artist.get_viewport_rect().size
	artist.prepare_grass(size)
	if artist.ground_art.use_stroke_mesh:
		artist.ground_art.prepare_pavement_strokes(artist.tile.x / 39.0)
	var parking_owned = artist._parking_owned()
	var translated = landed_origin != null
	var base_origin: Vector2 = landed_origin if translated else artist.origin
	var offset: Vector2 = artist.origin - base_origin + presentation_offset
	var key = [
		artist.ground_art.use_stroke_mesh,
		parking_owned,
		base_origin,
		artist.tile,
		artist.ui_scale,
		artist.zoom,
		artist.opacity,
		size,
		artist.game.wall_detail,
		artist.use_screen_culling,
		artist.grass_mesh,
		artist.ground_art.pavement_mesh,
		artist.ground_art.pavement_stroke_mesh,
		translated
	]
	if not canvas.is_valid():
		canvas = server.canvas_item_create()
		server.canvas_item_set_parent(canvas, artist.get_canvas_item())
		server.canvas_item_set_draw_behind_parent(canvas, true)
		server.canvas_item_set_draw_index(canvas, -1)
	if translated and not screen_canvas.is_valid():
		screen_canvas = server.canvas_item_create()
		server.canvas_item_set_parent(screen_canvas, artist.get_canvas_item())
		server.canvas_item_set_draw_behind_parent(screen_canvas, true)
		server.canvas_item_set_draw_index(screen_canvas, -2)
	if key != signature:
		server.canvas_item_clear(canvas)
		var saved_origin = artist.origin
		artist.origin = base_origin
		var painter = NativeArtist.new(artist, canvas)
		painter.server = server
		if translated:
			# Cache the union of all view positions in the natural descent before
			# revealing Welcome. Only the retained canvas transform then moves.
			painter.view_override = Rect2(
				Vector2(0, -size.y * 1.35), Vector2(size.x, size.y * 2.35)
			)
			server.canvas_item_clear(screen_canvas)
			server.canvas_item_add_rect(screen_canvas, Rect2(Vector2.ZERO, size), Color("c6d5ad"))
		else:
			painter.draw_rect(Rect2(Vector2.ZERO, size), Color("c6d5ad"))
		painter.art_transform(artist.origin, 0, Vector2.ONE * (artist.tile.x / 39.0))
		painter.draw_mesh(artist.grass_mesh, null)
		painter.art_transform(Vector2.ZERO)
		Neighborhood.draw_ground(painter, parking_owned)
		artist.ground_art.draw_pavement(painter)
		Neighborhood.draw_crossing(painter, parking_owned)
		artist.origin = saved_origin
		command_count = painter.commands
		signature = key.duplicate()
		rebuilds += 1
	if translated:
		server.canvas_item_set_transform(canvas, Transform2D(0, offset))
		server.canvas_item_set_visible(screen_canvas, true)
	elif screen_canvas.is_valid():
		server.canvas_item_set_transform(canvas, Transform2D.IDENTITY)
		server.canvas_item_set_visible(screen_canvas, false)
	server.canvas_item_set_visible(canvas, true)
	used = true
	return true
