extends SceneTree
const Placement=preload("res://scripts/dining_placement.gd")
class TestMain extends "res://tests/role_fixture.gd":
 var saves=0
 func _save():saves+=1;return true
var game
var checks=0
var failures=[]
var report=[]
func check(ok,label):
 checks+=1
 if not ok and not failures.has(label):failures.append(label);printerr(label)
func _initialize():run.call_deferred()
func capture(label):
 game._update_ui();game.illustration.queue_redraw()
 for frame in 4:await process_frame
 if DisplayServer.get_name()!="headless":
  await RenderingServer.frame_post_draw
  root.get_texture().get_image().save_png(OS.get_environment("OUTPUT")+"/service-"+label+".png")
 var contacts=[]
 for p in game.illustration.render_contacts:
  if p.staff:contacts.append({"id":p.id,"action":p.action,"progress":p.progress,"payload":p.payload,"hand_to_target":p.target_error,"prop_to_target":p.prop_target_error})
 var owners=[]
 for r in game.service_guests.values():owners.append({"plate":r.plate_owner,"drink":r.drink_owner,"collected":r.dishes_collected})
 report.append({"label":label,"contacts":contacts,"owners":owners,"table_height":Placement.TABLE_HEIGHT,"saves":game.saves})
func run():
 root.size=Vector2i(1800,1200);game=TestMain.new();root.add_child(game);game.set_process(false)
 await process_frame;game.illustration.set_process(false)
 game.model.operating_open=true;game.model._spawn_customer();game.model.operating_open=false
 var template=game.model.customers[0].duplicate(true);var staff_template=game.staff_states[0].duplicate(true)
 game.model.customers.clear();game.service_guests.clear();game.staff_states.clear()
 game.model.items=game.model.items.filter(func(item):return item.kind not in ["table","chair"])
 var tables=[Vector2i(4,6),Vector2i(8,6),Vector2i(4,10),Vector2i(8,10)]
 var directions=[Vector2i.RIGHT,Vector2i.DOWN,Vector2i.UP,Vector2i.LEFT]
 for i in range(4):
  var chair=tables[i]+directions[i]
  game.model.items.append({"id":100+i*2,"kind":"table","x":tables[i].x,"z":tables[i].y,"rot":0})
  game.model.items.append({"id":101+i*2,"kind":"chair","x":chair.x,"z":chair.y,"rot":0})
  var guest=template.duplicate(true)
  guest.id=i*3;guest.table_id=100+i*2;guest.chair_id=101+i*2;guest.x=chair.x+.5;guest.z=chair.y+.5
  guest.phase="cooking";guest.elapsed=0.0;guest.duration=6.0;guest.seated=true;guest.admitted=true;guest.waiting=false;guest.route=[];guest.route_index=0;guest.heading=-Vector2(directions[i]);guest.dismounting=false
  game.model.customers.append(guest)
  var staff=staff_template.duplicate(true);game._clear_service_job(staff)
  staff.role="waiter";staff.art_role="waiter";staff.on_duty=true;staff.pos=Vector2(tables[i]-directions[i])+Vector2(.5,.5)
  staff.path=[];staff.index=0;staff.heading=Vector2(directions[i]);staff.art_target=Vector2(tables[i])+Vector2(.5,.5)
  game.staff_states.append(staff)
 game._sync_service_guests();game._rebuild_furniture();game._update_people();game.editing=false;game.paused=true
 game.illustration.zoom=1.65;game.illustration.pan_offset=Vector2.ZERO;game.illustration.update_projection(false)
 game.illustration.pan_offset+=Vector2(900,660)-game.illustration.iso(6.5,8.5);game.illustration.update_projection(false)
 var immutable=JSON.stringify({"items":game.model.items,"positions":game.model.customers.map(func(g):return [g.x,g.z]),"staff":game.staff_states.map(func(st):return st.pos),"coins":game.model.coins})
 for kind in ["deliver_meal","deliver_drink","cleanup"]:
  for i in range(4):
   var g=game.model.customers[i];var r=game.service_guests[int(g.id)];var st=game.staff_states[i]
   g.phase="dirty" if kind=="cleanup" else "cooking"
   r.plate_owner="staff" if kind=="deliver_meal" else "table";r.plate_staff_index=i if kind=="deliver_meal" else -1
   r.drink_owner="staff" if kind=="deliver_drink" else "table";r.drink_staff_index=i if kind=="deliver_drink" else -1
   r.dishes_collected=false;st.job_kind=kind;st.job_guest_id=int(g.id);st.job_token=int(r.token)
  for phase in [.64,.65]:
   for i in range(4):
    var g=game.model.customers[i];var r=game.service_guests[int(g.id)];var st=game.staff_states[i];var table=game.model.get_item(int(g.table_id))
    var action="collecting" if kind=="cleanup" else "serving"
    game._service_contact(st,i,action,table,phase)
    var payload=game._staff_payload(st,i);game._set_staff_art(st,action,table,phase,payload)
    var expected="dishes" if kind=="cleanup" and phase>=.65 else ("plate" if kind=="deliver_meal" and phase<.65 else ("drink" if kind=="deliver_drink" and phase<.65 else "none"))
    check(payload==expected,"Held prop does not switch once at authoritative contact beat")
    check(r.plate_owner==("staff" if (kind=="cleanup" and phase>=.65) or (kind=="deliver_meal" and phase<.65) else "table"),"Table/hand plate ownership mismatch")
    var layout=Placement.layout(game.illustration._table_guest_direction(int(table.id)))
    check(game.illustration._table_surface_point(int(table.id))==layout.plate and game.illustration._table_surface_point(int(table.id),true)==layout.cup,"Service and visible tableware anchors differ")
   game.paused=false;game.illustration.update_motion(1.0);game.paused=true
   await capture(kind+("-before" if phase<.65 else "-after"))
   check(JSON.stringify({"items":game.model.items,"positions":game.model.customers.map(func(g):return [g.x,g.z]),"staff":game.staff_states.map(func(st):return st.pos),"coins":game.model.coins})==immutable,"Visual contact changes logical positions or wallet")
 for i in range(4):
  var g=game.model.customers[i];var st=game.staff_states[i];var r=game.service_guests[int(g.id)]
  r.plate_owner="cleared";r.drink_owner="cleared";r.dishes_collected=true
  game._set_staff_art(st,"wiping",game.model.get_item(int(g.table_id)),.5,"none")
 game.paused=false;game.illustration.update_motion(1.0);game.paused=true
 await capture("wiping-plane")
 check(game.saves==0,"Service capture writes a save")
 var output=OS.get_environment("OUTPUT")
 if output!="":FileAccess.open(output+"/service-handoffs.json",FileAccess.WRITE).store_string(JSON.stringify(report,"  "))
 print("DINING_SERVICE_RESULT ",JSON.stringify({"checks":checks,"failures":failures,"save_calls":game.saves,"states":report.size(),"plane_height":Placement.TABLE_HEIGHT,"handoff":"Existing symbolic ownership beat; held props remain attached to carry hands"}))
 for player in game.audio_players.values():player.stop();player.stream=null
 game.settings_controls.sfx_player.stop();game.settings_controls.sfx_player.stream=null
 for tween in get_processed_tweens():tween.kill()
 game.queue_free();await process_frame;quit(0 if failures.is_empty() else 1)
