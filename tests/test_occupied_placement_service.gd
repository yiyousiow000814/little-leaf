extends SceneTree
const Model=preload("res://scripts/cafe_model.gd")
const Pause=Model.PlacementPause
class TestMain extends "res://scripts/main.gd":
 var contacts=0
 func _load_startup():save_writes_suppressed=true;fresh_start=true;MinimalStart.apply(model)
 func _save():return true
 func _service_contact(staff:Dictionary,index:int,action:String,target:Dictionary,phase:float):
  if staff.job_kind=="cook":contacts+=1
  super._service_contact(staff,index,action,target,phase)
var checks=0
var failures=[]
func check(ok:bool,label:String):
 checks+=1
 if not ok:failures.append(label);push_error(label)
func _initialize():run.call_deferred()
func tick(game,delta):game._tick_live_service(delta);game._update_people();game._animate_staff(delta)
func capture(game,label:String):
 var output=OS.get_environment("OCCUPIED_CAPTURE_OUTPUT")
 if output=="" or DisplayServer.get_name()=="headless":return
 game._rebuild_furniture();game._update_people();game._update_ui();game.illustration.queue_redraw()
 for frame in 4:await process_frame
 await RenderingServer.frame_post_draw
 root.get_texture().get_image().save_png(output+"/"+label+".png")
func run():
 if not "saveguard" in OS.get_user_data_dir():quit(2);return
 root.size=Vector2i(1360,880)
 seed(123456)
 var game=TestMain.new();root.add_child(game);game.set_process(false);game.illustration.set_process(false)
 game.editing=false;game.paused=false;game.model.operating_open=true;game.model.coins=50000
 var chef
 for step in 3000:
  tick(game,.1)
  for worker in game.staff_states:
   if worker.art_action=="cooking":chef=worker;break
  if chef!=null:break
 check(chef!=null,"actual Main assigns and begins a real cook job")
 if chef==null:finish();return
 var m=game.model;var record=game.service_guests[int(chef.job_guest_id)];var guest=record.guest
 await capture(game,"before")
 m.enable_footprint_placement()
 for at in [Vector2i(8,5),Vector2i(10,5),Vector2i(9,6)]:check(m.place("plant",at.x,at.y),"purchase physical future obstruction")
 check(m.move(int(guest.table_id),9,4,0),"move occupied seat during actual cooking: "+m.last_error)
 check(Pause.blocked(guest) and is_same(record.guest,guest),"live service retains guest dictionary and pending identity")
 await capture(game,"blocked")
 record.meal_wait_seconds=game.MEAL_DEPARTURE_SECONDS
 var token=record.token;var payload=record.plate_owner;var clock=float(chef.job_elapsed);var phase=guest.phase
 var contacts=game.contacts
 game._advance_meal_wait(.5);game._resolve_meal_deadlines();game._animate_staff(.5)
 check(record.meal_wait_seconds==game.MEAL_DEPARTURE_SECONDS and not guest.meal_abandoned and guest.phase==phase,"pending guest at departure threshold is neither timed nor abandoned")
 check(chef.job_elapsed==clock and chef.job_step==1 and record.token==token and record.plate_owner==payload and game.contacts==contacts,"pending real cook preserves work clock/token/payload without contact")
 # Canonical full Main runtime, including the real in-flight cook job.
 m.service_snapshot=game._service_save_snapshot()
 check(m.save_placement("user://occupied-main-cook.json"),"full pending Main cook saves: "+m.last_error)
 var loaded=Model.new()
 check(loaded.load_placement("user://occupied-main-cook.json"),"full pending Main cook restores: "+loaded.last_error)
 check(loaded.coins==m.coins and loaded.customers.size()==m.customers.size() and Pause.blocked(loaded.customers[0]),"full reload retains wallet and visit")
 # Plating contact threshold and an already carried plate must both freeze.
 chef.job_step=2;chef.job_elapsed=.97;contacts=game.contacts
 game._animate_staff(.02)
 check(chef.job_elapsed==.97 and record.plate_owner=="kitchen" and game.contacts==contacts,"pending plating cannot cross real ownership contact threshold")
 record.plate_owner="staff";record.plate_staff_index=game.staff_states.find(chef);record.plate_target_id=-1
 chef.job_elapsed=1.49;contacts=game.contacts
 game._animate_staff(.02)
 check(chef.job_step==2 and chef.job_elapsed==1.49 and record.plate_owner=="staff" and record.plate_staff_index==game.staff_states.find(chef) and game.contacts==contacts,"pending carried payload cannot complete or change owner")
 # Unbound walking-origin floor work is independent of the paused diner.
 var cleaner
 for worker in game.staff_states:
  if worker.role=="cleaner":cleaner=worker;break
 var mess=game.floor_tasks.spawn(Vector2i(5,6),"banana",-1,3)
 check(mess>0 and cleaner!=null,"independent actual floor task exists")
 var progressed=false
 if cleaner!=null:
  game._clear_service_job(cleaner)
  for step in 200:
   game._animate_staff(.05)
   if cleaner.job_kind=="floor" and cleaner.job_elapsed>0.0:progressed=true;break
 check(progressed,"unbound floor job travels and advances while diner stays pending")
 check(chef.job_elapsed==1.49 and guest.phase==phase and record.token==token,"independent work leaves bound paused cook unchanged")
 # A separate admitted diner and detached dish queue are positive controls.
 check(m.place("table_set",9,7,0),"independent dining pair remains physically legal")
 var count=m.customers.size()
 if m.outside_queue.is_empty():m.OutsideQueue.add(m)
 if not m.outside_queue.is_empty():m._admit_queued_visitor(m.outside_queue[0])
 check(m.customers.size()>count,"independent diner receives its own actual reservation")
 if m.customers.size()<=count:game.queue_free();await process_frame;finish();return
 var other=m.customers[-1];var chair=m.get_item(int(other.chair_id))
 other.phase="ordering";other.seated=true;other.admitted=true;other.x=float(chair.x)+.5;other.z=float(chair.z)+.5;other.route=[];other.route_index=0
 other.erase("street_route_format");other.erase("street_origin_z")
 game._sync_service_guests()
 var other_record=game.service_guests[int(other.id)];var waiting=float(other_record.meal_wait_seconds)
 game._advance_meal_wait(.2)
 check(float(other_record.meal_wait_seconds)>waiting and record.meal_wait_seconds==game.MEAL_DEPARTURE_SECONDS,"ordinary admitted diner clock advances independently of pending diner")
 if cleaner!=null:
  game._clear_service_job(cleaner)
  var sink
  for item in m.items:
   if item.kind=="sink":sink=item;break
  game.dishwashing.restore({"next_id":2,"completed":0,"dishes":[{"id":1,"sink_id":int(sink.id),"elapsed":.1}]})
  check(game.dishwashing.assign(cleaner,game.staff_states.find(cleaner)),"detached synthetic dish queue assigns ordinary unbound wash")
  var destination=game._service_destination(cleaner,sink,Vector2i(floori(cleaner.pos.x),floori(cleaner.pos.y)))
  cleaner.pos=m.cell_center(destination);cleaner.path=[];cleaner.index=0;cleaner.destination=destination
  game._animate_staff(.05)
  check(cleaner.job_kind=="wash" and cleaner.job_elapsed>.1 and chef.job_elapsed==1.49,"unbound washer clock advances while bound carried plate stays frozen")
 # Repair publishes once, then real cardinal movement restores the owned seat.
 check(m.remove(int(m.item_at(8,5).id)),"repair current seat approach")
 var actual=Vector2(guest.x,guest.z);m.tick(.1)
 check(not Pause.blocked(guest) and Vector2(guest.x,guest.z)==actual,"legal retry is atomic and does not step on publication")
 for step in 200:
  if not Model.FurnitureMotion.active(guest):break
  m.tick(.1)
 check(guest.seated and not Model.FurnitureMotion.active(guest) and guest.phase==phase,"same real guest reaches relocated seat before service resumes")
 await capture(game,"repaired")
 record.meal_wait_seconds=0.0
 # Return existing chef to its actual stove contact; navigation remains ordinary.
 var target=game._service_target(chef);var dest=game._service_destination(chef,target,Vector2i(floori(chef.pos.x),floori(chef.pos.y)))
 chef.pos=m.cell_center(dest);chef.destination=dest;chef.path=[];chef.index=0
 contacts=game.contacts;game._animate_staff(.02)
 check(chef.job_step==3 and chef.job_elapsed==0.0 and game.contacts==contacts+1 and record.plate_owner=="staff","unblocked plating completes once with preserved carried plate")
 game._animate_staff(0.0)
 check(chef.job_step==3 and record.token==token and guest.id==record.guest.id,"subsequent synchronization cannot repeat completed plating or replace visit")
 if OS.get_environment("OCCUPIED_CAPTURE_OUTPUT")!="" and DisplayServer.get_name()!="headless":
  check(m.load_placement("user://occupied-main-cook.json"),"native controller reloads accepted pending runtime")
  game._resume_loaded_cafe()
  check(Pause.blocked(game.service_guests[int(guest.id)].guest),"native restore binds pending service to original visit")
  await capture(game,"reloaded")
 game.queue_free();await process_frame
 finish()
func finish():
 print("OCCUPIED_PLACEMENT_SERVICE_RESULT ",JSON.stringify({"checks":checks,"failures":failures}))
 quit(0 if failures.is_empty() else 1)
