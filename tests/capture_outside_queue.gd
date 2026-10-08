extends SceneTree
## Disposable visual fixture. Same driver runs on exact baseline and candidate.
class CaptureGame extends "res://scripts/main.gd":
	func _load_startup():
		save_writes_suppressed=true;fresh_start=false
class FixedArt extends "res://scripts/illustrated_cafe.gd":
	func update_projection(_clamp_camera:bool=true):
		ui_scale=.88;zoom=1.0;tile=Vector2(34.32,17.16);origin=Vector2(650,205)
var game
var frames=[]
func _initialize():_run.call_deferred()
func capture(second:int):
	game.illustration.queue_redraw()
	await process_frame
	await RenderingServer.frame_post_draw
	var queue=game.model.get("outside_queue")
	var visitors=[] if queue==null else queue
	var path=OS.get_environment("QUEUE_OUTPUT")
	root.get_texture().get_image().save_png(path+"/%03d.png"%second)
	frames.append({"second":second,"outside":visitors.duplicate(true),"customers":game.model.customers.duplicate(true),"coins":game.model.coins,"served":game.model.served})
func _run():
	seed(8124);root.size=Vector2i(1360,880)
	game=CaptureGame.new();root.add_child(game);game.set_process(false);game.paused=true;game.editing=false
	game.model.reset_new();game.model._spawn_customer()
	# Fill all stock pairs with synthetically seated visits. Hold meal elapsed
	# at zero until the explicit cleanup release at t=64; no player data used.
	for guest in game.model.customers:
		var chair=game.model.get_item(int(guest.chair_id))
		guest.x=chair.x+.5;guest.z=chair.z+.5;guest.phase="ordering";guest.seated=true;guest.admitted=true;guest.elapsed=0.0;guest.duration=game.model.PHASE_SECONDS.ordering;guest.route_index=guest.route.size()
	game.illustration.free();game.illustration=FixedArt.new();game.illustration.game=game;game.add_child(game.illustration);game.illustration.set_process(false)
	game._update_ui();game.paused=false
	await capture(0)
	for step in range(1,861):
		for guest in game.model.customers:
			if guest.phase=="ordering":guest.elapsed=0.0
		if step==640:
			var guest=game.model.customers[0]
			guest.phase="cleaning";guest.seated=false;guest.elapsed=0.0;guest.duration=game.model.PHASE_SECONDS.cleaning
		game.model.tick(.1)
		game.illustration._update_street_pedestrians(.1)
		game.illustration.update_motion(.1)
		if step%10==0:await capture(step/10)
	var report={"synthetic":true,"player_save_used":false,"driver":"fixed .1 simulation-second updates; full stock room; first table cleanup starts t64","source":OS.get_environment("QUEUE_SOURCE"),"frames":frames}
	FileAccess.open(OS.get_environment("QUEUE_OUTPUT")+"/motion.json",FileAccess.WRITE).store_string(JSON.stringify(preload("res://scripts/cafe_runtime_codec.gd").new().encode(report),"  "))
	print("OUTSIDE_QUEUE_CAPTURE_COMPLETE ",OS.get_environment("QUEUE_SOURCE"));quit()
