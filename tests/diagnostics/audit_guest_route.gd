extends SceneTree
const Motion=preload("res://scripts/cafe_furniture_motion.gd")
class TestMain extends "res://scripts/main.gd":
 func _load_startup():
  save_writes_suppressed=true;fresh_start=true;MinimalStart.apply(model);model.coins=100000
  for at in [Vector2i(6,5),Vector2i(9,5),Vector2i(3,6)]:assert(model.place("table_set",at.x,at.y,0),model.last_error)
var game
func _initialize():run.call_deferred()
func run():
 game=TestMain.new();root.add_child(game);game.set_process(false);game.illustration.set_process(false)
 assert(game.model.place("plant",11,7),game.model.last_error)
 var id=int(game.model.items[-1].id);game.model._arrival_elapsed=-1000000
 var found=false
 for tick in 6000:
  if game.model._next_customer_id<=4:game.model._spawn_customer()
  if game.model._next_customer_id==5 and game.model.customers.all(func(g):return bool(g.admitted)):game.model.set_operating_open(false)
  game._tick_live_service(1.0/30.0);game._animate_staff(1.0/30.0);game.animation_time+=1.0/30.0
  var plan=Motion.plan(game.model,id,2,0,0)
  if not plan.ok and plan.error=="Keep each guest's walking route connected":
   var copy=Motion.copy_model(game.model);var guests=copy.customers
   var no_guests:Array[Dictionary]=[];copy.customers=no_guests
   var static_ok=copy._move_static(id,2,0,0);copy.customers=guests
   var cases=[]
   for guest in guests:
    if guest.phase not in ["arriving","leaving","checkout_walk"]:continue
    var prior=guest.duplicate(true)
    var ok=copy.reroute_guest(guest)
    cases.append({"before":prior,"reroute_ok":ok,"after":guest})
   var result={"seconds":tick/30.0,"plant_id":id,"from":"(11,7)","to":"(2,0)","error":plan.error,"static_move_ok":static_ok,"guest_cases":cases,"items":game.model.items}
   FileAccess.open("res://qa/generated-diagnostic.json",FileAccess.WRITE).store_string(JSON.stringify(result,"  "))
   print("GUEST_ROUTE_REPRO ",JSON.stringify(result));found=true;break
  if tick%180==0:await process_frame
 print("GUEST_ROUTE_AUDIT found=",found)
 for player in game.audio_players.values():player.stop();player.stream=null
 game.settings_controls.sfx_player.stop();game.settings_controls.sfx_player.stream=null
 for tween in get_processed_tweens():tween.kill()
 game.queue_free();await process_frame;await process_frame;quit()
