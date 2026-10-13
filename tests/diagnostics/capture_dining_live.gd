extends SceneTree
class TestMain extends "res://scripts/main.gd":
 var saves=0
 func _load_startup():save_writes_suppressed=true;fresh_start=false;model.reset_new();paused=true
 func _save():saves+=1;return true
var game
var report=[]
func _initialize():run.call_deferred()
func capture(label):
 game._update_ui();game.illustration.queue_redraw()
 for frame in 4:await process_frame
 await RenderingServer.frame_post_draw
 root.get_texture().get_image().save_png(OS.get_environment("OUTPUT")+"/live-"+label+".png")
 var contacts=[]
 for p in game.illustration.render_contacts:
  if not p.staff:contacts.append({"id":p.id,"action":p.action,"progress":p.progress,"dining_pose":p.get("dining_pose",{})})
 report.append({"label":label,"paused":game.paused,"saves":game.saves,"contacts":contacts})
func run():
 root.size=Vector2i(1800,1200);game=TestMain.new();root.add_child(game);game.set_process(false)
 await process_frame;game.illustration.set_process(false)
 game.model.operating_open=true;game.model._spawn_customer();game.model.operating_open=false
 var template=game.model.customers[0].duplicate(true)
 game.model.customers.clear();game.service_guests.clear()
 game.model.items=game.model.items.filter(func(item):return item.kind not in ["table","chair"])
 var tables=[Vector2i(4,6),Vector2i(8,6),Vector2i(4,10),Vector2i(8,10)]
 var directions=[Vector2i.RIGHT,Vector2i.DOWN,Vector2i.UP,Vector2i.LEFT]
 for i in range(4):
  var chair=tables[i]-directions[i]
  game.model.items.append({"id":100+i*2,"kind":"table","x":tables[i].x,"z":tables[i].y,"rot":0})
  game.model.items.append({"id":101+i*2,"kind":"chair","x":chair.x,"z":chair.y,"rot":[1,2,0,3][i]})
  var guest=template.duplicate(true)
  guest.id=i*3;guest.table_id=100+i*2;guest.chair_id=101+i*2;guest.x=chair.x+.5;guest.z=chair.y+.5
  guest.phase="eating";guest.elapsed=0.0;guest.duration=6.0;guest.seated=true;guest.admitted=true;guest.waiting=false;guest.route=[];guest.route_index=0;guest.heading=Vector2(directions[i]);guest.dismounting=false
  game.model.customers.append(guest)
 game._sync_service_guests()
 game.illustration._update_meal_docking(0.0)
 for guest in game.model.customers:
  var record=game.service_guests[int(guest.id)];record.plate_owner="table";record.drink_owner="table";record.drink_done=true;record.dishes_collected=false
  var direction:Vector2=guest.heading;var key="guest_%s"%guest.id
  game.illustration.stance_offsets[key]=game.illustration._guest_seated_offset(guest,Vector2(guest.x,guest.z))
  game.illustration.seat_blends[int(guest.id)]=1.0
  game.illustration.character_facings[key]={"back":direction.x+direction.y<0,"mirror":-1.0 if direction.x-direction.y<0 else 1.0}
 for staff in game.staff_states:staff.on_duty=false
 game._rebuild_furniture();game._update_people();game.editing=false;game.paused=true
 game.illustration.zoom=2.1;game.illustration.pan_offset=Vector2.ZERO;game.illustration.update_projection(false)
 game.illustration.pan_offset+=Vector2(900,660)-game.illustration.iso(6.5,8.5)
 game.illustration.update_projection(false)
 var stages=[.235/4.0,.4/4.0,.61/4.0,.25,.4875,.805,.82,.995]
 for i in range(stages.size()):
  for guest in game.model.customers:guest.elapsed=stages[i]*6.0
  await capture(["scoop","lift","chew","interbite-rest","interbite-return","last-scoop","used-while-chewing","finished"][i])
 for guest in game.model.customers:guest.phase="checkout_wait";guest.elapsed=0.0
 game.paused=false
 for frame in range(21):
  game.illustration.update_motion(1.0/60.0)
  if frame in [0,8,20]:await capture("undock-"+str(frame))
 game.paused=true
 FileAccess.open(OS.get_environment("OUTPUT")+"/live-capture.json",FileAccess.WRITE).store_string(JSON.stringify(report,"  "))
 print("DINING_LIVE_RESULT facings=4 phases=11 paused=true save_calls=",game.saves)
 for player in game.audio_players.values():player.stop();player.stream=null
 game.settings_controls.sfx_player.stop();game.settings_controls.sfx_player.stream=null
 for tween in get_processed_tweens():tween.kill()
 game.queue_free();await process_frame;quit()
