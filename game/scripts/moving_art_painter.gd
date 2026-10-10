extends "res://scripts/illustrated_cafe.gd"
## Bakes the original source helpers without a game, simulation or UI.
var atlas
var bake_draws=0
func _ready():set_process(false)
func _draw():
	if atlas==null:return
	bake_draws+=1;opacity=1;use_cached_moving_art=false;use_cached_heads=false;ui_scale=1;zoom=1
	for entry in atlas.entries:
		var region:Rect2=atlas.regions[entry.key]
		art_transform(region.position-entry.bounds.position*atlas.BAKE_SCALE,0,Vector2.ONE*atlas.BAKE_SCALE)
		match entry.type:
			"limb":_round_limb_legacy(Vector2.ZERO,Vector2(0,entry.length),entry.color,entry.width)
			"foot":_foot_legacy(Vector2.ZERO)
			"shadow":_person_shadow_legacy(Vector2.ZERO)
			"fox_tail":_fox_tail_legacy(Vector2.ZERO,"c68b46")
			"apron":_apron_legacy(Vector2.ZERO)
			"tree":_tree_crown_legacy(Vector2.ZERO,1.0)
			"bin":_bin_body_legacy(Vector2.ZERO,int(entry.rotation))
			"body":_body_shape_legacy(Vector2.ZERO,entry.shirt,entry.seated,entry.fwd,entry.side)
	art_transform(Vector2.ZERO)
