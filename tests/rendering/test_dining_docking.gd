extends SceneTree
const Layout=preload("res://scripts/dining_placement.gd")
const Pose=preload("res://scripts/dining_pose.gd")
class TestMain extends "res://scripts/main.gd":
 var save_calls=0
 func _load_startup():save_writes_suppressed=true;fresh_start=false;model.reset_new();paused=true
 func _save():save_calls+=1;return true
var game
var checks=0
var failures=[]
func check(ok,label):
 checks+=1
 if not ok and not failures.has(label):failures.append(label);printerr(label)
func snapshot():return JSON.stringify({"items":game.model.items,"guests":game.model.customers,"service":game._service_save_snapshot(),"coins":game.model.coins,"payroll":game.model.payroll_elapsed,"earned":game.model.total_earned,"cleaned":game.model.total_cleaned})
func _initialize():run.call_deferred()
func run():
 game=TestMain.new();root.add_child(game);game.set_process(false);await process_frame;game.illustration.set_process(false)
 game.model.operating_open=true;game.model._spawn_customer();game.model.operating_open=false
 check(not game.model.customers.is_empty(),"Synthetic guest exists")
 var guest=game.model.customers[0];game.model.customers.resize(1)
 var table=game.model.get_item(int(guest.table_id));var chair=game.model.get_item(int(guest.chair_id));var a=game.illustration
 for forward in [Vector2.RIGHT,Vector2.DOWN,Vector2.UP,Vector2.LEFT]:
  chair.x=int(table.x-forward.x);chair.z=int(table.z-forward.y)
  guest.x=chair.x+.5;guest.z=chair.z+.5;guest.seated=true;guest.dismounting=false;guest.phase="eating";guest.elapsed=3.0;guest.duration=6.0;guest.heading=forward;guest.route=[];guest.route_index=0
  var key="guest_%s"%guest.id;var logical=Vector2(guest.x,guest.z);var chair_logical=Vector2(chair.x+.5,chair.z+.5)
  a.meal_chair_offsets.clear();a.stance_offsets.clear();a.table_dining_directions.clear();game.paused=true
  var before=snapshot();var paused_offset=a._meal_chair_offset(chair);var paused_actor=a._render_position(key,logical)
  check(paused_offset.is_equal_approx(forward*Layout.CHAIR_PULL),"Paused meal load leaves chair distant")
  check((paused_actor-chair_logical-paused_offset).is_equal_approx(forward*.12),"Paused load separates chair and guest")
  a.update_motion(1.0)
  check(a._meal_chair_offset(chair)==paused_offset and a._render_position(key,logical)==paused_actor,"Paused docking moves")
  check(snapshot()==before,"Paused rendering changes saved model/runtime data")
  # A live transition starts untucked and settles before the first pickup.
  a.meal_chair_offsets[int(chair.id)]=Vector2.ZERO;a.stance_offsets[key]=forward*.12;game.paused=false
  var prior_chair=Vector2.ZERO
  for frame in range(1,31):
   guest.elapsed=float(frame)/60.0;before=snapshot();a.update_motion(1.0/60.0)
   var offset=a._meal_chair_offset(chair);var actor=a._render_position(key,logical)
   check((actor-chair_logical-offset).is_equal_approx(forward*.12),"Chair/guest shared tuck separates")
   check(offset.distance_to(prior_chair)<=Layout.DOCK_SPEED/60.0+.00001,"Chair tuck jumps")
   check(snapshot()==before,"Docking changes model positions or runtime save snapshot")
   var f=guest.elapsed/guest.duration;var back=forward.x+forward.y<0;var mirror=-1.0 if forward.x-forward.y<0 else 1.0
   var d=Vector2(table.x+.5,table.z+.5)-actor
   var plate=(Vector2((d.x-d.y)*39,(d.x+d.y)*19.5)+a._table_surface_point(int(table.id)))*Vector2(mirror,1)-Vector2(2,-5.5)
   var p=Pose.pose(Vector2(7,-24) if back else Vector2(-7,-24),Vector2(-6,-26.5) if back else Vector2(6,-26.5),plate,f,back,Vector2.INF,mirror)
   if p.phase>=.20 and p.phase<Pose.PICKUP:check(p.plate_reach_error<.001 and p.tip.distance_to(p.plate_contact)<.001,"Live tuck misses first pickup")
   prior_chair=offset
  check(a._meal_chair_offset(chair).is_equal_approx(forward*Layout.CHAIR_PULL),"Chair never reaches meal tuck")
  var anchors=[a._table_surface_point(int(table.id)),a._table_surface_point(int(table.id),true),a._table_vase_point(int(table.id))]
  # Pause midway through an offset, then resume out without changing model data.
  a.meal_chair_offsets[int(chair.id)]=forward*.11;a.stance_offsets[key]=forward*.23;game.paused=true
  before=snapshot();a.update_motion(10.0)
  check(a._meal_chair_offset(chair).is_equal_approx(forward*.11),"Mid-tuck pause advances chair")
  check(snapshot()==before,"Paused transition mutates source state")
  game.paused=false;guest.phase="checkout_wait";prior_chair=a._meal_chair_offset(chair)
  for frame in range(30):
   before=snapshot();a.update_motion(1.0/60.0)
   var offset=a._meal_chair_offset(chair);var actor=a._render_position(key,logical)
   check((actor-chair_logical-offset).is_equal_approx(forward*.12),"Seated undocking separates chair and guest")
   check(offset.distance_to(prior_chair)<=Layout.DOCK_SPEED/60.0+.00001,"Chair undock jumps")
   check(snapshot()==before,"Undocking changes model/save state")
   prior_chair=offset
  check(a._meal_chair_offset(chair)==Vector2.ZERO,"Chair fails to return to its decorated position")
  for phase in ["checkout_walk","paying","leaving","dirty","cleaning"]:
   guest.phase=phase;guest.seated=false;before=snapshot();a.update_motion(1.0/60.0)
   check(anchors==[a._table_surface_point(int(table.id)),a._table_surface_point(int(table.id),true),a._table_vase_point(int(table.id))],"Tableware jumps during "+phase)
   check(snapshot()==before,"Post-meal render changes save state")
  game.editing=true;a.meal_chair_offsets[int(chair.id)]=forward*Layout.CHAIR_PULL
  check(a._meal_chair_offset(chair)==Vector2.ZERO,"Decorate inherits a moved logical chair")
  game.editing=false
 # Dining must not change ordinary walking/register stance easing.
 game.paused=false;guest.seated=false;guest.dismounting=false
 for phase in ["checkout_walk","paying"]:
  guest.phase=phase
  var key="guest_%s"%guest.id;var docking=Vector2.ZERO
  if phase=="paying":
   for item in game.model.items:
    if item.kind=="register":
     guest.checkout_register_id=int(item.id)
     var toward=Vector2(item.x+.5,item.z+.5)-Vector2(guest.x,guest.z)
     docking=toward.normalized()*preload("res://scripts/cafe_checkout_art.gd").payment_inset(toward,int(item.rot),false)
     break
  var prior=Vector2(.6,.2);a.stance_offsets[key]=prior;var before=snapshot()
  a.update_motion(1.0/60.0)
  check((a.stance_offsets[key] as Vector2).is_equal_approx(prior.move_toward(docking,1.5/60.0)),"Dining changes unseated/payment stance rate")
  check(snapshot()==before,"Unseated regression check mutates source state")
 check(game.save_calls==0,"Synthetic visual checks wrote a save")
 print("DINING_DOCKING_RESULT ",JSON.stringify({"checks":checks,"failures":failures,"save_calls":game.save_calls}))
 for player in game.audio_players.values():player.stop();player.stream=null
 game.settings_controls.sfx_player.stop();game.settings_controls.sfx_player.stream=null
 for tween in get_processed_tweens():tween.kill()
 game.queue_free();await process_frame;quit(0 if failures.is_empty() else 1)
