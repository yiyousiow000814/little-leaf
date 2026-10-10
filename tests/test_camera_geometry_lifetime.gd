extends SceneTree

const Background = preload("res://scripts/cafe_background_cache.gd")
const Body = preload("res://scripts/cafe_native_draw_node.gd")
const Shape = preload("res://scripts/cafe_shape_2d.gd")
const BodyGeometry = preload("res://scripts/scalable_body_geometry.gd")

class TestGame extends "res://scripts/main.gd":
	func _load_startup():
		save_writes_suppressed = true
		fresh_start = true
		model = Model.new()
		MinimalStart.apply(model)
	func _save(): return true
	func _setup_music(): pass

var checks = 0
var failures = []

func check(ok: bool, label: String):
	checks += 1
	if not ok:
		failures.append(label)
		push_error(label)

func _initialize(): run.call_deferred()

func run():
	root.size = Vector2i(1278, 1222)
	var game = TestGame.new()
	root.add_child(game)
	game.set_process(false)
	game.cafe_intro.finish()
	game.paused = true
	var artist = game.illustration
	artist.set_process(false)
	for tween in get_processed_tweens(): tween.kill()
	artist.update_projection()
	artist.ground_art.prepare(game.model)
	artist._presentation_offset = Vector2.ZERO
	artist._art_transform = Transform2D.IDENTITY
	var cache = Background.new()
	check(cache.update(artist), "initial background is eligible")
	var builds = cache.rebuilds
	var retained = cache.meshes.duplicate()
	for scale in [.7, 1.15, 2.0, 4.0, 13.0, .7]:
		artist.zoom = scale
		artist.tile = Vector2(39, 19.5) * artist.ui_scale * scale
		artist.origin += Vector2(43, -17)
		check(cache.update(artist), "camera update remains eligible")
		check(cache.rebuilds == builds, "pan and zoom reuse background geometry")
		check(cache.meshes == retained, "camera motion preserves mesh resources")
	cache.release()
	check(not cache.canvas.is_valid() and cache.meshes.is_empty(), "release clears retained resources")
	check(cache.previous_scale == -1.0 and cache.previous_grass == null and cache.material == null,
		"release clears transform and material state")
	check(cache.update(artist), "released cache can be reused at the same camera pose")
	check(cache.material != null and is_equal_approx(cache.previous_scale, artist.tile.x / 39.0),
		"reuse initializes the shader scale")
	cache.release()

	var invalid = Background.Painter.new()
	invalid.poly([Vector2.ZERO, Vector2.ONE], Color.WHITE)
	check(not invalid.valid and invalid.mesh() == null, "invalid geometry rejects the complete optimized mesh")
	var unsupported = Shape.new()
	unsupported.draw_method = &"draw_rect"
	unsupported.draw_arguments = [Rect2(0, 0, 10, 10), Color.WHITE]
	check(BodyGeometry.build([unsupported], 1).is_empty(), "unsupported command rejects the complete body")
	unsupported.free()
	var appearance = ["torso", "unsupported-regression"]
	check(Body.can_retain_scalable_body(appearance), "new body can attempt retained geometry")
	Body.unsupported_body_shapes[appearance] = true
	check(not Body.can_retain_scalable_body(appearance), "rejected body uses scale-aware native fallback")
	Body.unsupported_body_shapes.erase(appearance)

	game.queue_free()
	await process_frame
	print("CAMERA_GEOMETRY_LIFETIME_RESULT ", JSON.stringify({"checks": checks, "failures": failures}))
	quit(0 if failures.is_empty() else 1)
