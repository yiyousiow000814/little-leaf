extends SceneTree
## Actual Godot render only. Supply a baseline script from the exact source
## revision with KERB_BEFORE_SCRIPT and a new KERB_REVIEW_OUTPUT directory.
const Neighborhood=preload("res://scripts/exterior_environment.gd")
class KerbArt extends "res://scripts/illustrated_cafe.gd":
	var artist
	func _ready():set_process(false)
	func _draw():
		ui_scale=1.6666667;zoom=1.0;tile=Vector2(65,32.5);origin=Vector2(1880,430)
		draw_rect(get_viewport_rect(),Color("c6d5ad"))
		artist.draw_ground(self)
		artist.quad(self,-3.26,-30,-.26,30,"d7dcc2")
		artist.draw_props(self)
func detail(artist)->SubViewport:
	var view=SubViewport.new();view.size=Vector2i(1440,900);view.disable_3d=true;view.render_target_update_mode=SubViewport.UPDATE_ALWAYS
	root.add_child(view);var art=KerbArt.new();art.artist=artist;view.add_child(art);return view
func _initialize():run.call_deferred()
func run():
	var baseline=OS.get_environment("KERB_BEFORE_SCRIPT")
	var output=OS.get_environment("KERB_REVIEW_OUTPUT")
	if baseline.is_empty() or output.is_empty():printerr("Baseline script and output directory are required");quit(1);return
	var previous=load(baseline)
	if previous==null:quit(1);return
	var before=detail(previous);var after=detail(Neighborhood)
	for n in range(16):await process_frame
	await RenderingServer.frame_post_draw
	before.get_texture().get_image().save_png(output+"/kerb-before.png")
	after.get_texture().get_image().save_png(output+"/kerb-after.png")
	print("KERB_REVIEW_CAPTURE ",output);quit()
