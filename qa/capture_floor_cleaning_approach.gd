extends SceneTree
## Actual native renderer, synthetic floor jobs, isolated profile, no saves.
const Approach=preload("res://scripts/floor_cleaning_approach.gd")
class TestMain extends "res://scripts/main.gd":
	var saves=0
	func _load_startup():save_writes_suppressed=true;fresh_start=true;MinimalStart.apply(model)
	func _save():saves+=1;return true
var game
var records=[]
var obstruction_cases={}
func _initialize():run.call_deferred()
func capture(label:String,staff:Dictionary,entry:Dictionary):
	game.illustration.queue_redraw()
	for frame in range(6):await process_frame
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png(OS.get_environment("OUTPUT")+"/"+label+".png")
	var key="staff_%s"%game.staff_states.find(staff)
	var at=game.illustration._render_position(key,staff.pos)
	records.append({"label":label,"logical_position":str(staff.pos),"render_position":str(at),"contact":str(staff.art_target),"contact_distance":staff.pos.distance_to(staff.art_target),"render_contact_distance":at.distance_to(staff.art_target),"floor_work_cell":str(entry.floor_work_cell),"save_attempts":game.saves,"obstruction":Approach.solve(staff.pos,staff.art_target,game.model).obstruction})
func settle():
	game.illustration.motion=game.illustration.MotionArt.new();game.illustration.stance_offsets.clear();game.illustration.character_facings.clear()
	game.paused=false
	for tick in range(40):game.illustration.update_motion(1.0/60.0)
	game.paused=true
func capture_obstruction(staff:Dictionary,entry:Dictionary,kind:String):
	if obstruction_cases.has(kind):return
	var cell:Vector2i=entry.floor_work_cell
	for x in range(cell.x-1,cell.x+2):
		for z in range(cell.y-1,cell.y+2):
			for axis in (["x","z"] if kind=="wall" else [""]):
				if kind=="chair":game.model.items.append({"id":999,"kind":"chair","x":x,"z":z,"rot":0})
				else:game.model.built_walls.append(Approach.Walls.make(axis,x,z,"half"))
				game.model.revision+=1
				var result=Approach.solve(staff.pos,staff.art_target,game.model)
				# Keep the actual original floor work cell valid: this is body
				# clearance beside an obstacle, not a forged through-wall job.
				var valid=game.floor_tasks.geometry.work_cells(entry).has(cell)
				if result.obstruction!="" and valid:
					settle();await capture("obstacle-"+kind,staff,entry)
					obstruction_cases[kind]={"x":x,"z":z,"axis":axis,"reason":result.obstruction,"work_cell_still_valid":valid}
				game.model.items.clear();game.model.built_walls.clear();game.model.revision+=1
				if obstruction_cases.has(kind):return
func run():
	seed(310031);root.size=Vector2i(1360,880)
	game=TestMain.new();root.add_child(game);game.set_process(false);game.illustration.set_process(false);game.paused=true
	for frame in range(30):await process_frame
	game.model.customers.clear();game.service_guests.clear();game.model.items.clear();game.model.built_walls.clear();game.model.revision+=1;game.model.operating_open=false
	for worker in game.staff_states:
		worker.pos=Vector2(100,100);worker.path=[];worker.job_kind="";worker.art_action="idle";worker.art_payload="none";worker.art_tool="none"
	var staff=game.staff_states[2]
	staff.role="cleaner";staff.art_role="cleaner"
	var id=game.floor_tasks.spawn(Vector2i(6,5),"banana",1,3)
	assert(id>=0)
	var entry=game.floor_tasks.messes[id]
	game._update_ui()
	game.illustration.zoom=2.4;game.illustration.pan_offset=Vector2.ZERO;game.illustration.update_projection()
	game.illustration.pan_offset+=Vector2(680,550)-game.illustration.iso(6.5,5.5);game.illustration.update_projection()
	for action in ["sweeping","mopping"]:
		if action=="mopping":
			entry.floor_debris="none";entry.trash_owner="none";entry.floor_spill=true;entry.spill_remaining=1.0;entry.spill_cleaned=false;entry.erase("mess_shape")
			game.floor_tasks.geometry.ensure(entry)
		var cells=game.floor_tasks.geometry.work_cells(entry)
		for view in [[false,1.0,"front-right"],[false,-1.0,"front-left"],[true,1.0,"back-right"],[true,-1.0,"back-left"]]:
			var chosen=Vector2i(-1,-1);var farthest=-1.0
			for cell in cells:
				entry.floor_work_cell=cell;staff.pos=Vector2(cell)+Vector2(.5,.5)
				var target=game.floor_tasks.contact_target(entry,staff,action);var direction=target-staff.pos
				if (direction.x+direction.y<0)!=view[0] or (-1.0 if direction.x-direction.y<0 else 1.0)!=view[1]:continue
				if direction.length()>farthest:farthest=direction.length();chosen=cell
			assert(chosen!=Vector2i(-1,-1))
			entry.floor_work_cell=chosen;staff.pos=Vector2(chosen)+Vector2(.5,.5);staff.job_kind="floor";staff.job_mess_id=id;staff.job_step=0 if action=="sweeping" else 3;staff.job_elapsed=.2
			game._set_staff_art(staff,action,{},.25)
			settle()
			await capture(action+"-"+view[2],staff,entry)
			await capture_obstruction(staff,entry,"chair")
			await capture_obstruction(staff,entry,"wall")
	assert(game.saves==0 and game.save_writes_suppressed)
	FileAccess.open(OS.get_environment("OUTPUT")+"/runtime.json",FileAccess.WRITE).store_string(JSON.stringify({"synthetic":true,"player_save_used":false,"records":records,"obstruction_cases":obstruction_cases},"  "))
	print("FLOOR_CLEANING_NATIVE_RESULT ",JSON.stringify(records))
	for player in game.audio_players.values():player.stop();player.stream=null
	game.settings_controls.sfx_player.stop();game.settings_controls.sfx_player.stream=null
	for tween in get_processed_tweens():tween.kill()
	game.queue_free();await process_frame;quit()
