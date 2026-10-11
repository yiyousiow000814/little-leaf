extends SceneTree
const Motion=preload("res://scripts/cafe_furniture_motion.gd")
class TestMain extends "res://scripts/main.gd":
 func _load_startup():
  save_writes_suppressed=true;fresh_start=true;MinimalStart.apply(model);model.coins=100000
  for at in [Vector2i(6,5),Vector2i(9,5),Vector2i(3,6)]:assert(model.place("table_set",at.x,at.y,0),model.last_error)
var checks=0;var failures=[]
func check(ok,label):
 checks+=1
 if not ok:failures.append(label);printerr("FAIL ",label)
func _initialize():run.call_deferred()
func run():
 var game=TestMain.new();root.add_child(game);game.set_process(false);game.illustration.set_process(false)
 var paid_visits={};var abandoned_visits={};var duplicate_payments=[]
 game.model.meal_completed.connect(func(id,amount):
  if paid_visits.has(id):duplicate_payments.append(id)
  paid_visits[id]=amount)
 check(game.model.place("plant",11,7),"synthetic movable plant places")
 var id=int(game.model.items[-1].id);game.model._arrival_elapsed=-1000000
 var initial_coins=game.model.coins;var initial_wages=game.model.total_wages_paid
 var moved=false;var done=false;var repro_position=Vector2.ZERO
 var requested_visits={};var admitted_visits={}
 for tick in 18000:
  if requested_visits.size()<4:game.model._spawn_customer()
  for visitor in game.model.visual_customers():requested_visits[int(visitor.id)]=true
  for guest in game.model.customers:
   if bool(guest.admitted):admitted_visits[int(guest.id)]=true
  if admitted_visits.size()>=4:game.model.set_operating_open(false)
  game._tick_live_service(1.0/30.0);game._animate_staff(1.0/30.0);game.animation_time+=1.0/30.0
  for guest in game.model.customers:
   if guest.get("meal_abandoned",false):abandoned_visits[int(guest.id)]=true
  if not moved:
   for guest in game.model.customers:
    if guest.phase!="leaving" or not guest.paid or float(guest.x)>=0 or float(guest.x)<-.01:continue
    repro_position=Vector2(guest.x,guest.z)
    var before=guest.duplicate(true);var coins=game.model.coins;var layout=game.model.items.duplicate(true)
    var plan=Motion.plan(game.model,id,2,0,0,game.interaction._staff_positions())
    check(plan.ok,"real paid guest just outside doorway no longer blocks harmless plant move")
    check(guest==before and game.model.items==layout and game.model.coins==coins,"real preview is nonmutating")
    if not plan.ok:printerr(plan.error);break
    check(Motion.commit(game.model,plan),"live move commits atomically")
    check(guest==before and game.model.coins==coins,"paid guest tail/clock/body and wallet remain unchanged")
    game._rebuild_furniture();moved=true;break
  if tick%180==0:await process_frame
  if moved and game.model.customers.is_empty() and game.model.outside_queue.is_empty() and game.floor_tasks.messes.is_empty() and game.staff_states.all(func(s):return s.job_kind==""):done=true;break
 check(moved,"boundary epsilon case occurs in generated real traffic")
 check(done and game.model.served+abandoned_visits.size()==4 and game.model.total_cleaned==4,"all four served or abandoned visits depart and clean once after the edit")
 check(duplicate_payments.is_empty() and paid_visits.size()==game.model.served and abandoned_visits.keys().all(func(id):return not paid_visits.has(id)) and game.model.total_earned==paid_visits.size()*game.Model.MEAL_PAYMENT,"served diners pay exactly once and abandoned diners never pay")
 check(game.model.coins==initial_coins+game.model.total_earned-(game.model.total_wages_paid-initial_wages),"only genuine payments and wages change wallet")
 print("DEPARTING_ROUTE_SERVICE_RESULT ",JSON.stringify({"checks":checks,"failures":failures,"boundary_position":str(repro_position),"served":game.model.served,"cleaned":game.model.total_cleaned}))
 for player in game.audio_players.values():player.stop();player.stream=null
 game.settings_controls.sfx_player.stop();game.settings_controls.sfx_player.stream=null
 for tween in get_processed_tweens():tween.kill()
 game.queue_free();await process_frame;await process_frame;quit(0 if failures.is_empty() else 1)
