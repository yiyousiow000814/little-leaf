extends SceneTree
const Model=preload("res://scripts/core/cafe_model.gd")
const Tasks=preload("res://scripts/gameplay/cafe_floor_tasks.gd")
const Codec=preload("res://scripts/persistence/cafe_runtime_codec.gd")
const LegacyFixture=preload("res://tests/fixtures/build_litter_legacy_spill.gd")
const MessArt=preload("res://scripts/rendering/floor_mess_art.gd")
class Fixture extends RefCounted:
	const WorkClaims=preload("res://scripts/gameplay/cafe_work_claims.gd")
	var model=Model.new()
	var staff_states=[]
	var floor_tasks
	var service_guests={}
	var wall_detail=false
	func _task_owned(identity:Array,except_index:int=-1)->bool:
		for index in staff_states.size():
			if index!=except_index and WorkClaims.task_conflicts(identity,WorkClaims.task(staff_states[index])):return true
		return false
	func _floor_work_intent(staff:Dictionary,entry:Dictionary,cell:Vector2i)->Dictionary:
		var prospective={"job_kind":"floor","job_mess_id":int(entry.id),"job_token":int(entry.token)}
		return WorkClaims.contact(prospective,{"kind":"floor","id":-1000000-int(entry.id)},cell,staff_states.find(staff))
	func _work_cell_available(cell:Vector2i,staff:Dictionary,intent:Dictionary,claimed:Array,frame_claims:Dictionary={})->bool:
		# This model-only fixture exercises one cleaner's custody, not roster arbitration.
		# Fail explicitly if a future scenario needs Main's multi-worker interface.
		assert(staff_states.size()==1 and is_same(staff_states[0],staff) and claimed.is_empty() and frame_claims.is_empty())
		if intent.is_empty() or not _staff_walkable(cell) or model.checkout_claims().has(cell):return false
		var from=Vector2i(staff.pos.floor())
		return from==cell or not _static_service_path(from,cell).is_empty()
	func _staff_walkable(cell):
		if cell.x<1 or not model.is_floor_owned(cell):return false
		var item=model.item_at(cell.x,cell.y)
		return item.is_empty() or item.kind=="rug"
	func _is_station_workface(cell):
		for item in model.items:
			if item.kind=="bin" and model.bin_service_cells(item).has(cell):return true
			if item.kind in ["stove","beverage","sink","counter","register"] and model.workface_cell(item)==cell:return true
			if item.kind in ["counter","register"] and Vector2i(item.x,item.z)*2-model.workface_cell(item)==cell:return true
		return false
	func _static_service_path(a,b):return model.path_between(a,b)
	func _clear_service_job(staff):staff.job_kind="";staff.job_mess_id=-1
	func _service_station(kind,_from,_index):
		for item in model.items:
			if item.kind==kind:return item
		return {}
class TrafficProbe extends Tasks:
	var opportunities=0
	func spawn(_cell,_kind,_id=-1,_step=0):opportunities+=1;return -1
# Frozen #384 observation and ordered spawn reference. Shared geometry and codec
# are intentional: the change only replaces the floor-policy lookup.
class LegacyObservation extends Tasks:
	func observe_walks():
		var live={}
		for guest in game.model.customers:
			var id=int(guest.id);live[id]=true;var pos=Vector2(float(guest.x),float(guest.z));var cell=Vector2i(floori(pos.x),floori(pos.y))
			if not walks.has(id):walks[id]={"guest_id":id,"pos":pos,"cell":cell,"inside_steps":0,"dropped":false};continue
			if game.model.layout_held("guests",id):continue
			var track=walks[id];var old_cell:Vector2i=track.cell;var moved=pos.distance_to(track.pos)>.00001
			var adjacent=absi(cell.x-old_cell.x)+absi(cell.y-old_cell.y)==1
			if moved and adjacent and str(guest.phase) in WALKING_PHASES and not bool(guest.get("withdrawn",false)) and not game.model.segment_blocked(track.pos,pos) and scan_allowed(old_cell):
				track.inside_steps+=1
				# Each eligible crossing offers a small repeatable chance, so aggregate
				# frequency grows with customer traffic, not an every-footstep guarantee.
				var roll=posmod(id*53+int(track.inside_steps)*17,100)
				if not track.dropped and int(track.inside_steps)>=3 and roll<DROP_CHANCE_PERCENT:
					var kind=["banana","crumbs"][posmod(id+int(track.inside_steps),2)]
					var spawned=spawn(old_cell,kind,id,int(track.inside_steps))
					if spawned>=0:track.dropped=true
			track.pos=pos;track.cell=cell
		for id in walks.keys():
			if not live.has(id):walks.erase(id)
	func spawn(cell:Vector2i,kind:String,guest_id=-1,path_step=0)->int:
		if messes.size()>=MAX_NEW_LITTER or kind not in ["banana","crumbs"] or not scan_allowed(cell):return -1
		for entry in messes.values():
			var separation:Vector2i=entry.floor_cell-cell
			if absi(separation.x)<=1 and absi(separation.y)<=1:return -1
		var center=Vector2(cell)+Vector2(.5,.5);var id=next_id
		var entry={"id":id,"token":id,"floor_cell":cell,"floor_target":center,"debris_target":center+Vector2(.1,-.08),"spill_target":center+Vector2(-.1,.08),"floor_debris":"none" if kind=="spill" else kind,"floor_spill":kind=="spill","spill_remaining":1.0 if kind=="spill" else 0.0,"spill_cleaned":kind!="spill","trash_owner":"none" if kind=="spill" else "floor","trash_staff_index":-1,"trash_target_id":-1,"floor_dirty":true,"floor_cleaned":false,"source_guest_id":guest_id,"spawn_path_step":path_step}
		if not geometry.generate(entry,posmod(id*47+int(guest_id)*13,1000000000),LITTER_SCALE,true):return -1
		# Every visible piece must stay inside the actually traversed eligible tile.
		for point in entry.mess_shape.outline:
			if Vector2i(floori(point.x),floori(point.y))!=cell:return -1
		messes[id]=entry;next_id+=1
		return id
	func scan_allowed(cell:Vector2i)->bool:
		if not game._staff_walkable(cell) or game._is_station_workface(cell):return false
		for zone in litter_exclusions:
			if zone.has_point(cell):return false
		# There are no persisted zone labels in this baseline. Reserve the kitchen
		# station neighborhoods; future explicit zones use litter_exclusions above.
		for item in game.model.items:
			if str(item.kind) in KITCHEN_KINDS and Rect2i(Vector2i(int(item.x)-1,int(item.z)-1),Vector2i(3,3)).has_point(cell):return false
		return true
class ArtRecorder extends RefCounted:
	var game
	var ui_scale=1.0
	var zoom=1.0
	var commands=[]
	func iso(x,z,_h=0.0):return Vector2(350,55)+Vector2((x-z)*39,(x+z)*19.5)-Vector2(0,_h*ui_scale*zoom)
	func tint(c):return (Color(c) if c is String else c).to_html(true)
	func poly(points,c):commands.append({"type":"polygon","points":points,"color":tint(c)})
	func line(a,b,c,width=1.0):commands.append({"type":"line","a":a,"b":b,"color":tint(c),"width":width})
	func ellipse(center,size,c):commands.append({"type":"ellipse","center":center,"size":size,"color":tint(c)})
var checks=0
var failures=[]
var evidence={}
var fixtures=[]
func _init():call_deferred("run")
func check(ok,label):
	checks+=1
	if not ok:failures.append(label);printerr("FAIL ",label)
func walk(game,id=1):
	game.model.customers.clear();game.model.customers.append({"id":id,"x":2.5,"z":6.5,"phase":"arriving"})
	game.floor_tasks.observe_walks()
	for x in [3.5,4.5,5.5]:
		game.model.customers[0].x=x;game.floor_tasks.observe_walks()
func empty_floor():
	var game=Fixture.new();fixtures.append(game);game.model.items.clear();game.model.revision+=1;game.floor_tasks=Tasks.new(game)
	return game
func run():
	var out=OS.get_environment("LL_LITTER_EVIDENCE")
	check(OS.get_environment("XDG_DATA_HOME")!="" and OS.get_user_data_dir().replace("\\","/").begins_with(OS.get_environment("XDG_DATA_HOME").replace("\\","/")),"isolated user directory")
	var game=Fixture.new();fixtures.append(game);game.floor_tasks=Tasks.new(game)
	walk(game)
	var art=ArtRecorder.new();art.game=game
	for record in game.floor_tasks.messes.values():MessArt.draw(art,record)
	evidence={"fixture":"default furnished baseline, guest1 walks (2.5,6.5) through (5.5,6.5)","path":[Vector2(2.5,6.5),Vector2(3.5,6.5),Vector2(4.5,6.5),Vector2(5.5,6.5)],"messes":game.floor_tasks.snapshot(),"render_commands":art.commands}
	check(game.floor_tasks.messes.size()==1,"same route produces occasional litter")
	var entry=game.floor_tasks.messes.values()[0]
	check(not entry.floor_spill and entry.mess_shape.spill_outline.is_empty(),"new walking event contains no water polygon")
	check(entry.floor_cell==Vector2i(4,6) and entry.source_guest_id==1 and entry.spawn_path_step==3,"drop belongs to actual crossed tile and guest")
	for point in entry.mess_shape.outline:
		check(Vector2i(floori(point.x),floori(point.y))==entry.floor_cell,"litter visible footprint remains inside crossed tile")
	var before=game.floor_tasks.messes.size()
	for i in range(20):game.floor_tasks.observe_walks()
	check(game.floor_tasks.messes.size()==before,"stationary diners never spawn")
	check(game.floor_tasks.spawn(Vector2i(4,6),"banana",2,3)==-1,"duplicate tile rejected")
	check(game.floor_tasks.spawn(Vector2i(5,6),"crumbs",2,3)==-1,"adjacent density rejected")
	check(game.floor_tasks.spawn(Vector2i(2,3),"spill",2,3)==-1,"new spill spawning rejected")
	check(not game.floor_tasks.litter_allowed(Vector2i(8,0)),"kitchen neighborhood excluded")
	check(not game.floor_tasks.litter_allowed(Vector2i(8,3)),"staff workface excluded")
	check(not game.floor_tasks.litter_allowed(Vector2i(3,3)),"occupied furnishing excluded")
	check(not game.floor_tasks.litter_allowed(Vector2i(-1,5)),"outside invalid floor excluded")
	game.floor_tasks.litter_exclusions.append(Rect2i(2,4,2,2))
	check(not game.floor_tasks.litter_allowed(Vector2i(2,4)),"future toilet/staff-only exclusion")
	game.floor_tasks.litter_exclusions.clear()
	var empty=empty_floor()
	empty.model.customers.append({"id":1,"x":2.5,"z":5.5,"phase":"arriving"});empty.floor_tasks.observe_walks()
	empty.model.customers[0].x=7.5;empty.floor_tasks.observe_walks()
	check(empty.floor_tasks.walks[1].inside_steps==0,"unknown multi-cell jump does not infer visited tiles")
	var continued=empty_floor();walk(continued)
	for point in [Vector2(5.5,7.5),Vector2(4.5,7.5),Vector2(3.5,7.5),Vector2(2.5,7.5),Vector2(2.5,6.5)]:
		continued.model.customers[0].x=point.x;continued.model.customers[0].z=point.y;continued.floor_tasks.observe_walks()
	check(continued.floor_tasks.messes.size()==1,"one drop per guest visit despite continued walking")
	var checkout=Fixture.new();fixtures.append(checkout);checkout.floor_tasks=Tasks.new(checkout)
	checkout.model.customers.append({"id":1,"x":2.5,"z":6.5,"phase":"checkout_walk"});checkout.floor_tasks.observe_walks()
	for x in [3.5,4.5,5.5]:checkout.model.customers[0].x=x;checkout.floor_tasks.observe_walks()
	check(checkout.floor_tasks.messes.size()==1,"checkout walking is eligible customer traffic")
	var withdrawn=empty_floor();withdrawn.model.customers.append({"id":1,"x":2.5,"z":6.5,"phase":"leaving","withdrawn":true});withdrawn.floor_tasks.observe_walks()
	for x in [3.5,4.5,5.5]:withdrawn.model.customers[0].x=x;withdrawn.floor_tasks.observe_walks()
	check(withdrawn.floor_tasks.messes.is_empty(),"withdrawn customers never drop indoor litter")
	var counts=[]
	for population in [1,20]:
		var traffic=empty_floor();var probe=TrafficProbe.new(traffic);traffic.floor_tasks=probe
		for id in range(1,population+1):traffic.model.customers.append({"id":id,"x":2.5,"z":6.5,"phase":"arriving"})
		probe.observe_walks()
		for x in [3.5,4.5,5.5]:
			for guest in traffic.model.customers:guest.x=x
			probe.observe_walks()
		counts.append(probe.opportunities)
	check(counts[1]>counts[0] and counts[1]<20,"more customer traffic raises opportunities without guaranteed drops")
	evidence.traffic_opportunities={"one_customer":counts[0],"twenty_customers":counts[1]}
	var capped=empty_floor()
	for id in range(12):capped.floor_tasks.messes[id+1]={"floor_cell":Vector2i(100+id*3,100)}
	check(capped.floor_tasks.spawn(Vector2i(4,6),"banana",99,3)==-1,"new litter cap reached")
	# Real codec JSON roundtrip; old water jobs remain valid and keep geometry.
	var codec=Codec.new();var original=JSON.parse_string(FileAccess.get_file_as_string("res://tests/fixtures/litter_legacy_spill.json"))
	var regenerated=JSON.parse_string(JSON.stringify(LegacyFixture.build()))
	check(regenerated==original,"legacy fixture exactly reproduced from frozen geometry and synthetic constants")
	var legacy=codec.decode(original.messes)
	var restored=Tasks.new(game);restored.restore(legacy)
	check(restored.messes.values()[0].floor_spill,"legacy saved spill retained")
	check(Tasks.validate_snapshot(restored.snapshot(),[],{}, {1:{}},codec).ok,"legacy snapshot validates")
	var current=codec.decode(JSON.parse_string(JSON.stringify(codec.encode(game.floor_tasks.snapshot()))))
	var roundtrip=Tasks.new(game);roundtrip.restore(current)
	check(Tasks.validate_snapshot(roundtrip.snapshot(),[],{}, {1:{}},codec).ok,"new litter snapshot validates")
	check(roundtrip.messes.values()[0].mess_shape==entry.mess_shape,"new litter shape survives save roundtrip")
	# Sweep -> carried dustpan -> bin -> removed, using existing cleanup stages.
	game.model.items.append({"id":999,"kind":"bin","x":11,"z":7,"rot":0});game.model.revision+=1
	var cleaner={"role":"cleaner","pos":Vector2(4.5,5.5),"job_kind":"","path":[],"index":0};game.staff_states=[cleaner]
	game.floor_tasks.assign(cleaner,0)
	check(cleaner.job_kind=="floor","existing cleaner accepts litter")
	game.floor_tasks.contact(cleaner,0,"sweeping",{},1.0)
	check(entry.trash_owner=="staff" and game.floor_tasks.payload(cleaner,0)=="trash","sweep puts litter in dustpan")
	game.floor_tasks.complete_step(cleaner,0)
	check(cleaner.job_step==2,"litter goes to bin without mopping")
	game.floor_tasks.contact(cleaner,0,"disposing_trash",game.model.get_item(999),1.0)
	game.floor_tasks.complete_step(cleaner,0)
	check(game.floor_tasks.messes.is_empty() and cleaner.job_kind=="","completed litter job clears tile")
	extended_checks(codec,legacy)
	art.game=null
	for fixture in fixtures:
		fixture.floor_tasks.game=null;fixture.floor_tasks.geometry.game=null;fixture.floor_tasks=null
	fixtures.clear()
	evidence.checks=checks;evidence.failures=failures
	if out!="":
		var file=FileAccess.open(out,FileAccess.WRITE);file.store_string(JSON.stringify(Codec.new().encode(evidence),"\t"));file.close()
	print(JSON.stringify({"checks":checks,"failures":failures,"successful_drops":evidence.get("successful_drops",{})}))
	quit(0 if failures.is_empty() else 1)

func extended_checks(codec,legacy):
	test_observed_bin_side_geometry()
	test_observation_parity(codec)
	test_natural_walks()
	var total=0;var at_ten=0
	for id in range(1,101):
		var traffic=empty_floor();walk(traffic,id)
		total+=traffic.floor_tasks.messes.size()
		if id==10:at_ten=total
	check(at_ten>0 and total>at_ten and total<100,"successful litter, not just attempted spawns, grows across customer visits")
	evidence.successful_drops={"ten_visits":at_ten,"hundred_visits":total,"same_three_crossing_route":true,"clean_floor_between_visits":true}
	var stationary=empty_floor()
	stationary.model.customers.append({"id":1,"x":4.5,"z":6.5,"phase":"eating"})
	for i in range(100):stationary.floor_tasks.observe_walks()
	check(stationary.floor_tasks.messes.is_empty(),"customer presence without walking never creates litter")
	for phase in ["ordering","cooking","drinking","eating","paying","dirty","cleaning"]:
		var nonwalking=empty_floor()
		nonwalking.model.customers.append({"id":1,"x":2.5,"z":6.5,"phase":phase})
		nonwalking.floor_tasks.observe_walks()
		for x in [3.5,4.5,5.5]:nonwalking.model.customers[0].x=x;nonwalking.floor_tasks.observe_walks()
		check(nonwalking.floor_tasks.messes.is_empty(),"no drops in nonwalking phase "+phase)
	var wall=empty_floor()
	wall.model.built_walls.append({"axis":"z","x":5,"z":6,"height":"full","material":"sage_panels"});wall.model.revision+=1
	walk(wall)
	check(wall.floor_tasks.messes.is_empty() and wall.floor_tasks.walks[1].inside_steps==2,"a crossing through a wall never earns a litter event")
	var blocked=empty_floor();blocked.floor_tasks.litter_exclusions.append(Rect2i(1,1,10,7));walk(blocked)
	check(blocked.floor_tasks.messes.is_empty() and blocked.floor_tasks.walks[1].inside_steps==0,"whole future staff-only or toilet zone suppresses walking litter")
	var saved=empty_floor();walk(saved)
	var exact=codec.decode(JSON.parse_string(JSON.stringify(codec.encode(saved.floor_tasks.snapshot()))))
	saved.floor_tasks.restore(exact)
	for point in [Vector2(6.5,6.5),Vector2(7.5,6.5),Vector2(7.5,7.5),Vector2(6.5,7.5),Vector2(5.5,7.5),Vector2(4.5,7.5),Vector2(3.5,7.5)]:
		saved.model.customers[0].x=point.x;saved.model.customers[0].z=point.y;saved.floor_tasks.observe_walks()
	check(saved.floor_tasks.messes.size()==1 and saved.floor_tasks.walks[1].dropped,"save/reload preserves the one-drop-per-visit flag")
	saved.model.customers.clear();saved.floor_tasks.observe_walks()
	check(saved.floor_tasks.walks.is_empty() and saved.floor_tasks.messes.size()==1,"departed guests release tracking while litter remains for cleanup")
	var old=empty_floor();old.floor_tasks.restore(legacy)
	var spill=old.floor_tasks.messes.values()[0];var old_shape=spill.mess_shape.duplicate(true)
	var cleaner={"role":"cleaner","pos":Vector2(4.5,5.5),"job_kind":"","path":[],"index":0};old.staff_states=[cleaner]
	old.floor_tasks.assign(cleaner,0)
	check(cleaner.job_step==3,"legacy spill still selects the mopping stage")
	old.floor_tasks.contact(cleaner,0,"mopping",{},.4);cleaner.job_elapsed=.6
	var partly=codec.decode(JSON.parse_string(JSON.stringify(codec.encode(old.floor_tasks.snapshot()))))
	old.floor_tasks.restore(partly);spill=old.floor_tasks.messes.values()[0]
	check(spill.mess_shape==old_shape and cleaner.job_elapsed==.6 and float(spill.spill_remaining)>0 and float(spill.spill_remaining)<1,"legacy partial mop keeps geometry, elapsed time, and remaining water")
	old.floor_tasks.contact(cleaner,0,"mopping",{},1.0);old.floor_tasks.complete_step(cleaner,0)
	check(old.floor_tasks.messes.is_empty(),"legacy water remains completely cleanable")
	var held=empty_floor();walk(held)
	held.model.items.append({"id":999,"kind":"bin","x":11,"z":7,"rot":0});held.model.revision+=1
	var carrier={"role":"cleaner","pos":Vector2(4.5,5.5),"job_kind":"","path":[],"index":0};held.staff_states=[carrier]
	held.floor_tasks.assign(carrier,0);held.floor_tasks.contact(carrier,0,"sweeping",{},1.0);carrier.job_elapsed=.85
	var carried=codec.decode(JSON.parse_string(JSON.stringify(codec.encode(held.floor_tasks.snapshot()))))
	check(Tasks.validate_snapshot(carried,[carrier],{999:held.model.get_item(999)},{1:{}},codec).ok,"held litter remains a valid save")
	held.floor_tasks.restore(carried)
	check(held.floor_tasks.payload(carrier,0)=="trash" and carrier.job_elapsed==.85,"restoring carried litter preserves cleaner ownership and elapsed progress")
	held.floor_tasks.complete_step(carrier,0);held.floor_tasks.contact(carrier,0,"disposing_trash",held.model.get_item(999),1.0);held.floor_tasks.complete_step(carrier,0)
	check(held.floor_tasks.messes.is_empty(),"restored held litter completes at bin without duplication")
	var full=legacy.duplicate(true);full.walks=[];full.messes=[];full.next_id=25
	for i in range(24):
		var entry=legacy.messes[0].duplicate(true);entry.id=i+1;entry.token=i+1
		var shift=Vector2(i%8-3,i/8-3);entry.floor_cell+=Vector2i(shift)
		for key in ["floor_target","debris_target","spill_target"]:entry[key]+=shift
		entry.mess_shape.center+=shift
		for key in ["outline","spill_outline"]:
			for j in range(entry.mess_shape[key].size()):entry.mess_shape[key][j]+=shift
		full.messes.append(entry)
	var capacity=empty_floor();capacity.floor_tasks.restore(full)
	check(capacity.floor_tasks.messes.size()==24 and Tasks.validate_snapshot(capacity.floor_tasks.snapshot(),[],{}, {},codec).ok,"all 24 legacy entries survive the new 12-entry spawn cap")

func test_natural_walks():
	var natural=Fixture.new();fixtures.append(natural);natural.floor_tasks=Tasks.new(natural)
	natural.model._spawn_customer()
	check(not natural.model.customers.is_empty(),"real model creates customers for natural route test")
	natural.model.operating_open=false
	var visited={};var steps=0
	for frame in range(600):
		for guest in natural.model.customers:
			var id=int(guest.id)
			if not visited.has(id):visited[id]={}
			visited[id][Vector2i(floori(guest.x),floori(guest.z))]=true
		natural.floor_tasks.observe_walks();natural.model.tick(.1);steps+=1
	check(not natural.floor_tasks.messes.is_empty(),"natural model movement actually produces litter, not a vacuous route pass")
	var valid=true
	for entry in natural.floor_tasks.messes.values():
		valid=valid and visited.has(entry.source_guest_id) and visited[entry.source_guest_id].has(entry.floor_cell) and natural.floor_tasks.litter_allowed(entry.floor_cell) and not entry.floor_spill
	check(valid,"real model movement creates only dry litter on its observed eligible route")
	evidence.natural_walk={"simulation_seconds":60,"guests":visited.size(),"messes":natural.floor_tasks.messes.size(),"route_constrained":valid}

func test_observation_parity(codec):
	var actual=empty_floor()
	var oracle=empty_floor()
	oracle.floor_tasks=LegacyObservation.new(oracle)
	# Several distinct source tiles in one callback, including a rug-only floor,
	# actual bin service sides, kitchen fringe and a held crossing.
	for world in [actual,oracle]:
		world.model.items.assign([
			{"id":201,"kind":"bin","x":2,"z":2,"rot":2},
			{"id":202,"kind":"bin","x":8,"z":5,"rot":1},
			{"id":203,"kind":"stove","x":7,"z":1,"rot":0},
			{"id":204,"kind":"rug","x":4,"z":6,"rot":0},
			{"id":205,"kind":"register","x":10,"z":4,"rot":0},
		])
		world.model.built_walls.append({"id":210,"axis":"z","x":5,"z":4,"height":"full","material":"sage_panels"})
		world.model.revision+=1
		world.floor_tasks.litter_exclusions.append(Rect2i(3,7,1,1))
		world.model.service_snapshot.layout_hold={"guests":[{"id":7}]}
	check(oracle.model.bin_service_cells(oracle.model.items[0]).has(Vector2i(2,3)) and oracle.model.bin_service_cells(oracle.model.items[1]).has(Vector2i(8,6)),"parity fixture has two distinct real bin workfaces")
	check(oracle.model.segment_blocked(Vector2(4.5,4.5),Vector2(5.5,4.5)),"parity fixture contains an actual blocking wall")
	var initial=[Vector2(2.5,6.5),Vector2(2.5,3.5),Vector2(8.5,6.5),Vector2(6.5,2.5),Vector2(3.5,7.5),Vector2(4.5,4.5),Vector2(6.5,7.5),Vector2(7.5,7.5)]
	var crossing=[Vector2(3.5,6.5),Vector2(2.5,4.5),Vector2(9.5,6.5),Vector2(6.5,3.5),Vector2(4.5,7.5),Vector2(5.5,4.5),Vector2(7.5,7.5),Vector2(8.5,7.5)]
	for world in [actual,oracle]:
		for i in initial.size():
			var pos:Vector2=initial[i]
			world.model.customers.append({"id":i+1,"x":pos.x,"z":pos.y,"phase":"leaving" if i==7 else "checkout_walk","withdrawn":i==7})
		world.floor_tasks.observe_walks()
	check(actual.floor_tasks.snapshot()==oracle.floor_tasks.snapshot(),"new guests initialize identical track snapshots without a crossing")
	_observe_parity_step(actual,oracle,crossing,"mixed crossing")
	for id in range(2,9):
		check(actual.floor_tasks.walks[id].inside_steps==0,"ineligible crossing leaves exact zero steps for guest "+str(id))
	check(actual.floor_tasks.walks[7].pos==initial[6],"held crossing leaves track coordinates untouched")
	check(actual.floor_tasks.walks[8].pos==crossing[7],"withdrawn crossing still updates track coordinates")
	crossing[0]=Vector2(4.5,6.5)
	_observe_parity_step(actual,oracle,crossing,"second eligible crossing")
	crossing[0]=Vector2(5.5,6.5)
	_observe_parity_step(actual,oracle,crossing,"real drop on rug")
	check(actual.floor_tasks.messes.size()==1 and actual.floor_tasks.walks[1].dropped,"parity scenario reaches original deterministic drop")
	for world in [actual,oracle]:
		var round_trip=codec.decode(JSON.parse_string(JSON.stringify(codec.encode(world.floor_tasks.snapshot()))))
		world.floor_tasks.restore(round_trip)
	check(actual.floor_tasks.snapshot()==oracle.floor_tasks.snapshot(),"all mess and walk records match after actual save codec roundtrip")
	_observe_parity_step(actual,oracle,crossing,"stationary observation after restore")
	for world in [actual,oracle]:
		world.model.items.remove_at(1)
		world.model.revision+=1
		world.model.service_snapshot.erase("layout_hold")
	crossing[2]=Vector2(8.5,6.5)
	_observe_parity_step(actual,oracle,crossing,"layout changes and visit resumed after restore")
	crossing[2]=Vector2(9.5,6.5)
	_observe_parity_step(actual,oracle,crossing,"removed bin no longer reserves its former side")
	check(actual.floor_tasks.walks[3].inside_steps==2,"changed layout is read at subsequent observations")
	# This is a real door aperture in the wall used by the prior rejected crossing.
	for world in [actual,oracle]:
		world.model.wall_attachments.append({"id":211,"kind":"door","wall_ids":["wall:210"],"offset":.5,"width":1.0})
		world.model.revision+=1
	check(not oracle.model.segment_blocked(Vector2(5.5,4.5),Vector2(4.5,4.5)),"opening the wall really permits the same segment")
	crossing[5]=Vector2(4.5,4.5)
	_observe_parity_step(actual,oracle,crossing,"through actual wall aperture")
	check(actual.floor_tasks.walks[6].inside_steps==1,"crossing the opened door records a step")
	for world in [actual,oracle]:
		world.model.customers.clear()
		world.floor_tasks.observe_walks()
	check(actual.floor_tasks.snapshot()==oracle.floor_tasks.snapshot() and actual.floor_tasks.walks.is_empty() and actual.floor_tasks.messes.size()==1,"retire all track records but keep exactly the same residual mess")
	var capped_actual=empty_floor()
	var capped_oracle=empty_floor()
	capped_oracle.floor_tasks=LegacyObservation.new(capped_oracle)
	for world in [capped_actual,capped_oracle]:
		for id in range(12):world.floor_tasks.messes[id+1]={"floor_cell":Vector2i(100+id*3,100)}
		walk(world)
	check(capped_actual.floor_tasks.snapshot()==capped_oracle.floor_tasks.snapshot(),"full snapshot parity when the normal spawn opportunity reaches the 12-mess cap")
	check(capped_actual.floor_tasks.walks[1].inside_steps==3 and not capped_actual.floor_tasks.walks[1].dropped,"cap blocks the drop, not eligible track counting")

func _observe_parity_step(actual,oracle,positions:Array,label:String):
	for world in [actual,oracle]:
		for i in positions.size():
			world.model.customers[i].x=positions[i].x
			world.model.customers[i].z=positions[i].y
		world.floor_tasks.observe_walks()
	check(actual.floor_tasks.snapshot()==oracle.floor_tasks.snapshot(),"full legacy observation parity: "+label)

func test_observed_bin_side_geometry():
	var bin={"id":201,"kind":"bin","x":4,"z":5,"rot":0}
	var rug={"id":202,"kind":"rug","x":4,"z":6,"rot":0}
	var solid={"id":203,"kind":"table","x":4,"z":6,"rot":0}
	for row in [
		{"label":"wall cuts off bin side","items":[bin],"wall":true,"door":false,"bin_side":false,"steps":1},
		{"label":"door restores bin side","items":[bin],"wall":true,"door":true,"bin_side":true,"steps":0},
		{"label":"a rug alone does not obstruct bin side","items":[bin,rug],"wall":false,"door":false,"bin_side":true,"steps":0},
		{"label":"first rug permits the walk but second solid obstructs bin side","items":[bin,rug,solid],"wall":false,"door":false,"bin_side":false,"steps":1},
		{"label":"first solid blocks the walk before later rug","items":[bin,solid,rug],"wall":false,"door":false,"bin_side":false,"steps":0},
	]:
		var actual=empty_floor()
		var oracle=empty_floor()
		oracle.floor_tasks=LegacyObservation.new(oracle)
		for world in [actual,oracle]:
			world.model.items.assign(row.items.duplicate(true))
			if row.wall:
				world.model.built_walls.append({"id":210,"axis":"x","x":4,"z":6,"height":"full","material":"sage_panels"})
			if row.door:
				world.model.wall_attachments.append({"id":211,"kind":"door","wall_ids":["wall:210"],"offset":.5,"width":1.0})
			world.model.revision+=1
			world.model.customers.append({"id":1,"x":4.5,"z":6.5,"phase":"arriving"})
			world.floor_tasks.observe_walks()
		check(oracle.model.bin_service_cells(oracle.model.items[0]).has(Vector2i(4,6))==row.bin_side,"model bin service side: "+row.label)
		_observe_parity_step(actual,oracle,[Vector2(5.5,6.5)],row.label)
		check(actual.floor_tasks.walks[1].inside_steps==row.steps,"crossing step: "+row.label)
