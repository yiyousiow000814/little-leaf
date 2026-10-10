extends SceneTree
## Synthetic game viewport only: no desktop capture or real player profile.
const Fixture=preload("res://tests/role_fixture.gd")
var game
var facts={"synthetic":true,"viewport":[1360,880],"player_save_used":false,"states":[]}
func _initialize():run.call_deferred()
func capture(label:String):
 game._update_ui();game.illustration._process(.1);game.illustration.queue_redraw()
 for frame in 5:await process_frame
 await RenderingServer.frame_post_draw
 root.get_texture().get_image().save_png(OS.get_environment("OUTPUT")+"/"+label+".png")
 facts.states.append({"label":label,"queue":game.dishwashing.snapshot() if "dishwashing" in game else {},"staff":game.staff_states.map(func(w):return {"role":w.role,"action":w.art_action,"elapsed":w.job_elapsed,"position":str(w.pos)})})
func run():
 seed(472);root.size=Vector2i(1360,880)
 DisplayServer.window_set_title("Little Leaf dishwashing QA")
 game=Fixture.new();root.add_child(game);await process_frame
 game.set_process(false);game.illustration.set_process(false)
 game.illustration.zoom=1.35;game.illustration.pan_offset=Vector2(-140,95);game.illustration.update_projection()
 var r=game.setup_dirty(false)
 var newer="dishwashing" in game
 game.worker("cleaner").on_duty=newer
 var reached=false
 for tick in 1600:
  game.advance()
  var worker=game.worker("cleaner" if newer else "waiter")
  if worker.art_action=="washing" and worker.job_elapsed>=(5.0 if newer else .9):reached=true;break
  if tick%150==0:await process_frame
 assert(reached,"Actual service route must reach washing")
 await capture("after-cleaner-washing" if newer else "before-waiter-washing")
 if newer:
  # Queue quantities below are deliberately seeded fixture state. The same
  # production rendering draws one tier for each pending/currently washed dish.
  var sink_id=int(game.worker("cleaner").station_id)
  for n in 5:
   var id=game.dishwashing.next_id;game.dishwashing.next_id+=1
   game.dishwashing.dishes[id]={"id":id,"sink_id":sink_id,"elapsed":0.0}
  await capture("after-six-dish-stack")
  assert(game.model.place("sink",7,1,0),game.model.last_error)
  var second_id=int(game.model.items[-1].id)
  var id=game.dishwashing.next_id;game.dishwashing.next_id+=1
  game.dishwashing.dishes[id]={"id":id,"sink_id":second_id,"elapsed":0.0}
  game._rebuild_furniture()
  await capture("after-two-sinks")
 FileAccess.open(OS.get_environment("OUTPUT")+"/capture.json",FileAccess.WRITE).store_string(JSON.stringify(facts,"  "))
 print("DISHWASHING_NATIVE_CAPTURE ",JSON.stringify(facts))
 for player in game.audio_players.values():player.stop();player.stream=null
 game.settings_controls.sfx_player.stop();game.settings_controls.sfx_player.stream=null
 for tween in get_processed_tweens():tween.kill()
 game.queue_free();await process_frame;await process_frame;quit()
