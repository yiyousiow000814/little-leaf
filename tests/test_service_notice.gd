extends SceneTree
## Exercise the real scene and Decorate action with a disposable save profile.
var failures=[]
var checks=0
var capture_dir=""
var baseline=false
func _init():
 for arg in OS.get_cmdline_user_args():
  if arg.begins_with("--capture-dir="):capture_dir=arg.trim_prefix("--capture-dir=")
 baseline="--expect-baseline" in OS.get_cmdline_user_args()
 call_deferred("run")
func check(ok:bool,label:String):
 checks+=1
 if not ok:failures.append(label);printerr("FAIL ",label)
func settle():
 await process_frame
 await process_frame
func capture(name:String):
 if capture_dir=="":return
 await RenderingServer.frame_post_draw
 var image=root.get_texture().get_image()
 var error=image.save_png(capture_dir.path_join(name+".png"))
 check(error==OK,"capture "+name)
func has_service_copy(game)->bool:
 return game.status_text.visible and "Your team serves automatically" in game.status_text.text
func buttons_contain(node:Node,text:String)->bool:
 if node is Button and node.text==text:return true
 for child in node.get_children():
  if buttons_contain(child,text):return true
 return false
func run():
 root.size=Vector2i(1360,880)
 var game=load("res://main.tscn").instantiate();root.add_child(game)
 game.paused=true
 await settle()
 if baseline:
  check(game.compact_ui.starter_hint.visible,"baseline reproduces launch card")
  check(buttons_contain(game.ui,"Got it"),"baseline reproduces dismissal burden")
 else:
  check(not has_service_copy(game),"no auto-service notice at fresh launch")
  check(not buttons_contain(game.ui,"Got it"),"no manual dismissal burden")
 await capture("01-launch")
 game._toggle_edit();await settle()
 check(game.editing and not has_service_copy(game),"entering Decorate does not show service notice")
 await capture("02-decorate")
 game._toggle_edit();await settle()
 if baseline:check(not has_service_copy(game),"baseline exit lacks auto-service guidance")
 else:
  check(not game.editing and has_service_copy(game),"exit Decorate shows service guidance")
  check("Table set in Decorate · 140 coins." in game.status_text.text,"guidance uses current table-set price")
  check(game.toast_lifetime>0 and game.toast_lifetime<=3.0,"notice uses existing three-second lifetime")
 await capture("03-exit-decorate")
 # Let the actual process loop expire the toast; do not hide it in the test.
 await create_timer(3.3).timeout;await settle()
 if not baseline:check(not has_service_copy(game),"notice expires without player action")
 await capture("04-expired")
 if not baseline:
  game._update_ui();await settle()
  check(not has_service_copy(game),"UI refresh cannot resurrect expired notice")
  game._toggle_edit();game._toggle_edit();await settle()
  check(has_service_copy(game),"another completed Decorate visit gets a fresh notice")
  game._toggle_edit();await settle()
  check(not has_service_copy(game),"re-entering Decorate interrupts old service notice")
  game._toggle_edit();await settle()
  game.settings.show();game.compact_ui.sync();await settle()
  check(not game.compact_ui.status_notice.panel.visible,"settings cover the transient notice")
  await create_timer(3.3).timeout
  game.settings.hide();game.compact_ui.sync();await settle()
  check(not has_service_copy(game),"closing settings does not replay an expired notice")
  game.fresh_start=false
  game._toggle_edit();game._toggle_edit();await settle()
  check(has_service_copy(game),"loaded cafés receive guidance at the same action boundary")
  game.save_recovery_blocked=true;game.startup_notice="Recovery remains authoritative"
  game._toggle_edit();await settle()
  check(not game.editing and game.compact_ui.last_detail==game.startup_notice and not has_service_copy(game),"blocked Decorate action preserves recovery warning")
  game.save_recovery_blocked=false
 print("SERVICE_NOTICE_RESULT ",JSON.stringify({"baseline":baseline,"checks":checks,"failures":failures}))
 game.queue_free();await process_frame
 quit(0 if failures.is_empty() else 1)
