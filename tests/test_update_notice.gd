extends SceneTree
const WebSave=preload("res://scripts/cafe_web_save.gd")
const Notice=preload("res://scripts/cafe_update_notice.gd")
class TestMain extends "res://scripts/main.gd":
 var saves=0
 func _load_startup():save_writes_suppressed=true;fresh_start=true;MinimalStart.apply(model)
 func _save():saves+=1;return true
class UpdateApi extends RefCounted:
 var value={"available":true,"version":"0.1.11","busy":false,"reason":""}
 var starts=0
 var closes=0
 var dismissed=[]
 var reloads=0
 var callback:Callable
 func start(version):starts+=1
 func close():closes+=1
 func snapshot():return JSON.stringify(value)
 func dismiss(version):dismissed.append(version);value.available=false
 func reloadForUpdate(version,profile_id,revision,token,fn):reloads+=1;callback=fn
 func finish(result):callback.call([JSON.stringify(result)])
class Vault extends RefCounted:
 var value={"serverOwnership":true,"status":"active","ownershipPaused":false,"choicesAvailable":false}
 var calls=0
 var callback:Callable
 var payload=""
 func recoverySnapshot():return JSON.stringify(value)
 func saveForUpdate(data,revision,profile_id,fn):calls+=1;payload=data;callback=fn
 func finish(result):callback.call([JSON.stringify(result)])
class Controller extends WebSave:
 var fake_update=UpdateApi.new()
 var fake_vault=Vault.new()
 func _update_bridge():return fake_update
 func _recovery_bridge():return fake_vault
 func _make_recovery_callback(handler:Callable):return handler
 func check_runtime_recovery():pass
var game
var checks=0
var failures=[]
var geometry=[]
func _initialize():run.call_deferred()
func check(ok:bool,label:String):
 checks+=1
 if not ok:failures.append(label);printerr("FAIL ",label)
func settle():
 game._update_ui()
 for frame in 8:await process_frame
func run():
 root.size=Vector2i(390,844)
 game=TestMain.new();root.add_child(game);game.set_process(false);await process_frame
 var ui=game.compact_ui;var controller=Controller.new(game);controller.ready=true;controller.profile_id="synthetic";controller.revision=8;game.web_save=controller;game.save_writes_suppressed=false
 check(game.model.load_save("res://tests/fixtures/startup-retry-v15.json"),"generated save fixture validates")
 game._resume_loaded_cafe()
 ui.update_notice.panel.queue_free();var notice=Notice.new(ui);ui.update_notice=notice;notice.setup(controller.fake_update)
 await settle();check(controller.fake_update.starts==1 and notice.panel.visible,"one startup binds packed version and displays availability")
 for view in [Vector2i(390,844),Vector2i(344,680),Vector2i(844,390),Vector2i(566,360),Vector2i(1360,880)]:
  root.size=view;game.set_meta("hud_safe_insets",Vector4(8,20,8,16) if view==Vector2i(844,390) else Vector4.ZERO)
  for error in [false,true]:
   controller.update_message="Your progress is on this device. Cloud confirmation is still needed before updating." if error else ""
   await settle();var insets=ui.hud._safe_insets();var safe=Rect2(insets.x,insets.y,view.x-insets.x-insets.z,view.y-insets.y-insets.w)
   check(safe.encloses(notice.panel.get_global_rect()),str(view)+" update panel fits safe viewport "+str(notice.panel.get_global_rect())+" / "+str(safe))
   check(absf(notice.update_button.size.x-notice.later_button.size.x)<1,str(view)+" equal button widths")
   for button in [notice.update_button,notice.later_button]:
    var glyph=button.get_theme_font("font").get_string_size(button.text,HORIZONTAL_ALIGNMENT_LEFT,-1,button.get_theme_font_size("font_size")).x
    check(button.size.y>=44 and button.size.x>=glyph+24,str(view)+" touch target and text padding")
    check(notice.panel.get_global_rect().encloses(button.get_global_rect()),str(view)+" button stays inside panel")
   var buttons={}
   for key in ["update","later"]:
    var button=notice.update_button if key=="update" else notice.later_button
    var rect=button.get_global_rect();buttons[key]=[rect.position.x,rect.position.y,rect.size.x,rect.size.y]
   geometry.append({"viewport":{"width":view.x,"height":view.y},"error":error,"buttons":buttons})
 notice.later_button.pressed.emit();await settle();check(not notice.panel.visible and controller.fake_update.dismissed==["0.1.11"],"Later dismisses exact version")
 for frame in 5:notice.sync()
 check(not notice.panel.visible,"same dismissed version never reopens")
 controller.fake_update.value.available=true;controller.fake_update.value.version="0.1.12";controller.update_message="";game.paused=false;await settle()
 game.editing=true;game.selected_id=1
 var input_before=game.is_processing_input();var unhandled_before=game.is_processing_unhandled_input();var gui_before=root.gui_disable_input
 var model=game.model;var coins=game.model.coins
 var items=JSON.stringify(game.model.items)
 notice.update_button.pressed.emit();notice.update_button.pressed.emit();await settle()
 check(controller.fake_vault.calls==1 and controller.update_busy,"repeated Update click saves once")
 check(game.paused and game.save_recovery_blocked and game.save_writes_suppressed,"Update click freezes before async save")
 check(not game.is_processing_input() and not game.is_processing_unhandled_input() and root.gui_disable_input,"world and GUI input held before snapshot")
 var rotate=InputEventKey.new();rotate.keycode=KEY_R;rotate.pressed=true
 Input.parse_input_event(rotate)
 var click=InputEventMouseButton.new();click.button_index=MOUSE_BUTTON_LEFT;click.position=ui.remove_button.get_global_rect().get_center();click.pressed=true;Input.parse_input_event(click)
 var release=InputEventMouseButton.new();release.button_index=MOUSE_BUTTON_LEFT;release.position=click.position;release.pressed=false;Input.parse_input_event(release);Input.flush_buffered_events()
 game.interaction.handle_input(rotate);game.interaction.rotate_selection();game.interaction._commit_preview();game._upgrade();game._sell()
 ui._rotate_selected.call_deferred();ui._remove_selected.call_deferred();await settle()
 check(JSON.stringify(game.model.items)==items and game.model.coins==coins,"post-freeze R, drag commit, upgrade and deferred GUI removal cannot mutate model")
 check(notice.later_button.disabled and notice.update_button.disabled,"busy save cannot be dismissed or repeated")
 check(JSON.parse_string(controller.fake_vault.payload).coins==coins,"frozen latest wallet enters validated save")
 controller.fake_vault.finish({"ok":true,"durable":true,"profileId":"synthetic","revision":9,"cloudConfirmed":false});await settle()
 check(controller.revision==9 and controller.fake_update.reloads==0 and not controller.update_busy,"local durability advances revision but never reloads without cloud acknowledgment")
 check(game.model==model and not game.save_recovery_blocked,"safe current owner retains model and resumes on cloud failure")
 check(game.is_processing_input()==input_before and game.is_processing_unhandled_input()==unhandled_before and root.gui_disable_input==gui_before,"safe failure restores exact prior input state")
 notice.update_button.pressed.emit();var saved_callback=controller.fake_vault.callback
 controller.fake_vault.finish({"ok":true,"durable":true,"profileId":"synthetic","revision":10,"cloudConfirmed":true,"updateToken":"one-use-token"});await settle()
 check(controller.fake_update.reloads==1 and controller.update_busy and game.save_recovery_blocked,"cloud-confirmed receipt enters final gate while still frozen")
 game.interaction.rotate_selection();game._upgrade();ui._remove_selected.call_deferred();await settle()
 check(JSON.stringify(game.model.items)==items and game.model.coins==coins and root.gui_disable_input,"delayed final gate cannot lose new edits")
 saved_callback.call([JSON.stringify({"ok":true,"durable":true,"profileId":"synthetic","revision":10,"cloudConfirmed":true,"updateToken":"one-use-token"})]);check(controller.fake_update.reloads==1 and controller.update_busy,"duplicate save callback cannot reopen play or reload twice")
 controller.fake_vault.value.status="other-device";controller.fake_vault.value.ownershipPaused=true
 controller.fake_update.finish({"ok":false,"code":"OWNERSHIP_LOST"});await settle()
 check(not controller.update_busy and game.save_recovery_blocked and game.model==model,"lost-owner gate failure never refreshes or resumes stale model")
 check(not game.is_processing_input() and root.gui_disable_input==gui_before,"unsafe failure keeps world frozen but allows recovery GUI")
 game.interaction.rotate_selection();game.interaction._commit_preview();game._upgrade();game._sell();ui._rotate_selected();ui._remove_selected()
 check(JSON.stringify(game.model.items)==items and game.model.coins==coins,"recovery GUI cannot mutate protected model after unsafe failure")
 controller._release_update_input()
 controller.fake_vault.value.status="active";controller.fake_vault.value.ownershipPaused=false;game.save_recovery_blocked=false;game.save_writes_suppressed=false
 controller.save_and_update("0.1.12");var late_save=controller.fake_vault.callback;controller.stop()
 check(controller.fake_update.closes==1 and not controller.update_busy,"native stop closes update manager and releases operation")
 late_save.call([JSON.stringify({"ok":true,"durable":true,"profileId":"synthetic","revision":11,"cloudConfirmed":true,"updateToken":"late"})])
 check(controller.fake_update.reloads==1,"late save completion after stop cannot request reload")
 check(game.saves==0,"notice does not use ordinary uncontrolled save path")
 game.web_save=null;game.save_writes_suppressed=true
 print("UPDATE_NOTICE_RESULT ",JSON.stringify({"checks":checks,"failures":failures,"player_save_used":false,"real_browser":false,"geometry":geometry}))
 for player in game.audio_players.values():player.stop();player.stream=null
 game.settings_controls.sfx_player.stop();game.settings_controls.sfx_player.stream=null
 for tween in get_processed_tweens():tween.kill()
 game.queue_free();await process_frame;quit(0 if failures.is_empty() else 1)
