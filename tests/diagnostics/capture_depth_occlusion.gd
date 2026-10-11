extends SceneTree
## Manual dev-only pilot. Uses the existing role fixture/startup and live artist,
## expansion-tree predicate and Decorate interaction handlers. No player profile.
const Fixture=preload("res://tests/role_fixture.gd")
class ProbeStreet extends "res://scripts/street_pedestrians.gd":
	func advance(_delta:float,_queue_positions:Array=[]):pass
	func observe_customers(_customers:Array,_delta:float,_walk_speed:float,_parking_visits:Array=[]):pass
var game
var art
var rows=[]
var failures=[]
var max_frames=720
var label=""
var crop=Rect2i()
var output=""
func _initialize():run.call_deferred()
func check(ok:bool,message:String):
	if not ok:failures.append(message);printerr(message)
func vec(value:Vector2)->Array:return [value.x,value.y]
func frame():
	art.queue_redraw()
	await RenderingServer.frame_post_draw
	if rows.size()>=max_frames:check(false,"bounded frame budget exhausted");return
	var image=root.get_texture().get_image()
	var clipped=crop.intersection(Rect2i(Vector2i.ZERO,image.get_size()))
	check(clipped.has_area(),"diagnostic crop must be visible")
	if not clipped.has_area():return
	var index=rows.size();var file="frame-%04d.png"%index
	check(image.get_region(clipped).save_png(output+"/"+file)==OK,"frame PNG write")
	var events=art.depth_probe_events.duplicate(true)
	for row in events:
		if not row.has("node_id"):continue
		var node=instance_from_id(row.node_id)
		if is_instance_valid(node):
			row["index_at_completed_frame"]=node.get_index();row["visible_at_completed_frame"]=node.visible
			if node.get("draw_count")!=null:row["draw_count"]=node.draw_count
	var interaction=game.interaction
	rows.append({"sample":index,"label":label,"frame":Engine.get_frames_drawn(),"tick_usec":Time.get_ticks_usec(),"file":file,"crop":[clipped.position.x,clipped.position.y,clipped.size.x,clipped.size.y],"events":events,"dropped":art.depth_probe_dropped,"coins":game.model.coins,"items":game.model.items.duplicate(true),"preview":interaction.preview_active,"drag":interaction.drag_active,"rotation":interaction.drag_rotation,"cell":[interaction.drag_cell.x,interaction.drag_cell.y],"saves_suppressed":game.save_writes_suppressed})
func hold(count:int):
	for index in count:await frame()
func camera_at(world:Vector2):
	art.update_projection()
	game.interaction._pan_by(art.camera_safe_rect().get_center()+Vector2(0,65)-art.iso(world.x,world.y))
	var at=art.iso(world.x,world.y)
	crop=Rect2i(Vector2i(at)-Vector2i(220,240),Vector2i(440,360))
func walk_segment(from:Vector2,to:Vector2,actor:Dictionary,stage:String):
	label=stage;actor.position=from
	var started=Time.get_ticks_usec();var previous=started
	var duration=from.distance_to(to)/game.model.WALK_SPEED
	for index in 240:
		var now=Time.get_ticks_usec();var dt=clampf(float(now-previous)/1000000.,.000001,.1);previous=now
		var t=clampf(float(now-started)/1000000./duration,0,1)
		actor.position=from.lerp(to,t);actor.heading=(to-from).normalized()
		art.street_pedestrians.motion.update(actor.key,actor.position,dt)
		await frame()
		if t>=1:return
	check(false,"walk segment exceeded 240 completed frames")
func actor_tree():
	game.editing=false;game.paused=false
	var world=Vector2(-13.1,1.5);camera_at(world)
	check(art._scenery_tree_visible_at(world),"authored oak remains visible")
	var street=ProbeStreet.new();var actor={"key":"qa_depth_actor","appearance":102,"position":world+Vector2(.7,.7),"heading":Vector2.UP,"speed":game.model.WALK_SPEED}
	street.walkers=[actor];street.visible_ambient.clear();street.visible_ambient[actor.key]=true;art.street_pedestrians=street
	await walk_segment(world+Vector2(.7,.7),world-Vector2(.7,.7),actor,"tree-front-to-back")
	await walk_segment(world-Vector2(.7,.7),world+Vector2(.7,.7),actor,"tree-back-to-front")
	await walk_segment(world+Vector2(-.85,.35),world+Vector2(.85,-.35),actor,"tree-diagonal-crown-trunk-edge")
	check(rows.any(func(row):return row.events.any(func(e):return e.context.id=="qa_depth_actor")),"actual actor submissions observed")
	check(rows.any(func(row):return row.events.any(func(e):return e.context.part=="scenery_tree")),"actual tree submissions observed")
func decorate():
	game.paused=true;game.editing=true;game.model.begin_decoration_session()
	game.model.items=[{"id":101,"kind":"table","x":3,"z":3,"rot":0},{"id":102,"kind":"chair","x":5,"z":3,"rot":0}]
	game.model.dining_sets.clear();game.model.customers.clear()
	game.staff_states.clear();game._rebuild_furniture();game._update_ui()
	camera_at(Vector2(4.5,3.5));game.compact_ui._set_tray_reveal(1)
	var wallet=game.model.coins
	for id in [101,102]:
		for rotation in range(4):
			game.interaction.cancel();game.selected_id=id;game.selected_kind="";game.rotation_step=game.model.logical_rotation(id)
			for step in 4:
				if game.model.logical_rotation(id)==rotation:break
				game.interaction.rotate_selection()
			check(game.model.logical_rotation(id)==rotation,"requested synthetic rotation reached")
			label="decorate-%s-r%d-selected"%[id,rotation];await hold(3)
			var item=game.model.get_item(id);var original=item.duplicate(true)
			var press=art.iso(item.x+.5,item.z+.5)
			game.interaction._begin_left(press);await hold(2)
			var target=art.iso(item.x+.5,item.z+1.5)
			game.interaction._move_left(target);label="decorate-%s-r%d-preview"%[id,rotation];await hold(4)
			check(game.interaction.drag_active and game.interaction.preview_active,"real handlers entered drag preview")
			game.interaction._release_left(target);label="decorate-%s-r%d-confirm"%[id,rotation];await hold(4)
			check(not game.interaction.preview_active,"confirm clears preview")
			var confirmed=game.model.get_item(id).duplicate(true)
			check(int(confirmed.z)==int(original.z)+1,"confirmed synthetic item moves exactly one tile")
			press=art.iso(confirmed.x+.5,confirmed.z+.5);target=art.iso(confirmed.x+1.5,confirmed.z+.5)
			game.interaction._begin_left(press);game.interaction._move_left(target)
			label="decorate-%s-r%d-cancel-preview"%[id,rotation];await hold(4)
			game.interaction.cancel();label="decorate-%s-r%d-cancel"%[id,rotation];await hold(4)
			check(game.model.get_item(id)==confirmed,"cancel preserves confirmed item exactly")
			check(game.model.coins==wallet,"move/rotation/cancel preserves synthetic wallet")
			# Reset only the synthetic fixture placement between independent trials.
			game.model.get_item(id).x=original.x;game.model.get_item(id).z=original.z
func run():
	output=OS.get_environment("DEPTH_PROBE_OUTPUT")
	if output=="" or not "saveguard" in OS.get_user_data_dir() or DisplayServer.get_name()=="headless":printerr("Use isolated native diagnostic launcher");quit(2);return
	root.size=Vector2i(1360,880);game=Fixture.new();root.add_child(game)
	game.set_process(false);game.paused=true;game.model.operating_open=false
	if game.cafe_intro!=null:game.cafe_intro.finish()
	art=game.illustration;art.set_process(false)
	if art.get("depth_probe_active")==null:printerr("Use staged probe hooks");game.free();quit(2);return
	for index in 30:art.queue_redraw();await RenderingServer.frame_post_draw
	art.depth_probe_active=true
	await actor_tree()
	await decorate()
	art.depth_probe_active=false
	var contours=[]
	for index in art.exterior_tree_art.layers.size():
		var layer=art.exterior_tree_art.layers[index];var points=[]
		for point in layer[1]:points.append(vec(point))
		contours.append({"layer":index,"color":layer[0],"points":points})
	var report={"source":OS.get_environment("DEPTH_PROBE_SOURCE"),"engine":Engine.get_version_info().string,"adapter":RenderingServer.get_video_adapter_name(),"player_save_used":false,"synthetic":true,"tracked_production_source_modified":false,"fps_acceptance":false,"overlay":false,"tree_world":[-13.1,1.5],"authored_tree_contours":contours,"frames":rows,"failures":failures}
	FileAccess.open(output+"/capture.json",FileAccess.WRITE).store_string(JSON.stringify(report))
	print("DEPTH_OCCLUSION_CAPTURE ",JSON.stringify({"frames":rows.size(),"failures":failures,"player_save_used":false}))
	for player in game.audio_players.values():player.stop();player.stream=null
	game.settings_controls.sfx_player.stop();game.settings_controls.sfx_player.stream=null
	for tween in get_processed_tweens():tween.kill()
	game.free();quit(0 if failures.is_empty() else 1)
