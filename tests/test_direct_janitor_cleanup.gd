extends SceneTree
const Fixture=preload("res://tests/role_fixture.gd")
const Codec=preload("res://scripts/cafe_runtime_codec.gd")
const Minimal=preload("res://scripts/minimal_start.gd")
var game
var checks=0
var failures=[]
func _initialize():run.call_deferred()
func check(ok,label):
 checks+=1
 if not ok:failures.append(label);printerr("FAIL ",label)
func advance(seconds):
 for tick in roundi(seconds/.05):game.advance(.05)
func remove_bins():
 var keep:Array[Dictionary]=[]
 for item in game.model.items:
  if item.kind!="bin":keep.append(item)
 game.model.items.assign(keep)
func run():
 game=Fixture.new();root.add_child(game);await process_frame
 game.set_process(false);game.illustration.set_process(false)
 var record=game.setup_dirty();remove_bins()
 check(game.model.count_kind("bin")==0,"fixture genuinely has no bin")
 var guest_id=int(record.guest.id);var identity=game.ground_mess_identity("guest",guest_id)
 var coins=game.model.coins
 advance(40)
 check(record.floor_cleaned and record.trash_owner=="disposed" and record.spill_cleaned,"guest sweep disposal mop finish without bin")
 check(record.dishes_collected and record.table_wiped,"waiter table work survives floor simplification")
 check(not game.complete_ground_mess_if_ready(identity),"repeated guest completion is idempotent")
 check(game.model.coins==coins,"cleanup has no direct wallet reward")
 var cleaner=game.worker("cleaner")
 var id=game.floor_tasks.spawn(Vector2i(4,6),"crumbs")
 check(id>0,"independent litter spawns")
 var floor_identity=game.ground_mess_identity("floor",id)
 advance(30)
 check(not game.floor_tasks.messes.has(id) and game.floor_tasks.completed==1,"independent sweep finishes without bin exactly once")
 check(not game.complete_ground_mess_if_ready(floor_identity),"repeated independent completion is inert")
 for staff in game.staff_states:check(staff.job_kind!="floor","no independent claim remains")
 # A legacy half-disposed bin payload retains its real bin identity until
 # completion, even though new work never needs to visit it.
 game.model.included_bin_pending=true # Synthetic historical unclaimed entitlement.
 check(game.model.ensure_basic_bin(),"legacy fixture owns a real historical bin")
 id=game.floor_tasks.spawn(Vector2i(4,6),"banana");cleaner=game.worker("cleaner")
 game.floor_tasks.assign(cleaner,game.staff_states.find(cleaner))
 var entry=game.floor_tasks.messes[id];var bin_id=-1
 for item in game.model.items:
  if item.kind=="bin":bin_id=int(item.id)
 entry.trash_owner="bin";entry.trash_staff_index=-1;entry.trash_target_id=bin_id
 cleaner.job_step=2;cleaner.job_elapsed=.7;cleaner.station_id=bin_id
 var snapshot=game._service_save_snapshot()
 game.model.service_snapshot=snapshot
 check(game.model.save("user://direct-janitor.json"),"legacy bin snapshot saves")
 check(game.model.load_save("user://direct-janitor.json"),"legacy bin snapshot validates and loads")
 floor_identity=game.ground_mess_identity("floor",id)
 game._restore_service_runtime();cleaner=game.worker("cleaner")
 check(cleaner.job_step==2 and is_equal_approx(cleaner.job_elapsed,.7),"legacy disposal stage and elapsed survive restore")
 check(game.resolve_ground_mess(floor_identity,false).is_empty(),"restore invalidates pending identity")
 check(game.floor_tasks.messes[id].trash_target_id==bin_id,"legacy real bin reference remains until completion")
 advance(1)
 check(not game.floor_tasks.messes.has(id) and game.floor_tasks.completed==2,"legacy bin settles exactly once")
 advance(2);check(game.floor_tasks.completed==2,"repeated legacy completion does not count twice")
 # Manual and NPC callers share one settlement boundary.
 id=game.floor_tasks.spawn(Vector2i(4,6),"banana")
 floor_identity=game.ground_mess_identity("floor",id)
 cleaner=game.worker("cleaner");game.floor_tasks.assign(cleaner,game.staff_states.find(cleaner))
 check(game.complete_ground_mess(floor_identity),"manual visible-floor completion accepted")
 check(not game.complete_ground_mess(floor_identity) and game.floor_tasks.completed==3,"manual repeated click settles once")
 check(cleaner.job_kind!="floor","manual completion releases NPC floor claim")
 record=game.setup_dirty();identity=game.ground_mess_identity("guest",int(record.guest.id))
 var plate_owner=record.plate_owner;var table_wiped=record.table_wiped
 var stale_cleaner=game.legacy_job(record,3,.3).duplicate(true)
 check(game.complete_ground_mess(identity),"manual guest-ground completion accepted")
 check(record.plate_owner==plate_owner and record.table_wiped==table_wiped and not record.cleanup_done,"manual guest completion preserves unfinished waiter work")
 check(not game.complete_ground_mess(identity),"manual guest repeat has no second effect")
 game._service_contact(stale_cleaner,game.staff_states.find(game.worker("cleaner")),"sweeping",{},1.0)
 check(record.trash_owner=="disposed" and record.trash_staff_index==-1,"stale NPC sweep contact cannot reopen manually settled trash")
 id=game.floor_tasks.spawn(Vector2i(4,6),"crumbs");floor_identity=game.ground_mess_identity("floor",id)
 var saved_floor=game.floor_tasks.snapshot();game.floor_tasks.restore(saved_floor)
 check(not game.complete_ground_mess(floor_identity),"floor-only restore rejects old callback identity")
 Minimal.apply(game.model)
 check(game.model.count_kind("bin")==0,"fresh profile no longer auto-places mandatory bin")
 check(not game.model.included_bin_pending,"fresh profile has no free bin entitlement")
 var bin_price=0
 for product in game.model.catalog:
  if product.kind=="bin":bin_price=int(product.price)
 check(bin_price>0 and game.model.price_of("bin")==bin_price,"optional bin retains normal shop price")
 coins=game.model.coins;var bin_item_id=game.model._next_item_id
 check(game.model.place("bin",3,6),"fresh player may buy optional bin: "+game.model.last_error)
 check(game.model.coins==coins-bin_price and game.model.count_kind("bin")==1,"optional purchase charges once and owns one bin")
 check(game.model.save("user://optional-bin.json"),"synthetic purchased bin saves")
 check(game.model.load_save("user://optional-bin.json"),"synthetic purchased bin restores")
 check(game.model.get_item(bin_item_id).kind=="bin" and game.model.coins==coins-bin_price and game.model.logical_refund(bin_item_id)==floori(bin_price*.5),"restored owned bin and existing resale value survive")
 # A historic unclaimed entitlement is still interpreted by the existing reader.
 # Fresh initialization must not become a load-time migration or revoke it.
 Minimal.apply(game.model);game.model.included_bin_pending=true
 check(game.model.save("user://historic-bin-entitlement.json"),"synthetic historical entitlement saves")
 check(game.model.load_save("user://historic-bin-entitlement.json"),"synthetic historical entitlement restores")
 check(game.model.included_bin_pending and game.model.price_of("bin")==0,"historical entitlement is preserved")
 print("DIRECT_JANITOR_RESULT ",JSON.stringify({"checks":checks,"failures":failures}))
 quit(0 if failures.is_empty() else 1)
