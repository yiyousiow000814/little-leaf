extends SceneTree
const Pose=preload("res://scripts/cooking_tool_pose.gd")
const Art=preload("res://scripts/illustrated_cafe.gd")
const Furniture=preload("res://scripts/illustrated_furniture.gd")
class GeneratedMain extends "res://scripts/main.gd":
 func _load_startup():
  save_writes_suppressed=true;fresh_start=true;MinimalStart.apply(model)
var checks=0
var failures=[]
func check(ok,label):
 checks+=1
 if not ok:failures.append(label);printerr("FAIL ",label)
func _initialize():run.call_deferred()
func run():
 root.size=Vector2i(1360,880)
 for i in 1000:
  var seconds=i*.02
  var p=Pose.stroke(seconds)
  var v=Pose.vessel(seconds)
  check(p.body.length()<.20,"small shoulder displacement")
  check(absf(v.pot.x)<=.221 and absf(v.pot.y)<=.351,"small pot bob")
  check(absf(v.lid.x)<=.161 and absf(v.lid.y)<=.851,"small lid hop")
  check(v.pot.x*v.lid.x<=.000001,"opposed horizontal lid motion")
  for remaining in [-1.0,0.0]:
   var rest=Pose.vessel(seconds,remaining,0.0)
   check(rest.pot==Vector2.ZERO and rest.lid==Vector2.ZERO,"reduced-motion rests")
  var finish=Pose.vessel(seconds,0.0)
  check(finish.pot==Vector2.ZERO and finish.lid==Vector2.ZERO,"completion settles")
 # Live workcell stays fixed. The tiny inset stays inside its cardinal tile.
 for rotation in range(4):
  var toward=-Vector2(0,1).rotated(rotation*PI/2.0)
  var mirror=-1.0 if toward.x-toward.y<0 else 1.0
  var back=toward.x+toward.y<0
  var near=Vector2(7,-24) if back else Vector2(-7,-24)
  var far=Vector2(-6,-26.5) if back else Vector2(6,-26.5)
  var ground=Vector2((toward.x-toward.y)*39,(toward.x+toward.y)*19.5)*(1.0-Pose.WORK_INSET)
  check(Pose.WORK_INSET<.5,"Render inset remains in its logical work tile")
  for sample in 200:
   var seconds=sample*.04
   var target=(ground+Furniture.stove_handle_points(rotation)[1]+Pose.vessel(seconds).pot)*Vector2(mirror,1)-Pose.body_weight(seconds)
   var grip=Pose.grip_pose(near,far,target,seconds)
   check(grip.grip_error<.5,"Hand silhouette contacts actual moving grip")
   check(absf(grip.shoulder.distance_to(grip.elbow)-Pose.UPPER_ARM)<.0001,"Grip upper arm length fixed")
   check(absf(grip.elbow.distance_to(grip.hand)-Pose.FOREARM)<.0001,"Grip forearm length fixed")
   check(grip.use_near==back,"Correct near/far arm chosen in every rotation")
 var game=GeneratedMain.new();root.add_child(game);game.set_process(false);game.illustration.set_process(false)
 game.cafe_intro.active=false;game.paused=false;game.editing=false;game.model.operating_open=true;game._sync_staff_duty();game.model._spawn_customer()
 var chef={}
 for tick in 1200:
  game.model._arrival_elapsed=0.0;game._tick_live_service(.1);game._update_people();game._animate_staff(.1)
  for staff in game.staff_states:
   if staff.job_kind=="cook" and int(staff.job_step)==1 and staff.job_elapsed>.5:chef=staff;break
  if not chef.is_empty():break
 check(not chef.is_empty(),"real generated cooking job reached")
 if not chef.is_empty():
  var art=game.illustration
  var id=int(chef.station_id)
  check(not art._stove_heat_state(id).is_empty(),"owned active cooking")
  var logical:Vector2=chef.pos
  var key="staff_%s"%game.staff_states.find(chef)
  for settle in 10:art.update_motion(.1)
  var rendered=art._render_position(key,logical)
  check(chef.pos==logical,"Presentation inset never moves route position")
  check(Vector2i(rendered.floor())==Vector2i(logical.floor()),"Presentation remains on workcell side of furniture/walls")
  check(not game.model.segment_blocked(logical,rendered),"Presentation does not cross blocked wall segment")
  check(absf(rendered.distance_to(logical)-Pose.WORK_INSET)<.001,"Live cooking inset settles to full-tile clearance")
  var elapsed=float(chef.job_elapsed)
  game.paused=true
  for i in 10:art._update_cooking_motion(.05)
  check(art.cooking_motion_strength==0.0,"paused motion settles")
  check(chef.job_elapsed==elapsed,"visual pause never changes timer")
  game.paused=false;art._update_cooking_motion(.5)
  game.set_meta("hud_reduce_motion",true)
  check(art._stove_vessel_motion(id).pot==Vector2.ZERO,"runtime accessibility rests pot")
  check(art._stove_vessel_motion(id).lid==Vector2.ZERO,"runtime accessibility rests lid")
  game.set_meta("hud_reduce_motion",false)
  var step=chef.job_step;chef.job_step=2
  check(art._stove_heat_state(id).is_empty(),"stale art action cannot animate plating")
  chef.job_step=step
  var record=game.service_guests[chef.job_guest_id];var owner=record.plate_owner;record.plate_owner="station"
  check(art._stove_heat_state(id).is_empty(),"ready plate ownership stops vessel")
  record.plate_owner=owner
 game.free()
 print("GENTLE_COOKING_RESULT ",JSON.stringify({"checks":checks,"failures":failures,"player_save_used":false}))
 quit(0 if failures.is_empty() else 1)
