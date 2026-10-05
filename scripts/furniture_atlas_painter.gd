extends "res://scripts/illustrated_cafe.gd"
## Bake-only artist. Inherits the live renderer's unchanged native primitives.
## This object has no game, does not process, and draws no live service state.
var atlas
var bake_draws := 0

func _ready(): set_process(false)

func _draw():
	if atlas==null: return
	bake_draws+=1
	opacity=1.0
	furniture_art.cache_enabled=false
	for part in atlas.PARTS:
		for rotation in atlas.rotations_for(part):
			var region: Rect2=atlas.regions[atlas.key(part,rotation)]
			var anchor: Vector2=region.position-atlas.bounds(part).position*atlas.BAKE_SCALE
			art_transform(anchor,0,Vector2.ONE*atlas.BAKE_SCALE)
			furniture_art.draw_static_part(self,part,Vector2.ZERO,rotation)
	art_transform(Vector2.ZERO)
