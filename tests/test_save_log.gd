extends SceneTree
const SaveLog=preload("res://scripts/cafe_save_log.gd")
var checks=0
var failures=[]
func check(ok:bool,label:String):
 checks+=1
 if not ok:failures.append(label);printerr("FAIL ",label)
func _init():call_deferred("run")
func run():
 var game=load("res://main.tscn").instantiate();root.add_child(game)
 await process_frame;await process_frame
 game.set_process(false)
 var ui=game.compact_ui
 var log=ui.save_log_panel
 check(log!=null and not log.panel.visible,"Log does not open automatically")
 var entry=game.settings.find_child("SaveLogEntry",true,false)
 check(entry!=null and entry.text=="Log","Settings entry is exactly Log")
 check(not log.log_text.editable and log.log_text.wrap_mode==TextEdit.LINE_WRAPPING_BOUNDARY,"Log is read-only with wrapped scrollable text")
 game.settings.show();entry.pressed.emit();await process_frame
 check(log.panel.visible and not game.settings.visible and ui.has_open_popup(),"Settings Log opens within modal flow")
 check("Session only" in log.log_text.text and "app " in log.log_text.text,"version and copy-before-refresh notice visible")
 var model=game.model;var source=game.startup_save_source;var blocked=game.save_recovery_blocked
 SaveLog.record("save_failure",{"layer":"controller","profileId":"SECRET_PROFILE_ID","revision":12,"code":"secret url /wallet?token=SECRET","payload":"SECRET_SAVE_PAYLOAD","coins":99999})
 var text=SaveLog.text()
 check(not "SECRET" in text and not "99999" in text and "code=STORAGE_ERROR" in text,"native log excludes IDs payloads wallets and raw errors")
 check("profile="+SaveLog._fingerprint("SECRET_PROFILE_ID") in text and "revision=12" in text,"opaque fingerprint and revision retained")
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
 check(not log.panel.visible and game.settings.visible,"Back restores Settings")
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
 print("SAVE_LOG_RESULT ",JSON.stringify({"checks":checks,"failures":failures}))
 game.queue_free();await process_frame;quit(0 if failures.is_empty() else 1)
