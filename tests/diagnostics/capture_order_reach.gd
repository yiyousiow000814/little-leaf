extends SceneTree
const Fixture=preload("res://tests/fixtures/order_reach_fixture.gd")
var game
var states=[]
func _initialize():run.call_deferred()
func capture(label):
 game._update_people();game._update_ui();game.illustration.queue_redraw()
 for frame in 4:await process_frame
 await RenderingServer.frame_post_draw
 var path=OS.get_environment("OUTPUT")+"/"+label+".png"
 assert(root.get_texture().get_image().save_png(path)==OK)
 var state=game.snapshot();state.label=label;state.path=path;states.append(state)
func run():
 seed(472);root.size=Vector2i(1360,880)
 assert(OS.get_environment("OUTPUT")!="")
 game=Fixture.new();root.add_child(game);game.set_process(false);game.illustration.set_process(false)
 if game.cafe_intro!=null:game.cafe_intro.finish()
 game.setup();game.paused=false
 if OS.get_environment("ORDER_REACH_IDLE_CHEF")=="1":game.setup_idle_chef()
 if OS.get_environment("ORDER_REACH_TARGETLESS_COOK")=="1":game.setup_targetless_cook()
 game.illustration.zoom=1.7;game.illustration.update_projection()
 game.illustration.pan_offset+=Vector2(680,490)-game.illustration.iso(5.5,5.5);game.illustration.update_projection()
 # Identical scene, clock, route/gesture updates and camera on both sources.
 for tick in range(120):
  game._animate_staff(.05);game.animation_time+=.05;game.illustration.update_motion(.05)
  if tick==49:await capture("order-at-2.5s")
  if tick%20==0:await process_frame
 await capture("order-at-6s")
 var facts={"synthetic":true,"player_save_used":false,"save_writes_suppressed":game.save_writes_suppressed,"viewport":[1360,880],"zoom":1.7,"states":states}
 FileAccess.open(OS.get_environment("OUTPUT")+"/capture.json",FileAccess.WRITE).store_string(JSON.stringify(facts,"  "))
 print("ORDER_REACH_NATIVE ",JSON.stringify(facts))
 for player in game.audio_players.values():player.stop();player.stream=null
 game.settings_controls.sfx_player.stop();game.settings_controls.sfx_player.stream=null
 for tween in get_processed_tweens():tween.kill()
 game.queue_free();await process_frame;await process_frame;quit()
