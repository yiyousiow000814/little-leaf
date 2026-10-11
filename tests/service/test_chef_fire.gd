extends SceneTree
const Pose=preload("res://scripts/cooking_tool_pose.gd")
const Character=preload("res://scripts/directional_character_art.gd")
const Furniture=preload("res://scripts/illustrated_furniture.gd")
const Model=preload("res://scripts/cafe_model.gd")
var checks=0
var failures=[]
func check(ok,label):
 checks+=1
 if not ok:failures.append(label);push_error(label)
func _initialize():run.call_deferred()
func tick(game,delta):
 game._tick_live_service(delta);game._update_people();game._animate_staff(delta)
func run():
 for rear in [false,true]:
  var shoulder=Vector2(7,-24) if rear else Vector2(-7,-24)
  var pan=Vector2(23.4,-43.7) if rear else Vector2(23.4,-20.3)
  var length=-1.0
  for i in range(370):
   var t=float(i)/370*Pose.FRY_SECONDS
   var body=Pose.body_weight(t)
   var p=Pose.pose(shoulder,pan-body,t)
   if length<0:length=p.tool_length
   check(absf(p.hand.distance_to(p.contact)-length)<.0001,"Spatula shaft changes length")
   check(absf(p.elbow.distance_to(shoulder)-Pose.UPPER_ARM)<.00001 and absf(p.hand.distance_to(p.elbow)-Pose.FOREARM)<.00001,"Arm segments change length")
   var tip=p.contact+body-pan
   check(absf(tip.x)<6.0 and tip.y>=-4.801 and tip.y<=.451,"Blade leaves the bounded pan/lift region")
   if p.motion.on_food_plane:check(absf(tip.y)<.451,"Scrape loses food-plane contact")
   check(p.motion.load>=0 and p.motion.load<=1,"Food load out of bounds")
   if not rear:
    check(p.hand.y-1.75>-25,"Front palm intersects head")
    check(p.thumb.y-1.15>-25,"Front thumb intersects head")
   var repeat=Pose.pose(shoulder,pan-body,t+Pose.FRY_SECONDS)
   check(p.hand.distance_to(repeat.hand)<.0001 and p.contact.distance_to(repeat.contact)<.0001,"Loop is discontinuous")
   var legs=Character.leg_pose({},false,0,rear)
   var near_ground:Vector2=legs.body+legs.near_foot
   var far_ground:Vector2=legs.body+legs.far_foot
   Pose.apply_body_weight(legs,t)
   check((legs.body+legs.near_foot).distance_to(near_ground)<.00001 and (legs.body+legs.far_foot).distance_to(far_ground)<.00001,"Body lean slides planted feet")
   check(absf(legs.near_hip.distance_to(legs.near_foot)-9.5)<.00001 and absf(legs.far_hip.distance_to(legs.far_foot)-9.5)<.00001,"Body lean stretches legs")
 var front_pan=Vector2(23.4,-20.3)
 var gather_time=.05
 var push_time=Pose.FRY_SECONDS*.37
 var gather=Pose.pose(Vector2(-7,-24),front_pan-Pose.body_weight(gather_time),gather_time)
 var pushed=Pose.pose(Vector2(-7,-24),front_pan-Pose.body_weight(push_time),push_time)
 check((pushed.contact+Pose.body_weight(push_time)).x-(gather.contact+Pose.body_weight(gather_time)).x>4.0,"Front spatula scrape must travel visibly across food")
 check(Pose.stroke(.05).body==Vector2.ZERO and Pose.stroke(.05).stage=="gather","Natural gather pause is missing")
 for rot in range(4):
  var parts=Furniture.part_sequence("stove",rot)
  check(parts.find("heat")>parts.find("stove_base") and parts.find("heat")<parts.find("stove_pan"),"Flame must be behind the pan")
  check(Furniture.stove_food_surface(rot).is_equal_approx(Furniture.KitchenGeometry.surface(Vector2.ZERO,41,rot)),"Pan/food/utensil target mismatch")
 for level in range(1,4):
  seed(123456)
  var game=load("res://main.tscn").instantiate();game.set_process(false);root.add_child(game)
  game.editing=false;game.paused=false;game.model.operating_open=true;game.model.get_item(1).level=level
  var staff
  for step in range(3000):
   tick(game,.1)
   for candidate in game.staff_states:
    if candidate.art_action=="cooking":staff=candidate;break
   if staff!=null:break
  check(staff!=null,"Real cooking job must start")
  if staff==null:game.queue_free();await process_frame;continue
  var art=game.illustration
  check(not art._stove_heat_state(1).is_empty(),"Active cooking has no fire")
  check(art._cooking_food_owned_by_pose(1),"Active ingredients are not owned by the blade pose")
  check(not art._cooking_food_owned_by_pose(999),"Another stove loses its normal food pass")
  check(art._stove_heat_state(999).is_empty(),"Another stove gets phantom fire")
  var elapsed=float(staff.job_elapsed)
  game.paused=true;game.compact_ui.viewport_too_small=false;game._process(.25)
  check(is_equal_approx(staff.job_elapsed,elapsed) and is_equal_approx(art._stove_heat_state(1).elapsed,elapsed),"Pause advances flame/work clock")
  game.paused=false;game.editing=true
  check(art._stove_heat_state(1).is_empty(),"Decorate shows a working flame")
  check(not art._cooking_food_owned_by_pose(1),"Decorate retains working ingredients")
  game.compact_ui.viewport_too_small=false;game._process(.25)
  check(is_equal_approx(staff.job_elapsed,elapsed),"Decorate advances work")
  game.editing=false
  for action in ["idle","blocked","walking","preparing_food","plating"]:
   staff.art_action=action;check(art._stove_heat_state(1).is_empty(),action+" keeps flame on")
   check(not art._cooking_food_owned_by_pose(1),action+" suppresses the normal food pass")
  staff.art_action="cooking"
  staff.job_step=2;check(art._stove_heat_state(1).is_empty(),"Completed cooking keeps flame on");staff.job_step=1
  var record=game.service_guests[int(staff.job_guest_id)]
  record.plate_owner="counter";check(art._stove_heat_state(1).is_empty(),"Moved food keeps flame on");record.plate_owner="kitchen"
  game.compact_ui.viewport_too_small=false;game._process(.25)
  check(absf(staff.job_elapsed-elapsed-.25)<.00001,"normal speed must advance cooking once")
  var expected=45.0/(1.0+.4*(level-1))
  check(absf(Model.cooking_seconds(Model.stove_speed_multiplier(game.model.get_item(1)))-expected)<.00001,"Recipe duration changed")
  staff.job_elapsed=expected-.1;game._animate_staff(.05)
  check(int(staff.job_step)==1 and not art._stove_heat_state(1).is_empty(),"Cooking/fire ends early")
  game._animate_staff(.05)
  check(int(staff.job_step)==2 and art._stove_heat_state(1).is_empty(),"Completion does not extinguish flame")
  game.queue_free();await process_frame
 print("CHEF_FIRE_TESTS checks=",checks," failures=",failures.size())
 quit(0 if failures.is_empty() else 1)
