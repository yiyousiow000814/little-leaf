extends SceneTree
const SaveLog=preload("res://scripts/cafe_save_log.gd")
var checks=0
var failures=[]
var web_points={}
func point(control:Control)->Array:
 var center=control.get_global_rect().get_center();return [center.x,center.y]
func settle():
 for i in range(4):await process_frame
func check(ok:bool,label:String):
 checks+=1
 if not ok:failures.append(label);printerr("FAIL ",label)
func _init():call_deferred("run")
func run():
 root.size=Vector2i(1360,880)
 var game=load("res://main.tscn").instantiate();root.add_child(game)
 await process_frame;await process_frame
 game.set_process(false)
 var ui=game.compact_ui
 var log=ui.save_log_panel
 check(log!=null and not log.panel.visible,"Log does not open automatically")
 var entry=ui.help_panel.find_child("SaveLogEntry",true,false)
 check(entry!=null and entry.text=="Log","Help entry is exactly Log")
 check(not log.log_text.editable and log.log_text.wrap_mode==TextEdit.LINE_WRAPPING_BOUNDARY,"Log is read-only with wrapped scrollable text")
 await settle()
 web_points.settings=point(ui.settings_button)
 web_points.pause=point(game.pause_button)
 game.settings.show();await settle();ui._fit_themed_popups();await settle()
 web_points.help=point(ui.settings_help)
 ui.settings_help.pressed.emit();await settle()
 web_points.log=point(entry)
 entry.pressed.emit();await settle();ui._fit_themed_popups();await settle()
 web_points.copy=point(log.copy_button)
 for key in web_points:
  var p=web_points[key]
  check(p[0]>=0 and p[0]<1360 and p[1]>=0 and p[1]<880,"browser input point inside viewport: "+key)
 check(log.panel.visible and not game.settings.visible and not ui.help_panel.visible and ui.has_open_popup(),"Help Log opens within modal flow")
 check("Session only" in log.log_text.text and "app " in log.log_text.text,"version and copy-before-refresh notice visible")
 var model=game.model;var source=game.startup_save_source;var blocked=game.save_recovery_blocked
 SaveLog.record("save_failure",{"layer":"controller","profileId":"SECRET_PROFILE_ID","revision":12,"code":"secret url /wallet?token=SECRET","payload":"SECRET_SAVE_PAYLOAD","coins":99999})
 var text=SaveLog.text()
 check(not "SECRET" in text and not "99999" in text and "code=STORAGE_ERROR" in text,"native log excludes IDs payloads wallets and raw errors")
 check("profile="+SaveLog._fingerprint("SECRET_PROFILE_ID") in text and "revision=12" in text,"opaque fingerprint and revision retained")
 SaveLog.record("save_failure",{"layer":"controller","revision":0,"code":"InvalidStateError"})
 check("code=InvalidStateError" in SaveLog.text(),"controller preserves the allowlisted closed-connection error code")
 for i in range(260):SaveLog.record("save_requested",{"layer":"controller","revision":i})
 log._refresh()
 check(SaveLog.entries.size()==240 and SaveLog.dropped>0,"session history is bounded")
 check(log.log_text.get_line_count()>240,"bounded events remain inspectable in scrollable text")
 log._show_copy_status("unavailable");await process_frame
 check(log.copy_note.visible and "copy manually" in log.copy_note.text and log.log_text.has_selection(),"clipboard failure leaves selected read-only text and manual fallback")
 log._show_copy_status("pending")
 check(log.waiting_for_copy and "Copying" in log.copy_note.text,"pending clipboard request never claims copied")
 log._show_copy_status("copied")
 check(not log.waiting_for_copy and log.copy_note.text=="Log copied","copy confirmation shown only after success")
 log.back_button.pressed.emit();await process_frame
 check(not log.panel.visible and ui.help_panel.visible,"Back restores Help")
 entry.pressed.emit();await process_frame
 check(log.panel.visible and not log.copy_note.visible,"repeated open resets stale copy feedback")
 var event=InputEventKey.new();event.keycode=KEY_ESCAPE;event.pressed=true
 ui.handle_input(event);await process_frame
 check(not log.panel.visible,"Escape closes the Log")
 check(game.model==model and game.startup_save_source==source and game.save_recovery_blocked==blocked,"Log navigation never mutates model or recovery state")
 for size in [Vector2i(1280,800),Vector2i(800,600),Vector2i(640,480)]:
  root.size=size;root.content_scale_size=size;log.show()
  await process_frame;await process_frame
  ui._fit_themed_popups()
  check(log.panel.size.x<=size.x and log.panel.position.x>=0 and log.panel.position.y>=0,"Log fits viewport "+str(size))
  check(log.panel.size.y<=size.y,"Log footer reachable by outer scroll "+str(size))
 var result={"checks":checks,"failures":failures,"web_input_points":web_points,"web_viewport":{"width":1360,"height":880}}
 if OS.get_environment("LL_UI_RESULT")!="":
  var file=FileAccess.open(OS.get_environment("LL_UI_RESULT"),FileAccess.WRITE);file.store_string(JSON.stringify(result))
 print("SAVE_LOG_RESULT ",JSON.stringify(result))
 game.queue_free();await process_frame;quit(0 if failures.is_empty() else 1)
