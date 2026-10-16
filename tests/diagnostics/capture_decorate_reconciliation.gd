extends SceneTree
## Same generated natural-service scene on the retained coordinator and candidate.
## No renderer overrides; assertions/receipts describe the actual controller calls.
class Fixture extends "res://scripts/main.gd":
 func _load_startup():save_writes_suppressed=true;fresh_start=true;MinimalStart.apply(model)
var game
var states=[]
func _initialize():run.call_deferred()
func snapshot(label:String)->Dictionary:
 var workers=[]
 for worker in game.staff_states:workers.append({"role":worker.role,"job":worker.job_kind,"step":worker.job_step,"elapsed":worker.job_elapsed,"token":worker.job_token,"station_id":worker.station_id})
 return {"label":label,"coins":game.model.coins,"editing":game.editing,"items":game.model.items.duplicate(true),"customers":game.model.customers.duplicate(true),"workers":workers,"service":game._service_save_snapshot(),"selected_id":game.selected_id,"sell_disabled":game.compact_ui.remove_button.disabled}
func capture(label:String):
 game._update_people();game._update_ui();game.illustration.queue_redraw()
 for frame in 8:await process_frame
 await RenderingServer.frame_post_draw
 var path=OS.get_environment("OUTPUT")+"/"+label+".png"
 assert(root.get_texture().get_image().save_png(path)==OK)
 var state=snapshot(label);state.path=path;states.append(state)
func run():
 assert("saveguard" in OS.get_user_data_dir() and OS.get_environment("OUTPUT")!="")
 seed(472);root.size=Vector2i(1360,880)
 game=Fixture.new();root.add_child(game);game.set_process(false);game.illustration.set_process(false)
 if game.cafe_intro!=null:game.cafe_intro.finish()
 game.model.coins=10000;game.model.first_guest_pending=false;game.model._spawn_walkers(1)
 var phase=OS.get_environment("CAPTURE_PHASE");var found=false
 for tick in 6000:
  game.model._arrival_elapsed=0.0
  if game.model.customers.any(func(g):return g.phase=="ordering"):game.model.operating_open=false
  game._tick_live_service(.1);game._animate_staff(.1);game.animation_time+=.1;game.illustration.update_motion(.1)
  for worker in game.staff_states:
   if phase=="stove" and worker.job_kind=="cook" and int(worker.job_step)==1 and float(worker.job_elapsed)>.5:found=true
   if phase=="sink" and worker.job_kind=="wash" and float(worker.job_elapsed)>1.0:found=true
  if found:break
  if tick%250==0:await process_frame
 assert(found)
 game.illustration.zoom=1.0;game.illustration.update_projection()
 game._toggle_edit();game.compact_ui._set_tray_reveal(1)
 var target=game.model.items.filter(func(item):return item.kind==phase)[0].duplicate(true)
 game.selected_id=int(target.id);await capture(phase+"-before-sell")
 game._sell();await capture(phase+"-after-sell")
 if game.has_method("_publish_layout_plan"):
  assert(game.model.get_item(int(target.id)).is_empty())
  game._toggle_edit();assert(not game.editing)
  for tick in 30:game._tick_live_service(.1);game._animate_staff(.1)
  game.model.service_snapshot=game._service_save_snapshot()
  assert(game.model.save("user://capture-held.json"))
  assert(game.model.load_save("user://capture-held.json"));game._restore_service_runtime()
  await capture(phase+"-held-after-reload")
  game._toggle_edit()
  var planner=game.interaction.edit_plan
  var quote=planner.prepare(game.model,phase,-1,int(target.rot),Vector2i(target.x,target.z),[],1)
  assert(quote.ok and planner.commit(game.model,quote))
  game._toggle_edit();assert(not game.editing)
  await capture(phase+"-rebound-progress")
  for tick in 10:game._tick_live_service(.1);game._animate_staff(.1);game.animation_time+=.1;game.illustration.update_motion(.1)
  await capture(phase+"-resumed-work")
 var facts={"synthetic":true,"player_save_used":false,"normal_save_writes_suppressed":game.save_writes_suppressed,"viewport":[1360,880],"zoom":1.0,"states":states}
 FileAccess.open(OS.get_environment("OUTPUT")+"/"+phase+"-capture.json",FileAccess.WRITE).store_string(JSON.stringify(preload("res://scripts/persistence/cafe_runtime_codec.gd").new().encode(facts),"  "))
 print("DECORATE_NATIVE_CAPTURE ",phase," states=",states.size())
 for player in game.audio_players.values():player.stop();player.stream=null
 game.settings_controls.sfx_player.stop();game.settings_controls.sfx_player.stream=null
 for tween in get_processed_tweens():tween.kill()
 game.queue_free();await process_frame;await process_frame;quit()
