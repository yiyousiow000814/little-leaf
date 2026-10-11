extends "res://tests/diagnostics/capture_depth_occlusion.gd"
## Six frames only: three fixed states, each with overlay off/on.
const Overlay = preload("res://tests/diagnostics/depth_debug_overlay.gd")
var debug_view

func pair(state: String) -> void:
	crop = Rect2i(Vector2i.ZERO,root.size)
	debug_view.hide();label=state+"-off";await frame()
	debug_view.observe(rows.back().events,rows.back().frame,rows.back().dropped)
	check(not rows.back().events.is_empty(),"debug state has actual probe observations")
	debug_view.show();label=state+"-on";await frame()
	# The annotation shows the explicitly labelled preceding completed frame.
	# Its fixed state and raw actual-order observations are retained in capture.json.
	debug_view.hide()

func run():
	output=OS.get_environment("DEPTH_PROBE_OUTPUT")
	if output=="" or not "saveguard" in OS.get_user_data_dir() or DisplayServer.get_name()=="headless":printerr("Use isolated native diagnostic launcher");quit(2);return
	max_frames=8;root.size=Vector2i(1360,880)
	game=Fixture.new();root.add_child(game)
	game.set_process(false);game.paused=true;game.model.operating_open=false
	if game.cafe_intro!=null:game.cafe_intro.finish()
	art=game.illustration;art.set_process(false)
	if art.get("depth_probe_active")==null:printerr("Use staged probe hooks");game.free();quit(2);return
	for index in 2:art.queue_redraw();await RenderingServer.frame_post_draw
	art.depth_probe_active=true
	var layer=CanvasLayer.new();layer.layer=100;root.add_child(layer)
	debug_view=Overlay.new();layer.add_child(debug_view)
	game.editing=false;camera_at(Vector2(-13.1,1.5))
	var street=ProbeStreet.new();var actor={"key":"qa_depth_actor","appearance":102,"position":Vector2(-12.4,2.2),"heading":Vector2.UP,"speed":game.model.WALK_SPEED}
	street.walkers.clear();street.walkers.append(actor);street.visible_ambient.clear();street.visible_ambient[actor.key]=true;art.street_pedestrians=street
	await pair("debug-tree-front")
	actor.position=Vector2(-13.8,.8);await pair("debug-tree-back")
	game.editing=true;game.model.items.clear();game.model.items.append({"id":102,"kind":"chair","x":3,"z":3,"rot":0})
	game.model.customers.clear();game.staff_states.clear();game._rebuild_furniture();game._update_ui();camera_at(Vector2(3.5,3.5))
	await pair("debug-chair-parts")
	check(rows.size()==6,"exactly three overlay-off/on pairs")
	FileAccess.open(output+"/capture.json",FileAccess.WRITE).store_string(JSON.stringify({"source":OS.get_environment("DEPTH_PROBE_SOURCE"),"engine":Engine.get_version_info().string,"adapter":RenderingServer.get_video_adapter_name(),"capture_mode":"debug_view","player_save_used":false,"synthetic":true,"fps_acceptance":false,"frames":rows,"failures":failures}))
	for player in game.audio_players.values():player.stop();player.stream=null
	game.settings_controls.sfx_player.stop();game.settings_controls.sfx_player.stream=null
	for tween in get_processed_tweens():tween.kill()
	layer.free();game.free();quit(0 if failures.is_empty() else 1)
