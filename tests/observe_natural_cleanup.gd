extends SceneTree
## Real-time 1x generated-profile observation. Never inject arrivals or litter,
## advance a synthetic delta, change balances, or click dirt. Close only after
## the observation objective, then watch the existing cafe drain normally.
const Main=preload("res://scripts/main.gd")
var game
var started=0
var phase="observing"
var close_at=0.0
var samples=[]
var seen={}
var live={}
var cleared={}
var initial={}
var opened_for_observation=false
var observation_seconds=600.0
var drain_seconds=300.0
func _initialize():run.call_deferred()
func wall_seconds()->float:return (Time.get_ticks_msec()-started)/1000.0
func targets()->Dictionary:
 var result={}
 for id in game.floor_tasks.messes:
  var record=game.floor_tasks.messes[id]
  if str(record.trash_owner)=="floor" or (record.floor_spill and not record.spill_cleaned):result["floor:%d:%d"%[id,record.token]]=record.floor_target
 for id in game.service_guests:
  var record=game.service_guests[id]
  if record.floor_dirty and not record.floor_cleaned and (str(record.trash_owner)=="floor" or (record.floor_spill and not record.spill_cleaned)):result["guest:%d:%d"%[id,record.token]]=record.floor_target
 return result
func sample():
 var current=targets();var seconds=wall_seconds();var oldest=0.0
 for key in current:
  if not seen.has(key):seen[key]={"wall_seconds":seconds,"game_seconds":game.animation_time,"at":str(current[key])}
  oldest=maxf(oldest,seconds-float(seen[key].wall_seconds))
 for key in live:
  if not current.has(key):cleared[key]={"wall_seconds":seconds,"game_seconds":game.animation_time}
 live=current
 var staff=[]
 for worker in game.staff_states:
  if worker.role=="cleaner":staff.append({"job":worker.job_kind,"step":worker.job_step,"blocked":worker.blocked_reason})
 samples.append({"phase":phase,"wall_seconds":seconds,"game_seconds":game.animation_time,"served":game.model.served,"customers":game.model.customers.size(),"tutorial":game.model.tutorial_state.duplicate(true),"independent_messes":game.floor_tasks.messes.size(),"independent_completed":game.floor_tasks.completed,"visible_targets":current.size(),"oldest_visible_seconds":oldest,"dishes":game.dishwashing.dishes.size(),"cleaners":staff})
func write_result(status:String,reason:String):
 var report={"status":status,"reason":reason,"source_head":OS.get_environment("EXPECTED_HEAD"),"generated_profile":true,"player_save_used":false,"arrival_injection":false,"mess_injection":false,"manual_cleanup":false,"engine_time_scale":Engine.time_scale,"simulation_rate":"normal-only","wall_seconds":wall_seconds(),"game_seconds":game.animation_time,"tutorial_handling":"Intro bypassed with --skip-intro; non-modal tutorial left intact; normal business control opens cafe once", "initial":initial,"opened_via_normal_business_toggle":opened_for_observation,"final_coins":game.model.coins,"served":game.model.served,"natural_targets_seen":seen,"targets_no_longer_visible":cleared,"independent_completed":game.floor_tasks.completed,"samples":samples}
 var output=OS.get_environment("NATURAL_CLEANUP_OUTPUT")
 if output!="":FileAccess.open(output+"/natural-cleanup.json",FileAccess.WRITE).store_string(JSON.stringify(report,"  "))
 print("NATURAL_CLEANUP_RESULT ",JSON.stringify(report))
 quit(1 if status=="failed" else 0)
func run():
 var isolated=OS.get_environment("XDG_DATA_HOME")
 if isolated=="" or not OS.get_user_data_dir().begins_with(isolated):push_error("Generated isolated profile required");quit(2);return
 root.size=Vector2i(1360,880);Engine.max_fps=30;started=Time.get_ticks_msec()
 game=Main.new();root.add_child(game);await process_frame
 if not game.fresh_start or game.save_recovery_blocked or game.paused:write_result("failed","Fresh 1x operating start unavailable");return
 initial={"coins":game.model.coins,"items":game.model.items.duplicate(true),"staff":game.model.staff_roster(),"open":game.model.operating_open,"tutorial":game.model.tutorial_state.duplicate(true)}
 # Public startup may intentionally wait closed for the player to open. Use
 # that ordinary action once, without injecting customers or dirt.
 if not game.model.operating_open:
  game._toggle_business();opened_for_observation=true
 initial["observed_open"]=game.model.operating_open
 if not game.model.operating_open:write_result("failed","Normal business toggle did not open the generated cafe");return
 while true:
  await create_timer(1.0).timeout
  sample()
  if Engine.time_scale!=1.0 or game.paused or game.save_recovery_blocked:write_result("failed","Observation left uninterrupted normal-speed play");return
  if phase=="observing":
   if not game.model.operating_open:write_result("failed","Cafe closed unexpectedly during natural observation");return
   if game.model.served>=3 and not cleared.is_empty():
    phase="draining";close_at=wall_seconds()
    if game.model.operating_open:game._toggle_business()
   elif wall_seconds()>=observation_seconds:
    write_result("inconclusive" if seen.is_empty() else "failed","No naturally visible dirt occurred in the observation window" if seen.is_empty() else "Three settled services and automatic visible cleanup were not established within the observation window");return
  else:
   if game.model.customers.is_empty() and game.floor_tasks.messes.is_empty() and game.dishwashing.dishes.is_empty():write_result("passed","Natural operating cafe automatically cleaned observed dirt and drained after closing");return
   if wall_seconds()-close_at>=drain_seconds:write_result("failed","Existing work did not drain within five minutes after closing");return
