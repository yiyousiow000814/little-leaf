extends SceneTree
const Approach=preload("res://scripts/floor_cleaning_approach.gd")
const Pose=preload("res://scripts/cleaning_tool_pose.gd")
const Art=preload("res://scripts/illustrated_cafe.gd")
const Model=preload("res://scripts/cafe_model.gd")
const Relocation=preload("res://scripts/cafe_staff_relocation.gd")
const Walls=preload("res://scripts/cafe_walls.gd")
class Fixture extends Node:
	var model=Model.new()
	var staff_states=[]
	var service_guests={}
	var floor_tasks={"messes":{}}
	var editing=false
	var paused=false
	var speed=1.0
var checks=0
var failures=[]
var lengths=[]
func check(ok,label):
	checks+=1
	if not ok:failures.append(label);printerr("FAIL ",label)
func _initialize():run.call_deferred()
func run():
	var center=Vector2(5.5,5.5)
	var open_model=Model.new();open_model.items.clear();open_model.customers.clear()
	# Sample all bearings and near/far contacts; the body clearance includes
	# adjacent chairs and wall edges, not only the point at the worker's feet.
	for angle in range(360):
		var direction=Vector2.from_angle(deg_to_rad(angle))
		for distance in [.0,.1,.49,.5,.51,.8,1.15,1.205]:
			var target=center+direction*distance
			var offset=Approach.offset(center,target,open_model)
			var shown=center+offset
			check(shown.x>=5.05-.000001 and shown.x<=5.95+.000001 and shown.y>=5.05-.000001 and shown.y<=5.95+.000001,"body remains inside routed cell")
			check(offset.length()<=.5+.000001,"bounded work approach")
			check(absf(offset.cross(direction))<.000001,"approach aims at actual contact")
			check(shown.distance_to(target)>=minf(.5,distance)-.000001,"feet keep distance from mess")
			check(shown.distance_to(target)<=distance+.000001,"approach never retreats from contact")
			if distance<=.5:check(offset.length()<.000001,"near contact does not move the worker")
	var game=Fixture.new();var art=Art.new();art.game=game
	game.model.items.clear();game.model.customers.clear()
	for direction in [Vector2i.RIGHT,Vector2i.DOWN,Vector2i.LEFT,Vector2i.UP]:
		var neighbor=Vector2i(center.floor())+direction
		game.model.items.append({"id":100,"kind":"chair","x":neighbor.x,"z":neighbor.y,"rot":0})
		var shown=center+Approach.offset(center,center+Vector2(direction)*1.15,game.model)
		check(shown==center and Relocation.point_clear(game.model,shown,game.model.items),"same body radius stays clear of adjacent chair "+str(direction))
		var wall=Walls.make("z",6 if direction.x>0 else 5,5) if direction.x!=0 else Walls.make("x",5,6 if direction.y>0 else 5)
		game.model.built_walls.append(wall);game.model.items.clear();game.model.revision+=1
		var blocked=Approach.solve(center,center+Vector2(direction)*1.15,game.model)
		check(blocked.offset==Vector2.ZERO and blocked.obstruction.begins_with("wall"),"actual wall blocks full approach "+str(direction))
		game.model.built_walls.clear();game.model.revision+=1
		game.model.items.clear()
	# The endpoints can both be clear while the complete swept body hits a chair.
	game.model.items.append({"id":101,"kind":"chair","x":5,"z":5,"rot":0})
	check(Relocation.point_clear(game.model,Vector2(4.5,5.5),game.model.items) and Relocation.point_clear(game.model,Vector2(6.5,5.5),game.model.items),"swept test endpoints are both clear")
	check(Approach.blocked_by(game.model,Vector2(4.5,5.5),Vector2(6.5,5.5)).begins_with("furniture"),"mid-segment chair blocks the swept body")
	game.model.items.clear()
	game.model.built_walls.append(Walls.make("z",6,5));game.model.revision+=1
	check(Approach.blocked_by(game.model,Vector2(5.5,5.5),Vector2(6.5,5.5)).begins_with("wall"),"mid-segment wall blocks the swept body")
	game.model.built_walls.clear();game.model.revision+=1
	# No route, job, contact, claim or model coordinate may change when only
	# the actual renderer advances its feet and stance.
	var staff={"pos":center,"path":[Vector2i(5,5)],"index":1,"destination":Vector2i(5,5),"job_kind":"floor","job_mess_id":7,"job_step":1,"job_elapsed":.4,"art_action":"sweeping","art_target":center+Vector2(1,-.6),"art_station":center+Vector2.LEFT,"art_phase":.32,"art_payload":"none","art_tool":"broom"}
	game.staff_states=[staff]
	var saved=staff.duplicate(true)
	art.update_motion(0.0)
	var previous=center
	for step in range(30):
		art.update_motion(1.0/60.0)
		var current=art._render_position("staff_0",staff.pos)
		check(current.distance_to(previous)<=.025+.000001,"approach never teleports")
		previous=current
	check(staff==saved,"rendering preserves job, route, target and model coordinates")
	check(previous.distance_to(staff.art_target)<center.distance_to(staff.art_target)-.15,"live renderer actually approaches sweep contact")
	check(art._staff_visual_heading(staff,{"blend":1.0}).is_equal_approx(staff.art_target-staff.pos),"floor facing follows contact, not station or walk history")
	var paused=art.stance_offsets.duplicate(true);var motion=art.motion.sample("staff_0")
	game.paused=true;art.update_motion(2.0)
	check(art.stance_offsets==paused and art.motion.sample("staff_0")==motion and staff==saved,"pause freezes approach, feet and work state")
	game.paused=false;game.editing=true;art.update_motion(2.0)
	check(art.stance_offsets==paused,"edit mode freezes approach")
	game.editing=false;staff.art_action="mopping";staff.art_tool="mop"
	art.update_motion(.1)
	check(art.stance_offsets==paused,"mop uses the same stable floor contact approach")
	staff.art_action="carrying_trash";staff.art_payload="trash";staff.art_tool="dustpan"
	var retreat_start=art._render_position("staff_0",staff.pos)
	art.update_motion(1.0/60.0)
	check(art._render_position("staff_0",staff.pos).distance_to(retreat_start)<=.025+.000001,"finished sweep retreats without a snap")
	for step in range(30):art.update_motion(1.0/60.0)
	check(art.stance_offsets.staff_0==Vector2.ZERO,"travel returns to the routed center")
	for action in ["idle","blocked","walking"]:
		staff.art_action=action;art.update_motion(.1)
		check(art.stance_offsets.staff_0==Vector2.ZERO,"non-floor action keeps prior center "+action)
	# Use the production tool pose to measure maximum normal contact reach
	# in four facings. The short arms and brush/pan contact remain unchanged.
	for direction in [Vector2.RIGHT,Vector2.DOWN,Vector2.LEFT,Vector2.UP]:
		var target=center+direction*1.15
		var offset=Approach.offset(center,target,open_model)
		var back=direction.x+direction.y<0
		var mirror=-1.0 if direction.x-direction.y<0 else 1.0
		var near=Vector2(7,-24) if back else Vector2(-7,-24)
		var far=Vector2(-6,-26.5) if back else Vector2(6,-26.5)
		var old_ground=Art.MotionArt.project(target-center)*Vector2(mirror,1)
		var ground=Art.MotionArt.project(target-center-offset)*Vector2(mirror,1)
		for sweep in [true,false]:
			var old=Pose.floor_pose(near,far,old_ground,back,.25,sweep)
			var pose=Pose.floor_pose(near,far,ground,back,.25,sweep)
			check(pose.near_hand.distance_to(near)>10.4999 and pose.near_hand.distance_to(near)<10.5001,"near arm keeps authored length")
			check(pose.far_hand.distance_to(far)>10.4999 and pose.far_hand.distance_to(far)<10.5001,"far arm keeps authored length")
			check(pose.shaft_top.distance_to(pose.brush)<old.shaft_top.distance_to(old.brush),"floor tool shaft shortens "+str(direction))
			check((pose.brush-ground).is_equal_approx(old.brush-old_ground),"brush stroke remains at the same world contact")
			lengths.append({"direction":str(direction),"action":"sweep" if sweep else "mop","before":old.shaft_top.distance_to(old.brush),"after":pose.shaft_top.distance_to(pose.brush)})
	art.game=null;art.free();game.free()
	print("FLOOR_CLEANING_APPROACH_RESULT ",JSON.stringify({"checks":checks,"failures":failures,"shaft_lengths":lengths}))
	quit(0 if failures.is_empty() else 1)
