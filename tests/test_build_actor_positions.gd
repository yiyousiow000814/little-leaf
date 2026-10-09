extends SceneTree
## Presentation stances must never become authority for Decorate validation.
## All state and saves belong to the disposable generated profile.
class TestMain extends "res://scripts/main.gd":
 var saves=0
 func _load_startup():save_writes_suppressed=true;fresh_start=true;MinimalStart.apply(model)
 func _save():saves+=1;return true
var game
var checks=0
var failures=[]
var evidence=[]
func check(ok:bool,label:String):
 checks+=1
 if not ok:failures.append(label);printerr("FAIL ",label)
func _initialize():run.call_deferred()
func settle():
 game._update_ui()
 for frame in 8:await process_frame
func click(point:Vector2):
 var motion=InputEventMouseMotion.new();motion.position=point;motion.global_position=point;root.push_input(motion,true)
 for pressed in [true,false]:
  var event=InputEventMouseButton.new();event.position=point;event.global_position=point;event.button_index=MOUSE_BUTTON_LEFT;event.pressed=pressed;root.push_input(event,true)
 await settle()
func run():
 if not "saveguard" in OS.get_user_data_dir():printerr("Use isolated generated profile");quit(2);return
 root.size=Vector2i(1164,624);game=TestMain.new();root.add_child(game);game.set_process(false);game.illustration.set_process(false);game.paused=true
 await process_frame;game.model.coins=1600;game._toggle_edit();game._set_catalog_category("Build");game.compact_ui._set_tray_reveal(1);await settle()
 var tool=game.build_tools;var art=game.illustration;var model=game.model
 # Actual GUI dispatch at the reported embedded-canvas size and desktop size.
 for view in [Vector2i(1164,624),Vector2i(1360,880)]:
  root.size=view;await settle()
  for kind in ["door","window","door","window"]:
   var wallet=model.coins;var saves=game.saves
   await click(tool.tool_buttons[kind].get_global_rect().get_center())
   check(tool.mode==kind,"real card click selects "+kind+" at "+str(view))
   check(model.coins==wallet and game.saves==saves,"selection never charges or saves")
 # Force the existing, unmodified renderer to produce authentic service poses.
 # Washing and rear table wiping cross .5 tile; cashier contact is also visual.
 var initial_staff=[]
 for worker in game.staff_states:initial_staff.append(worker.pos)
 for spec in [["washing","sink",Vector2i.DOWN],["wiping","table",Vector2i.RIGHT],["taking_payment","register",Vector2i.UP]]:
  var station={}
  for item in model.items:
   if item.kind==spec[1]:station=item;break
  check(not station.is_empty(),"fixture has "+str(spec[1]));if station.is_empty():continue
  var cell=Vector2i(station.x,station.z)+spec[2]
  if spec[0]=="washing":cell=model.workface_cell(station)
  elif spec[0]=="taking_payment":cell=model.checkout_rear(station)
  var raw=model.cell_center(cell);var worker=game.staff_states[0]
  worker.pos=raw;worker.art_action=spec[0];worker.art_target_id=station.id;worker.art_target=Vector2(station.x+.5,station.z+.5)
  art.stance_offsets.clear();game.editing=false;game.paused=false;art.update_motion(1.0);game.editing=true;game.paused=true
  var rendered=art._render_position("staff_0",raw);var actors=tool.actor_positions()
  check(actors[0]==raw,"build uses authoritative "+str(spec[0])+" position")
  check(not rendered.is_equal_approx(raw),"fixture exercises real "+str(spec[0])+" stance")
  if spec[0]=="wiping":check(Vector2i(rendered.floor())==Vector2i(station.x,station.z),"table visual lean still stress-tests occupied-cell authority")
  if spec[0]=="washing":
   check(Vector2i(rendered.floor())==cell,"washing stance remains outside the full-cell sink")
   check(is_equal_approx(rendered.distance_to(raw),art.SinkWashArt.work_inset(int(station.rot))),"washing exercises the actual bounded presentation inset")
  for kind in ["door","window"]:
   var before=model.coins
   check(model.can_place_wall_attachment(kind,"shell:back",2.5,actors),str(spec[0])+" allows unrelated "+kind+": "+model.last_error)
   check(model.coins==before,"preview leaves wallet unchanged")
  check(model.can_place_wall("x",7,6,"full","sage_panels",actors),str(spec[0])+" allows unrelated new wall: "+model.last_error)
  check(model.wall_replacement_quote("shell:back#2","full","cream_stripe",actors).valid,str(spec[0])+" allows unrelated wall replacement")
  evidence.append({"action":spec[0],"raw":str(raw),"rendered":str(rendered),"uses_authority":actors[0]==raw})
  for index in game.staff_states.size():game.staff_states[index].pos=initial_staff[index];game.staff_states[index].art_action="idle"
 # A guest's lean and seated pose likewise cannot rewrite their logical cell.
 model.customers.append({"id":98765,"phase":"eating","x":3.5,"z":4.5})
 art.stance_offsets["guest_98765"]=Vector2(0,-.6)
 check(tool.actor_positions()[-1]==Vector2(3.5,4.5),"guest pose is excluded from authoritative build positions")
 model.customers.clear();art.stance_offsets.clear()
 # Commit through ordinary pointer dispatch while a washer is visually leaning.
 var sink=model.get_item(3);var worker=game.staff_states[0];worker.pos=model.cell_center(model.workface_cell(sink));worker.art_action="washing";worker.art_target_id=sink.id;worker.art_target=Vector2(sink.x+.5,sink.z+.5)
 game.editing=false;game.paused=false;art.update_motion(1.0);game.editing=true;game.paused=true
 for kind in ["door","window"]:
  await click(tool.tool_buttons[kind].get_global_rect().get_center())
  var point=art.iso(2.5 if kind=="door" else 3.5,0,70)
  # Keep the exact host comfortably clear of HUD and tray without changing zoom.
  game.interaction._pan_by(art.camera_safe_rect().get_center()-point);point=art.iso(2.5 if kind=="door" else 3.5,0,70)
  var wallet=model.coins;var count=model.wall_attachments.size();var saves=game.saves
  await click(point)
  check(model.wall_attachments.size()==count+1,"real click attaches "+kind+" while washing")
  check(model.coins==wallet-model.attachment_price(kind) and game.saves==saves+1,"attachment charges and saves once")
  await click(point)
  check(model.wall_attachments.size()==count+1 and model.coins==wallet-model.attachment_price(kind),"repeated same opening click cannot charge twice")
 # Actual people and route conflicts remain protected.
 worker.pos=Vector2(7.5,6.0);art.stance_offsets["staff_0"]=Vector2(0,-.55)
 check(not model.can_place_wall("x",7,6,"full","sage_panels",tool.actor_positions()),"real body crossing still rejects wall")
 check(model.last_error.contains("crossing"),"crossing rejection retains specific explanation")
 worker.pos=Vector2(7.5,6.5);art.stance_offsets.clear();var actors=tool.actor_positions()
 for spec in [["x",7,6],["z",7,6],["x",7,7]]:check(model.place_wall(spec[0],spec[1],spec[2],"full","sage_panels",actors),"three-sided enclosure fixture")
 var wallet=model.coins
 check(not model.place_wall("z",8,6,"full","sage_panels",actors),"actual fourth wall cannot trap worker")
 check(model.coins==wallet,"blocked enclosure never charges")
 nonworsening_cases()
 print("BUILD_ACTOR_POSITIONS_RESULT ",JSON.stringify({"checks":checks,"failures":failures,"poses":evidence,"player_save_used":false,"native_render_verified":false}))
 for player in game.audio_players.values():player.stop();player.stream=null
 game.settings_controls.sfx_player.stop();game.settings_controls.sfx_player.stream=null
 for tween in get_processed_tweens():tween.kill()
 game.queue_free();await process_frame;quit(0 if failures.is_empty() else 1)

func nonworsening_cases():
 var m=game.Model.new();m.items.clear();m.dining_sets.clear();m.customers.clear();m.coins=10000;m._notify()
 var trapped=[Vector2(3.5,3.5)]
 for spec in [["x",3,3],["z",3,3],["x",3,4],["z",4,3],["x",8,6],["x",9,6]]:
  check(m.place_wall(spec[0],spec[1],spec[2]),"legacy enclosed-room fixture")
 check(not m._wall_reachable(m.built_walls,m.items,m.owned_parcels).has(Vector2i(3,3)),"fixture has a genuine unrelated pre-existing trapped cell")
 var quote=m.wall_replacement_quote("x:8:6","full","cream_stripe",trapped)
 check(quote.valid,"existing built-wall finish ignores unrelated trapped worker")
 var wallet=m.coins
 check(m.replace_wall("x:8:6","full","cream_stripe",trapped),"existing wall finish commits while distant legacy trap remains")
 check(m.coins==wallet-int(quote.net),"cosmetic replacement keeps exact quote/payment")
 check(m.wall_replacement_quote("shell:back#2","full","cream_stripe",trapped).valid,"existing shell style ignores unrelated trapped worker")
 var first=m.get_wall("x:8:6");var second=m.get_wall("x:9:6")
 check(m.place_wall_attachment("window","wall:"+str(first.id),.5,trapped),"window on existing solid wall ignores unrelated trapped worker")
 var window_id=m.wall_attachments[-1].id
 check(m.move_wall_attachment(window_id,"shell:back",2.5,trapped),"window move cannot close a ground path")
 check(m.remove_wall_attachment(window_id,trapped),"window removal cannot close a ground path")
 check(m.place_wall_attachment("door","wall:"+str(second.id),.5,trapped),"new door only opens paths despite unrelated trapped worker")
 check(not m.can_place_wall_attachment("window","wall:"+str(second.id),.5,trapped),"overlapping aperture remains rejected")
 check(not m.wall_replacement_quote("x:9:6","half","sage_panels",trapped).valid,"opening still requires full-height support")
 check(not m.can_place_wall_attachment("window","wall:99999",.5,trapped),"missing host remains rejected")
 check(not m.can_place_wall_attachment("door","shell:back",-.5,trapped),"out-of-host opening remains rejected")
 # Repairing the trapped room by adding a door is always permitted. Closing
 # or moving that sole doorway must still use the full egress/body guards.
 var host="wall:"+str(m.get_wall("z:4:3").id)
 check(m.place_wall_attachment("door",host,.5,trapped),"adding door repairs pre-existing trapped room")
 var exit_id=m.wall_attachments[-1].id;wallet=m.coins
 check(not m.remove_wall_attachment(exit_id,trapped),"removing only room exit still rejected")
 check(not m.move_wall_attachment(exit_id,"shell:back",2.5,trapped),"moving only room exit still rejected")
 check(m.coins==wallet and m.get_wall_attachment(exit_id).host_id==host,"rejected closures preserve wallet and old door")
