extends SceneTree
const Neighborhood=preload("res://scripts/exterior_environment.gd")
class CaptureGame extends "res://scripts/main.gd":
	func _load_startup():save_writes_suppressed=true;fresh_start=false;MinimalStart.apply(model)
class AfterArt extends "res://scripts/illustrated_cafe.gd":
	func update_projection(_clamp_camera:bool=true):ui_scale=.86;zoom=1.0;tile=Vector2(33.54,16.77);origin=Vector2(800,345)
class DetailArt extends "res://scripts/illustrated_cafe.gd":
	var before=false
	var before_environment
	func _ready():set_process(false)
	func _draw():
		ui_scale=2.0;zoom=1.0;tile=Vector2(78,39);origin=Vector2(2200,600)
		draw_rect(get_viewport_rect(),Color("c6d5ad"))
		var environment=before_environment if before else Neighborhood
		environment.draw_ground(self)
		environment.quad(self,-3.26,-30,-.26,30,"d7dcc2")
		if before:environment.draw_props(self)
		else:environment.draw_props(self,_draw_bus_stop_people.bind(true),_draw_bus_stop_people.bind(false))
func scene(before:bool)->Dictionary:
	var view=SubViewport.new();view.size=Vector2i(1654,951);view.disable_3d=true;view.render_target_update_mode=SubViewport.UPDATE_ALWAYS
	root.add_child(view);var game=CaptureGame.new();view.add_child(game);game.set_process(false);game.paused=false
	game.illustration.free();game.illustration=load(OS.get_environment("STOP_BEFORE_ART")).new() if before else AfterArt.new();game.illustration.game=game
	game.add_child(game.illustration);game.illustration.set_process(false);game._update_ui()
	return {"view":view,"game":game,"art":game.illustration}
func detail(before:bool,game)->Dictionary:
	var view=SubViewport.new();view.size=Vector2i(1240,760);view.disable_3d=true;view.render_target_update_mode=SubViewport.UPDATE_ALWAYS
	root.add_child(view);var art=DetailArt.new();art.game=game;art.before=before
	if before:art.before_environment=load(OS.get_environment("STOP_BEFORE_ENV"))
	if not before:art.bus_stop_pedestrians=game.illustration.bus_stop_pedestrians
	view.add_child(art);return {"view":view,"art":art}
func _initialize():run.call_deferred()
func run():
	seed(8124);root.size=Vector2i(1654,951)
	var before=scene(true);var after=scene(false)
	var close_before=detail(true,before.game);var close_after=detail(false,after.game)
	var output=OS.get_environment("STOP_MOTION_OUTPUT");var records=[]
	# Advance only existing presentation systems. Cafe authority stays frozen.
	# These are 16 actual native samples at .5s intervals, not interpolated art.
	for frame in range(16):
		before.art._update_street_pedestrians(.5);after.art._update_street_pedestrians(.5)
		for artist in [before.art,after.art,close_before.art,close_after.art]:artist.queue_redraw()
		await process_frame;await RenderingServer.frame_post_draw
		for pair in [["before",before.view],["after",after.view],["detail-before",close_before.view],["detail-after",close_after.view]]:
			pair[1].get_texture().get_image().save_png(output+"/%s-%02d.png"%[pair[0],frame])
		var states=[]
		for actor in after.art.bus_stop_pedestrians.actors:states.append({"key":actor.key,"state":actor.state,"position":[actor.position.x,actor.position.y],"visible":actor.visible})
		records.append({"frame":frame,"time_seconds":(frame+1)*.5,"people":states})
	var f=FileAccess.open(output+"/motion-records.json",FileAccess.WRITE);f.store_string(JSON.stringify(records,"\t"));f.close()
	print("STOP_MOTION_CAPTURE ",output);quit()
