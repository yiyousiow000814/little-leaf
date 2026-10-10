extends SceneTree
const Pack = preload("res://scripts/character_sprite_pack.gd")
const SOURCE = "aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa"
var checks := 0
var failures: Array = []
var pack = Pack.new()
var manifest: Dictionary
var directory: String
var baseline_texture: Texture2D
var candidate := false

class Canvas extends Node2D:
	var owner_test
	func _draw(): owner_test.paint(self)

func check(value: bool, label: String) -> void:
	checks += 1
	if not value:
		failures.append(label)
		print("FAILED ", label)

func write_manifest(value: Dictionary) -> void:
	var file := FileAccess.open(directory.path_join("pack.json"), FileAccess.WRITE)
	file.store_string(JSON.stringify(value))

func load_manifest(value: Dictionary) -> Dictionary:
	write_manifest(value)
	var result := pack.import_pack(directory.path_join("pack.json"), SOURCE)
	print("IMPORT ", result)
	return result

func _initialize(): call_deferred("run")

func run():
	directory = OS.get_environment("CHARACTER_PACK_OUTPUT")
	if directory.is_empty(): directory = OS.get_user_data_dir().path_join("character-sprite-pack-synthetic")
	DirAccess.make_dir_recursive_absolute(directory)
	# Test markers only; deliberately not character art or a model export.
	var image := Image.create(5120, 640, false, Image.FORMAT_RGBA8)
	image.fill(Color.TRANSPARENT)
	var frames: Array = []
	for i in range(8):
		var tone := Color.from_hsv(float(i) / 8.0, 0.6, 0.9)
		image.fill_rect(Rect2i(i * 640 + 240, 240, 160, 344), tone)
		image.fill_rect(Rect2i(i * 640 + 248 + i * 8, 128, 48, 112), tone)
		frames.append({"pose": "idle", "facing": Pack.FACINGS[i], "frame": 0, "rect": [i * 640, 0, 640, 640]})
	check(image.save_png(directory.path_join("markers.png")) == OK, "write synthetic marker sheet")
	baseline_texture = ImageTexture.create_from_image(image)
	manifest = {"format": Pack.FORMAT, "source_sha256": SOURCE, "species": "bear", "cell": [80, 80], "pivot": [40, 73], "density": 8, "image": "markers.png", "image_sha256": FileAccess.get_sha256(directory.path_join("markers.png")), "frames": frames}
	check(load_manifest(manifest).ok, "import exact hashed source/export")
	for facing in Pack.FACINGS:
		check(pack.has_frame("idle", facing), "retained facing " + facing)
		check(not pack.has_frame("task", facing), "missing pose cannot substitute idle " + facing)
	var mutations: Array = [
		["source_sha256", "bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb", "source_authority_mismatch"],
		["image_sha256", SOURCE, "image_hash_mismatch"],
		["image", "../markers.png", "invalid_image_path"],
		["image", "C:\\markers.png", "invalid_image_path"],
		["species", "unknown", "incompatible_geometry"],
		["pivot", [40, 72], "incompatible_geometry"],
		["density", 4, "incompatible_geometry"],
		["format", "future", "unknown_format"]
	]
	for mutation in mutations:
		var changed := manifest.duplicate(true)
		changed[mutation[0]] = mutation[1]
		var result := load_manifest(changed)
		check(not result.ok and result.error == mutation[2], "reject " + str(mutation[0]) + " " + str(mutation[1]))
		check(pack.has_frame("idle", "e"), "rejected replacement retains previous pack")
	for defect in ["duplicate", "missing", "bounds", "fraction", "direction"]:
		var changed := manifest.duplicate(true)
		match defect:
			"duplicate": changed.frames.append(changed.frames[0].duplicate(true))
			"missing": changed.frames.pop_back()
			"bounds": changed.frames[0].rect[0] = 8192
			"fraction": changed.frames[0].frame = 0.5
			"direction": changed.frames[0].facing = "east"
		check(not load_manifest(changed).ok, "reject " + defect)
	# Forged huge dimensions must be rejected before allocating decoded pixels.
	var forged := FileAccess.open(directory.path_join("huge.png"), FileAccess.WRITE)
	forged.store_buffer(PackedByteArray([137, 80, 78, 71, 13, 10, 26, 10]))
	forged.big_endian = true
	forged.store_32(13)
	forged.store_buffer("IHDR".to_ascii_buffer())
	forged.store_32(8192)
	forged.store_32(8192)
	forged.store_buffer(PackedByteArray([8, 6, 0, 0, 0, 0, 0, 0, 0]))
	forged.close()
	var huge := manifest.duplicate(true)
	huge.image = "huge.png"
	huge.image_sha256 = FileAccess.get_sha256(directory.path_join("huge.png"))
	var huge_result := load_manifest(huge)
	check(not huge_result.ok and huge_result.error == "invalid_dimensions_or_alpha", "reject decoded pixel budget before decoding")
	check(pack.has_frame("idle", "e"), "huge rejected replacement keeps prior pack")
	var opaque := Image.create(640, 640, false, Image.FORMAT_RGBA8)
	opaque.fill(Color.RED)
	opaque.save_png(directory.path_join("opaque.png"))
	var no_alpha := manifest.duplicate(true)
	no_alpha.image = "opaque.png"
	no_alpha.image_sha256 = FileAccess.get_sha256(directory.path_join("opaque.png"))
	var opaque_result := load_manifest(no_alpha)
	check(not opaque_result.ok and opaque_result.error == "invalid_dimensions_or_alpha", "reject opaque floor baked into sprites")
	check(pack.has_frame("idle", "e"), "opaque rejected replacement keeps prior pack")
	check(load_manifest(manifest).ok, "restore valid manifest")
	var leaked := pack.metadata()
	leaked.species = "cat"
	check(pack.metadata().get("species") == "bear", "caller cannot mutate retained metadata")
	pack.clear()
	check(not pack.has_frame("idle", "e") and pack.metadata().is_empty(), "clear releases retained pack")
	check(load_manifest(manifest).ok, "reload after clear")
	if DisplayServer.get_name() == "headless":
		finish("headless import and resource ownership; no rendered acceptance")
		return
	var canvas := Canvas.new()
	canvas.owner_test = self
	canvas.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	root.add_child(canvas)
	root.size = Vector2i(1280, 380)
	await process_frame
	await RenderingServer.frame_post_draw
	var before := root.get_texture().get_image()
	before.save_png(directory.path_join("baseline.png"))
	candidate = true
	canvas.queue_redraw()
	await process_frame
	await RenderingServer.frame_post_draw
	var after := root.get_texture().get_image()
	after.save_png(directory.path_join("candidate.png"))
	check(before.get_data() == after.get_data(), "native 8 facings at 1x/2x exact RGBA parity")
	finish("native synthetic import/contact markers; not character art")

func finish(surface: String):
	print("CHARACTER_SPRITE_PACK_RESULT ", JSON.stringify({"checks": checks, "failures": failures, "visual_surface": surface, "player_saves_used": false}))
	quit(0 if failures.is_empty() else 1)

func paint(canvas: CanvasItem):
	canvas.draw_rect(Rect2(0, 0, 1280, 380), Color("f1ead7"))
	for row in range(2):
		var scale_factor := float(row + 1)
		for i in range(8):
			var floor_root := Vector2(80 + i * 160, 100 + row * 230)
			canvas.draw_line(floor_root - Vector2(24, 0), floor_root + Vector2(24, 0), Color("697a60"), 1)
			canvas.draw_line(floor_root - Vector2(0, 8), floor_root + Vector2(0, 8), Color("697a60"), 1)
			if candidate:
				check(pack.draw_frame(canvas, floor_root, "idle", Pack.FACINGS[i], 0, scale_factor), "draw exact facing at floor contact")
			else:
				canvas.draw_texture_rect_region(baseline_texture, Rect2(floor_root - Pack.PIVOT * scale_factor, Vector2(80, 80) * scale_factor), Rect2(i * 640, 0, 640, 640))
