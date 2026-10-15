extends "res://scripts/rendering/illustrated_cafe.gd"
## Bake-only artist. Inherits the live renderer's unchanged native primitives.
## This object has no game, does not process, and draws no live service state.
var atlas
var bake_draws := 0
var bake_parts: Array = []
var bake_regions: Dictionary = {}
var bake_bounds: Dictionary = {}

func _ready(): set_process(false)

func _draw():
	if atlas==null: return
	bake_draws+=1
	opacity=1.0
	furniture_art.cache_enabled=false
	var parts: Array=bake_parts if not bake_parts.is_empty() else atlas.PARTS
	var regions: Dictionary=bake_regions if not bake_regions.is_empty() else atlas.regions
	for part in parts:
		for rotation in atlas.rotations_for(part):
			var region: Rect2=regions[atlas.key(part,rotation)]
			var part_bounds: Rect2=bake_bounds[part] if not bake_bounds.is_empty() else atlas.bounds(part)
			var anchor: Vector2=region.position-part_bounds.position*atlas.BAKE_SCALE
			art_transform(anchor,0,Vector2.ONE*atlas.BAKE_SCALE)
			furniture_art.draw_static_part(self,part,Vector2.ZERO,rotation)
	art_transform(Vector2.ZERO)
