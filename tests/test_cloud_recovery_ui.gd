extends SceneTree
## Native recovery controls, fake JS boundary, generated café and isolated files only.
const WebSave=preload("res://scripts/cafe_web_save.gd")
class TestMain extends "res://scripts/main.gd":
 var saves=0
 var resumes=0
 func _load_startup():save_writes_suppressed=true;fresh_start=true;MinimalStart.apply(model)
 func _save():saves+=1;return true
 func _resume_loaded_cafe():resumes+=1;compact_ui.help_panel.hide();_update_ui()
class Bridge extends RefCounted:
 var value={"available":true,"busy":false,"canExport":true,"cloudRevision":8,"pendingRevision":6,"expectedCloudDigest":"aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa","reason":""}
 var recover_calls=0
 var export_calls=0
 var callback:Callable
 func recoverySnapshot():return JSON.stringify(value)
 func recoverCloud(fn):recover_calls+=1;callback=fn
 func exportRecovery(fn):export_calls+=1;callback=fn
 func finish(value):callback.call([JSON.stringify(value)])
class Controller extends WebSave:
 var bridge=Bridge.new()
 func _recovery_bridge():return bridge
 func _make_recovery_callback(handler:Callable):return handler
var game
var checks=0
var failures=[]
var records=[]
func _initialize():run.call_deferred()
func check(ok:bool,label:String):
 checks+=1
 if not ok:failures.append(label);printerr("FAIL ",label)
func settle():
 game._update_ui()
 for frame in 12:await process_frame
func run():
 root.size=Vector2i(390,844)
 game=TestMain.new();root.add_child(game);game.set_process(false);game.paused=true;await process_frame
 var ui=game.compact_ui;var controller=Controller.new(game);game.web_save=controller
 var bridge=controller.bridge;controller.startup_error="Synthetic conflicting pending café";game.save_recovery_blocked=true
 game.startup_notice="Saved café could not be opened. Another device has newer progress. Pending progress is preserved on this device; do not overwrite it. Original progress is unchanged."
 ui.show_help();await settle()
 check(ui.help_load_cloud.visible and ui.help_export_pending.visible and not ui.help_retry.visible,"verified recovery replaces looping Retry with explicit cloud choice")
 check("will not be overwritten" in ui.help_text.text and "Cloud save: 8" in ui.help_text.text,"recovery copy and cloud revision disclosed")
 for view in [Vector2i(390,844),Vector2i(344,680),Vector2i(844,390),Vector2i(566,360),Vector2i(1360,880)]:
  root.size=view;game.set_meta("hud_safe_insets",Vector4(8,20,8,16) if view==Vector2i(844,390) else Vector4.ZERO)
  for mode in ["cloud","loading","retry"]:
   var recover=mode!="retry"
   bridge.value.available=recover;bridge.value.canExport=recover;controller.retrying=mode=="loading";ui.show_help();await settle()
   var label="%s %s"%[str(view),mode]
   var inset=ui.hud._safe_insets();var safe=Rect2(inset.x,inset.y,view.x-inset.x-inset.z,view.y-inset.y-inset.w)
   check(safe.encloses(ui.help_panel.get_global_rect()),label+" Help inside safe viewport")
   var panel=ui.help_panel.get_global_rect();var style=ui.help_panel.get_theme_stylebox("panel")
   var inside=Rect2(panel.position+Vector2(style.get_margin(SIDE_LEFT),style.get_margin(SIDE_TOP)),panel.size-style.get_minimum_size())
   var actions=[ui.help_load_cloud,ui.help_export_pending,ui.help_retry,ui.help_overview,ui.help_notes,ui.help_done]
   for action in actions:
    if not action.visible:continue
    check(ui.help_footer.is_ancestor_of(action) and not ui.help_scroll.is_ancestor_of(action),label+" action outside text scroll")
    check(absf(action.size.x-ui.help_done.size.x)<1,label+" equal action widths")
    check(action.size.y>=44,label+" minimum touch height")
    var glyph_width=action.get_theme_font("font").get_string_size(action.text,HORIZONTAL_ALIGNMENT_LEFT,-1,action.get_theme_font_size("font_size")).x
    check(action.size.x>=glyph_width+24,label+" button text retains horizontal padding: "+action.text)
    check(inside.encloses(action.get_global_rect()),label+" action inside board: "+action.text)
   check(ui.help_scroll.size.y>=99,label+" details have readable scroll viewport")
   var footer=ui.help_footer.get_global_rect();ui.help_scroll.scroll_vertical=100000;await settle()
   check(ui.help_footer.get_global_rect().is_equal_approx(footer),label+" actions remain fixed at text end")
   check(ui.help_scroll.get_v_scroll_bar().value+ui.help_scroll.get_v_scroll_bar().page>=ui.help_scroll.get_v_scroll_bar().max_value-1,label+" all recovery text reachable")
   records.append({"view":str(view),"recovery":recover,"panel":str(panel),"footer":str(footer),"body_height":ui.help_scroll.size.y})
 controller.retrying=false;bridge.value.available=true;bridge.value.canExport=true;root.size=Vector2i(390,844);ui.show_help();await settle()
 var original=game.model;var old_notice=game.startup_notice
 ui.help_load_cloud.pressed.emit();ui.help_load_cloud.pressed.emit();await settle()
 check(bridge.recover_calls==1 and controller.recovery_busy,"repeated cloud clicks call bridge once")
 check(ui.help_load_cloud.disabled and ui.help_export_pending.disabled,"busy cloud recovery guards all recovery actions")
 var cancelled_callback=bridge.callback
 bridge.finish({"ok":false,"code":"RECOVERY_CANCELLED"});await settle()
 check(not controller.recovery_busy and game.model==original and game.startup_notice==old_notice,"cancel clears busy without altering model or error")
 ui.help_export_pending.pressed.emit();ui.help_export_pending.pressed.emit();await settle();check(bridge.export_calls==1,"repeated export clicks call bridge once")
 check(ui.help_export_pending.text=="Preparing export…" and ui.help_load_cloud.text=="Load cloud café","export never claims a cloud load is in progress")
 cancelled_callback.call([JSON.stringify({"ok":false,"code":"RECOVERY_CHANGED","error":"stale callback"})]);check(controller.recovery_busy and game.startup_notice==old_notice,"old recovery callback cannot finish a newer export")
 bridge.finish({"ok":true});await settle();check(game.model==original and game.save_recovery_blocked and "export prepared" in controller.recovery_message,"export does not unblock or replace café")
 ui.help_load_cloud.pressed.emit();bridge.finish({"ok":false,"code":"RECOVERY_CHANGED","error":"The cloud café changed. Review the updated details and confirm again."});await settle()
 check(game.model==original and game.save_recovery_blocked and not controller.ready,"changed cloud remains blocked")
 check("confirm again" in game.startup_notice and "Cloud café loaded" not in controller.recovery_message,"error has useful retry guidance and no false loaded message")
 var payload=FileAccess.get_file_as_string("res://tests/fixtures/startup-retry-v15.json");var corrupt=JSON.parse_string(payload);corrupt.items[0].x=9999
 ui.help_load_cloud.pressed.emit();bridge.finish({"ok":true,"source":"authority","profileId":"synthetic","revision":8,"payload":JSON.stringify(corrupt)});await settle()
 check(game.model==original and game.save_recovery_blocked and "Cloud café loaded" not in controller.recovery_message,"native validator rejects invalid returned cloud café")
 ui.help_load_cloud.pressed.emit();bridge.finish({"ok":true,"source":"authority","profileId":"synthetic","revision":8,"payload":payload});await settle()
 check(controller.ready and not game.save_recovery_blocked and game.model!=original and game.model.coins==42000,"native validator accepts exact valid saved café")
 bridge.finish({"ok":true,"source":"authority","profileId":"synthetic","revision":8,"payload":payload});check(game.resumes==1,"duplicate recovery callback cannot resume twice")
 check(game.resumes==1 and controller.profile_id=="synthetic" and controller.revision==8,"accepted receipt resumes once with matching identity")
 ui.show_help();await settle();check(ui.help_export_pending.visible and not ui.help_load_cloud.visible,"preserved pending café remains exportable after normal play resumes")
 bridge.value.available=false;bridge.value.reason="A different pending café is already preserved. Exporting does not remove the backup.";ui._sync_help_content();check("does not remove the backup" in ui.help_text.text,"full archive remains explicitly explained outside startup recovery")
 check(not bool(controller.recovery_snapshot().get("available",false)),"loaded café cannot be replaced by startup recovery")
 var calls=bridge.recover_calls;controller.recover_cloud();check(bridge.recover_calls==calls,"programmatic repeat cannot bypass loaded-café guard")
 check(game.saves==0,"recovery UI never submits a save")
 # Restore isolated guard before releasing the generated scene.
 game.save_writes_suppressed=true;game.web_save=null
 var result={"checks":checks,"failures":failures,"geometry":records,"player_save_used":false}
 print("CLOUD_RECOVERY_UI_RESULT ",JSON.stringify(result))
 for player in game.audio_players.values():player.stop();player.stream=null
 game.settings_controls.sfx_player.stop();game.settings_controls.sfx_player.stream=null
 for tween in get_processed_tweens():tween.kill()
 game.queue_free();await process_frame;quit(0 if failures.is_empty() else 1)
