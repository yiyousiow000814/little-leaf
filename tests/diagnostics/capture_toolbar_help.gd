extends SceneTree
## Actual GL rendered controls; generated café, isolated profile, no saved progress.
class TestMain extends "res://scripts/main.gd":
 var saves=0
 func _load_startup():save_writes_suppressed=true;fresh_start=true;MinimalStart.apply(model)
 func _save():saves+=1;return true
var game
var records=[]
func _initialize():run.call_deferred()
func settle():
 game._update_ui();game.illustration.queue_redraw()
 for frame in 8:await process_frame
 await RenderingServer.frame_post_draw
func shot(label:String):
 root.get_texture().get_image().save_png(OS.get_environment("OUTPUT")+"/"+OS.get_environment("PHASE")+"-"+label+".png")
func run():
 seed(8246);game=TestMain.new();root.add_child(game);game.set_process(false);game.paused=true
 await process_frame
 var ui=game.compact_ui;var hud=ui.hud
 var cases=[Vector2i(960,540),Vector2i(1360,880),Vector2i(390,844),Vector2i(566,360),Vector2i(640,480),Vector2i(344,680),Vector2i(565,700),Vector2i(566,700),Vector2i(960,599),Vector2i(960,600),Vector2i(606,400),Vector2i(390,844)]
 for index in cases.size():
  var view=cases[index];root.size=view
  var safe=index>=10;game.set_meta("hud_safe_insets",Vector4(8,20,8,16) if safe else Vector4.ZERO)
  game.editing=false;game.settings.hide();ui._hide_popups();await settle()
  var label="%dx%d%s"%[view.x,view.y,"-safe" if safe else ""]
  shot(label+"-toolbar")
  game.editing=true;await settle();shot(label+"-toolbar-edit")
  game.editing=false;await settle()
  game.settings.show();ui._show_help_from_settings();await settle()
  shot(label+"-help-top")
  var scroll:ScrollContainer
  if ui.help_panel.get_child(0) is ScrollContainer:scroll=ui.help_panel.get_child(0)
  else:scroll=ui.help_panel.get_child(0).get_child(1)
  scroll.scroll_vertical=100000;await settle();shot(label+"-help-bottom")
  records.append({"label":label,"toolbar":str(hud.layout_host.get_global_rect()),"help":str(ui.help_panel.get_global_rect()),"scroll":str(scroll.get_global_rect()),"footer":str(ui.help_done.get_global_rect()),"save_writes":game.saves,"save_writes_suppressed":game.save_writes_suppressed})
 FileAccess.open(OS.get_environment("OUTPUT")+"/"+OS.get_environment("PHASE")+"-geometry.json",FileAccess.WRITE).store_string(JSON.stringify(records,"  "))
 print("TOOLBAR_HELP_CAPTURE ",JSON.stringify(records))
 for player in game.audio_players.values():player.stop();player.stream=null
 game.settings_controls.sfx_player.stop();game.settings_controls.sfx_player.stream=null
 for tween in get_processed_tweens():tween.kill()
 game.queue_free();await process_frame;quit()
