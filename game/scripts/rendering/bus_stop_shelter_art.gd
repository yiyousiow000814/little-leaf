extends RefCounted
## Accepted D textures keep the original full canvas and world pivot.
## Common sampling is asset-local; current-source native validation is pending.
const CanvasDraw = preload("res://scripts/rendering/cafe_canvas_draw.gd")
const BACK = preload("res://assets/exterior/bus_stop_c/C-back.png")
const FRONT = preload("res://assets/exterior/bus_stop_c/C-front.png")
const BACK_ID = "4793fa9e59c13322668311784817c0fd0341c8c3acfe01266bd1b7f92aca6e83"
const FRONT_ID = "b346c9e687cc2e6f66eb1e320075187a3a6c6e0cefd6c93985ac6d004646d73f"
const BACK_MATERIAL = preload("res://assets/exterior/bus_stop_c/common-back.tres")
const SAMPLING_ID = "post-sample-whole-front-v1"
const CANVAS = Vector2(384, 320)
const PIVOT = Vector2(192, 200)
const ANCHOR = Vector2(-12.55, 7.95)

static func draw(artist, front: bool, world_offset: Vector2 = Vector2.ZERO) -> bool:
	# Projection-only test artists keep the original procedural painter fallback.
	if not artist.has_method("art_draw_texture_rect_region") and not artist.has_method("draw_texture_rect_region"):
		return false
	var scale: float = artist.tile.x / 39.0
	if scale <= 0.0:
		return false
	var texture: Texture2D = FRONT if front else BACK
	var anchor = ANCHOR + world_offset
	var rect = Rect2(artist.iso(anchor.x, anchor.y) - PIVOT * scale, CANVAS * scale)
	var draw_target = artist.get("native_draw_target") if artist is Node2D else null
	var cursor: int = draw_target.shape_cursor if draw_target != null else -1
	CanvasDraw.draw_texture_rect_region(artist, texture, rect, Rect2(Vector2.ZERO, texture.get_size()), artist.col(Color.WHITE))
	if not front and draw_target != null and draw_target.shape_cursor == cursor + 1:
		var shape = draw_target.shapes[cursor]
		if shape.draw_method == &"draw_texture_rect_region" and shape.draw_arguments[0] == BACK:
			# configure() already resets materials when the retained slot is reused.
			# Rebind only on appearance redraw, never an unchanged material each frame.
			if shape.material != BACK_MATERIAL:
				shape.material = BACK_MATERIAL
	return true
