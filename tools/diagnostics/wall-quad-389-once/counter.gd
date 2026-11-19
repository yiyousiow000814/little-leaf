extends SceneTree
## Disposable, wall-only native driver counter. No product project, timing, or FPS.
const FRAME := Vector2i(1360, 880)
const WARM := 3
const SAMPLE := 5
const FIXTURE := "388527b937e67df65e55cbee3b6f88c56b42d2aae9d6b82584d64a3a2825e273"
var vp: SubViewport
var items: Array[RID] = []
var report_path := ""
var stamp := ""

func _initialize() -> void:
	call_deferred("_run")

func _bytes_hash(bytes: PackedByteArray) -> String:
	var digest := HashingContext.new()
	if digest.start(HashingContext.HASH_SHA256) != OK or digest.update(bytes) != OK:
		return ""
	return digest.finish().hex_encode()

func _finish(code: int) -> void:
	for rid in items:
		RenderingServer.free_rid(rid)
	items.clear()
	quit(code)

func _write(doc: Dictionary, code: int) -> void:
	doc["schema"] = "wall-fixed-canvas-counter-v1"
	doc["fixture_sha256"] = stamp
	var file := FileAccess.open(report_path, FileAccess.WRITE)
	if file == null:
		_finish(3)
		return
	file.store_line(JSON.stringify(doc))
	file.close()
	_finish(code)

func _run() -> void:
	var args := OS.get_cmdline_user_args()
	if args.size() != 2 or DisplayServer.get_name() != "X11" or OS.get_name() != "Linux":
		_finish(2)
		return
	report_path = args[1]
	var version := Engine.get_version_info()
	if version.get("string") != "4.6.3-stable (official)" and not str(version.get("string", "")).begins_with("4.6.3"):
		_write({"status":"inconclusive", "reason":"not_godot_4_6_3"}, 2)
		return
	if RenderingServer.get_current_rendering_method() != "gl_compatibility":
		_write({"status":"inconclusive", "reason":"not_gl_compatibility"}, 2)
		return
	stamp = FileAccess.get_sha256(args[0])
	if stamp != FIXTURE:
		_write({"status":"inconclusive", "reason":"fixture_identity"}, 2)
		return
	var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(args[0]))
	if not parsed is Dictionary or not parsed.get("scenes", []) is Array or parsed["scenes"].is_empty():
		_write({"status":"inconclusive", "reason":"fixture_schema"}, 2)
		return
	var scene: Dictionary = parsed["scenes"][0]
	if scene.get("name") != "starter" or scene.get("slots", []).size() != 84:
		_write({"status":"inconclusive", "reason":"unexpected_wall_scenario"}, 2)
		return
	var slots: Array = scene["slots"]
	vp = SubViewport.new()
	vp.world_2d = World2D.new()
	vp.size = FRAME
	vp.disable_3d = true
	vp.transparent_bg = true
	vp.render_target_clear_mode = SubViewport.CLEAR_MODE_ALWAYS
	vp.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	root.add_child(vp)
	var committed := 0
	for slot: Dictionary in slots:
		if slot["quads"].is_empty():
			_write({"status":"inconclusive", "reason":"empty_slot"}, 2)
			return
		committed += slot["quads"].size()
		var rid := RenderingServer.canvas_item_create()
		RenderingServer.canvas_item_set_parent(rid, vp.world_2d.canvas)
		RenderingServer.canvas_item_set_draw_index(rid, items.size())
		items.append(rid)
	if committed != 330:
		_write({"status":"inconclusive", "reason":"unexpected_wall_command_count"}, 2)
		return
	var arms: Array = []
	for packed: bool in [false, true, false, true]:
		_submit(slots, packed)
		for frame in range(WARM):
			await RenderingServer.frame_post_draw
		var calls: Array[int] = []
		var primitives: Array[int] = []
		for frame in range(SAMPLE):
			await RenderingServer.frame_post_draw
			calls.append(RenderingServer.viewport_get_render_info(vp.get_viewport_rid(),
				RenderingServer.VIEWPORT_RENDER_INFO_TYPE_CANVAS, RenderingServer.VIEWPORT_RENDER_INFO_DRAW_CALLS_IN_FRAME))
			primitives.append(RenderingServer.viewport_get_render_info(vp.get_viewport_rid(),
				RenderingServer.VIEWPORT_RENDER_INFO_TYPE_CANVAS, RenderingServer.VIEWPORT_RENDER_INFO_PRIMITIVES_IN_FRAME))
		var image := vp.get_texture().get_image()
		if image == null or image.get_size() != FRAME:
			_write({"status":"inconclusive", "reason":"no_framebuffer"}, 2)
			return
		image.convert(Image.FORMAT_RGBA8)
		var bytes := image.get_data()
		var visible := false
		for pixel in range(3, bytes.size(), 4):
			if bytes[pixel] > 0:
				visible = true
				break
		arms.append({"arm":"packed" if packed else "control", "calls":calls, "primitives":primitives,
			"rgba_sha256":_bytes_hash(bytes), "visible":visible, "committed_commands":items.size() if packed else committed})
	var software := "llvmpipe" in RenderingServer.get_video_adapter_name().to_lower()
	_write({"status":"observed", "renderer_class":"llvmpipe" if software else "other",
		"rendering_method":"gl_compatibility", "size":[FRAME.x,FRAME.y], "arms":arms}, 0)

func _submit(slots: Array, packed: bool) -> void:
	for i in range(items.size()):
		var rid := items[i]
		RenderingServer.canvas_item_clear(rid)
		var run_xy := PackedVector2Array()
		var run_rgba := PackedColorArray()
		var run_indices := PackedInt32Array()
		for q: Dictionary in slots[i]["quads"]:
			var xy := PackedVector2Array()
			var rgba := PackedColorArray()
			for k in range(q["xy"].size()):
				var p: Array = q["xy"][k]
				var c: Array = q["rgba"][k]
				xy.append(Vector2(float(p[0]),float(p[1])))
				rgba.append(Color(float(c[0]),float(c[1]),float(c[2]),float(c[3])))
			if not packed:
				RenderingServer.canvas_item_add_polygon(rid, xy, rgba)
			else:
				var base := run_xy.size()
				run_xy.append_array(xy)
				run_rgba.append_array(rgba)
				for j: int in q["indices"]:
					run_indices.append(base + j)
		if packed:
			RenderingServer.canvas_item_add_triangle_array(rid, run_indices, run_xy, run_rgba)
