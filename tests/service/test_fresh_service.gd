extends SceneTree
const Main=preload("res://scripts/main.gd")
class ClockMain extends Main:
 func _load_startup():
  save_writes_suppressed=true;fresh_start=true;paused=true;model.reset_new()
  for item in model.items:
   if item.kind in ["stove","beverage","sink"]:item.rot=2
var checks=0
var failures=[]
func _initialize():run.call_deferred()
func check(ok:bool,label:String):
 checks+=1
 if not ok:failures.append(label);printerr("FAIL ",label)
func release_game(game):
 var reference=weakref(game)
 for player in game.audio_players.values():player.stop();player.stream=null
 game.settings_controls.sfx_player.stop();game.settings_controls.sfx_player.stream=null
 for tween in get_processed_tweens():tween.kill()
 game.queue_free();await process_frame;await process_frame
 check(reference.get_ref()==null,"owned game released after service fixture")
func guest_identity(guest:Dictionary)->Array:
 # JSON numbers decode as floats; compare the schema's identity types exactly.
 return [int(guest.id),int(guest.table_id),int(guest.chair_id),float(guest.x),float(guest.z),int(guest.get("appearance_sequence",guest.id))]
func completion_clock():
 var game=ClockMain.new();root.add_child(game);game.set_process(false);game.illustration.set_process(false)
 game.model._spawn_customer()
 check(game.model.customers.size()==2 and game.model.cooks==1 and game.model.count_kind("stove")==1,"two generated diners share one stove")
 if game.model.customers.size()!=2:
  await release_game(game);return
 for step in range(1000):
  game.model._arrival_elapsed=0.0;game.model.tick(.1)
  if game.model.customers.all(func(guest):return bool(guest.seated)):break
 var first=game.model.customers[0];var second=game.model.customers[1]
 check(first.seated and second.seated,"generated diners reached their actual chairs")
 for guest in game.model.customers:
  guest.phase="cooking";guest.elapsed=0.0;guest.duration=game.Model.PHASE_SECONDS.cooking
 second.elapsed=5.86081833333331
 game._sync_service_guests()
 var record=game.service_guests[int(second.id)]
 var identity=guest_identity(second);var token=int(record.token)
 game._tick_live_service(.1)
 check(is_equal_approx(second.elapsed,5.86081833333331),"unfinished second diner remains behind the first logical stove slot")
 var waiter={}
 for staff in game.staff_states:
  if staff.role=="waiter":waiter=staff;break
 var table=game.model.get_item(int(second.table_id))
 var counter=game.model.items.filter(func(item):return item.kind=="counter")[0]
 record.meal_ready=true;record.meal_pass_id=int(counter.id)
 record.plate_owner="staff";record.plate_staff_index=game.staff_states.find(waiter);record.plate_target_id=-1
 waiter.job_kind="deliver_meal";waiter.job_guest_id=int(second.id);waiter.job_token=token
 waiter.job_step=1;waiter.job_elapsed=.8*.65;waiter.station_id=int(counter.id)
 var cell=game._service_destination(waiter,table,Vector2i(floori(waiter.pos.x),floori(waiter.pos.y)))
 check(cell!=Vector2i(-1,-1),"actual table delivery destination remains available")
 if cell==Vector2i(-1,-1):
  await release_game(game);return
 waiter.pos=Vector2(cell)+Vector2(.5,.5);waiter.destination=cell;waiter.path.clear();waiter.index=0
 game._service_contact(waiter,game.staff_states.find(waiter),"serving",table,.65)
 game._tick_live_service(.1)
 check(record.plate_owner=="table" and not record.meal_done and second.phase=="cooking","65 percent table contact transfers custody without completing cooking")
 game._animate_staff(.8*.35+.001)
 check(record.meal_done and waiter.job_kind=="" and second.phase=="cooking","only the final real serving step confirms pending completion")
 check(guest_identity(second)==identity and int(record.token)==token,"real contact retains diner identity and service token")
 var wallet=[game.model.coins,game.model.served,game.model.total_earned]
 game.model.service_snapshot=game._service_save_snapshot()
 var saved=game.model.save("user://service-clock-delivered.json")
 check(saved,"legacy delivered-cooking state saves under the existing codec: "+game.model.last_error)
 if not saved:
  await release_game(game);return
 var hash_before=FileAccess.get_sha256("user://service-clock-delivered.json")
 var header=JSON.parse_string(FileAccess.get_file_as_string("user://service-clock-delivered.json"))
 check(header.version==15 and header.runtime.service.version==5,"completion adds no save capability or service marker")
 var restored=game.model.load_save("user://service-clock-delivered.json")
 check(restored,"legacy delivered-cooking state loads unchanged: "+game.model.last_error)
 if not restored:
  await release_game(game);return
 game._restore_service_runtime()
 check(not game.model.complete_meal_delivery(second),"stale pre-restore guest dictionary cannot publish completion")
 first=game.model.customers[0];second=game.model.customers[1];record=game.service_guests[int(second.id)]
 check(second.phase=="cooking" and record.meal_done,"loading itself does not advance a confirmed meal")
 game._tick_live_service(0.0)
 game.paused=true;game._process(.1)
 check(second.phase=="cooking","zero-time and actual paused updates preserve pending completion")
 game.paused=false;game.editing=true;game._process(.1)
 check(second.phase=="cooking","Decorate does not consume pending completion")
 game.editing=false;game._tick_live_service(.1)
 check(second.phase=="drinking" and first.phase=="cooking","confirmed second meal advances independently of the occupied logical stove")
 if second.phase!="drinking":
  await release_game(game);return
 check(is_zero_approx(second.elapsed) and second.duration==game.Model.PHASE_SECONDS.drinking,"existing beverage wait/consumption duration starts normally")
 check(guest_identity(second)==identity and int(record.token)==token and record.plate_owner=="table" and int(record.plate_target_id)==int(second.table_id),"phase publication retains identity, token and table custody")
 second.elapsed=.5
 check(not game.model.complete_meal_delivery(second) and second.elapsed==.5,"repeated delivery confirmation cannot restart the next phase")
 check(wallet==[game.model.coins,game.model.served,game.model.total_earned] and not second.paid,"meal delivery never performs payment")
 check(FileAccess.get_sha256("user://service-clock-delivered.json")==hash_before,"restoration and reconciliation preserve the input save")
 for staff in game.staff_states:
  if staff.role=="waiter":waiter=staff;break
 game._assign_service_job(waiter,game.staff_states.find(waiter))
 check(waiter.job_kind=="brew" and int(waiter.job_guest_id)==int(second.id) and int(waiter.job_token)==token,"the same diner becomes eligible for its real beverage task")
 game.model.service_snapshot=game._service_save_snapshot()
 check(game.model.save("user://service-clock-reconciled.json"),"reconciled phase and jobs remain valid in the unchanged reader: "+game.model.last_error)
 var standalone=game.Model.new()
 standalone._spawn_customer()
 for guest in standalone.customers:
  guest.phase="cooking";guest.elapsed=0.0;guest.duration=standalone.PHASE_SECONDS.cooking
 standalone._arrival_elapsed=0.0;standalone.tick(.1)
 check(standalone.customers[0].phase=="cooking" and is_equal_approx(standalone.customers[0].elapsed,.1) and is_zero_approx(standalone.customers[1].elapsed),"standalone model keeps its timed recipe and capacity contract")
 check(game.Model.cooking_seconds()==45.0 and game.MEAL_DEPARTURE_SECONDS==120.0,"recipe and abandonment durations stay unchanged")
 await release_game(game)
func run():
 root.size=Vector2i(1360,880)
 check(OS.get_environment("XDG_DATA_HOME")!="" and OS.get_user_data_dir().begins_with(OS.get_environment("XDG_DATA_HOME")),"isolated generated profile")
 var game=Main.new();root.add_child(game);game.set_process(false);game.illustration.set_process(false)
 check(game.fresh_start and not game.save_recovery_blocked,"actual fresh startup path")
 var initial={"items":game.model.items.duplicate(true),"coins":game.model.coins,"cooks":game.model.cooks,"waiters":game.model.waiters,"cleaners":game.model.cleaners,"cashiers":game.model.cashiers}
 for kind in ["stove","beverage","sink"]:
  var item=game.model.items.filter(func(i):return i.kind==kind)[0]
  check(game.model._workface_open_in(item,game.model.items),"fresh "+kind+" workfront open")
 game.model._spawn_customer()
 check(game.model.customers.size()==1,"fresh table admits one real customer")
 var seconds=0.0
 for frame in range(4000):
  game.model._arrival_elapsed=0.0;game._tick_live_service(.1);game._animate_staff(.1);game.animation_time+=.1;seconds+=.1
  if game.model.served==1:break
 check(game.model.served==1 and game.model.total_earned==game.model.MEAL_PAYMENT,"untouched public fresh layout serves and settles first meal")
 check(not game.model.customers.is_empty() and not game.model.customers[0].meal_abandoned,"fresh diner finishes without meal abandonment")
 await release_game(game)
 await completion_clock()
 print("FRESH_SERVICE_RESULT ",JSON.stringify({"checks":checks,"failures":failures,"initial":initial,"first_payment_seconds":seconds,"player_save_used":false}))
 quit(0 if failures.is_empty() else 1)
