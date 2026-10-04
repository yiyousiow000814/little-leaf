extends "res://scripts/illustrated_cafe.gd"
## Bake-only source artist; no game, profile, simulation or live state.
var atlas
var bake_draws:=0
func _ready():set_process(false)
func _draw():
	if atlas==null:return
	bake_draws+=1;opacity=1.0;use_cached_heads=false
	for entry in atlas.entries:
		var region:Rect2=atlas.regions[atlas.key(entry.species,entry.away,entry.blink,entry.chef,entry.blocked,entry.view)]
		var anchor:Vector2=region.position-atlas.ART_RECT.position*atlas.BAKE_SCALE
		draw_set_transform(anchor,0,Vector2.ONE*atlas.BAKE_SCALE)
		_draw_head_legacy(Vector2.ZERO,entry.species,entry.away,entry.blink,entry.chef,entry.blocked,entry.view)
	draw_set_transform(Vector2.ZERO)
