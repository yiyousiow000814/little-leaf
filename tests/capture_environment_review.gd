extends SceneTree
const Neighborhood=preload("res://scripts/exterior_environment.gd")
class CaptureGame extends "res://scripts/main.gd":
	func _load_startup():
		save_writes_suppressed=true;fresh_start=false;MinimalStart.apply(model)
class FixedArt extends "res://scripts/illustrated_cafe.gd":
	func update_projection(_clamp_camera:bool=true):
		ui_scale=.86;zoom=1.0;tile=Vector2(33.54,16.77);origin=Vector2(800,345)
class BusArt extends "res://scripts/illustrated_cafe.gd":
	var previous_art
	func _ready():set_process(false)
	func _draw():
		ui_scale=2.2;zoom=1.0;tile=Vector2(85.8,42.9);origin=Vector2(360,270)
		draw_rect(get_viewport_rect(),Color("c6d5ad"))
		if previous_art!=null:previous_art.draw_car(self,Vector2.ZERO,1,"ced6b8",true)
		else:Neighborhood.draw_bus(self,Vector2.ZERO)
func bus_view(previous=null)->SubViewport:
	var view=SubViewport.new();view.size=Vector2i(720,460);view.disable_3d=true;view.render_target_update_mode=SubViewport.UPDATE_ALWAYS
	root.add_child(view);var art=BusArt.new();art.previous_art=previous;view.add_child(art);return view
func _initialize():run.call_deferred()
func run():
	seed(8124);root.size=Vector2i(1654,951)
	var game=CaptureGame.new();root.add_child(game);game.set_process(false);game.paused=true
	game.illustration.free();game.illustration=FixedArt.new();game.illustration.game=game;game.add_child(game.illustration);game.illustration.set_process(false);game._update_ui()
	var after=bus_view();var before:SubViewport
	var previous=OS.get_environment("BUS_BEFORE_SCRIPT")
	if previous!="":before=bus_view(load(previous))
	for n in range(16):game.illustration.queue_redraw();await process_frame
	await RenderingServer.frame_post_draw
	var output=OS.get_environment("ENV_REVIEW_OUTPUT")
	root.get_texture().get_image().save_png(output+"/layout-after.png")
	after.get_texture().get_image().save_png(output+"/bus-after.png")
	if before!=null:before.get_texture().get_image().save_png(output+"/bus-before.png")
	print("ENVIRONMENT_REVIEW_CAPTURE ",output);quit()
