extends SceneTree
const GroundRing = preload("res://scripts/staff_ground_ring.gd")
var failures: Array = []
var checks = 0
var directory: String
var rings
var anchors: Dictionary = {}

class Floor:
	extends Node2D
	func _draw():
		draw_rect(Rect2(0, 0, 1024, 560), Color("d4d8bc"))
		for row in range(2):
			var y = 210 + row * 280
			# Clearly labeled fixture rug, under both actor and employee ring.
			draw_rect(Rect2(420, y - 24, 160, 48), Color("8e9d81"))
			for i in range(5):
				var p = Vector2(100 + i * 190, y)
				draw_line(p - Vector2(4, 0), p + Vector2(4, 0), Color("69735d"))
				draw_string(ThemeDB.fallback_font, p + Vector2(-38, 35), ["Chef", "Waiter", "Cleaner / rug", "Cashier / solid", "Customer"][i], HORIZONTAL_ALIGNMENT_LEFT, -1, 14, Color("384b36"))
		draw_string(ThemeDB.fallback_font, Vector2(25, 25), "Opt-in employee ground ring | existing procedural staff | 1x / 2x", HORIZONTAL_ALIGNMENT_LEFT, -1, 18, Color("384b36"))
		draw_string(ThemeDB.fallback_font, Vector2(25, 50), "Green rectangles = fixture rugs; brown blocks = fixture solid occluders. No gameplay integration.", HORIZONTAL_ALIGNMENT_LEFT, -1, 14, Color("384b36"))

class Actors:
	extends "res://scripts/illustrated_cafe.gd"
	func _draw():
		use_cached_heads = false
		use_cached_moving_art = false
		for row in range(2):
			for i in range(5):
				art_transform(Vector2(100 + i * 190, 210 + row * 280), 0, Vector2.ONE * (row + 1))
				character(Vector2.ZERO, i, i < 4, false, false, "idle", 0, Vector2(18, -28), Vector2(1, 0), "none", "none", {}, ["chef", "waiter", "cleaner", "cashier", "customer"][i])
		art_transform(Vector2.ZERO)

class Solids:
	extends Node2D
	func _draw():
		for row in range(2):
			var scale_factor = row + 1
			var p = Vector2(670, 210 + row * 280)
			draw_rect(Rect2(p + Vector2(3, -7) * scale_factor, Vector2(18, 10) * scale_factor), Color("977252"))

func check(condition: bool, message: String):
	checks += 1
	if not condition: failures.append(message)

func _initialize():
	call_deferred("run")

func capture(name: String) -> Image:
	await process_frame
	await RenderingServer.frame_post_draw
	var image = root.get_texture().get_image()
	image.save_png(directory.path_join(name))
	return image

func run():
	directory = OS.get_environment("STAFF_RING_OUTPUT")
	if directory.is_empty(): directory = OS.get_user_data_dir().path_join("staff-ring-synthetic")
	DirAccess.make_dir_recursive_absolute(directory)
	root.size = Vector2i(1024, 560)
	root.add_child(Floor.new())
	rings = GroundRing.new()
	root.add_child(rings)
	var actors = Actors.new()
	actors.z_index = 1
	root.add_child(actors)
	var solids = Solids.new()
	solids.z_index = 2
	root.add_child(solids)
	# The scale belongs to each ground layer, not the character art/state.
	var large = GroundRing.new()
	root.add_child(large)
	for i in range(4): anchors["staff_%s" % i] = Vector2(100 + i * 190, 210)
	var large_anchors: Dictionary = {}
	for i in range(4): large_anchors["staff_%s" % i] = Vector2(100 + i * 190, 490)
	rings.sync_staff(anchors, 0)
	check(rings.inventory().rings == 0 and not rings.visible, "opt-in disabled allocates no rings")
	var before: Image = await capture("baseline.png")
	rings.enabled = true
	large.enabled = true
	rings.sync_staff(anchors, 0)
	large.sync_staff(large_anchors, 0, false, 2)
	check(rings.inventory().rings == 4 and large.inventory().rings == 4, "exact four staff anchors per scale; no customer ring")
	var initial: Image = await capture("candidate.png")
	var changed = 0
	var rug_changed = 0
	var customer_unchanged = true
	for y in range(560):
		for x in range(1024):
			if before.get_pixel(x, y) != initial.get_pixel(x, y):
				changed += 1
				if x >= 820: customer_unchanged = false
				if x >= 420 and x < 580: rug_changed += 1
	check(changed > 40, "ring visible around existing staff feet")
	check(customer_unchanged, "customer region remains identical")
	check(rug_changed > 20, "ring is above rug layer")
	for row in range(2):
		var scale_factor = row + 1
		var p = Vector2i(670, 210 + row * 280)
		var rect = Rect2i(p + Vector2i(3, -7) * scale_factor, Vector2i(18, 10) * scale_factor)
		check(before.get_region(rect).get_data() == initial.get_region(rect).get_data(), "ring stays below solid layer at %sx" % scale_factor)
	var owned_children = rings.get_children()
	rings.sync_staff(anchors, 3)
	large.sync_staff(large_anchors, 3, false, 2)
	var moved: Image = await capture("rotated.png")
	check(moved.get_data() != initial.get_data(), "slow twelve-second ground rotation visible")
	check(rings.get_children() == owned_children, "animation retains original nodes and geometry")
	var phase = rings.inventory().phase
	rings.sync_staff(anchors, 8, true)
	large.sync_staff(large_anchors, 8, true, 2)
	var paused: Image = await capture("paused.png")
	check(paused.get_data() == moved.get_data() and rings.inventory().phase == phase, "paused visual clock keeps exact pixels")
	rings.enabled = false
	large.enabled = false
	rings.sync_staff(anchors, 8)
	large.sync_staff(large_anchors, 8, false, 2)
	var hidden: Image = await capture("disabled.png")
	check(hidden.get_data() == before.get_data(), "disabled ground layer restores baseline pixels")
	rings.enabled = true
	rings.sync_staff({"only": Vector2(100, 210)}, 0)
	check(rings.inventory().rings == 1 and rings.get_child_count() == 1, "removed staff releases retained rings")
	rings.clear()
	large.clear()
	check(rings.get_child_count() == 0 and rings.inventory().rings == 0, "clear releases all live ring nodes")
	print("STAFF_GROUND_RING_RESULT ", JSON.stringify({"checks": checks, "failures": failures, "player_saves_used": false, "surface": "native fixture; existing staff art and explicit rug/solid proxies; gameplay hook pending"}))
	quit(0 if failures.is_empty() else 1)
