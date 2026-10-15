extends SceneTree
const AudioDrain = preload("res://tests/fixtures/audio_mixer_drain.gd")
## Physical bodies, not hypothetical staff relocation, govern editor geometry.
## Ordinary active-service reader/custody rules remain separate.
const Model=preload("res://scripts/core/cafe_model.gd")
class TestMain extends "res://scripts/main.gd":
 var save_calls=0
 func _load_startup():save_writes_suppressed=true;fresh_start=true;MinimalStart.apply(model)
 func _save():
  save_calls+=1
  # This geometry fixture has no live service. Persist only its generated layout.
  var service=model.service_snapshot;model.service_snapshot={}
  var saved=model.save("user://worker-egress-interval.json")
  model.service_snapshot=service
  if saved:platform_autosave_dirty=false;progress_unsaved=false
  return saved
 func _interaction_over_ui(_screen:Vector2)->bool:return false
var checks=0;var failures=[];var ui_events=0
func _init():call_deferred("run")
func check(ok:bool,label:String):
 checks+=1
 if not ok:failures.append(label);printerr("FAIL ",label)
func blank(model=null):
 var m=Model.new() if model==null else model
 m.items.clear();m.dining_sets.clear();m.customers.clear();m.built_walls.clear();m.wall_actor_positions.clear()
 m.cashiers=0;m.included_checkout_pending=true;m.duty_targets.cashier=0;m.duty_counts.cashier=0
 m.coins=100000;m._notify();return m
func state(m):
 return {"items":m.items.duplicate(true),"sets":m.dining_sets.duplicate(true),"guests":m.customers.duplicate(true),"walls":m.built_walls.duplicate(true),"coins":m.coins,"revision":m.revision,"next_id":m._next_item_id,"event":m.last_event,"service":m.service_snapshot.duplicate(true),"served":m.served,"earned":m.total_earned}
func unchanged(m,before:Dictionary,label:String):check(state(m)==before,label+" preserves layout, IDs, wallet, service and revision")
func model_cases():
 var m=blank();var center=Vector2(3.5,3.5);var before=state(m)
 check(not m.can_place("plant",3,3,-1,0,[center]),"preview refuses actual worker body")
 check(not m.place("plant",3,3,0,[center]),"purchase refuses actual worker body")
 unchanged(m,before,"body refusal")
 check(not m.place("plant",4,3,0,[Vector2(3.8,3.5)]),"body radius extends beyond worker cell")
 unchanged(m,before,"body-radius refusal")
 check(m.place("rug",3,3,0,[center]),"walkable rug may remain under a worker")
 m=blank();check(m.place("plant",6,3),"move source places");var id=int(m.items[-1].id);before=state(m)
 check(not m.move(id,3,3,0,[center]),"move refuses actual body")
 unchanged(m,before,"move refusal")
 check(m.move(id,7,3,0,[center]),"distant body-clear move remains valid")
 m=blank();check(m.place("table_set",6,4,0),"rotation source group places")
 id=int(m.dining_sets[-1].table_id)
 var old_cells=m.placement_parts("table_set",6,4,0,id).map(func(part):return Vector2i(part.x,part.z))
 var rotated=m.placement_parts("table_set",6,4,1,id);var body=Vector2.ZERO
 for part in rotated:
  if Vector2i(part.x,part.z) not in old_cells:body=m.cell_center(Vector2i(part.x,part.z))
 check(body!=Vector2.ZERO,"rotation introduces one previously clear physical cell")
 before=state(m);check(not m.move(id,6,4,1,[body]),"rotation refuses the new chair/body overlap")
 unchanged(m,before,"rotation refusal")
 m=blank()
 for spec in [["x",3,3],["z",3,3],["x",3,4]]:check(m.place_wall(spec[0],spec[1],spec[2],"full","sage_panels",[center]),"three-sided wall fixture")
 check(m.can_place("plant",4,3,-1,0,[center]),"body-clear enclosure preview uses geometry")
 check(m.place_wall("z",4,3,"full","sage_panels",[center]),"future staff exit cannot veto body-clear wall")
 check(not m._wall_reachable(m.built_walls,m.items,m.owned_parcels).has(Vector2i(3,3)),"real operational graph still observes enclosure")
 m=blank();before=state(m)
 check(not m.place_wall("z",4,3,"full","sage_panels",[Vector2(4,3.5)]),"wall refuses actual crossing body")
 unchanged(m,before,"crossing refusal")
 m.customers.assign([{"id":900,"phase":"arriving","x":9.5,"z":7.5,"route":[Vector2(3.5,3.5)]}])
 check(m.can_place("plant",3,3),"future guest route is not an occupied footprint")
 m.customers[0].x=3.5;m.customers[0].z=3.5;before=state(m)
 check(not m.can_place("plant",3,3),"present guest body refuses physical overlap")
 unchanged(m,before,"guest-body preview")
 # Structural exit seeds stay independent of corridor-only guest admission.
 for spec in [{"cell":Vector2i(1,3),"closing":Vector2i(2,3),"public_escape":true},{"cell":Vector2i(11,3),"closing":Vector2i(10,3),"public_escape":false}]:
  m=blank();var cell:Vector2i=spec.cell;var closing:Vector2i=spec.closing
  check(m.place("plant",cell.x,cell.y-1),"corridor fixture upper obstacle places")
  check(m.place("plant",cell.x,cell.y+1),"corridor fixture lower obstacle places")
  var candidate=m.items.duplicate(true);candidate.append({"id":-1,"kind":"plant","x":closing.x,"z":closing.y,"rot":0})
  check(m._wall_reachable(m.built_walls,candidate,m.owned_parcels).has(cell),"original structural exit remains distinct from guest admission")
  var approach=Vector2i(-1,cell.y) if cell.x==1 else Vector2i(Model.BASE_WIDTH,cell.y)
  check(m._public_exterior_cell(approach)==spec.public_escape,"guest approach keeps corridor distinct from private land")
func frames(n=2):
 for unused in range(n):await process_frame
func mouse(point:Vector2,pressed:bool):
 var event=InputEventMouseButton.new();event.position=point;event.global_position=point;event.button_index=MOUSE_BUTTON_LEFT;event.pressed=pressed;event.button_mask=MOUSE_BUTTON_MASK_LEFT if pressed else 0
 Input.parse_input_event(event);ui_events+=1;await frames()
func ui_cases():
 root.size=Vector2i(1360,880);Input.use_accumulated_input=false
 var cafe=TestMain.new();root.add_child(cafe);cafe.set_process(false);cafe.illustration.set_process(false);cafe.paused=true
 for player in cafe.audio_players.values():player.stop()
 blank(cafe.model);cafe.editing=true;cafe.ui.hide()
 for i in cafe.staff_states.size():cafe.staff_states[i].pos=Vector2(2.5+i,.5)
 cafe._rebuild_furniture();cafe._update_ui();cafe.ui.hide();cafe.illustration.update_projection();await frames()
 var field=cafe.interaction.edit_plan;var actors=cafe.interaction._staff_positions();var before=state(cafe.model);var saves=cafe.save_calls
 cafe.platform_autosave_dirty=false;cafe.progress_unsaved=false;cafe.save_timer=0.0
 var dirty_generation=cafe.platform_dirty_generation
 var point=cafe.illustration.iso(2.5,.5);cafe.selected_kind="plant";cafe.rotation_step=0
 cafe.interaction.refresh(point)
 check(not cafe.interaction.drag_footprint_valid and not cafe.interaction.drag_valid,"actual UI refuses hidden worker body")
 var receipt=field.prepare(cafe.model,"plant",-1,0,Vector2i(2,0),actors)
 check(not receipt.physical_ok and not field.commit(cafe.model,receipt,actors),"invalid body receipt cannot publish")
 await mouse(point,true);await mouse(point,false)
 unchanged(cafe.model,before,"rejected pointer purchase")
 check(cafe.save_calls==saves and cafe.interaction._staff_positions()==actors,"body refusal neither saves nor relocates staff")
 cafe.interaction.cancel();unchanged(cafe.model,before,"cancel")
 receipt=field.prepare(cafe.model,"table_set",-1,0,Vector2i(6,6),actors)
 check(receipt.ok and receipt.physical_ok,"clear group receipt prepares")
 cafe.staff_states[0].pos=Vector2(6.5,6.5)
 check(not field.commit(cafe.model,receipt,cafe.interaction._staff_positions()),"changed live body refuses stale receipt")
 unchanged(cafe.model,before,"stale body receipt")
 cafe.staff_states[0].pos=actors[0];cafe.selected_kind="table_set";cafe.rotation_step=0;point=cafe.illustration.iso(6.5,6.5);cafe.interaction.refresh(point)
 await mouse(point,true);await mouse(point,false)
 check(cafe.model.items.size()==before.items.size()+2 and cafe.model.coins==before.coins-cafe.model.price_of("table_set"),"real pointer purchase publishes group and charges once")
 check(cafe.save_calls==saves and cafe.platform_dirty_generation>dirty_generation and cafe.platform_autosave_dirty and cafe.interaction._staff_positions()==actors,"purchase marks dirty without an operation save or hypothetical relocation")
 cafe.save_writes_suppressed=false;cafe._tick_autosave(4.9)
 check(cafe.save_calls==saves and cafe.platform_autosave_dirty,"purchased furniture remains dirty until the five-second slot")
 cafe._tick_autosave(.1);cafe.save_writes_suppressed=true
 var durable=Model.new()
 check(cafe.save_calls==saves+1 and not cafe.platform_autosave_dirty and durable.load_save("user://worker-egress-interval.json"),"five-second slot writes one reloadable purchased layout")
 check(durable.items==cafe.model.items and durable.coins==cafe.model.coins and durable.dining_sets==cafe.model.dining_sets,"durable purchase retains exact bodies, dining group and charged wallet")
 dirty_generation=cafe.platform_dirty_generation
 check(not cafe.model.dining_sets.is_empty(),"real pointer purchase retains dining-group metadata for selected R")
 if not cafe.model.dining_sets.is_empty():
  var id=int(cafe.model.dining_sets[-1].table_id);cafe.interaction._select_item(cafe.model.get_item(id));var money=cafe.model.coins
  var key=InputEventKey.new();key.keycode=KEY_R;key.pressed=true;Input.parse_input_event(key);ui_events+=1;await frames()
  check(cafe.model.logical_rotation(id)==1,"selected R uses clear physical footprint")
  check(cafe.model.coins==money and cafe.save_calls==saves+1 and cafe.platform_dirty_generation>dirty_generation and cafe.platform_autosave_dirty,"rotation keeps wallet and marks dirty without an operation save")
  cafe.save_writes_suppressed=false;cafe._tick_autosave(5.0);cafe.save_writes_suppressed=true
  durable=Model.new()
  check(cafe.save_calls==saves+2 and not cafe.platform_autosave_dirty and durable.load_save("user://worker-egress-interval.json"),"next five-second slot writes one reloadable rotated layout")
  check(durable.logical_rotation(id)==1 and durable.coins==money and durable.items==cafe.model.items,"durable rotation retains its exact body positions and unchanged wallet")
  check(cafe.interaction._staff_positions()==actors,"rotation does not teleport workers")
 for tween in get_processed_tweens():tween.kill()
 cafe.settings_controls.sfx_player.stop();cafe.queue_free();await frames()
 var audio_drain = await AudioDrain.wait_for_mixer_cycles(self)
 check(audio_drain.ok, "audio teardown observes two mixer cycles within 1s")
 print("AUDIO_TEARDOWN_RESULT ", JSON.stringify(audio_drain))
func run():
 if not "--fresh-review" in OS.get_cmdline_user_args():quit(2);return
 model_cases();await ui_cases()
 var report={"checks":checks,"failures":failures,"native_input_events":ui_events,"scope":"generated physical-body/model and actual Main input; no player save or pixel acceptance"}
 print("FURNITURE_WORKER_EGRESS ",JSON.stringify(report))
 var path=OS.get_environment("LL_UI_RESULT")
 if path!="":var file=FileAccess.open(path,FileAccess.WRITE);file.store_string(JSON.stringify(report,"  "));file.close()
 quit(0 if failures.is_empty() else 1)
