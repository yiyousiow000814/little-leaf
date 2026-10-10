extends RefCounted
const Outline = preload("res://scripts/ordered_pocket_triangles.gd")
const LIMIT = 256
var meshes = {}
var builds = 0


func get_mesh(
	points: PackedVector2Array, size: Vector2, tint: Color, raster: Transform2D, raster_scale: float
) -> ArrayMesh:
	var basis = Transform2D(raster.x, raster.y, Vector2.ZERO)
	var key = [size, tint, basis.x, basis.y, raster_scale]
	if meshes.has(key):
		return meshes[key]
	var triangles = Geometry2D.triangulate_polygon(points)
	if triangles.is_empty():
		return null
	var colors = PackedColorArray()
	colors.resize(points.size())
	colors.fill(tint)
	var combined = Outline.new()
	combined.append_triangles(points, colors, triangles)
	var closed = points.duplicate()
	closed.append(closed[0])
	var outline = Outline.new()
	if raster_scale > 1.0:
		if is_zero_approx(basis.determinant()):
			return null
		outline.append_closed_outline(basis * closed, tint, .7 * raster_scale)
		combined.append_triangles(
			basis.affine_inverse() * outline.vertices, outline.colors, outline.indices
		)
	else:
		outline.append_closed_outline(closed, tint, .7)
		combined.append_triangles(outline.vertices, outline.colors, outline.indices)
	var arrays = []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = combined.vertices
	arrays[Mesh.ARRAY_COLOR] = combined.colors
	arrays[Mesh.ARRAY_INDEX] = combined.indices
	var mesh = ArrayMesh.new()
	mesh.add_surface_from_arrays(
		Mesh.PRIMITIVE_TRIANGLES, arrays, [], {}, Mesh.ARRAY_FLAG_USE_2D_VERTICES
	)
	if meshes.size() >= LIMIT:
		meshes.erase(meshes.keys()[0])
	meshes[key] = mesh
	builds += 1
	return mesh


# The core stroke scales with the ellipse. Only its AA fringe needs to remain
# one raster pixel wide; the vertex shader applies the original native rule.
var scalable_meshes = {}


func get_scalable_mesh(points: PackedVector2Array, size: Vector2, tint: Color) -> ArrayMesh:
	var key = [size, tint]
	if scalable_meshes.has(key):
		return scalable_meshes[key]
	var triangles = Geometry2D.triangulate_polygon(points)
	if triangles.is_empty():
		return null
	var colors = PackedColorArray()
	colors.resize(points.size())
	colors.fill(tint)
	var core = Outline.new()
	var full = Outline.new()
	core.append_triangles(points, colors, triangles)
	full.append_triangles(points, colors, triangles)
	var closed = points.duplicate()
	closed.append(closed[0])
	core.append_closed_outline(closed, tint, .7, 0.0)
	full.append_closed_outline(closed, tint, .7, 1.25)
	var offsets = PackedVector2Array()
	for index in range(core.vertices.size()):
		offsets.append(full.vertices[index] - core.vertices[index])
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
	if scalable_meshes.size() >= LIMIT:
		scalable_meshes.erase(scalable_meshes.keys()[0])
	scalable_meshes[key] = mesh
	builds += 1
	return mesh
