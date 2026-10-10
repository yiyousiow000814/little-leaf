extends RefCounted
## Conservative, render-only bounds. Unknown projections fail open.
static func visible(bounds:Rect2,viewport:Rect2,padding:float=4.0)->bool:
	if not bounds.position.is_finite() or not bounds.size.is_finite():return true
	return bounds.abs().grow(padding).intersects(viewport,true)
static func points_bounds(points)->Rect2:
	if points.is_empty():return Rect2()
	var bounds=Rect2(points[0],Vector2.ZERO)
	for point in points:bounds=bounds.expand(point)
	return bounds
static func local_bounds(anchor:Vector2,scale:float,bounds:Rect2)->Rect2:
	return Rect2(anchor+bounds.position*scale,bounds.size*scale).abs()
