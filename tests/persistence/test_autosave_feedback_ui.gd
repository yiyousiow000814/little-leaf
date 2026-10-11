extends SceneTree
## Existing Help/Settings state checks; no player save or new global channel.
const WebSave=preload("res://scripts/cafe_web_save.gd")
const NoBottom=preload("res://tests/no_bottom_notifications.gd")
class FakeApi extends RefCounted:
 func creditForSave(_payload):return 0
 func save(_payload,_revision,_profile,_callback):pass
var checks=0
var failures=[]
func check(ok:bool,label:String):
 checks+=1
 if not ok:failures.append(label);printerr("FAIL ",label)
func _init():call_deferred("run")
func settle(game):
 game._update_ui()
 await process_frame;await process_frame
func ack(save):save._on_commit([JSON.stringify({"ok":true,"profileId":"synthetic-ui","revision":save.revision+1,"durable":true,"creditedCoins":0})])
func run():
 root.size=Vector2i(1360,880)
 var game=load("res://main.tscn").instantiate();root.add_child(game)
 game.set_process(false);game.paused=true
 await settle(game)
 var save=WebSave.new(game);save.ready=true;save.profile_id="synthetic-ui";save.api=FakeApi.new();game.web_save=save;game.save_writes_suppressed=false
 save.request_save();await settle(game)
 check(save.pending and game.progress_unsaved and game._unsaved_progress_message()=="","normal pending save has no error detail")
 check(not game.compact_ui.has_open_popup(),"pending save opens no popup")
 NoBottom.verify(game,check,"pending save")
 ack(save);await settle(game)
 check(not game.progress_unsaved and not game.compact_ui.has_open_popup(),"durable success clears state without a popup")
 for size in [Vector2i(1360,880),Vector2i(960,540),Vector2i(390,844)]:
  root.size=size;await settle(game)
  save.request_save();save._on_commit([JSON.stringify({"ok":false,"code":"QUOTA","error":"Browser storage is full"})]);await settle(game)
  check(not game.compact_ui.has_open_popup(),"transient failure opens no replacement notification "+str(size))
  var warning=game._unsaved_progress_message()
  check("Keep this page open; saving will retry" in warning,"failure retains actionable details "+str(size))
  game.settings.show();await settle(game)
  check(game._unsaved_progress_message()==warning,"opening Settings retains error state "+str(size))
  game.compact_ui.settings_help.pressed.emit();await settle(game)
  check(game.compact_ui.help_panel.visible and not game.settings.visible,"Settings opens existing Help "+str(size))
  check(warning in game.compact_ui.help_text.text,"Help displays genuine save error and retry guidance "+str(size))
  check(Rect2(Vector2.ZERO,Vector2(size)).encloses(game.compact_ui.help_panel.get_global_rect()),"existing Help stays within viewport "+str(size))
  game.compact_ui._close_help();await settle(game)
  check(game.settings.visible and game._unsaved_progress_message()==warning,"Help returns to Settings without clearing failure "+str(size))
  game.settings.hide();save.request_save();await settle(game)
  check(game._unsaved_progress_message()==warning and not game.compact_ui.has_open_popup(),"retry retains details without a popup "+str(size))
  game.compact_ui.show_help();await settle(game)
  check(warning in game.compact_ui.help_text.text,"retry detail remains in already-open Help "+str(size))
  ack(save);await settle(game)
  check(game._unsaved_progress_message()=="" and not game.progress_unsaved,"durable recovery clears error "+str(size))
  check(game.compact_ui.help_panel.visible and not "Browser storage is full" in game.compact_ui.help_text.text,"already-open Help clears recovered error without reopening "+str(size))
  game.compact_ui._close_help();await settle(game)
  NoBottom.verify(game,check,"save recovery "+str(size))
 root.size=Vector2i(1360,880);await settle(game)
 game.settings.show()
 var preferences=game.settings_controls.WebPreferences.new();game.settings_controls.web_preferences=preferences
 preferences.last_error="Synthetic preferences quota";await settle(game)
 check(game.settings_controls.preference_storage_note.is_visible_in_tree() and "Synthetic preferences quota" in game.settings_controls.preference_storage_note.text,"existing Settings note exposes browser preference failure")
 check(not game.compact_ui.help_panel.visible,"preference failure does not open Help")
 preferences.last_error="";await settle(game)
 check(not game.settings_controls.preference_storage_note.visible,"durable preference recovery clears its existing Settings note")
 game.settings_controls.web_preferences=null;game.settings.hide();await settle(game)
 save.request_save();save._on_commit([JSON.stringify({"ok":false,"code":"REVISION_CONFLICT","error":"Original progress preserved"})]);await settle(game)
 check(game.save_recovery_blocked and game.progress_unsaved and not save.ready,"hard failure keeps fail-closed guards")
 check(not game.compact_ui.has_open_popup(),"hard commit failure opens no replacement global notification")
 check("Quick help" in game._unsaved_progress_message() and not "will retry" in game._unsaved_progress_message(),"hard failure never promises unsafe automatic retry")
 game.compact_ui.show_help();await settle(game)
 check(game.compact_ui.help_panel.visible,"existing hard failure Help can be opened")
 check("Original progress preserved" in game.compact_ui.help_text.text,"Help retains exact hard failure details")
 NoBottom.verify(game,check,"hard failure Help")
 game.save_writes_suppressed=true;game.web_save=null;save.stop();save=null
 for player in game.audio_players.values():player.stop();player.stream=null
 game.settings_controls.sfx_player.stop();game.settings_controls.sfx_player.stream=null
 for tween in get_processed_tweens():tween.kill()
 game.queue_free();await process_frame;await process_frame
 print("AUTOSAVE_UI_RESULT ",JSON.stringify({"checks":checks,"failures":failures,"rendered_pixels_verified":false}))
 quit(0 if failures.is_empty() else 1)
