extends SceneTree
class CaptureGame extends "res://scripts/main.gd":
	func _load_startup():
		save_writes_suppressed=true;fresh_start=false;MinimalStart.apply(model)
class FixedArt extends "res://scripts/illustrated_cafe.gd":
	func update_projection(_clamp_camera:bool=true):
		ui_scale=.86;zoom=1.0;tile=Vector2(33.54,16.77);origin=Vector2(800,345)
func _initialize():run.call_deferred()
func run():
	seed(8124);root.size=Vector2i(1654,951)
	var game=CaptureGame.new();root.add_child(game);game.set_process(false);game.paused=true
	game.illustration.free();game.illustration=FixedArt.new();game.illustration.game=game;game.add_child(game.illustration);game.illustration.set_process(false)
	game._update_ui()
	for n in range(16):game.illustration.queue_redraw();await process_frame
	await RenderingServer.frame_post_draw
	var path=OS.get_environment("ENV_CAPTURE")
	root.get_texture().get_image().save_png(path)
	print("ENVIRONMENT_CAPTURE ",path);quit()
