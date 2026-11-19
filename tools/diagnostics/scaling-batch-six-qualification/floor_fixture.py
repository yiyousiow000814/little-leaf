"""Stage a scoped fixture in disposable copies of the exact original native capture."""
from hashlib import sha256

FIXTURE = "tests/diagnostics/capture_floor_cleaning_approach.gd"
ORIGINAL = "e2018c96d12b1a72c2b4313044b6201e1a65608769213fbe59a0ee63777c9e65"


def overlay(original: bytes) -> bytes:
    if sha256(original).hexdigest() != ORIGINAL:
        raise ValueError("Original floor fixture digest differs")
    text = original.decode()
    start = text.index("func settle():")
    text = text[:start]
    text = text.replace("var obstruction_cases={}", '''const Walls=preload("res://scripts/gameplay/cafe_walls.gd")
var semantic_only=OS.get_environment("FLOOR_SEMANTIC_ONLY")=="1"
var facts={}''')
    text = text.replace("game.illustration.queue_redraw()\n\tfor frame in range(2):await process_frame\n\tawait RenderingServer.frame_post_draw\n\troot.get_texture().get_image().save_png(OS.get_environment(\"OUTPUT\")+\"/\"+label+\".png\")",
'''if not semantic_only:
		assert(visible_cafe(),"Cafe visible before native draw")
		game.illustration.queue_redraw()
		for frame in range(2):await process_frame
		await RenderingServer.frame_post_draw
		assert(visible_cafe(),"Cafe visible after native draw")
		var image:=root.get_texture().get_image()
		assert(image!=null and image.get_size()==Vector2i(1360,880))
		assert(image.save_png(OS.get_environment("OUTPUT")+"/"+label+".png")==OK)''')
    text = text.replace('"obstruction":Approach.solve(staff.pos,staff.art_target,game.model).obstruction', '"solution":str(Approach.solve(staff.pos,staff.art_target,game.model)), "stance":str(game.illustration.stance_offsets.get(key,Vector2.ZERO)), "state":serial_staff(staff), "door_host":game.model.wall_attachments[0].wall_ids[0], "aperture_count":game.model.wall_openings().size()')
    return (text + EXTRA).encode()


EXTRA = '''
func serial_staff(staff:Dictionary)->String:
	var copy=staff.duplicate(true)
	copy.erase("node")
	return str(copy)

func visible_cafe()->bool:
	return game.cafe_intro!=null and not game.cafe_intro.active and not game.cafe_intro.preparing and not game.cafe_intro.cover.is_visible_in_tree()

func place_door(host:String):
	game.model.wall_attachments.assign([{"id":1,"kind":"door","wall_ids":[host],"offset":.5,"width":.75}])
	game.model.revision+=1
	assert(game.model.wall_openings().size()==1,"Installed door must resolve")

func reset_motion():
	game.illustration.motion=game.illustration.MotionArt.new()
	game.illustration.stance_offsets.clear()
	game.illustration.character_facings.clear()
	game.illustration.floor_approach_cache.clear()

func step(count:int):
	game.paused=false
	for tick in range(count):game.illustration.update_motion(1.0/60.0)
	game.paused=true

func run():
	seed(310031);root.size=Vector2i(1360,880)
	game=TestMain.new();root.add_child(game);game.set_process(false);game.illustration.set_process(false);game.paused=true
	if not semantic_only:
		for wait_frame in 900:
			if not is_instance_valid(game.startup_readiness) or game.startup_readiness.completed:break
			await process_frame
		assert(not game.startup_preparation_report.is_empty() and not game.startup_preparation_report.timed_out and game.startup_preparation_report.ready==3)
		game.cafe_intro.finish()
		assert(visible_cafe())
	else:
		for frame in range(4):await process_frame
	for tween in get_processed_tweens():tween.kill()
	game.animation_time=1.0
	game.model.customers.clear();game.service_guests.clear();game.model.items.clear();game.model.built_walls.clear();game.model.wall_attachments.clear();game.model.revision+=1;game.model.operating_open=false
	for worker in game.staff_states:
		worker.pos=Vector2(100,100);worker.path=[];worker.job_kind="";worker.art_action="idle";worker.art_payload="none";worker.art_tool="none"
	var staff:Dictionary=game.staff_states[2]
	staff.role="cleaner";staff.art_role="cleaner"
	var id:int=game.floor_tasks.spawn(Vector2i(6,5),"banana",1,3)
	assert(id>=0)
	var entry:Dictionary=game.floor_tasks.messes[id]
	staff.pos=Vector2(5.5,5.5);entry.floor_work_cell=Vector2i(5,5)
	staff.job_kind="floor";staff.job_mess_id=id;staff.job_step=0;staff.job_elapsed=.2
	game._set_staff_art(staff,"sweeping",{},.25)
	staff.art_target=Vector2(6.65,5.5)
	game._update_ui()
	game.illustration.zoom=2.4;game.illustration.pan_offset=Vector2.ZERO;game.illustration.update_projection()
	game.illustration.pan_offset+=Vector2(680,550)-game.illustration.iso(6.5,5.5);game.illustration.update_projection()
	for z in [4,5,6]:
		game.model.built_walls.append(Walls.installed("wall:fixture:%d"%z,Walls.make("z",6,z,"half"),0,0))
	place_door("wall:fixture:5")
	var key="staff_2"
	var saved=staff.duplicate(true)
	reset_motion()
	assert(Approach.solve(staff.pos,staff.art_target,game.model).offset.length()>.2,"Door cut must permit stance")
	step(1)
	var first:Vector2=game.illustration.stance_offsets.get(key,Vector2.ZERO)
	assert(first.length()>0 and staff==saved,"Cold live renderer must move without mutating the worker")
	await capture("approach-cold",staff,entry)
	step(8)
	var grown:Vector2=game.illustration.stance_offsets.get(key,Vector2.ZERO)
	assert(grown.length()>first.length() and staff==saved and game.illustration.floor_approach_cache[key].current.length()>0)
	await capture("approach-transitional",staff,entry)
	var sample=game.illustration.motion.sample(key).duplicate(true)
	game.illustration.update_motion(2.0)
	assert(game.illustration.stance_offsets[key]==grown and game.illustration.motion.sample(key)==sample and staff==saved)
	await capture("paused",staff,entry)
	place_door("wall:fixture:4")
	reset_motion();step(12)
	var blocked=Approach.solve(staff.pos,staff.art_target,game.model)
	assert(blocked.obstruction.begins_with("wall") and game.illustration.stance_offsets[key]==Vector2.ZERO)
	await capture("solid-first",staff,entry)
	place_door("wall:fixture:5")
	reset_motion();step(12)
	assert(game.illustration.stance_offsets[key].length()>.2)
	await capture("through-door",staff,entry)
	game.model.items.append({"id":999,"kind":"chair","x":6,"z":5,"rot":0})
	game.model.revision+=1;reset_motion();step(12)
	var chair=Approach.solve(staff.pos,staff.art_target,game.model)
	assert(chair.obstruction=="furniture 999" and game.illustration.stance_offsets[key]==Vector2.ZERO)
	await capture("furniture",staff,entry)
	assert(Approach.blocked_by(game.model,Vector2(-1,.1),Vector2(-1,1.1))=="unowned floor")
	game.model.items.clear();game.model.revision+=1
	entry.floor_debris="none";entry.trash_owner="none";entry.floor_spill=true;entry.spill_remaining=1.0;entry.spill_cleaned=false;entry.erase("mess_shape")
	game.floor_tasks.geometry.ensure(entry)
	staff.job_step=3;game._set_staff_art(staff,"mopping",{},.25);staff.art_target=Vector2(6.65,5.5)
	reset_motion();step(12)
	assert(game.illustration.stance_offsets[key].length()>.2)
	await capture("mop",staff,entry)
	assert(game.saves==0 and game.save_writes_suppressed)
	facts={"records":records,"player_save_used":false,"native_visible":not semantic_only and visible_cafe(),"unowned":"unowned floor"}
	FileAccess.open(OS.get_environment("OUTPUT")+"/runtime.json",FileAccess.WRITE).store_string(JSON.stringify(facts,"  "))
	print("FLOOR_CLEANING_NATIVE_RESULT ",JSON.stringify(facts))
	for player in game.audio_players.values():player.stop();player.stream=null
	game.settings_controls.sfx_player.stop();game.settings_controls.sfx_player.stream=null
	for tween in get_processed_tweens():tween.kill()
	game.queue_free();await process_frame;quit()
'''
