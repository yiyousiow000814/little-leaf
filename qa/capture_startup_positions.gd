extends SceneTree
## Untimed screenshots of the actual main scene, generated fresh model only.
const Main = preload("res://scripts/main.gd")
const Intro = preload("res://scripts/cafe_intro.gd")
class CaptureGame extends Main:
	func _load_startup():
		save_writes_suppressed = true;fresh_start = true;MinimalStart.apply(model)
	func _autosave():return
	func _save():return true
var records = []
func _initialize():run.call_deferred()
func run():
	if DisplayServer.get_name() == "headless":quit(2);return
	for size in [Vector2i(1360,880), Vector2i(390,844)]:
		root.size = size
		await process_frame
		seed(42)
		Intro.shown_this_session = false
		var game = CaptureGame.new();root.add_child(game)
		game.process_mode = Node.PROCESS_MODE_DISABLED
		var art = game.illustration
		var atlases = [art.furniture_art.static_atlas, art.head_atlas, art.moving_atlas]
		var deadline = Time.get_ticks_msec() + 30000
		while not (atlases[0].is_ready() and atlases[1].is_ready() and atlases[2].is_ready()):
			if Time.get_ticks_msec() > deadline:push_error("Atlas timeout");quit(1);return
			await process_frame
		for elapsed in [0.0,2.375,3.75,5.125,6.5]:
			var intro = game.cafe_intro
			intro.elapsed = elapsed
			intro.descent = smoothstep(intro.DESCENT_START,intro.DURATION,elapsed)
			intro.sky_alpha = 1.0 - smoothstep(1.4,4.8,elapsed)
			intro._present()
			if elapsed == 6.5:intro.finish()
			art.update_projection();art.queue_redraw()
			await process_frame
			await RenderingServer.frame_post_draw
			var file = "%dx%d-%04d.png" % [size.x,size.y,roundi(elapsed*1000)]
			var error = root.get_texture().get_image().save_png(OS.get_environment("OUTPUT").path_join(file))
			if error != OK:push_error("Capture write failed");quit(1);return
			records.append({"file":file,"intro_elapsed":elapsed,"viewport":[size.x,size.y],"all_atlases_ready":true,"save_writes_suppressed":game.save_writes_suppressed})
		game.queue_free();await process_frame
	FileAccess.open(OS.get_environment("OUTPUT").path_join("captures.json"),FileAccess.WRITE).store_string(JSON.stringify({"records":records,"scope":"Untimed frozen production scene; generated fresh model; not live frame timing or browser audio."},"  "))
	quit()
