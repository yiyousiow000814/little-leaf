extends SceneTree
## Actual Main/IllustratedCafe, fully synthetic startup; no player save reads/writes.
class TestMain:
	extends "res://scripts/main.gd"
	var save_attempts = 0
	func _load_startup():
		save_writes_suppressed = true
		fresh_start = true
		MinimalStart.apply(model)
	func _save():
		save_attempts += 1
		return true

var game
var checks = 0
var failures: Array = []
var directory: String
var records: Array = []

func _initialize(): run.call_deferred()

func check(condition: bool, message: String):
	checks += 1
	if not condition: failures.append(message)

func ring_nodes() -> Array:
	var result: Array = []
	for node in game.illustration.native_object_nodes.values():
		if node.visible and not node.appearance.is_empty() and node.appearance[0] is Array and node.appearance[0][0] == "staff-ground-ring": result.append(node)
	return result

func capture(name: String) -> Image:
	game.illustration.queue_redraw()
	for frame in range(6): await process_frame
	await RenderingServer.frame_post_draw
	var image = root.get_texture().get_image()
	image.save_png(directory.path_join(name))
	var nodes = ring_nodes()
	records.append({"capture": name, "rings": nodes.size(), "draw_counts": nodes.map(func(n):return n.draw_count), "positions": nodes.map(func(n):return str(n.transform.origin)), "clock": game.animation_time, "editing": game.editing, "zoom": game.illustration.zoom})
	return image

func run():
	directory = OS.get_environment("STAFF_RING_OUTPUT")
	root.size = Vector2i(1360, 880)
	seed(1776)
	game = TestMain.new()
	root.add_child(game)
	game.set_process(false)
	game.illustration.set_process(false)
	game.paused = true
	for frame in range(60): await process_frame
	game.cafe_intro.preparing = false
	game.cafe_intro.finish()
	if game.startup_readiness != null: game.startup_readiness.hide()
	game.model.customers.clear()
	# Clear complete synthetic dining sets so no chair/table covers the rug probe.
	game.model.items = game.model.items.filter(func(item):return not str(item.kind) in ["table", "chair", "bench"])
	game.model.dining_sets.clear()
	game.animation_time = 0.0
	for i in range(game.staff_states.size()):
		var staff = game.staff_states[i]
		staff.pos = Vector2(1.5 + i, 2.5)
		staff.path = []
		staff.job_kind = ""
		staff.art_action = "standby"
		staff.art_payload = "none"
		staff.art_tool = "none"
		staff.art_target = staff.pos
		staff.art_station = staff.pos + Vector2(1, 0)
	# A real existing rug painter, under the second synthetic employee.
	game.model.items.append({"id": 9000, "kind": "rug", "x": 2, "z": 2, "rot": 0})
	game.illustration.motion = game.illustration.MotionArt.new()
	game.illustration.stance_offsets.clear()
	game.illustration.zoom = 1.0
	game.illustration.pan_offset = Vector2.ZERO
	game.illustration.update_projection()
	var positions = game.staff_states.map(func(s):return s.pos)
	var economy = [game.model.coins, game.model.total_wages_paid, game.model.total_earned]
	game.illustration.use_staff_ground_rings = false
	var baseline: Image = await capture("game-baseline.png")
	game.illustration.use_staff_ground_rings = true
	var candidate: Image = await capture("game-candidate.png")
	var nodes = ring_nodes()
	check(nodes.size() == game.staff_states.size(), "actual ground pass draws once per staff outside contact splits")
	check(candidate.get_data() != baseline.get_data(), "gameplay ring activation changes actual rendered pixels")
	var rug_anchor = game.illustration.iso(2.5, 2.5)
	var rug_area = Rect2i(Vector2i(rug_anchor) - Vector2i(18, 9), Vector2i(36, 18))
	var white_rug_pixels = 0
	for y in range(rug_area.position.y, rug_area.end.y):
		for x in range(rug_area.position.x, rug_area.end.x):
			var color = candidate.get_pixel(x, y)
			if color.r > .9 and color.g > .9 and color.b > .9 and color.b - baseline.get_pixel(x, y).b > .1: white_rug_pixels += 1
	check(white_rug_pixels > 3, "employee white ring remains visible above real rug")
	records.append({"white_rug_pixels": white_rug_pixels})
	for node in nodes:
		var i = int(node.appearance[0][1])
		var position = game.illustration._render_position("staff_%s" % i, game.staff_states[i].pos)
		check(node.transform.origin.distance_to(game.illustration.iso(position.x, position.y)) < .01, "ring shares rendered staff foot anchor " + str(i))
	var draws = nodes.map(func(n):return n.draw_count)
	game.animation_time = 3.0
	var rotated: Image = await capture("game-rotated.png")
	check(ring_nodes() == nodes and nodes.map(func(n):return n.draw_count) == draws, "rotation updates retained transforms without geometry repaint")
	var paused: Image = await capture("game-paused.png")
	check(rotated.get_data() == paused.get_data(), "paused Main clock preserves exact game pixels")
	game.editing = true
	await capture("game-decorate.png")
	check(ring_nodes().is_empty(), "Decorate hides rings along with staff")
	game.editing = false
	game.animation_time = 0.0
	game.illustration.zoom = minf(3.0, game.illustration.camera_zoom_limits().y)
	game.illustration.update_projection()
	game.illustration.pan_offset += Vector2(680, 540) - game.illustration.iso(2.5, 2.5)
	game.illustration.update_projection()
	game.illustration.use_staff_ground_rings = false
	await capture("game-close-baseline.png")
	game.illustration.use_staff_ground_rings = true
	await capture("game-close.png")
	check(game.staff_states.map(func(s):return s.pos) == positions, "renderer leaves synthetic staff positions unchanged")
	check([game.model.coins, game.model.total_wages_paid, game.model.total_earned] == economy, "renderer leaves wallet, wages and earnings unchanged")
	check(game.save_attempts == 0 and game.save_writes_suppressed, "actual Main fixture loads no player saves and attempts no saves")
	FileAccess.open(directory.path_join("game-records.json"), FileAccess.WRITE).store_string(JSON.stringify(records, "  "))
	print("STAFF_GROUND_RING_GAME_RESULT ", JSON.stringify({"checks": checks, "failures": failures, "player_saves_used": false, "save_attempts": game.save_attempts, "surface": "native actual Main with synthetic staff and existing rug"}))
	for player in game.audio_players.values(): player.stop(); player.stream = null
	for tween in get_processed_tweens(): tween.kill()
	game.queue_free()
	for frame in range(8): await process_frame
	quit(0 if failures.is_empty() else 1)
