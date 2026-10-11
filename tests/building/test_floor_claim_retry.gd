extends SceneTree
const Fixture=preload("res://tests/role_fixture.gd")
const Tasks=preload("res://scripts/cafe_floor_tasks.gd")
const Codec=preload("res://scripts/cafe_runtime_codec.gd")
var game
var checks=0
var failures=[]
func _initialize():run.call_deferred()
func check(ok,label):
 checks+=1
 if not ok:failures.append(label);printerr("FAIL ",label)
func advance(seconds:float):
 for tick in roundi(seconds/.05):game.advance(.05)
func finish(id:int):
 for tick in 350:
  game.advance(.1)
  if not game.floor_tasks.messes.has(id):return
func reset_fixture():
 for staff in game.staff_states:staff.node.queue_free()
 game.staff_states.clear()
 game.model.reset_new();game.model.ensure_basic_bin();game.model.operating_open=false
 game.model.customers.clear();game.service_guests.clear();game.floor_tasks=Tasks.new(game)
 game.dishwashing.dishes.clear();game.dishwashing.completed=0;game._update_people()
 for staff in game.staff_states:
  game._clear_service_job(staff);staff.path.clear();staff.index=0;staff.destination=Vector2i(-100,-100)
  staff.on_duty=true;staff.duty_pending=false
 game.worker("cleaner").pos=Vector2(4.5,5.5)
func litter(cell:Vector2i,kind="banana")->int:
 var id=game.floor_tasks.spawn(cell,kind)
 check(id>0,"synthetic litter spawns on open floor "+str(cell))
 return id
func cover(cell:Vector2i)->int:
 check(game.model.place("plant",cell.x,cell.y),"ordinary furniture placement can cover existing litter")
 return int(game.model.item_at(cell.x,cell.y).id)
func canonical(value):return JSON.parse_string(JSON.stringify(Codec.new().encode(value)))
func roundtrip(label:String):
 var before=game._service_save_snapshot();var wallet=game.model.coins
 game.model.service_snapshot=before
 var saved=game.model.save("user://floor-claim-fixture.json")
 check(saved,label+" saves: "+game.model.last_error)
 if not saved:return
 var bytes=FileAccess.get_sha256("user://floor-claim-fixture.json")
 var loaded=game.model.load_save("user://floor-claim-fixture.json")
 check(loaded,label+" loads: "+game.model.last_error)
 if not loaded:return
 game._restore_service_runtime()
 check(FileAccess.get_sha256("user://floor-claim-fixture.json")==bytes,label+" load does not rewrite synthetic save")
 check(game.model.coins==wallet,label+" wallet unchanged")
 check(canonical(game.floor_tasks.snapshot())==canonical(before.floor_tasks),label+" every mess, shape, owner and completion count survives")
 check(canonical(game._service_save_snapshot().records)==canonical(before.records),label+" every diner cleanup record and token survives")
 for i in before.staff.size():
  var old=before.staff[i];var restored=game.staff_states[i]
  check(restored.job_kind==old.job_kind and restored.job_step==old.job_step and restored.job_elapsed==old.job_elapsed,label+" active staff stage and elapsed unchanged "+str(i))
func run():
 root.size=Vector2i(1360,880);game=Fixture.new();root.add_child(game);await process_frame
 game.set_process(false);game.illustration.set_process(false)
 check(game.save_writes_suppressed and OS.get_environment("XDG_DATA_HOME")!="","isolated generated profile only")
 # An unreachable first mess must remain pending without monopolizing a worker.
 reset_fixture()
 var first=litter(Vector2i(4,6));var original=game.floor_tasks.messes[first].duplicate(true)
 var furniture=cover(Vector2i(4,6));var cleaner=game.worker("cleaner")
 check(not game.floor_tasks.geometry.layout_clear(original.mess_shape),"covered saved footprint is genuinely obstructed")
 check(game.floor_tasks.geometry.destination(original,cleaner,Vector2i(4,5),[])==Vector2i(-1,-1),"obstructed footprint has no cleanup destination")
 advance(.1)
 check(cleaner.job_kind=="","unreachable litter alone does not reserve the cleaner")
 var second=litter(Vector2i(2,5),"crumbs")
 finish(second)
 check(game.floor_tasks.messes.has(first) and not game.floor_tasks.messes.has(second),"later reachable litter finishes while blocked litter remains")
 check(game.floor_tasks.completed==1,"only reachable job counted once")
 check(game.floor_tasks.messes[first]==original,"deferral leaves blocked litter and saved geometry untouched")
 roundtrip("blocked pending")
 check(game.model.remove(furniture,false),"obstruction removed through ordinary model operation")
 finish(first)
 check(game.floor_tasks.messes.is_empty() and game.floor_tasks.completed==2,"previously blocked litter retries after space becomes available")
 advance(3)
 check(game.floor_tasks.completed==2,"repeated ticks never duplicate completed litter")
 # A claim made before a layout change also yields before contact starts.
 reset_fixture();first=litter(Vector2i(4,6));cleaner=game.worker("cleaner")
 game.floor_tasks.assign(cleaner,game.staff_states.find(cleaner))
 check(cleaner.job_kind=="floor" and int(cleaner.job_mess_id)==first and cleaner.job_elapsed==0,"reachable initial claim acquired before contact")
 furniture=cover(Vector2i(4,6));second=litter(Vector2i(2,5),"crumbs")
 roundtrip("blocked pre-contact claim")
 cleaner=game.worker("cleaner");advance(.05)
 check(cleaner.job_kind=="floor" and int(cleaner.job_mess_id)==second,"restored blocked claim releases and selects reachable litter")
 finish(second)
 check(game.floor_tasks.messes.has(first) and not game.floor_tasks.messes.has(second),"reassigned cleaner actually completes reachable litter")
 # An active gesture retains its exact elapsed time and original owner.
 reset_fixture();first=litter(Vector2i(4,6));cleaner=game.worker("cleaner")
 game.floor_tasks.assign(cleaner,game.staff_states.find(cleaner));cleaner.job_elapsed=.35
 furniture=cover(Vector2i(4,6));second=litter(Vector2i(2,5),"crumbs")
 roundtrip("partial sweep")
 cleaner=game.worker("cleaner");advance(.1)
 check(cleaner.job_kind=="floor" and int(cleaner.job_mess_id)==first and cleaner.job_elapsed==.35,"partial sweeping is never discarded or reassigned")
 # Compatibility saves can own trash before their elapsed sweep has ended.
 # Obstruction must preserve that exact stage, clock and hand through reload.
 reset_fixture();first=litter(Vector2i(4,6));cleaner=game.worker("cleaner")
 var held_index=game.staff_states.find(cleaner)
 game.floor_tasks.assign(cleaner,held_index)
 game.floor_tasks.contact(cleaner,held_index,"sweeping",game.floor_tasks.target(cleaner),1.0);cleaner.job_elapsed=.35
 furniture=cover(Vector2i(4,6));roundtrip("held partial sweep")
 cleaner=game.worker("cleaner");advance(.1)
 check(cleaner.job_kind=="floor" and int(cleaner.job_mess_id)==first and cleaner.job_step==0 and cleaner.job_elapsed==.35,"held partial sweep keeps its saved stage and exact clock")
 check(game.floor_tasks.messes[first].trash_owner=="staff" and game.floor_tasks.messes[first].trash_staff_index==held_index,"held partial sweep retains exact trash ownership")
 check(cleaner.art_action not in ["sweeping","mopping"],"inaccessible held partial sweep never draws a through-obstacle cleaning gesture")
 # Held litter/disposal must keep the worker until ownership reaches the bin.
 reset_fixture();first=litter(Vector2i(4,6));cleaner=game.worker("cleaner")
 var index=game.staff_states.find(cleaner)
 game.floor_tasks.assign(cleaner,index)
 game.floor_tasks.contact(cleaner,index,"sweeping",game.floor_tasks.target(cleaner),1.0)
 game.floor_tasks.complete_step(cleaner,index)
 furniture=cover(Vector2i(4,6));second=litter(Vector2i(2,5),"crumbs")
 roundtrip("held litter")
 cleaner=game.worker("cleaner");advance(.05)
 check(int(cleaner.job_mess_id)==first and cleaner.job_step==2 and game.floor_tasks.messes[first].trash_owner=="staff","covered original footprint never releases carried litter or disposal")
 finish(second)
 check(game.floor_tasks.messes.is_empty() and game.floor_tasks.completed==2,"held litter and following reachable litter each dispose exactly once")
 # Multiple cleaners cannot claim the same reachable entry after deferral.
 reset_fixture();first=litter(Vector2i(4,6));furniture=cover(Vector2i(4,6));second=litter(Vector2i(2,5),"crumbs")
 game.model.cleaners=2;game.model.duty_targets.cleaner=2;game.model.duty_counts.cleaner=2;game._update_people()
 var assigned=[]
 for worker in game.staff_states:
  if worker.role!="cleaner":continue
  game.floor_tasks.assign(worker,game.staff_states.find(worker))
  if worker.job_kind=="floor":assigned.append(int(worker.job_mess_id))
 check(assigned==[second],"two cleaners claim reachable litter exactly once and leave blocked litter pending")
 roundtrip("multiple cleaners")
 # Old diner-owned floor work must not monopolize the same cleaner either.
 for preclaimed in [false,true]:
  reset_fixture()
  var record=game.setup_dirty(true)
  record.dishes_collected=true;record.plate_owner="clean";record.plate_staff_index=-1;record.plate_target_id=-1
  record.table_wiped=true;record.drink_owner="cleared";record.dish_sink_id=-1
  cleaner=game.worker("cleaner")
  var shape=game.floor_tasks.geometry.ensure(record).duplicate(true)
  var guest_id=int(record.guest.id);var token=int(record.token)
  if preclaimed:
   game._assign_service_job(cleaner,game.staff_states.find(cleaner))
   check(cleaner.job_kind=="cleanup" and cleaner.job_step==3,"legacy floor claim acquired before obstruction")
  furniture=cover(record.floor_cell);second=litter(Vector2i(2,5),"crumbs")
  roundtrip("legacy blocked "+str(preclaimed))
  record=game.service_guests[guest_id];cleaner=game.worker("cleaner")
  finish(second)
  check(not game.floor_tasks.messes.has(second),"legacy blocked floor permits other reachable litter "+str(preclaimed))
  check(record.mess_shape==shape and int(record.token)==token and record.trash_owner=="floor" and not record.floor_cleaned,"legacy deferral preserves original physical work "+str(preclaimed))
  check(game.model.remove(furniture,false),"legacy obstruction removed")
  for tick in 350:
   game.advance(.1)
   if record.floor_cleaned:break
  check(record.floor_cleaned and record.trash_owner=="disposed" and record.spill_cleaned,"legacy floor retries and finishes after obstruction removal "+str(preclaimed))
 var report={"checks":checks,"failures":failures,"test":"blocked floor claims, real routing and staff simulation, generated save roundtrips","player_save_used":false}
 print("FLOOR_CLAIM_RETRY_RESULT ",JSON.stringify(report));quit(0 if failures.is_empty() else 1)
