extends SceneTree
## Live worker route/body guard through model mutations and native edit input.
## All fixtures and save calls are isolated; no player profile is loaded/written.
const Model=preload("res://scripts/cafe_model.gd")
const CENTER=Vector2(3.5,3.5)
class TestMain extends "res://scripts/main.gd":
 var save_calls=0
 func _load_startup():
  save_writes_suppressed=true;fresh_start=true;MinimalStart.apply(model)
  # Preserve the crowded legacy restaurant that these workface cases target.
  # This is an owned saved counter, not a purchase in the new-game catalog.
  assert(model.move(int(model.checkout_register().id),6,4,1),model.last_error)
  model.items.append({"id":model._next_item_id,"kind":"counter","x":6,"z":2,"rot":0});model._next_item_id+=1;model._notify()
 func _save():save_calls+=1;return true
 func _interaction_over_ui(_screen:Vector2)->bool:return false
var checks=0;var failures=[];var ui_events=0
func _init():call_deferred("run")
func check(ok:bool,label:String):
 checks+=1
 if not ok:failures.append(label);printerr("FAIL ",label)
func blank(model=null):
 var m=Model.new() if model==null else model
 m.items.clear();m.dining_sets.clear();m.customers.clear();m.built_walls.clear();m.wall_actor_positions.clear()
 m.coins=100000;m._notify()
 return m
func ring(m):
 for spec in [[3,2,2],[2,3,1],[3,4,0]]:
  check(m.place("table_set",spec[0],spec[1],spec[2]),"three-sided furniture fixture places "+str(spec))
func state(m):
 return {"items":m.items.duplicate(true),"sets":m.dining_sets.duplicate(true),"guests":m.customers.duplicate(true),"walls":m.built_walls.duplicate(true),"coins":m.coins,"revision":m.revision,"next_id":m._next_item_id,"event":m.last_event,"service":m.service_snapshot.duplicate(true),"served":m.served,"earned":m.total_earned}
func unchanged(m,before:Dictionary,label:String):check(state(m)==before,label+" preserves layout, IDs, wallet, service and revision")
func model_cases():
 var m=blank();ring(m)
 check(m.wall_actor_positions.is_empty() and m.built_walls.is_empty(),"fixture has no cached workers or built walls")
 check(not m.path_between(Vector2i(3,3),Model.ENTRY_LANDING).is_empty(),"worker starts with an escape")
 var before=state(m)
 check(not m.can_place("table_set",4,3,-1,3,[CENTER]),"explicit live worker rejects empty-chair enclosure preview")
 check("staff" in m.last_error,"blocked preview explains staff egress")
 unchanged(m,before,"invalid dining preview")
 check(not m.place("table_set",4,3,3,[CENTER]),"authoritative dining purchase rejects enclosure")
 unchanged(m,before,"rejected dining purchase")
 check(not m.can_place("plant",4,3,-1,0,[CENTER]),"single furniture preview rejects enclosure")
 check(not m.place("plant",4,3,0,[CENTER]),"single furniture purchase rejects enclosure")
 unchanged(m,before,"rejected single purchase")
 check(m.place("table_set",6,3,3,[CENTER]),"safe source table set places")
 var id=int(m.items[-2].id);before=state(m)
 check(not m.move(id,4,3,3,[CENTER]),"authoritative dining move rejects enclosure")
 unchanged(m,before,"rejected dining move")
 check(m.move(id,7,3,3,[CENTER]),"safe dining move remains allowed")
 check(m.place("plant",6,3,0,[CENTER]),"safe single source places")
 id=int(m.items[-1].id);before=state(m)
 check(not m.move(id,4,3,0,[CENTER]),"authoritative single move rejects enclosure")
 unchanged(m,before,"rejected single move")
 m=blank();ring(m);check(m.place("table_set",4,2,3,[CENTER]),"rotation source stays open")
 id=int(m.items[-2].id);before=state(m)
 check(not m.move(id,4,2,0,[CENTER]),"rotating only the chair cannot seal the worker")
 unchanged(m,before,"rejected rotation")
 m=blank();before=state(m)
 check(not m.place("plant",4,3,0,[Vector2(3.8,3.5)]),"authoritative body-radius overlap rejected outside target tile")
 unchanged(m,before,"direct body overlap")
 check(m.place("rug",3,3,0,[CENTER]),"walkable rug can go under a worker")
 m=blank();ring(m);check(m.place("table_set",4,3,3),"legacy trapped fixture constructs without runtime actors")
 check(m.path_between(Vector2i(3,3),Model.ENTRY_LANDING).is_empty(),"legacy fixture starts trapped")
 check(m.place("plant",9,7,0,[CENTER]),"unrelated safe edit allowed while legacy worker remains trapped")
 check(m.move(int(m.dining_sets[-1].table_id),6,3,3,[CENTER]),"moving enclosure outward frees already-trapped worker")
 check(not m.path_between(Vector2i(3,3),Model.ENTRY_LANDING).is_empty(),"repairing furniture move reopens real route")
 m=blank()
 for spec in [["x",3,3],["z",3,3],["x",3,4]]:check(m.place_wall(spec[0],spec[1],spec[2],"full","sage_panels",[CENTER]),"three-sided wall fixture places")
 before=state(m)
 check(not m.place("plant",4,3,0,[CENTER]),"furniture cannot seal final exit from wall-only room")
 unchanged(m,before,"wall-room enclosure rejected")
 check(not m.place_wall("z",4,3,"full","sage_panels",[CENTER]),"existing final-wall staff egress guard still holds")
 check(m.place("plant",4,3),"legacy mixed wall/furniture trap constructs")
 id=int(m.items[-1].id)
 check(m.place("plant",9,7,0,[CENTER]),"unrelated edit allowed in existing walled trap")
 check(m.move(id,6,3,0,[CENTER]),"furniture can reopen existing walled trap")
 # A 2-cell enclosed room cannot be reduced to one cell by a new purchase.
 m=blank()
 for spec in [["x",3,3],["x",4,3],["x",3,4],["x",4,4],["z",3,3],["z",5,3]]:check(m.place_wall(spec[0],spec[1],spec[2]),"legacy two-cell room wall")
 before=state(m)
 check(not m.place("plant",4,3,0,[CENTER]),"already-trapped worker cannot lose remaining walkway")
 unchanged(m,before,"worsened legacy trap rejected")
 # Guest/public egress can go through x=0 or grass; staff transit cannot.
 for spec in [{"cell":Vector2i(1,3),"closing":Vector2i(2,3),"label":"x0 arrival strip"},{"cell":Vector2i(11,3),"closing":Vector2i(10,3),"label":"unowned exterior grass"}]:
  m=blank();var cell:Vector2i=spec.cell;var closing:Vector2i=spec.closing;var actor=m.cell_center(cell)
  check(m.place("plant",cell.x,cell.y-1),spec.label+" upper obstacle places")
  check(m.place("plant",cell.x,cell.y+1),spec.label+" lower obstacle places")
  check(m._furniture_actor_component(Model.ENTRY_LANDING,m.items).has(cell),spec.label+" worker initially connected to indoor service floor")
  var candidate=m.items.duplicate(true);candidate.append({"id":-1,"kind":"plant","x":closing.x,"z":closing.y,"rot":0})
  check(m._wall_reachable(m.built_walls,candidate,m.owned_parcels).has(cell),spec.label+" fixture proves generic public graph would miss trap")
  check(not m._furniture_actor_component(Model.ENTRY_LANDING,candidate).has(cell),spec.label+" staff-specific graph rejects apparent escape")
  before=state(m)
  check(not m.can_place("plant",closing.x,closing.y,-1,0,[actor]),spec.label+" live preview rejects new trap")
  check(not m.place("plant",closing.x,closing.y,0,[actor]),spec.label+" authoritative purchase rejects new trap")
  unchanged(m,before,spec.label+" rejected closure")
  check(m.place("plant",closing.x,closing.y),spec.label+" legacy fixture can be constructed")
  id=int(m.items[-1].id)
  check(m.place("rug",6,6,0,[actor]),spec.label+" unrelated legacy edit remains allowed")
  check(m.move(id,7,7,0,[actor]),spec.label+" outward repair remains allowed")
  check(m._furniture_actor_component(Model.ENTRY_LANDING,m.items).has(cell),spec.label+" repair restores staff route")
 # The shared placement rule protects both required appliance fronts.
 for kind in ["beverage","sink"]:
  m=blank();check(m.place(kind,6,1,0),"required-front fixture places: "+kind)
  check(not m.can_place("table_set",6,2,-1,3,[Vector2(9.5,7.5)]),"authoritative policy rejects a newly blocked front: "+kind)
  check("front blocked" in m.placement_warning("table_set",6,2,-1,3),"rejected front retains its precise diagnostic: "+kind)
func frames(n=2):
 for unused in range(n):await process_frame
func mouse(point:Vector2,pressed:bool):
 var event=InputEventMouseButton.new();event.position=point;event.global_position=point;event.button_index=MOUSE_BUTTON_LEFT;event.pressed=pressed;event.button_mask=MOUSE_BUTTON_MASK_LEFT if pressed else 0
 Input.parse_input_event(event);ui_events+=1;await frames()
func motion(point:Vector2):
 var event=InputEventMouseMotion.new();event.position=point;event.global_position=point;event.button_mask=MOUSE_BUTTON_MASK_LEFT
 Input.parse_input_event(event);ui_events+=1;await frames()
func reset_ui(cafe):
 cafe.interaction.cancel();blank(cafe.model);ring(cafe.model)
 for i in cafe.staff_states.size():cafe.staff_states[i].pos=CENTER if i==0 else Vector2(9.5,6.5+i*.4)
 cafe._rebuild_furniture();cafe._update_ui();cafe.ui.hide();cafe.illustration.update_projection()
func ui_cases():
 root.size=Vector2i(1360,880);Input.use_accumulated_input=false
 var cafe=TestMain.new();root.add_child(cafe);cafe.set_process(false);cafe.illustration.set_process(false)
 for player in cafe.audio_players.values():player.stop()
 cafe.editing=true;cafe.ui.hide();await frames()
 # Arrange the crowded relocation case explicitly; public fresh starts now
 # place workers at their posts rather than supplying this back-wall fixture.
 for i in 3:
  cafe.staff_states[i].pos=Vector2(2.5+i,.5)
  cafe.staff_states[i].node.position=Vector3(2.5+i,0,.5)
 var field=cafe.interaction.edit_plan
 var point=cafe.illustration.iso(2.5,.5)
 cafe.selected_kind="table_set";cafe.rotation_step=0
 var before=state(cafe.model);var positions=cafe.interaction._staff_positions();var saves=cafe.save_calls
 cafe.interaction.refresh(point)
 check(cafe.interaction.drag_valid,"hidden-worker floor previews safe relocation")
 unchanged(cafe.model,before,"relocation preview")
 check(cafe.interaction._staff_positions()==positions,"preview does not move staff")
 var receipt=field.prepare(cafe.model,"table_set",-1,0,Vector2i(2,0),positions)
 check(not field.commit(cafe.model,receipt,positions),"model-only commit cannot omit live staff transition")
 unchanged(cafe.model,before,"missing staff transaction consumer")
 cafe.interaction.cancel()
 check(cafe.interaction._staff_positions()==positions,"cancel does not move staff")
 unchanged(cafe.model,before,"cancel preview")
 cafe.selected_kind="table_set";cafe.rotation_step=0;cafe.interaction.refresh(point)
 receipt=field.prepare(cafe.model,"table_set",-1,0,Vector2i(2,0),positions)
 cafe.staff_states[0].pos=Vector2(5.5,.5)
 check(not field.commit(cafe.model,receipt,cafe.interaction._staff_positions(),cafe._apply_edit_staff_positions),"changed staff position rejects stale relocation receipt")
 unchanged(cafe.model,before,"stale staff transaction")
 cafe.staff_states[0].pos=positions[0];cafe.interaction.refresh(point)
 await mouse(point,true);await mouse(point,false)
 check(cafe.model.items.size()==before.items.size()+2 and cafe.model.coins==before.coins-cafe.model.price_of("table_set"),"live purchase commits full group and charges once")
 check(cafe.save_calls==saves+1,"live relocation purchase saves once")
 check(cafe.staff_states[0].pos!=positions[0],"obstructing worker stepped aside")
 for index in cafe.staff_states.size():
  var pos:Vector2=cafe.staff_states[index].pos
  check(cafe.interaction.edit_plan.StaffRelocation.point_clear(cafe.model,pos,cafe.model.items),"worker body clears all furniture "+str(index))
  check(cafe.model._furniture_actor_component(Model.ENTRY_LANDING,cafe.model.items).has(Vector2i(pos.floor())),"worker has indoor exit "+str(index))
  if index>0:check(pos==positions[index],"unaffected worker stays put "+str(index))
 # Immediate selected R uses the same joint transaction as a drag release.
 var id=int(cafe.model.items[-2].id);cafe.interaction._select_item(cafe.model.get_item(id))
 var money=cafe.model.coins;var old_pos=cafe.staff_states[0].pos
 var key=InputEventKey.new();key.keycode=KEY_R;key.pressed=true;Input.parse_input_event(key);ui_events+=1;await frames()
 check(cafe.model.logical_rotation(id)==1,"selected R safely rotates onto hidden worker's former tile")
 check(cafe.model.coins==money and cafe.save_calls==saves+2,"rotation keeps money and saves once")
 check(cafe.staff_states[0].pos!=old_pos and cafe._staff_walkable(Vector2i(cafe.staff_states[0].pos.floor())),"rotation moves worker to clear floor")
 var actors=cafe.interaction._staff_positions()
 check(field.prepare(cafe.model,"table_set",id,1,Vector2i(2,0),actors).ok,"own unchanged group footprint remains valid")
 cafe.selected_kind="table_set";cafe.selected_id=-1;cafe.rotation_step=0
 for at in [Vector2i(7,3),Vector2i(7,4),Vector2i(5,4)]:
  var receipt_at=field.prepare(cafe.model,"table_set",-1,0,at,actors)
  check(not receipt_at.ok and "blocked" in receipt_at.error,"workface remains blocked despite relocation "+str(at))
 check(not field.prepare(cafe.model,"table_set",-1,0,Vector2i(8,2),actors).ok,"safe staff relocation cannot give away the reserved stove workface")
 # A sealed old room cannot be escaped by teleporting through its walls.
 var enclosed=blank()
 for spec in [["x",3,3],["x",4,3],["x",3,4],["x",4,4],["z",3,3],["z",5,3]]:enclosed.place_wall(spec[0],spec[1],spec[2])
 var failed=cafe.interaction.edit_plan.StaffRelocation.plan(enclosed,"plant",-1,3,3,0,[CENTER])
 check(not failed.ok,"relocation cannot cross a sealed wall room")
 var closing=blank();ring(closing)
 var plan=cafe.interaction.edit_plan.StaffRelocation.plan(closing,"table_set",-1,4,3,3,[CENTER])
 check(plan.ok and plan.moves.size()==1,"worker may leave an open pocket before furniture closes it")
 if plan.ok:
  check(not closing.path_between(Vector2i(3,3),Vector2i(plan.positions[0].floor())).is_empty(),"step-aside destination is reachable in old layout")
  check(closing.place("table_set",4,3,3,plan.positions),"new layout validates against relocated worker")
  check(closing._furniture_actor_component(Model.ENTRY_LANDING,closing.items).has(Vector2i(plan.positions[0].floor())),"relocated worker remains outside closed pocket")
 for tween in get_processed_tweens():tween.kill()
 cafe.settings_controls.sfx_player.stop();cafe.queue_free();await frames()
func run():
 if not "--fresh-review" in OS.get_cmdline_user_args():quit(2);return
 model_cases();await ui_cases()
 var report={"checks":checks,"failures":failures,"native_input_events":ui_events,"scope":"isolated model and actual Main native mouse/key paths; no player save"}
 print("FURNITURE_WORKER_EGRESS ",JSON.stringify(report))
 var path=OS.get_environment("LL_UI_RESULT")
 if path!="":var file=FileAccess.open(path,FileAccess.WRITE);file.store_string(JSON.stringify(report,"  "));file.close()
 quit(0 if failures.is_empty() else 1)
