extends SceneTree
## Real-time observer. No fixture startup, manual simulation ticks, forced guests,
## table assignment, accelerated clock, or edits to gameplay state.
const Main = preload("res://scripts/main.gd")
var game
var started_ms = 0
var events = {}
var failures = []
var checks = 0
var scenario = OS.get_environment("LL_ARRIVAL_SCENARIO")
var samples = []
var initial = {}
var next_sample = 0.0
var maximum_seconds = 180.0
var tracked_guest_id = -1
var capture_requests = []
var until_event = OS.get_environment("LL_ARRIVAL_UNTIL")
var capture_directory = OS.get_environment("LL_ARRIVAL_CAPTURES")

func _initialize():run.call_deferred()
func check(value:bool,label:String):
 checks += 1
 if not value:failures.append(label);printerr("FAIL ",label)
func seconds()->float:return float(Time.get_ticks_msec()-started_ms)/1000.0
func event(name:String, detail:Dictionary = {}):
 if events.has(name):return
 detail["wall_seconds"]=seconds()
 detail["animation_seconds"]=game.animation_time
 detail["arrival_elapsed"]=game.model._arrival_elapsed
 events[name]=detail
 if name in ["guest_created","guest_foot_enters_play_rect","guest_seated","order_done","first_payment"]:capture_requests.append(name)
 print("FRESH_ARRIVAL_EVENT ",JSON.stringify({"name":name,"detail":detail}))
func snapshot()->Dictionary:
 var guests=[]
 for guest in game.model.customers:
  guests.append({"id":guest.id,"phase":guest.phase,"x":guest.x,"z":guest.z,"seated":guest.get("seated",false)})
 return {"wall_seconds":seconds(),"open":game.model.operating_open,"paused":game.paused,"editing":game.editing,"intro":game.cafe_intro.active,"blocked":game.save_recovery_blocked,"too_small":game.compact_ui.viewport_too_small,"arrival_elapsed":game.model._arrival_elapsed,"animation_seconds":game.animation_time,"coins":game.model.coins,"served":game.model.served,"customers":guests,"business_text":game.compact_ui.business_state.text,"business_visible":game.business_button.is_visible_in_tree(),"pause_tooltip":game.pause_button.tooltip_text,"state_badge_visible":game.state_badge.is_visible_in_tree()}
func click(control:Control):
 var point=control.get_global_rect().get_center()
 var motion=InputEventMouseMotion.new();motion.position=point;motion.global_position=point
 root.push_input(motion,true)
 var down=InputEventMouseButton.new();down.position=point;down.global_position=point;down.button_index=MOUSE_BUTTON_LEFT;down.pressed=true;down.button_mask=MOUSE_BUTTON_MASK_LEFT
 root.push_input(down,true)
 await process_frame
 var up=InputEventMouseButton.new();up.position=point;up.global_position=point;up.button_index=MOUSE_BUTTON_LEFT;up.pressed=false
 root.push_input(up,true)
 await process_frame
func run():
 var isolated=OS.get_environment("XDG_DATA_HOME")
 check(isolated!="" and OS.get_user_data_dir().begins_with(isolated),"isolated generated profile")
 check(not FileAccess.file_exists(Main.SAVE_FILE),"no existing primary save")
 root.size=Vector2i(1360,880)
 started_ms=Time.get_ticks_msec()
 game=Main.new();root.add_child(game)
 initial=snapshot()
 check(game.fresh_start and not game.save_recovery_blocked,"normal fresh startup loaded")
 check(game.model.operating_open==(scenario!="tutorial") and not game.paused and not game.editing,"expected normal startup admissions state, running and Play")
 check(game.model.customers.is_empty() and is_zero_approx(game.model._arrival_elapsed),"starts with no guests and zero arrival clock")
 print("FRESH_ARRIVAL_INITIAL ",JSON.stringify(initial))
 if capture_directory!="":capture_requests.append("startup")
 if scenario=="skip":
  await create_timer(.25).timeout
  # Actual press/release delivered through root GUI input. The intro owns it.
  await click(game.business_button)
  check(not game.cafe_intro.active and game.model.operating_open,"intro skip does not accidentally close cafe")
  event("skip_finished")
 if scenario=="tutorial":
  check(game.get("tutorial")!=null,"combined tutorial exists")
  if game.get("tutorial")==null:
   quit(1)
   return
  while game.cafe_intro.active:await process_frame
  await click(game.business_button);await create_timer(.2).timeout
  check(game.model.operating_open,"real tutorial Open admits guests")
  event("tutorial_opened")
  await click(game.compact_ui.staff_access);await create_timer(.2).timeout
  check(game.compact_ui.staff_panel.panel.visible,"real Staff control opens staffing")
  await click(game.compact_ui.staff_panel.done_button);await create_timer(.2).timeout
  check(not game.compact_ui.staff_panel.panel.visible,"real Staff Done returns to cafe")
  await click(game.edit_button);await create_timer(.2).timeout
  check(game.editing,"real Decorate control starts editing")
  await click(game.edit_button);await create_timer(.2).timeout
  check(not game.editing,"real Done returns to live service")
  event("tutorial_back_to_service")
 if scenario=="controls":
  while game.cafe_intro.active:await process_frame
  await click(game.edit_button)
  check(game.editing,"actual Decorate click enters edit mode")
  var clock_before=game.model._arrival_elapsed;var positions_before=game.model.customers.duplicate(true)
  await create_timer(5.0).timeout
  check(is_equal_approx(game.model._arrival_elapsed,clock_before) and game.model.customers==positions_before,"Decorate stops arrivals and movement")
  event("decorate_holds_simulation")
  await click(game.edit_button)
  check(not game.editing,"Done resumes Play")
  await click(game.pause_button)
  check(game.paused,"actual Pause click pauses")
  clock_before=game.model._arrival_elapsed;positions_before=game.model.customers.duplicate(true)
  await create_timer(5.0).timeout
  check(is_equal_approx(game.model._arrival_elapsed,clock_before) and game.model.customers==positions_before,"Pause stops arrivals and movement")
  event("pause_holds_simulation")
  await click(game.pause_button)
  check(not game.paused,"Resume resumes simulation")
  await click(game.business_button)
  check(not game.model.operating_open,"actual Close click closes admissions")
  await create_timer(5.0).timeout
  check(is_zero_approx(game.model._arrival_elapsed),"Closed stops arrival clock")
  event("closed_holds_arrivals")
  await click(game.business_button)
  check(game.model.operating_open,"actual Open click resumes admissions")
  event("reopened")
 while seconds()<maximum_seconds:
  if not game.cafe_intro.active:event("intro_finished")
  for guest in game.model.customers:
   if tracked_guest_id<0 and not bool(guest.get("withdrawn",false)):tracked_guest_id=int(guest.id)
   if int(guest.id)!=tracked_guest_id:continue
   event("guest_created",{"position":[guest.x,guest.z],"route":str(guest.route)})
   var point=game.illustration.iso(float(guest.x),float(guest.z))
   var play_rect=game.illustration.camera_play_rect()
   if not game.cafe_intro.active and play_rect.has_point(point):event("guest_foot_enters_play_rect",{"screen":[point.x,point.y],"position":[guest.x,guest.z],"not_rendered_pixel_evidence":true})
   if guest.get("admitted",false):event("guest_admitted")
   if guest.get("seated",false):event("guest_seated")
   if str(guest.phase)!="arriving":event("phase_"+str(guest.phase))
   if game.service_guests.has(tracked_guest_id):
    var service=game.service_guests[tracked_guest_id]
    if bool(service.get("order_done",false)):event("order_done")
  if until_event=="spawned" and events.has("guest_created"):break
  if until_event=="seated" and events.has("guest_seated"):break
  if game.model.served>0:
   event("first_payment",{"served":game.model.served,"earned":game.model.total_earned})
   await capture_pending()
   if scenario=="tutorial":
    await create_timer(.25).timeout
    check(game.tutorial.finish_button.is_visible_in_tree(),"tutorial reaches completion only after real payment")
    await click(game.tutorial.finish_button)
    check(game.model.tutorial_state.get("status")=="completed","real tutorial finish control completes guide")
   break
  if seconds()>=next_sample:
   var record=snapshot();samples.append(record);print("FRESH_ARRIVAL_SAMPLE ",JSON.stringify(record));capture_requests.append("at_"+str(int(next_sample))+"_seconds");next_sample+=10.0
  await capture_pending()
  await create_timer(.05).timeout
 check(events.has("guest_created"),"guest spawned naturally")
 if until_event!="spawned":
  check(events.has("guest_foot_enters_play_rect"),"first guest entered default camera projection")
  check(events.has("guest_seated"),"first guest naturally seated")
 if until_event not in ["spawned","seated"]:check(events.has("first_payment"),"first meal naturally paid")
 var result={"checks":checks,"failures":failures,"scenario":scenario,"until":until_event if until_event!="" else "paid","initial":initial,"events":events,"samples":samples,"final":snapshot(),"fresh_default_startup":true,"manual_ticks":false,"forced_guests":false,"gameplay_state_mutated_by_harness":false,"headless":DisplayServer.get_name()=="headless","real_browser_verified":false,"player_save_used":false}
 var output=OS.get_environment("LL_ARRIVAL_OUTPUT")
 if output!="":FileAccess.open(output,FileAccess.WRITE).store_string(JSON.stringify(result,"  "))
 print("FRESH_ARRIVAL_RESULT ",JSON.stringify(result))
 game.queue_free();await process_frame;await process_frame
 quit(0 if failures.is_empty() else 1)

func capture_pending():
 if capture_directory=="" or DisplayServer.get_name()=="headless":
  capture_requests.clear();return
 if capture_requests.is_empty():return
 await RenderingServer.frame_post_draw
 var rendered=root.get_texture().get_image()
 for name in capture_requests:
  rendered.save_png(capture_directory+"/"+name+".png")
 capture_requests.clear()
