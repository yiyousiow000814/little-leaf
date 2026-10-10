extends RefCounted
## Merge adjacent commands with the same AA width, preserving painter order.
## Mesh vertices hold the original stroke core; UV holds its AA fringe offset.
const Outline = preload("res://scripts/ordered_pocket_triangles.gd")
const Strokes = preload("res://scripts/retained_aa_strokes.gd")


static func build(shapes: Array, count: int) -> Array:
	var segments = []
	var current = {}
	for index in range(count):
		var shape = shapes[index]
		if not "draw_method" in shape:
			return []
		var args = shape.draw_arguments
		var core = Outline.new()
		var full = Outline.new()
		var width = float(current.get("width", .7))
		match shape.draw_method:
			&"draw_colored_polygon":
				if not args[2].is_empty() or args[3] != null:
					return []
				var triangles = Geometry2D.triangulate_polygon(args[0])
				if triangles.is_empty():
					return []
				var colors = PackedColorArray()
				colors.resize(args[0].size())
				colors.fill(args[1])
				core.append_triangles(args[0], colors, triangles)
				full.append_triangles(args[0], colors, triangles)
			&"scalable_polyline":
				width = args[2]
				core.append_closed_outline(args[0], args[1], width, 0.0)
				full.append_closed_outline(args[0], args[1], width, 1.25)
			&"scalable_line":
				width = args[3]
				var a = Strokes.new()
				var b = Strokes.new()
				a.add_line(args[0], args[1], args[2], width, 0.0)
				b.add_line(args[0], args[1], args[2], width, 1.25)
				core.append_triangles(a.vertices, a.colors, a.indices)
				full.append_triangles(b.vertices, b.colors, b.indices)
			&"retained_aa_mesh":
				width = .7
				var arrays = args[0].surface_get_arrays(0)
				var vertices = PackedVector2Array()
				for point in arrays[Mesh.ARRAY_VERTEX]:
					vertices.append(Vector2(point.x, point.y))
				core.append_triangles(vertices, arrays[Mesh.ARRAY_COLOR], arrays[Mesh.ARRAY_INDEX])
				var offsets = arrays[Mesh.ARRAY_TEX_UV]
				for vertex in range(vertices.size()):
					vertices[vertex] += offsets[vertex]
				full.append_triangles(vertices, arrays[Mesh.ARRAY_COLOR], arrays[Mesh.ARRAY_INDEX])
			_:
				return []
		# Body commands have unit local transforms; the parent owns camera scale.
		var placement = shape.transform
		if (
			not is_equal_approx(placement.x.length_squared(), 1.0)
			or not is_equal_approx(placement.y.length_squared(), 1.0)
			or not is_zero_approx(placement.x.dot(placement.y))
		):
			return []
		if current.is_empty() or not is_equal_approx(current.width, width):
			current = {"width": width, "core": Outline.new(), "full": Outline.new()}
			segments.append(current)
		current.core.append_triangles(placement * core.vertices, core.colors, core.indices)
		current.full.append_triangles(placement * full.vertices, full.colors, full.indices)
	var result = []
	for segment in segments:
		var core = segment.core
		var offsets = PackedVector2Array()
		for index in range(core.vertices.size()):
			offsets.append(segment.full.vertices[index] - core.vertices[index])
		var arrays = []
		arrays.resize(Mesh.ARRAY_MAX)
		arrays[Mesh.ARRAY_VERTEX] = core.vertices
		arrays[Mesh.ARRAY_COLOR] = core.colors
		arrays[Mesh.ARRAY_TEX_UV] = offsets
		arrays[Mesh.ARRAY_INDEX] = core.indices
		var mesh = ArrayMesh.new()
		mesh.add_surface_from_arrays(
			Mesh.PRIMITIVE_TRIANGLES, arrays, [], {}, Mesh.ARRAY_FLAG_USE_2D_VERTICES
		)
		result.append([mesh, segment.width])
	return result
