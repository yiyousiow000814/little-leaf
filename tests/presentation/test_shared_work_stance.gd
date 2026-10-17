extends "res://tests/service/test_work_claim_policy.gd"
const Art=preload("res://scripts/rendering/illustrated_cafe.gd")
const Approach=preload("res://scripts/gameplay/floor_cleaning_approach.gd")
const Pose=preload("res://scripts/rendering/cleaning_tool_pose.gd")
func three(g):
 var guest=g.model.customers[0].duplicate(true);guest.id=2;guest.table_id=200;guest.chair_id=201;guest.x=3.5;guest.z=5.5
 g.model.customers.append(guest)
 g.model.items.append({"id":200,"kind":"table","x":3,"z":4,"rot":0})
 g.model.items.append({"id":201,"kind":"chair","x":3,"z":5,"rot":0})
 g.model.items.append({"id":202,"kind":"plant","x":2,"z":4,"rot":0});g.model.revision+=1
 g._sync_service_guests();g._add_staff("waiter",Vector2(CELL)+Vector2(.5,.5))
 var staff=g.staff_states[-1];var record=g.service_guests[2]
 record.order_done=true;record.meal_ready=true;record.meal_done=false;record.plate_owner="staff";record.plate_target_id=-1;record.plate_staff_index=g.staff_states.size()-1
 staff.job_kind="deliver_meal";staff.job_guest_id=2;staff.job_token=record.token;staff.job_step=1;staff.job_elapsed=.1
 return staff
func separation(a:Vector2,b:Vector2)->float:
 return minf((Art.MotionArt.project(a-b)/Vector2(26.2,25.4)).length(),a.distance_to(b)/.6)
func run():
 for cleaner_first in [true,false]:
  for scene in ["sweep","local_finish","three"]:
   var g=fixture(cleaner_first,2 if scene=="local_finish" else 0)
   var staff=[worker(g,"cleaner"),worker(g,"waiter")]
   if scene=="three":staff.append(three(g))
   var art=Art.new();art.game=g;var previous={}
   for frame in 10:
    tick(g)
    var before=g._current_service_snapshot();var full_staff=g.staff_states.duplicate(true)
    art.update_motion(.05)
    check(g._current_service_snapshot()==before and g.staff_states==full_staff,"renderer leaves full service state untouched")
    for actor in staff:
     var key="staff_%s"%g.staff_states.find(actor);var shown=art._render_position(key,actor.pos)
     if previous.has(key):check(shown.distance_to(previous[key])<=.075001,"display step uses original continuous stance speed")
     previous[key]=shown
     check(Vector2i(shown.floor())==CELL and Approach.blocked_by(g.model,actor.pos,shown)=="","shared display stays clear of furniture and walls")
   var points=[]
   for actor in staff:points.append(art._render_position("staff_%s"%g.staff_states.find(actor),actor.pos))
   for a in points.size():
    for b in range(a+1,points.size()):check(separation(points[a],points[b])>=.99999,"settled "+scene+" intact bodies separate in both roster orders")
   var cleaner=staff[0];var shown:Vector2=points[0]
   if scene!="local_finish":
    var heading:Vector2=cleaner.art_target-cleaner.pos;var back=heading.x+heading.y<0;var mirror=-1.0 if heading.x-heading.y<0 else 1.0
    var near=Vector2(7,-24) if back else Vector2(-7,-24);var far=Vector2(-6,-26.5) if back else Vector2(6,-26.5)
    var ground=Art.MotionArt.project(cleaner.art_target-shown)*Vector2(mirror,1)
    var old_ground=Art.MotionArt.project(cleaner.art_target-cleaner.pos)*Vector2(mirror,1)
    var pose=Pose.floor_pose(near,far,ground,back,cleaner.art_phase,true);var original=Pose.floor_pose(near,far,old_ground,back,cleaner.art_phase,true)
    check(is_equal_approx(pose.near_hand.distance_to(near),10.5) and is_equal_approx(pose.far_hand.distance_to(far),10.5),"shared floor work keeps both authored arm lengths")
    check((Art.MotionArt.project(shown)+pose.brush*Vector2(mirror,1)).is_equal_approx(Art.MotionArt.project(cleaner.pos)+original.brush*Vector2(mirror,1)),"brush stroke retains exact world contact")
    check(pose.shaft_top.distance_to(pose.brush)<=original.shaft_top.distance_to(original.brush)+.001,"separation never lengthens the floor handle beyond original center stance")
   evidence.append({"scene":scene,"cleaner_first":cleaner_first,"shown":points,"logical":staff.map(func(s):return s.pos),"elapsed":staff.map(func(s):return s.job_elapsed)})
   var offsets=art.stance_offsets.duplicate(true);g.paused=true;art.update_motion(1.0)
   check(art.stance_offsets==offsets,"pause freezes separated bodies")
   art.game=null;art.free();release(g)
 sink_wait_case()
 print("SHARED_WORK_STANCE_RESULT ",JSON.stringify({"checks":checks,"failures":failures,"evidence":evidence,"pixel_qualification":false,"player_save_used":false}))
 quit(0 if failures.is_empty() else 1)
func sink_wait_case():
 for cleaner_first in [true,false]:
  var g=fixture(cleaner_first);var waiter=worker(g,"waiter");var cleaner=worker(g,"cleaner")
  g._clear_service_job(cleaner);g.floor_tasks.messes.clear()
  var sink={}
  for item in g.model.items:
   if item.kind=="sink":sink=item
  sink.x=4;sink.z=5;sink.rot=2;g.model.revision+=1
  g.dishwashing.dishes[1]={"id":1,"sink_id":int(sink.id),"elapsed":19.96};g.dishwashing.next_id=2
  cleaner.job_kind="wash";cleaner.job_dish_id=1;cleaner.job_token=1;cleaner.job_step=0;cleaner.station_id=int(sink.id);cleaner.job_elapsed=19.96
  cleaner.destination=CELL;cleaner.pos=Vector2(CELL)+Vector2(.5,.5);cleaner.path=[];waiter.pos=cleaner.pos;waiter.path=[]
  tick(g)
  check(g.dishwashing.completed==1 and is_equal_approx(waiter.job_elapsed,.1),"completion snapshot still owns equipment for this frame")
  check(waiter.art_action!="blocked" and waiter.blocked_reason=="Waiting for the work space","one-frame equipment wait is not a Decorate fault")
  waiter.pos=Vector2(CELL)+Vector2(.5,.5);waiter.path=[];tick(g)
  check(waiter.job_elapsed>.1 and waiter.blocked_reason=="","next frame service timing remains unchanged")
  release(g)
 # A real geometric obstruction must retain its visible actionable warning.
 var g=fixture(true);var waiter=worker(g,"waiter");g.model.items.append({"id":999,"kind":"plant","x":CELL.x,"z":CELL.y,"rot":0});g.model.revision+=1
 tick(g)
 check(waiter.blocked_reason.contains("Decorate"),"actual blocked geometry keeps actionable fault text")
 release(g)
