extends SceneTree
## Native save-choice UI. Generated profile and synthetic JS boundary only.
const WebSave=preload("res://scripts/cafe_web_save.gd")
class TestMain extends "res://scripts/main.gd":
 var saves=0
 var resumes=0
 func _load_startup():save_writes_suppressed=true;fresh_start=true;MinimalStart.apply(model)
 func _save():saves+=1;return true
 func _resume_loaded_cafe():resumes+=1;compact_ui.help_panel.hide();_update_ui()
class Bridge extends RefCounted:
 var value={"available":true,"choicesAvailable":true,"busy":false,"expectedLocalDigest":"bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb","expectedCloudDigest":"aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa","choices":[{"id":"local","coins":42000,"lastSavedLabel":"9 Oct 2026, 04:35","device":"Android phone"},{"id":"cloud","coins":37000,"lastSavedLabel":"9 Oct 2026, 04:32","device":"Unknown device"}],"reason":""}
 var prepare_calls=0
 var confirm_calls=0
 var preserve_calls=0
 var switch_calls=0
 var finish_calls=0
 var callback:Callable
 func recoverySnapshot():return JSON.stringify(value)
 func prepareChoice(choice,local_digest,cloud_digest,fn):prepare_calls+=1;callback=fn
 func confirmChoice(token,fn):confirm_calls+=1;callback=fn
 func preserveRuntime(payload,revision,profile_id,fn):preserve_calls+=1;callback=fn
 func preserveOwnerRuntime(payload,revision,profile_id,fn):preserve_calls+=1;callback=fn
 func requestTakeover(fn):switch_calls+=1;callback=fn
 func finishTakeover(fn):finish_calls+=1;callback=fn
 func forceTakeover(fn):switch_calls+=1;callback=fn
 func finish(result):callback.call([JSON.stringify(result)])
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
 var bridge=controller.bridge;controller.startup_error="Synthetic save conflict";game.save_recovery_blocked=true
 ui.show_help();await settle()
 check(ui.help_choose_local.visible and ui.help_choose_cloud.visible and not ui.help_retry.visible,"genuine conflict offers both saves")
 check("Last saved" in ui.help_choice_labels.local.text and "Unknown device" in ui.help_choice_labels.cloud.text,"cards show coins, last saved, truthful device")
 for view in [Vector2i(390,844),Vector2i(344,680),Vector2i(844,390),Vector2i(566,360),Vector2i(1360,880)]:
  root.size=view;game.set_meta("hud_safe_insets",Vector4(8,20,8,16) if view==Vector2i(844,390) else Vector4.ZERO)
  for mode in ["cloud","loading","retry","other-device","waiting","handoff-requested","timeout","offline","resume-needed"]:
   var choice=mode in ["cloud","loading"]
   var owner=mode in ["other-device","waiting","handoff-requested","timeout","offline","resume-needed"]
   bridge.value.available=choice;bridge.value.choicesAvailable=choice;controller.retrying=mode=="loading"
   bridge.value.serverOwnership=owner;bridge.value.ownershipPaused=owner;bridge.value.status="takeover-ready" if mode=="timeout" else mode
   bridge.value.canRequestTakeover=mode in ["other-device","handoff-requested","resume-needed"];bridge.value.canForceTakeover=mode=="timeout"
   ui.show_help();await settle()
   if mode=="resume-needed":check(ui.help_heading.text=="Could not resume yet" and ui.help_switch_device.text=="Try again","failed resume offers accurate retry")
   var label="%s %s"%[str(view),mode];var inset=ui.hud._safe_insets()
   var safe=Rect2(inset.x,inset.y,view.x-inset.x-inset.z,view.y-inset.y-inset.w)
   check(safe.encloses(ui.help_panel.get_global_rect()),label+" panel inside safe viewport")
   var panel=ui.help_panel.get_global_rect();var style=ui.help_panel.get_theme_stylebox("panel")
   var inside=Rect2(panel.position+Vector2(style.get_margin(SIDE_LEFT),style.get_margin(SIDE_TOP)),panel.size-style.get_minimum_size())
   for action in [ui.help_choose_local,ui.help_choose_cloud,ui.help_switch_device,ui.help_retry,ui.help_overview,ui.help_notes,ui.help_done]:
    if not action.visible:continue
    check(ui.help_footer.is_ancestor_of(action) and not ui.help_scroll.is_ancestor_of(action),label+" action outside detail scroll")
    check(absf(action.size.x-ui.help_done.size.x)<1,label+" equal action widths")
    check(action.size.y>=44,label+" minimum touch height")
    var glyph=action.get_theme_font("font").get_string_size(action.text,HORIZONTAL_ALIGNMENT_LEFT,-1,action.get_theme_font_size("font_size")).x
    check(action.size.x>=glyph+24,label+" horizontal text padding "+action.text)
    check(inside.encloses(action.get_global_rect()),label+" action inside panel")
   check(ui.help_scroll.size.y>=99,label+" readable detail viewport")
   if choice:check(ui.help_scroll.get_global_rect().encloses(ui.help_choices.get_global_rect()),label+" both save cards visible before scrolling")
   var footer=ui.help_footer.get_global_rect();ui.help_scroll.scroll_vertical=100000;await settle()
   check(ui.help_footer.get_global_rect().is_equal_approx(footer),label+" footer stays fixed while scrolling")
   check(ui.help_scroll.get_v_scroll_bar().value+ui.help_scroll.get_v_scroll_bar().page>=ui.help_scroll.get_v_scroll_bar().max_value-1,label+" all details reachable")
   records.append({"view":str(view),"mode":mode,"panel":str(panel),"body_height":ui.help_scroll.size.y})
 controller.retrying=false;bridge.value.available=true;bridge.value.choicesAvailable=true;bridge.value.serverOwnership=false;bridge.value.ownershipPaused=false;root.size=Vector2i(390,844);ui.show_help();await settle()
 var original=game.model
 ui.help_choose_local.pressed.emit();ui.help_choose_local.pressed.emit();await settle()
 check(bridge.prepare_calls==1 and controller.recovery_busy,"repeated choice clicks prepare once")
 check(ui.help_choose_local.disabled and ui.help_choose_cloud.disabled,"both choices disabled while busy")
 var payload=FileAccess.get_file_as_string("res://tests/fixtures/startup-retry-v15.json");var corrupt=JSON.parse_string(payload);corrupt.items[0].x=9999
 bridge.finish({"ok":true,"source":"authority","selectionToken":"invalid","profileId":"synthetic","revision":8,"payload":JSON.stringify(corrupt)});await settle()
 check(bridge.confirm_calls==0 and game.model==original,"invalid native candidate cannot confirm or replace model")
 ui.help_choose_cloud.pressed.emit();bridge.finish({"ok":true,"source":"authority","selectionToken":"cancel","profileId":"synthetic","revision":8,"payload":payload});await settle()
 check(bridge.confirm_calls==1 and game.model==original,"validated candidate waits for player confirmation")
 var stale=bridge.callback;bridge.finish({"ok":false,"code":"RECOVERY_CANCELLED"});await settle()
 check(not controller.recovery_busy and game.model==original and game.save_recovery_blocked,"cancellation leaves original model paused")
 ui.help_choose_cloud.pressed.emit();stale.call([JSON.stringify({"ok":true,"source":"authority","profileId":"synthetic","revision":8,"payload":payload})])
 check(controller.recovery_busy and game.model==original,"stale callback cannot replace model")
 bridge.finish({"ok":true,"source":"authority","selectionToken":"accept","profileId":"synthetic","revision":8,"payload":payload});await settle()
 bridge.value.available=false;bridge.value.choicesAvailable=false
 bridge.finish({"ok":true,"source":"authority","profileId":"synthetic","revision":8,"payload":payload});await settle()
 check(controller.ready and not game.paused and not game.save_recovery_blocked and game.model!=original and game.model.coins==42000,"matching committed receipt applies validated model")
 bridge.finish({"ok":true,"source":"authority","profileId":"synthetic","revision":8,"payload":payload});check(game.resumes==1,"duplicate receipt cannot resume twice")
 ui.show_help();await settle();check(not ui.help_choose_local.visible and not ui.help_choose_cloud.visible,"normal play has no conflict actions")
 check(not ui.help_switch_device.visible,"takeover absent without server capability")
 bridge.value.serverOwnership=true;bridge.value.ownershipPaused=true;bridge.value.status="other-device";bridge.value.canRequestTakeover=true;bridge.value.canForceTakeover=false
 controller.check_runtime_recovery()
 check(game.paused and game.save_recovery_blocked and game.save_writes_suppressed and bridge.preserve_calls==1,"ownership loss freezes and snapshots live model once")
 controller.switch_to_this_device();check(bridge.switch_calls==0,"cannot switch before durable snapshot")
 bridge.finish({"ok":true,"durable":true,"profileId":"synthetic","revision":9});await settle()
 controller._takeover_finish_attempted=true
 controller.switch_to_this_device();controller.switch_to_this_device();check(bridge.switch_calls==1,"explicit switch starts exactly one request")
 bridge.value.canRequestTakeover=false;bridge.value.status="waiting";bridge.finish({"ok":true,"status":"waiting"});await settle()
 check(game.save_recovery_blocked and bridge.finish_calls==0,"waiting does not resume")
 bridge.value.status="takeover-ready";bridge.value.canForceTakeover=false;controller.check_runtime_recovery();check(bridge.finish_calls==1,"server acknowledgment finishes pending switch")
 bridge.value.ownershipPaused=false;bridge.value.status="active";bridge.finish({"ok":true,"source":"authority","profileId":"synthetic","revision":10,"payload":payload});await settle()
 check(game.resumes==2 and not game.paused and controller.revision==10 and not game.save_recovery_blocked,"validated takeover receipt resumes without reload")
 bridge.value.ownershipPaused=true;bridge.value.status="offline";controller.pending=true;controller.check_runtime_recovery()
 check(game.paused and game.save_recovery_blocked and bridge.preserve_calls==1,"ownership pause freezes before an in-flight save completes")
 controller.pending=false;controller.check_runtime_recovery();check(bridge.preserve_calls==2,"completed in-flight save allows exact live snapshot")
 bridge.finish({"ok":true,"durable":true,"profileId":"synthetic","revision":11});await settle()
 check(ui.help_heading.text=="Waiting for connection","offline does not falsely claim another device")
 bridge.value.ownershipPaused=false;bridge.value.status="active";controller.check_runtime_recovery();check(bridge.finish_calls==2,"same-owner reconnection reconciles before resuming")
 bridge.finish({"ok":true,"source":"authority","profileId":"synthetic","revision":11,"payload":payload});await settle()
 check(game.resumes==3 and not game.paused and not game.save_recovery_blocked,"same-owner reconnect resumes validated preserved snapshot")
 bridge.value.accountChanged=true;controller.check_runtime_recovery();check(game.save_recovery_blocked and game.paused,"account switch preserves current model on page")
 check(game.saves==0,"UI never submits an ordinary save")
 game.save_writes_suppressed=true;game.web_save=null
 print("CLOUD_RECOVERY_UI_RESULT ",JSON.stringify({"checks":checks,"failures":failures,"geometry":records,"player_save_used":false}))
 for player in game.audio_players.values():player.stop();player.stream=null
 game.settings_controls.sfx_player.stop();game.settings_controls.sfx_player.stream=null
 for tween in get_processed_tweens():tween.kill()
 game.queue_free();await process_frame;quit(0 if failures.is_empty() else 1)
