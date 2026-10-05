extends SceneTree
const Fixture=preload("res://tests/role_fixture.gd")
const BeforeFixture=preload("res://tests/fixtures/before_role_fixture.gd")
const Codec=preload("res://scripts/cafe_runtime_codec.gd")
var game
var checks=0
var failures=[]
var results=[]
func _initialize():run.call_deferred()
func check(ok,label):
 checks+=1
 if not ok:failures.append(label);printerr("FAIL ",label)
func index(staff):return game.staff_states.find(staff)
func table_done(record):return record.dishes_collected and record.plate_owner in ["clean","dish_queue"] and record.drink_owner=="cleared" and record.table_wiped
func save_reload(label):
 var before=game._service_save_snapshot();game.model.service_snapshot=before
 var money=[game.model.coins,game.model.payroll_elapsed,game.model.payroll_accrued,game.model.wages_due,game.model.total_wages_paid]
 var ok=game.model.save("user://role-test.json")
 check(ok,label+" real model save: "+game.model.last_error)
 if not ok:return false
 var body=FileAccess.get_file_as_string("user://role-test.json")
 var raw=JSON.parse_string(body)
 var valid=Codec.new().validate(raw.runtime,game.model.items,game.model.cooks,game.model.PHASES,game.model.SAVE_VERSION,game.model.staff_roster(),game.model.duty_counts)
 check(valid.ok,label+" codec accepts: "+str(valid.get("error","")))
 ok=game.model.load_save("user://role-test.json")
 check(ok,label+" real model reload: "+game.model.last_error)
 if not ok:return false
 game._restore_service_runtime()
 var after=game._service_save_snapshot()
 check(before.staff.map(func(s):return s.role)==after.staff.map(func(s):return s.role),label+" staff roles/indices unchanged")
 check(money==[game.model.coins,game.model.payroll_elapsed,game.model.payroll_accrued,game.model.wages_due,game.model.total_wages_paid],label+" payroll/wallet unchanged")
 check(before.serial==after.serial and before.records[0].token==after.records[0].token,label+" guest and job token retained")
 return true
func finish(limit=3000):
 var seen=[]
 for tick in range(limit):
  game.advance()
  for staff in game.staff_states:
   if staff.job_kind=="cleanup" and float(staff.job_elapsed)>0:
    var key="%s:%s"%[staff.role,int(staff.job_step)]
    if not seen.has(key):seen.append(key)
  var record=game.service_guests.values()[0]
  if record.cleanup_done:return seen
 return seen
func run():
 game=Fixture.new();root.add_child(game);await process_frame
 game.set_process(false);game.illustration.set_process(false)
 game.model.operating_open=false
 check(game.save_writes_suppressed and OS.get_environment("XDG_DATA_HOME")!="","normal saves suppressed and isolated XDG")
 var record=game.setup_dirty(true)
 var roles=game.staff_states.map(func(s):return s.role)
 var seen=finish()
 check(record.cleanup_done,"real movement completes both table and floor")
 for step in [0,1,2]:check(seen.has("waiter:%s"%step),"waiter physically performs table stage %s"%step)
 for step in [3,5,6]:check(seen.has("cleaner:%s"%step),"cleaner physically performs floor stage %s"%step)
 check(not seen.has("waiter:3") and not seen.has("waiter:5") and not seen.has("waiter:6"),"waiter never performs floor work")
 check(not seen.has("cleaner:0") and not seen.has("cleaner:1") and not seen.has("cleaner:2"),"new cleaner never performs table work")
 check(roles==game.staff_states.map(func(s):return s.role),"job handoff retains staff roster")
 results.append({"case":"new full cleanup","stages":seen,"done":record.cleanup_done})
 # No waiter: cleaner may finish floor but cannot claim table-only work.
 record=game.setup_dirty(true);game.worker("waiter").on_duty=false
 seen=finish(1500)
 check(record.floor_cleaned and not record.cleanup_done and not record.table_wiped and not record.dishes_collected,"floor completion leaves blocked table unfinished")
 check(game.worker("cleaner").job_kind=="","cleaner releases guest when only table remains")
 game.worker("waiter").on_duty=true;seen=finish()
 check(record.cleanup_done and table_done(record),"waiter later resumes table without repeating floor")
 # No cleaner: waiter table completion must never erase floor litter/spill.
 record=game.setup_dirty(true);game.worker("cleaner").on_duty=false
 seen=finish(1500)
 check(table_done(record) and not record.cleanup_done and record.trash_owner=="floor" and record.spill_remaining==1.0,"table completion retains independent floor work")
 game.worker("cleaner").on_duty=true;finish();check(record.cleanup_done,"cleaner later completes remaining floor")
 # Floor assignment does not require a sink or an available tabletop.
 record=game.setup_dirty(true);game.worker("waiter").on_duty=false
 var saved_items=game.model.items.duplicate(true)
 game.model.items=game.model.items.filter(func(i):return i.kind!="sink");game.model.revision+=1
 var cleaner=game.worker("cleaner");game._assign_service_job(cleaner,index(cleaner))
 check(cleaner.job_kind=="cleanup" and cleaner.job_step==3,"floor-only assignment succeeds without sink")
 seen=finish(1500)
 check(record.floor_cleaned and record.trash_owner=="disposed" and record.spill_cleaned and not record.cleanup_done,"floor route completes without sink and preserves unfinished table")
 check(seen.has("cleaner:3") and seen.has("cleaner:5") and seen.has("cleaner:6"),"sink-free cleaner physically sweeps, reaches bin and mops")
 game.model.items=saved_items;game.model.revision+=1
 # Save/load real waiter actions at collecting, carrying, washing and wiping.
 for desired in ["collecting","carrying_dishes","dropping_dishes","wiping"]:
  record=game.setup_dirty(true)
  var reached=false
  for tick in range(2500):
   game.advance();var waiter=game.worker("waiter")
   if waiter.job_kind=="cleanup" and waiter.art_action==desired and (waiter.job_elapsed>.15 or desired=="carrying_dishes"):
    reached=true;break
  check(reached,"reach waiter "+desired)
  var prior=game.worker("waiter").duplicate(true)
  save_reload("waiter "+desired)
  var waiter=game.worker("waiter")
  check(waiter.pos==prior.pos and waiter.job_step==prior.job_step and is_equal_approx(waiter.job_elapsed,prior.job_elapsed),"waiter "+desired+" position and elapsed retained")
  seen=finish();check(game.service_guests.values()[0].cleanup_done,"restored waiter "+desired+" finishes")
 # Each legacy input is created by real movement in the unchanged old Main.
 var old=BeforeFixture.new();root.add_child(old);await process_frame
 old.set_process(false);old.illustration.set_process(false)
 for stage in ["idle_collect","pre_contact_collect","held_collect","carrying","washing_sink","partial_wipe","idle_wipe","held_trash"]:
  record=old.setup_dirty(true)
  cleaner=old.worker("cleaner")
  var reached=false
  if stage=="idle_collect":old._assign_service_job(cleaner,old.staff_states.find(cleaner));reached=true
  for tick in range(2500):
   if reached:break
   old.advance()
   match stage:
    "pre_contact_collect":reached=cleaner.art_action=="collecting" and cleaner.job_elapsed>=.2 and not record.dishes_collected
    "held_collect":reached=cleaner.art_action=="collecting" and cleaner.job_elapsed>=.55 and record.plate_owner=="staff"
    "carrying":reached=cleaner.art_action=="carrying_dishes" and cleaner.job_step==1
    "washing_sink":reached=cleaner.art_action=="washing" and cleaner.job_elapsed>=.95 and record.plate_owner=="sink"
    "partial_wipe":reached=cleaner.art_action=="wiping" and cleaner.job_elapsed>=.3
    "idle_wipe":reached=cleaner.job_step==2 and cleaner.job_elapsed==0
    "held_trash":reached=cleaner.art_action=="carrying_trash" and record.trash_owner=="staff"
  check(reached,"old runtime reaches legacy "+stage)
  var prior=cleaner.duplicate(true)
  old.model.service_snapshot=old._service_save_snapshot()
  var legacy_path="res://tests/fixtures/legacy-"+stage+".json"
  check(old.model.save(legacy_path),"old runtime saves legacy "+stage+": "+old.model.last_error)
  check(game.model.load_save(legacy_path),"new runtime loads legacy "+stage+": "+game.model.last_error)
  game._restore_service_runtime()
  cleaner=game.worker("cleaner");record=game.service_guests.values()[0]
  check(cleaner.pos==prior.pos,"legacy "+stage+" no teleport")
  if stage in ["idle_collect","idle_wipe"]:check(cleaner.job_kind=="" or int(cleaner.job_step)>=3,"legacy "+stage+" immediately releases unstarted table work")
  elif stage=="washing_sink":check(cleaner.job_kind=="wash" and is_equal_approx(cleaner.job_elapsed,prior.job_elapsed/1.5*20.0),"legacy wash fraction preserved in cleaner queue job")
  else:check(cleaner.job_step==prior.job_step and is_equal_approx(cleaner.job_elapsed,prior.job_elapsed),"legacy "+stage+" elapsed/stage retained")
  if stage in ["held_collect","carrying"]:check(record.plate_owner=="staff" and record.plate_staff_index==index(cleaner),"legacy "+stage+" held dishes retained")
  if stage=="held_trash":check(record.trash_owner=="staff" and record.trash_staff_index==index(cleaner),"legacy held trash retained")
  save_reload("migrated legacy "+stage)
  record=game.service_guests.values()[0]
  seen=finish();check(record.cleanup_done,"legacy "+stage+" completes real route")
  if stage in ["pre_contact_collect","held_collect","carrying","washing_sink"]:check(not seen.has("cleaner:2") and seen.has("waiter:2"),"legacy "+stage+" gives tabletop wipe to waiter")
  results.append({"case":"legacy "+stage,"stages":seen,"done":record.cleanup_done,"fixture":legacy_path})
 old.queue_free()
 # Crumb litter uses its unchanged stage 4, never a waiter floor stage.
 record=game.setup_dirty(true);record.floor_debris="crumbs"
 seen=finish();check(record.cleanup_done and seen.has("cleaner:4") and not seen.has("waiter:4"),"cleaner handles crumb stage 4")
 # Invalid waiter floor ownership must still be rejected.
 record=game.setup_dirty(true);var waiter=game.worker("waiter")
 waiter.job_kind="cleanup";waiter.job_guest_id=record.guest.id;waiter.job_token=record.token;waiter.job_step=3
 game.model.service_snapshot=game._service_save_snapshot()
 check(not game.model.save("user://bad-role.json") and game.model.last_error.contains("Waiter cannot own floor cleanup"),"codec rejects waiter floor stage")
 var report={"checks":checks,"failures":failures,"results":results,"engine":Engine.get_version_info(),"save_writes_suppressed":game.save_writes_suppressed}
 FileAccess.open("res://docs/role-boundaries/test-results.json",FileAccess.WRITE).store_string(JSON.stringify(report,"  "))
 print("ROLE_BOUNDARIES_RESULT ",JSON.stringify(report))
 quit(0 if failures.is_empty() else 1)
