extends SceneTree
class CaptureGame extends "res://scripts/main.gd":
	func _load_startup():
		save_writes_suppressed=true;fresh_start=true;MinimalStart.apply(model)
class FixedArt extends "res://scripts/illustrated_cafe.gd":
	func update_projection(_clamp_camera:bool=true):
		ui_scale=.86;zoom=1.0;tile=Vector2(33.54,16.77);origin=Vector2(780,490)
func _initialize():run.call_deferred()
func run():
	seed(8431);root.size=Vector2i(1654,951)
	var game=CaptureGame.new();root.add_child(game);game.set_process(false)
	game.illustration.free();game.illustration=FixedArt.new();game.illustration.game=game;game.add_child(game.illustration);game.illustration.set_process(false)
	game.model.first_guest_pending=false;game.model.first_guest_start=Vector2.INF
	game.paused=false;game.model.coins=10000;game.model.begin_decoration_session();assert(game.model.buy_parking());game.model.finish_decoration_session()
	var p=game.model.Parking
	if p.FORMAT=="little_leaf.parking.v1":p.reserve(game.model)
	else:assert(p.reserve(game.model,4))
	for n in range(30):game.illustration.queue_redraw();await process_frame
	game.tutorial.skip();game.model.set_operating_open(true);game._update_ui()
	var elapsed=0.0;var events=[];var output=OS.get_environment("PARKING_CAPTURE_OUTPUT")
	for clock in [0.0,27.25,27.5,28.5,29.5,30.0,31.0,32.0,40.0,90.0,130.0,140.0,145.0,150.0,155.0,156.0,157.0,158.0,159.0,160.0,170.0,200.0]:
		while elapsed<clock-.00001:
			var step=minf(1.0/30.0 if elapsed>=148 and elapsed<=166 else .1,clock-elapsed)
			game.model._arrival_elapsed=0;game._tick_live_service(step);game._animate_staff(step);game.illustration._update_street_pedestrians(step);elapsed+=step
		game._update_ui();game.illustration.queue_redraw();await process_frame;await RenderingServer.frame_post_draw
		root.get_texture().get_image().save_png(output+"/frame-%04d.png"%int(clock*30))
		events.append({"clock":clock,"operating_open":game.model.operating_open,"served":game.model.served,"earned":game.model.total_earned,"cars":game.model.RuntimeCodec.new().encode(game.model.parking_visits),"guest_ids":game.model.customers.map(func(g):return g.id),"queue_ids":game.model.outside_queue.map(func(g):return g.id)})
	var file=FileAccess.open(output+"/capture.json",FileAccess.WRITE);file.store_string(JSON.stringify({"synthetic_profile":true,"save_writes_suppressed":game.save_writes_suppressed,"events":events},"\t"))
	print("PARKING_PIXEL_CAPTURE_DONE");quit()
