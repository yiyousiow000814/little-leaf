extends SceneTree
const Main=preload("res://scripts/main.gd")
const Model=preload("res://scripts/cafe_model.gd")
const Codec=preload("res://scripts/cafe_runtime_codec.gd")
var checks=0
var failures=[]
var game
var result={}
func _initialize():run.call_deferred()
func check(ok,label):
 checks+=1
 if not ok:failures.append(label);printerr("FAIL ",label)
func roster():
 return game.staff_states.map(func(s):return {"role":s.role,"pos":[s.pos.x,s.pos.y],"home":[s.idle_home_cell.x,s.idle_home_cell.y],"action":s.art_action})
func saved_fields_match(expected,actual):
 if expected.size()!=actual.size():return false
 for i in expected.size():
  for key in expected[i]:
   if expected[i][key]!=actual[i].get(key):return false
 return true
func end():
 result.merge({"checks":checks,"failures":failures,"normal_writes_suppressed":game.save_writes_suppressed},true)
 print("STAFF_START_RESULT ",JSON.stringify(result))
 var path=OS.get_environment("LL_START_RESULT")
 if path!="":FileAccess.open(path,FileAccess.WRITE).store_string(JSON.stringify(result,"  "))
 for tween in get_processed_tweens():tween.kill()
 for player in game.audio_players.values():player.stop();player.stream=null
 game.queue_free();await process_frame;await process_frame
 quit(0 if failures.is_empty() else 1)
func run():
 var data=OS.get_environment("XDG_DATA_HOME")
 check(data!="" and OS.get_user_data_dir().begins_with(data),"isolated test data directory")
 check("--visual-qa" in OS.get_cmdline_user_args(),"automatic writes suppressed")
 game=Main.new();game.process_mode=Node.PROCESS_MODE_DISABLED;root.add_child(game)
 result["initial_roster"]=roster()
 var mode=OS.get_environment("LL_START_CASE")
 result["case"]=mode
 if mode=="bad-load":
  check(game.save_recovery_blocked and game.paused,"invalid source remains recovery-blocked and paused")
  check(not game.fresh_start,"invalid source never becomes a fresh game")
  check(game.staff_states[0].pos==Vector2(2.5,.5),"recovery fallback does not use new-game placement")
  check(FileAccess.get_file_as_string(game.SAVE_FILE)=="not a valid cafe", "corrupt source unchanged")
  end();return
 if mode=="standalone-load":
  check(not game.fresh_start and not game.save_recovery_blocked,"standalone model save still loads")
  check(game.model.service_snapshot.is_empty(),"standalone fixture has no runtime positions")
  check(game.staff_states[0].pos==Vector2(2.5,.5),"non-fresh empty snapshot keeps historical fallback")
  end();return
 if mode=="saved-load":
  check(not game.fresh_start and not game.save_recovery_blocked,"real startup loaded generated saved profile")
  var expected=Model.new()
  check(expected.load_save(game.SAVE_FILE),"generated source passes model validation")
  check(saved_fields_match(expected.service_snapshot.staff,game._service_save_snapshot().staff),"actual startup preserves every saved staff field")
  check(game.staff_states.any(func(s):return s.job_kind!=""),"loaded active job retained")
  end();return
 check(game.fresh_start and not game.save_recovery_blocked,"real new-game startup")
 check(game.staff_states.map(func(s):return s.role)==["chef","waiter","cleaner","cashier"],"same four roles in same stable order")
 var occupied=[]
 for worker in game.staff_states:
  var cell=Vector2i(worker.pos.floor())
  check(cell==worker.idle_home_cell,worker.role+" starts at its existing work/standby post")
  check(game._staff_walkable(cell) and not game._static_service_path(Model.ENTRY_LANDING,cell).is_empty(),worker.role+" starts reachable and on empty floor")
  check(not game._is_door_landing(cell),worker.role+" clears door landing")
  check(not occupied.has(cell),worker.role+" has a distinct standing tile")
  occupied.append(cell)
 check(game.staff_states[0].pos==Vector2(8.5,2.5),"chef begins at stove front")
 check(game.staff_states[3].pos==game.model.cell_center(game.model.checkout_rear(game.model.checkout_register())),"cashier remains behind register")
 check(not game.staff_states.slice(0,3).all(func(s):return s.pos.y==.5),"initial workers no longer line up along back wall")
 check(game.model.coins==Model.INITIAL_COINS and game.model.served==0 and game.model.customers.is_empty(),"placement does not advance gameplay, charge or spawn guests")
 check(game.model.save("user://staff-start-standalone.json"),"standalone model fixture saves")
 var initial=game._service_save_snapshot()
 game._animate_staff(.001)
 check(initial.staff.map(func(s):return s.pos)==game.staff_states.map(func(s):return s.pos),"first simulation step leaves idle workers at their posts")
 # Exercise real service, retain an in-progress job, then round-trip it.
 var reached=false
 for tick in 4500:
  game._tick_live_service(1.0/30.0);game._animate_staff(1.0/30.0);game.animation_time+=1.0/30.0
  if game.staff_states.any(func(s):return s.job_kind!="" and s.job_elapsed>.25):reached=true;break
  if tick%120==0:await process_frame
 check(reached,"new starting positions enter real customer service")
 game.model.service_snapshot=game._service_save_snapshot()
 var before=game.model.service_snapshot.duplicate(true)
 var save_path="user://staff-start-roundtrip.json"
 check(game.model.save(save_path),"generated active runtime saves: "+game.model.last_error)
 var loaded=Model.new()
 check(loaded.load_save(save_path),"generated active runtime loads: "+loaded.last_error)
 if not loaded.service_snapshot.is_empty():
  game.model=loaded;game._restore_service_runtime()
  check(saved_fields_match(before.staff,game._service_save_snapshot().staff),"all saved positions, routes and jobs restored even while fresh_start remains true")
  check(game.service_serial==int(before.serial),"service ownership serial preserved")
  check(game.animation_time==float(before.animation_time),"service animation clock preserved")
  result["roundtrip_roster"]=roster()
 # Normal closure completes this visit once; initial positioning is not reapplied.
 game.model.set_operating_open(false)
 var finished=false
 for tick in 9000:
  game._tick_live_service(1.0/30.0);game._animate_staff(1.0/30.0);game.animation_time+=1.0/30.0
  if game.model.customers.is_empty() and game.floor_tasks.messes.is_empty() and game.staff_states.all(func(s):return s.job_kind==""):finished=true;break
  if tick%120==0:await process_frame
 check(finished and game.model.served==1 and game.model.total_cleaned==1,"restored visit finishes and cleans once")
 end()
