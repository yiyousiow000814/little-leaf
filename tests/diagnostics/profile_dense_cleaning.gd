extends SceneTree
const Model=preload("res://scripts/cafe_model.gd")
const Art=preload("res://scripts/illustrated_cafe.gd")
const Walls=preload("res://scripts/cafe_walls.gd")
class Fixture extends Node:
	var model=Model.new()
	var staff_states=[]
	var service_guests={}
	var floor_tasks={"messes":{}}
	var editing=false
	var paused=false
	var speed=1.0
func _initialize():run.call_deferred()
func run():
	var fixture=Fixture.new();root.add_child(fixture)
	var model=fixture.model;model.items.clear();model.customers.clear()
	model.owned_parcels.assign(Model.PARCEL_IDS);model._sync_floor_bounds()
	var id=1
	for z in range(18):
		for x in range(10,18):
			if (x+z)%2==0:model.items.append({"id":id,"kind":"chair","x":x,"z":z,"rot":0});id+=1
	for z in range(18):
		for x in [12,16]:
			var wall=Walls.make("x",x,z);wall.id=id;id+=1;model.built_walls.append(wall)
	model.revision+=1
	for index in 3:
		var position=Vector2(4.5+index,5.5)
		fixture.staff_states.append({"pos":position,"art_action":"sweeping","art_target":position+Vector2.DOWN*1.15,"art_phase":.32,"art_payload":"none","art_tool":"broom"})
	var art=Art.new();art.hide();art.game=fixture;fixture.add_child(art);art.set_process(false)
	for frame in 60:art.update_motion(1.0/60)
	var stages=[]
	for action in ["sweeping","mopping"]:
		for staff in fixture.staff_states:staff.art_action=action
		var timings=[]
		for repeat in 3:
			var start=Time.get_ticks_usec()
			for frame in 300:art.update_motion(1.0/60)
			timings.append(Time.get_ticks_usec()-start)
		stages.append({"action":action,"batch_us":timings,"frames_per_batch":300,"stance":art.stance_offsets.duplicate(true)})
	var invalidated_start=Time.get_ticks_usec()
	for frame in 30:model.revision+=1;art.update_motion(1.0/60)
	stages.append({"action":"revision_changes_every_frame","batch_us":[Time.get_ticks_usec()-invalidated_start],"frames_per_batch":30,"stance":art.stance_offsets.duplicate(true)})
	var report={"engine":Engine.get_version_info().string,"mode":"headless CPU update_motion only; no render/FPS/thermal claim","furniture":model.items.size(),"walls":model.built_walls.size(),"cleaners":3,"stages":stages}
	FileAccess.open(OS.get_environment("OUTPUT")+"/profile.json",FileAccess.WRITE).store_string(JSON.stringify(report,"  "))
	print("DENSE_CLEANING_RESULT ",JSON.stringify(report));quit()
