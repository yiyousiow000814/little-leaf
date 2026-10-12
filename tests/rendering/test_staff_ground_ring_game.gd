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
	var unit = game.illustration.ui_scale * game.illustration.zoom * (1.55 if game.wall_detail else 1.0)
	records.append({"tile_bbox_px": str(game.illustration.tile * 2.0), "ring_outer_bbox_px": str(game.illustration.StaffGroundRing.RADIUS * unit * 2.0), "ring_gap_min_bbox_px": str(game.illustration.StaffGroundRing.RADIUS * unit * 2.0 * cos(deg_to_rad(12.0))), "segments": game.illustration.StaffGroundRing._geometry.size()})
	records.append({"capture": name, "rings": nodes.size(), "draw_counts": nodes.map(func(n):return n.draw_count), "positions": nodes.map(func(n):return str(n.transform.origin)), "clock": game.animation_time, "editing": game.editing, "zoom": game.illustration.zoom})
	return image

func own_ring_over_rug(before: Image, after: Image, nodes: Array) -> Dictionary:
	var target
	var rug
	for node in nodes:
		if int(node.appearance[0][1]) == 1: target = node
	for node in game.illustration.native_object_nodes.values():
		if not node.visible or node.appearance.is_empty() or not node.appearance[0] is Array: continue
		var key = node.appearance[0]
		if key.size() > 2 and key[0] == "furniture" and key[2] is Dictionary and int(key[2].get("id", -1)) == 9000: rug = node
	if target == null or rug == null: return {"white_rug_pixels": 0, "target_or_rug_missing": true}
	var own_inverse: Transform2D = target.transform.affine_inverse()
	var rug_inverse: Transform2D = rug.transform.affine_inverse()
	var unit = game.illustration.ui_scale * game.illustration.zoom * (1.55 if game.wall_detail else 1.0)
	var bounds = Rect2i(Vector2i(rug.transform.origin - Vector2(30, 17) * unit), Vector2i(Vector2(60, 34) * unit) + Vector2i(2, 2))
	var count = 0
	var eligible = 0
	var excluded_neighbor_samples = 0
	for y in range(bounds.position.y, bounds.end.y):
		for x in range(bounds.position.x, bounds.end.x):
			var pixel = Vector2(x + .5, y + .5)
			var own = own_inverse * pixel
			var radius = own.length()
			var angle = fposmod(atan2(own.y, own.x), PI * .5)
			if radius < .87 or radius > .98 or angle < deg_to_rad(14) or angle > deg_to_rad(76): continue
			# Existing real rug: illustrated_furniture.point uses34/17 and its
			# face is the world rectangle +/- .43 / .34. Stay within its interior.
			var local = rug_inverse * pixel
			var rug_x = (local.x / 34.0 + local.y / 17.0) * .5
			var rug_z = (local.y / 17.0 - local.x / 34.0) * .5
			if absf(rug_x) > .40 or absf(rug_z) > .30: continue
			var neighbor = false
			for node in nodes:
				if node == target: continue
				var other_radius = (node.transform.affine_inverse() * pixel).length()
				# Exclude a widened annulus irrespective of the neighbor's gap phase.
				if other_radius >= .80 and other_radius <= 1.04: neighbor = true
			if neighbor: excluded_neighbor_samples += 1; continue
			eligible += 1
			var color = after.get_pixel(x, y)
			if minf(color.r, minf(color.g, color.b)) > .8 and maxf(color.r, maxf(color.g, color.b)) - minf(color.r, minf(color.g, color.b)) < .08 and color.b - before.get_pixel(x, y).b > .2: count += 1
	return {"white_rug_pixels": count, "eligible_own_annulus_rug_samples": eligible, "neighbor_annulus_samples_excluded": excluded_neighbor_samples, "target_staff_index": 1, "rug_id": 9000, "target_anchor": str(target.transform.origin), "rug_anchor": str(rug.transform.origin), "mask": "own annulus + real rug interior; all neighboring annuli excluded"}

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
	# Keep asynchronous tutorial layout outside the paired floor-pixel probe.
	game.tutorial.set_process(false)
	game.tutorial.panel.hide()
	game.tutorial.pointer.hide()
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
	# Offset the same real rug one fixture cell so the second staff ring
	# crosses it; its central hole no longer serves as the rug-order probe.
	game.model.items.append({"id": 9000, "kind": "rug", "x": 3, "z": 2, "rot": 0})
	game.illustration.motion = game.illustration.MotionArt.new()
	game.illustration.stance_offsets.clear()
	game.illustration.zoom = 1.0
	game.illustration.pan_offset = Vector2.ZERO
	game.illustration.update_projection()
	var positions = game.staff_states.map(func(s):return s.pos)
	var economy = [game.model.coins, game.model.total_wages_paid, game.model.total_earned]
	var unit = game.illustration.ui_scale * game.illustration.zoom * (1.55 if game.wall_detail else 1.0)
	var tile_minimum = game.illustration.tile * 2.0
	var visible_ring_minimum = game.illustration.StaffGroundRing.RADIUS * unit * 2.0 * cos(deg_to_rad(12.0))
	check(visible_ring_minimum.x >= tile_minimum.x and visible_ring_minimum.y >= tile_minimum.y and game.illustration.StaffGroundRing._geometry.size() == 4, "four-segment outer ring bounds are at least one projected ground tile")
	game.illustration.use_staff_ground_rings = false
	var baseline: Image = await capture("game-baseline.png")
	game.illustration.use_staff_ground_rings = true
	var candidate: Image = await capture("game-candidate.png")
	var nodes = ring_nodes()
	check(nodes.size() == game.staff_states.size(), "actual ground pass draws once per staff outside contact splits")
	check(candidate.get_data() != baseline.get_data(), "gameplay ring activation changes actual rendered pixels")
	var rug_proof = own_ring_over_rug(baseline, candidate, nodes)
	check(int(rug_proof.white_rug_pixels) > 3, "target staff ring is above the real rug with every neighboring annulus excluded")
	records.append(rug_proof)
	for node in nodes:
		var i = int(node.appearance[0][1])
		var position = game.illustration._render_position("staff_%s" % i, game.staff_states[i].pos)
		check(node.transform.origin.distance_to(game.illustration.iso(position.x, position.y)) < .01, "ring shares rendered staff foot anchor " + str(i))
	var draws = nodes.map(func(n):return n.draw_count)
	game.animation_time = 1.5
	var rotated: Image = await capture("game-rotated.png")
	check(ring_nodes() == nodes and nodes.map(func(n):return n.draw_count) == draws, "rotation updates retained transforms without geometry repaint")
	check(rotated.get_data() != candidate.get_data(), "four-segment gap rotation is visible at a nonsymmetric 45-degree phase")
	var paused: Image = await capture("game-paused.png")
	check(rotated.get_data() == paused.get_data(), "paused Main clock preserves exact game pixels")
	game.editing = true
	await capture("game-decorate.png")
	check(ring_nodes().is_empty(), "Decorate hides rings along with staff")
	game.editing = false
	game.animation_time = 0.0
	game.illustration.zoom = minf(2.0, game.illustration.camera_zoom_limits().y)
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
