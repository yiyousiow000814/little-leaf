extends SceneTree
const Neighborhood=preload("res://scripts/exterior_environment.gd")
class CaptureGame extends "res://scripts/main.gd":
	func _load_startup():save_writes_suppressed=true;fresh_start=false;MinimalStart.apply(model)
class FixedArt extends "res://scripts/illustrated_cafe.gd":
	func update_projection(_clamp_camera:bool=true):ui_scale=.86;zoom=1.0;tile=Vector2(33.54,16.77);origin=Vector2(800,345)
class DetailArt extends "res://scripts/illustrated_cafe.gd":
	var previous_art
	var greenery_review=false
	func _ready():set_process(false)
	func _draw():
		ui_scale=2.0;zoom=1.0;tile=Vector2(78,39);origin=Vector2(1980,520)
		draw_rect(get_viewport_rect(),Color("c6d5ad"))
		if greenery_review:
			var variants=["oak","airy","columnar","sapling"]
			for i in range(4):
				var p=Vector2(110+i*220,390)
				if i==0:_tree(p,1)
				else:Neighborhood.greenery.draw_tree(self,p,2.0,variants[i])
			for i in range(3):Neighborhood.greenery.draw_layers(self,Neighborhood.greenery.pockets[i],Vector2(170+i*270,555),2.0)
			return
		var artist=Neighborhood if previous_art==null else previous_art
		artist.draw_ground(self)
		# Match the normal renderer's pavement fill without importing world state.
		artist.quad(self,-3.26,-30,-.26,30,"d7dcc2")
		artist.draw_props(self)
func detail(previous=null,plants=false)->SubViewport:
	var view=SubViewport.new();view.size=Vector2i(960,640);view.disable_3d=true;view.render_target_update_mode=SubViewport.UPDATE_ALWAYS
	root.add_child(view);var art=DetailArt.new();art.previous_art=previous;art.greenery_review=plants;view.add_child(art);return view
func _initialize():run.call_deferred()
func run():
	seed(8124);root.size=Vector2i(1654,951)
	var game=CaptureGame.new();root.add_child(game);game.set_process(false);game.paused=true
	game.illustration.free();game.illustration=FixedArt.new();game.illustration.game=game;game.add_child(game.illustration);game.illustration.set_process(false);game._update_ui()
	var before=detail(load(OS.get_environment("SHELTER_BEFORE_SCRIPT")))
	var after=detail();var plants=detail(null,true)
	for n in range(16):game.illustration.queue_redraw();await process_frame
	await RenderingServer.frame_post_draw
	var output=OS.get_environment("SHELTER_REVIEW_OUTPUT")
	root.get_texture().get_image().save_png(output+"/layout-after.png")
	before.get_texture().get_image().save_png(output+"/shelter-before.png")
	after.get_texture().get_image().save_png(output+"/shelter-after.png")
	plants.get_texture().get_image().save_png(output+"/greenery-after.png")
	print("SHELTER_REVIEW_CAPTURE ",output);quit()
