extends SceneTree
## Synthetic native reproduction: one janitor washes while a waiter drops at a side.
const Fixture=preload("res://tests/role_fixture.gd")
var game
var failures=[]
var checks=0
var facts={"player_save_used":false,"states":[]}
func _initialize():run.call_deferred()
func check(ok,label):
 checks+=1
 if not ok:failures.append(label);printerr("FAIL ",label)
func capture(label):
 if DisplayServer.get_name()=="headless":return
 game._update_ui();game.illustration._process(.1);game.illustration.queue_redraw()
 for frame in 3:await process_frame
 await RenderingServer.frame_post_draw
 root.get_texture().get_image().save_png(OS.get_environment("OUTPUT")+"/"+label+".png")
func snapshot(label,record):
 facts.states.append({"label":label,"owner":record.plate_owner,"queue":game.dishwashing.snapshot(),"staff":game.staff_states.map(func(w):return {"role":w.role,"job":w.job_kind,"action":w.art_action,"elapsed":w.job_elapsed,"position":str(w.pos),"destination":str(w.destination)})})
func run():
 seed(472);root.size=Vector2i(1360,880)
 game=Fixture.new();root.add_child(game);await process_frame
 game.set_process(false);game.illustration.set_process(false)
 var record=game.setup_dirty(false)
 var sink={}
 for item in game.model.items:
  if item.kind=="sink":sink=item;break
 sink.x=6;sink.z=4;sink.rot=0
 var register=game.model.checkout_register();register.x=2;register.z=6;register.rot=0
 # Preserve the complete synthetic dining pair when clearing the drop cells.
 for group in game.model.dining_sets:
  var table=game.model.get_item(int(group.table_id));var seat=game.model.get_item(int(group.seat_id))
  if Vector2i(int(table.x),int(table.z))==Vector2i(6,5):table.x-=2;seat.x-=2
 game.model.rebuild_dining_sets()
 game.model.items=game.model.items.filter(func(i):return i.kind=="sink" or Vector2i(int(i.x),int(i.z)) not in [Vector2i(5,4),Vector2i(7,4),Vector2i(6,5)])
 game.model.revision+=1;game._rebuild_furniture()
 for i in game.staff_states.size():
  var worker=game.staff_states[i]
  worker.on_duty=false;worker.pos=Vector2(1.5,3.5+i)
 var cleaner=game.worker("cleaner");var waiter=game.worker("waiter")
 cleaner.on_duty=true;waiter.on_duty=true
 game.dishwashing.dishes[1]={"id":1,"sink_id":int(sink.id),"elapsed":5.0};game.dishwashing.next_id=2
 cleaner.pos=Vector2(6.5,5.5)
 check(game.dishwashing.assign(cleaner,game.staff_states.find(cleaner)),"janitor owns original queued dish")
 cleaner.destination=Vector2i(6,5);cleaner.job_elapsed=5.0
 waiter.pos=Vector2(5.5,3.5);waiter.job_kind="cleanup";waiter.job_step=1;waiter.job_elapsed=0.0
 waiter.job_guest_id=int(record.guest.id);waiter.job_token=int(record.token);waiter.station_id=int(sink.id)
 record.plate_owner="staff";record.plate_staff_index=game.staff_states.find(waiter);record.dish_sink_id=int(sink.id)
 record.dishes_collected=true;record.table_wiped=false;record.drink_owner="cleared"
 var from=Vector2i(5,3)
 var selected=game._service_destination(waiter,sink,from)
 facts.initial_destination=str(selected)
 check(selected in [Vector2i(5,4),Vector2i(7,4)],"active wash permits a reachable lateral drop-off")
 if game.dishwashing.has_method("drop_destination"):
  var blocker={"id":99991,"kind":"stove","x":5,"z":4,"rot":0}
  game.model.items.append(blocker);game.model.revision+=1
  check(game._service_destination(waiter,sink,from)==Vector2i(7,4),"blocked left side falls back to reachable right")
  var blocker2={"id":99992,"kind":"stove","x":7,"z":4,"rot":0}
  game.model.items.append(blocker2);game.model.revision+=1
  check(game._service_destination(waiter,sink,from)==Vector2i(-1,-1),"both lateral sides blocked retain held dish")
  game.model.items.erase(blocker);game.model.items.erase(blocker2);game.model.revision+=1
  var peer=game.worker("chef");var peer_pos=peer.pos
  peer.pos=Vector2(5.5,4.5)
  check(game._service_destination(waiter,sink,from)==Vector2i(7,4),"occupied left side excludes another character")
  peer.pos=peer_pos
 game.illustration.zoom=1.6;game.illustration.pan_offset=Vector2(-140,95);game.illustration.update_projection()
 game.advance(.05);snapshot("carrying",record);await capture("01-carrying")
 var reached_drop=false;var reached_queue=false;var progressed_together=false;var precontact=false
 for tick in 100:
  var previous_wash=float(cleaner.job_elapsed);var previous_drop=float(waiter.job_elapsed)
  game.advance(.05)
  if waiter.art_action=="dropping_dishes" and record.plate_owner=="staff":
   if not reached_drop:snapshot("dropping",record);await capture("02-dropping")
   reached_drop=true
   if not precontact and float(waiter.job_elapsed)>=.4:
    precontact=true;snapshot("precontact",record);await capture("02b-precontact")
   if cleaner.job_elapsed>previous_wash and waiter.job_elapsed>previous_drop:progressed_together=true
  if record.plate_owner=="dish_queue":reached_queue=true;break
 check(reached_drop and reached_queue,"walk and physical gesture hand off held dish during wash")
 check(progressed_together,"different sink cells advance washing and drop-off together")
 check(cleaner.job_kind=="wash" and int(cleaner.job_dish_id)==1 and cleaner.job_elapsed<20.0,"janitor retains original job and progress")
 check(waiter.pos.distance_to(cleaner.pos)>.9,"workers stand on separate adjacent cells")
 check(game.dishwashing.count_at(int(sink.id))==2,"original and newly dropped dish each exist once")
 if reached_queue:
  var count=game.dishwashing.dishes.size()
  check(game.dishwashing.deposit(record,waiter,game.staff_states.find(waiter),sink) and game.dishwashing.dishes.size()==count,"replayed drop does not duplicate dish")
 snapshot("queued",record);await capture("03-queued")
 check(game.save_writes_suppressed,"fixture suppresses player saves")
 facts.checks=checks;facts.failures=failures;facts.source_commit=OS.get_environment("SOURCE_COMMIT")
 FileAccess.open(OS.get_environment("OUTPUT")+"/result.json",FileAccess.WRITE).store_string(JSON.stringify(facts,"  "))
 print("SINK_SIDE_HANDOFF_RESULT ",JSON.stringify(facts))
 for player in game.audio_players.values():player.stop();player.stream=null
 for tween in get_processed_tweens():tween.kill()
 game.queue_free();await process_frame;await process_frame;quit(0 if failures.is_empty() else 1)
