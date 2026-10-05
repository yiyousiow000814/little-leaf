extends SceneTree
const Fixture=preload("res://tests/role_fixture.gd")
const Tasks=preload("res://scripts/cafe_floor_tasks.gd")
const Approach=preload("res://scripts/floor_cleaning_approach.gd")
const Walls=preload("res://scripts/cafe_walls.gd")
class StageProbe extends "res://scripts/cafe_floor_geometry.gd":
	var actions=[]
	func destination(entry:Dictionary,staff:Dictionary,from:Vector2i,claimed:Array,action:String="")->Vector2i:
		actions.append(action)
		return super.destination(entry,staff,from,claimed,action)
var checks=0
var failures=[]
func check(ok,label):
	checks+=1
	if not ok:failures.append(label);printerr("FAIL ",label)
func _initialize():run.call_deferred()
func run():
	var game=Fixture.new();root.add_child(game);await process_frame
	game.set_process(false);game.illustration.set_process(false);game.model.operating_open=false
	game.model.items.clear();game.model.built_walls.clear();game.model.customers.clear();game.service_guests.clear();game.model.revision+=1
	game.floor_tasks=Tasks.new(game)
	for staff in game.staff_states:game._clear_service_job(staff);staff.path.clear();staff.index=0
	var cleaner=game.worker("cleaner");cleaner.pos=Vector2(5.5,6.5)
	var id=game.floor_tasks.spawn(Vector2i(6,5),"banana",1,3)
	check(id>0,"actual synthetic walking litter created")
	var entry=game.floor_tasks.messes[id];entry.floor_work_cell=Vector2i(5,6)
	var shape=entry.mess_shape.duplicate(true)
	var contact=game.floor_tasks.contact_target(entry,cleaner,"sweeping")
	check(game.floor_tasks.geometry.work_cells(entry).has(Vector2i(5,6)),"open original work side is eligible")
	game.model.items.append({"id":999,"kind":"chair","x":5,"z":5,"rot":0});game.model.revision+=1
	check(Approach.solve(cleaner.pos,contact,game.model).obstruction=="furniture 999","reported chair blocks actual body approach")
	check(not game.floor_tasks.geometry.work_cells(entry).has(Vector2i(5,6)),"chair-blocked body approach is excluded despite clear tool ray")
	var chosen=game.floor_tasks.geometry.destination(entry,cleaner,Vector2i(5,6),[])
	check(chosen!=Vector2i(-1,-1) and chosen!=Vector2i(5,6),"another reachable work side is selected")
	check(not game._static_service_path(Vector2i(5,6),chosen).is_empty(),"alternate side uses an actual grid route")
	var from=game.model.cell_center(chosen);var next_contact=game.floor_tasks.contact_target(entry,{"pos":from},"sweeping")
	check(Approach.solve(from,next_contact,game.model).obstruction=="","alternate side supports the full physical approach")
	check(entry.mess_shape==shape and entry.trash_owner=="floor","selection preserves exact geometry and ownership")
	# Block the original diagonal approach with the user's wall fixture as well.
	game.model.items.clear();game.model.built_walls.append(Walls.make("z",6,5));game.model.revision+=1;entry.floor_work_cell=Vector2i(5,6)
	check(not game.floor_tasks.geometry.work_cells(entry).has(Vector2i(5,6)),"wall-end body obstruction excludes original work side")
	chosen=game.floor_tasks.geometry.destination(entry,cleaner,Vector2i(5,6),[])
	check(chosen!=Vector2i(-1,-1) and chosen!=Vector2i(5,6),"wall case selects another reachable side")
	# A genuinely enclosed footprint has no admissible side. Row29 must leave
	# it pending rather than own it indefinitely or draw an impossible action.
	game.model.built_walls.clear()
	for wall in [Walls.make("z",6,5),Walls.make("z",7,5),Walls.make("x",6,5),Walls.make("x",6,6)]:game.model.built_walls.append(wall)
	game.model.revision+=1
	check(game.floor_tasks.geometry.layout_clear(entry.mess_shape),"enclosed mess shape itself remains clear")
	check(game.floor_tasks.geometry.destination(entry,cleaner,Vector2i(5,6),[])==Vector2i(-1,-1),"no clear side returns NO_CELL")
	var pending=entry.duplicate(true)
	game.floor_tasks.assign(cleaner,game.staff_states.find(cleaner))
	check(cleaner.job_kind=="" and entry==pending,"merged row29 leaves inaccessible mess pending without ownership or timing changes")
	# Switching a legacy mixed mess from dry litter to water must not reuse the
	# sweep eligibility cache; shape and layout remain unchanged at this point.
	game.model.built_walls.clear();game.model.revision+=1
	entry.floor_spill=true;entry.spill_cleaned=false;entry.spill_remaining=1.0;entry.spill_target=entry.floor_target+Vector2(.13,-.1);entry.erase("mess_shape")
	game.floor_tasks.geometry.ensure(entry);game.floor_tasks.geometry.work_cells(entry)
	var cache=game.floor_tasks.geometry.work_cell_cache.size()
	entry.trash_owner="staff";game.floor_tasks.geometry.work_cells(entry)
	check(game.floor_tasks.geometry.work_cell_cache.size()==cache+1,"stage-specific eligibility cache separates sweep and mop")
	# Loaded saves may already own trash while retaining an elapsed sweep.
	# The current step, not ownership inferred from the record, chooses contact.
	var probe=StageProbe.new(game);game.floor_tasks.geometry=probe
	cleaner.job_kind="floor";cleaner.job_mess_id=id;cleaner.job_step=0;cleaner.job_elapsed=.35
	game.floor_tasks.destination(cleaner,Vector2i(5,6),[])
	check(probe.actions[-1]=="sweeping","held standalone partial sweep keeps sweep eligibility")
	cleaner.job_kind="cleanup";cleaner.job_step=3
	entry.guest={"id":101};cleaner.job_guest_id=101;cleaner.job_token=entry.token
	game.floor_tasks.destination_for_record(entry,cleaner,Vector2i(5,6),[])
	check(probe.actions[-1]=="sweeping","held diner partial sweep keeps sweep eligibility")
	check(cleaner.job_elapsed==.35 and entry.trash_owner=="staff","eligibility does not change partial time or held ownership")
	cleaner.job_step=6;game.floor_tasks.destination_for_record(entry,cleaner,Vector2i(5,6),[])
	check(probe.actions[-1]=="mopping","actual resumed mop step uses mop eligibility")
	cleaner.job_kind="";cleaner.job_step=0;game.floor_tasks.destination_for_record(entry,cleaner,Vector2i(5,6),[])
	check(probe.actions[-1]=="","idle candidate ranking keeps first-needed inference")
	cleaner.job_kind="cleanup";cleaner.job_step=3;cleaner.job_guest_id=102
	game.floor_tasks.destination_for_record(entry,cleaner,Vector2i(5,6),[])
	check(probe.actions[-1]=="","another record's active step cannot affect candidate ranking")
	# Independent review found this legacy mixed shape: its mop contact is
	# safe at (5,6), but an already-held sweep still collides with chair999.
	game.model.items.clear();game.model.items.append({"id":999,"kind":"chair","x":6,"z":6,"rot":0});game.model.revision+=1
	var legacy={"id":49,"token":49,"floor_cell":Vector2i(6,5),"floor_target":Vector2(6.5,5.5),"debris_target":Vector2(6.6,5.42),"spill_target":Vector2(6.4,5.58),"floor_debris":"banana","floor_spill":true,"spill_cleaned":false,"spill_remaining":1.0,"trash_owner":"staff","floor_work_cell":Vector2i(5,6)}
	legacy.mess_shape=Tasks.Geometry._build(legacy,49,1.0)
	game.floor_tasks.messes[49]=legacy;cleaner.pos=Vector2(5.5,6.5);cleaner.job_kind="floor";cleaner.job_mess_id=49;cleaner.job_step=0
	var actual=probe.contact_target(legacy,cleaner,"sweeping")
	check(Approach.solve(cleaner.pos,actual,game.model).obstruction=="furniture 999","regression reproduces held sweep's unsafe original contact")
	check(probe.work_cells(legacy,"mopping").has(Vector2i(5,6)) and not probe.work_cells(legacy,"sweeping").has(Vector2i(5,6)),"regression requires action-specific physical eligibility")
	chosen=game.floor_tasks.destination(cleaner,Vector2i(5,6),[])
	check(chosen!=Vector2i(5,6),"held partial sweep never selects a mop-only safe side")
	if chosen!=Vector2i(-1,-1):
		var shown=game.model.cell_center(chosen);var sweep_contact=probe.contact_target(legacy,{"pos":shown},"sweeping")
		check(Approach.solve(shown,sweep_contact,game.model).obstruction=="","held sweep alternate side is safe for its actual contact")
	print("FLOOR_WORK_SIDE_RESULT ",JSON.stringify({"checks":checks,"failures":failures,"alternate_cell":str(chosen)}))
	game.queue_free();await process_frame;quit(0 if failures.is_empty() else 1)
