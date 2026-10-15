extends SceneTree
const AudioDrain = preload("res://tests/fixtures/audio_mixer_drain.gd")
var game
var checks=0
var failures=[]
func check(ok:bool,label:String):
 checks+=1
 if not ok:failures.append(label);printerr("FAIL ",label)
func _initialize():run.call_deferred()
func run():
 game=load("res://main.tscn").instantiate();root.add_child(game)
 await process_frame
 game.set_process(false);game.paused=true
 for view in [Vector2i(1360,880),Vector2i(960,540),Vector2i(800,600),Vector2i(640,480),Vector2i(390,844)]:
  root.size=view
  for active in [false,true]:
   var wallet=game.model.coins;var layout=game.model.items.duplicate(true)
   game._toggle_edit()
   check(game.editing and game.model.decoration_session_active,str(view)+" enters a real Decorate session")
   game.selected_kind="plant" if active else ""
   game._update_ui()
   for frame in range(4):await process_frame
   var hud=game.compact_ui.hud
   var button_center=hud.edit_cancel.get_global_rect().get_center()
   var glyph_center=hud.cancel_art.get_global_transform()*(hud.cancel_art.size/2)
   check(glyph_center.distance_to(button_center)<0.01,str(view)+" glyph center matches button center")
   check(is_equal_approx(hud.cancel_art.rotation,PI/4),str(view)+" preserves rotated plus artwork")
   check(not hud.edit_cancel.disabled,str(view)+" session Cancel remains enabled with or without selection")
   for pressed in [true,false]:
    var click=InputEventMouseButton.new();click.position=button_center;click.global_position=button_center;click.button_index=MOUSE_BUTTON_LEFT;click.pressed=pressed;root.push_input(click,true)
   await process_frame
   check(game.selected_kind=="",str(view)+" centered click clears current selection")
   check(not game.editing and not game.model.decoration_session_active,str(view)+" centered click cancels the whole session")
   check(game.model.coins==wallet and game.model.items==layout,str(view)+" Cancel preserves baseline wallet and layout")
 var report={"checks":checks,"failures":failures}
 for player in game.audio_players.values():player.stop();player.stream=null
 game.settings_controls.sfx_player.stop();game.settings_controls.sfx_player.stream=null
 for tween in get_processed_tweens():tween.kill()
 game.queue_free();await process_frame
 var audio_drain = await AudioDrain.wait_for_mixer_cycles(self)
 check(audio_drain.ok, "audio teardown observes two mixer cycles within 1s")
 print("AUDIO_TEARDOWN_RESULT ", JSON.stringify(audio_drain))
 report.checks=checks;report.failures=failures
 print("CANCEL_ICON_RESULT ",JSON.stringify(report))
 quit(0 if failures.is_empty() else 1)
