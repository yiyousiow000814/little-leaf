extends RefCounted
const Background = preload("res://scripts/cafe_background_cache.gd")
const Neighborhood = preload("res://scripts/exterior_environment.gd")
var meshes = {}


class Painter:
	extends Background.Painter
	var circle = PackedVector2Array()

	func poly(points: Array, value):
		var vertices = PackedVector2Array(points)
		var a = full.append_contour(vertices, col(value), .7)
		# Keep both tessellations paired, even if one input is invalid.
		var b = center.append_contour(vertices, col(value), 0.0)
		valid = valid and a and b

	func ellipse(at: Vector2, size: Vector2, value):
		poly(Array(Transform2D(Vector2(size.x, 0), Vector2(0, size.y), at) * circle), value)

	func rounded_poly(points: Array, r: float, value):
		var smooth = []
		for i in range(points.size()):
			var vertex: Vector2 = points[i]
			var previous: Vector2 = points[(i + points.size() - 1) % points.size()]
			var following: Vector2 = points[(i + 1) % points.size()]
			var a = (
				vertex
				+ (previous - vertex).normalized() * minf(r, vertex.distance_to(previous) * .3)
			)
			var b = (
				vertex
				+ (following - vertex).normalized() * minf(r, vertex.distance_to(following) * .3)
			)
			for k in range(6):
				var t = float(k) / 5.0
				smooth.append((1 - t) * (1 - t) * a + 2 * (1 - t) * t * vertex + t * t * b)
		poly(smooth, value)


func draw(artist, at: Vector2, direction: int, color) -> bool:
	var key = [direction, color, artist.opacity]
	if not meshes.has(key):
		var painter = Painter.new()
		painter.circle = artist._unit_circle
		painter.opacity = artist.opacity
		Neighborhood.draw_car(painter, Vector2.ZERO, direction, color)
		if not painter.valid:
			return false
		var mesh = painter.mesh()
		if mesh == null:
			return false
		mesh.custom_aabb = AABB()
		if meshes.size() >= 64:
			meshes.erase(meshes.keys()[0])
		meshes[key] = mesh
	artist.draw_scaled_contours(meshes[key], artist.iso(at.x, at.y), artist.ui_scale * artist.zoom)
	return true
