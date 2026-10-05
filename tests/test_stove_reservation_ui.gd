extends SceneTree
const NoBottom=preload("res://tests/no_bottom_notifications.gd")
class FixtureMain extends "res://scripts/main.gd":
 var saves=0
 func _load_startup():save_writes_suppressed=true;fresh_start=true;MinimalStart.apply(model)
 func _save():saves+=1;return true
 func _interaction_over_ui(_screen:Vector2)->bool:return false
var game;var checks=0;var failures=[];var evidence=[]
func check(ok,label):
 checks+=1
 if not ok:failures.append(label);printerr("FAIL ",label)
func _initialize():run.call_deferred()
func state():return JSON.stringify([game.model.items,game.model.customers,game.model.coins,game.model.revision,game.model._next_item_id,game.saves])
func frames():
 for repeat in 3:game.illustration.queue_redraw();await process_frame
func key(code):
 var event=InputEventKey.new();event.keycode=code;event.pressed=true
 game.interaction.handle_input(event)
func capture(label,front):
 var folder=OS.get_environment("LL_STOVE_CAPTURE")
 if folder=="" or DisplayServer.get_name()=="headless":return
 await RenderingServer.frame_post_draw
 root.get_texture().get_image().save_png(folder+"/"+label+".png")
 var at=game.illustration.iso(front.x+.5,front.y+.5)
 evidence.append({"file":label+".png","front":[front.x,front.y],"screen":[at.x,at.y],"viewport":[root.size.x,root.size.y]})
func run():
 root.size=Vector2i(1360,880);game=FixtureMain.new();root.add_child(game);game.set_process(false);game.illustration.set_process(false);game.paused=true;game.editing=true
 var m=game.model;m.items.clear();m.dining_sets.clear();m.customers.clear();m.coins=100000;m.checkout_staff_claims.clear();m.wall_actor_positions.clear();m._notify()
 for staff in game.staff_states:staff.pos=Vector2(1.5,7.5)
 check(m.place("stove",5,4),"isolated stove fixture places")
 var stove=m.items[-1];game._rebuild_furniture();game._update_ui();await frames()
 for rot in 4:
  game.interaction.cancel();check(m.move(int(stove.id),5,4,rot),"fixture rotates toward clear floor r"+str(rot));game._rebuild_furniture()
  var front=m.workface_cell(stove);var guide=game.workface_guidance
  game.selected_id=-1;game.selected_kind="";game.interaction.preview_active=false;guide._refresh()
  check(game.interaction.floor_availability.refresh(m)[front].blocked,"unselected stove reserves red ground cell r"+str(rot))
  var before=state();await frames();await capture("unselected-r"+str(rot),front)
  game.interaction._select_item(stove);guide._refresh()
  check(guide.markers.size()==1 and guide.markers[0].cell==front and guide.markers[0].clear,"selected marker uses true clear front r"+str(rot))
  check(guide.markers[0].reserved and guide.marker_color(guide.markers[0])==Color("aa5845"),"selected reserved marker stays red r"+str(rot))
  check(state()==before,"selection/presentation makes no save or layout change r"+str(rot))
  game.selected_id=-1;game.selected_kind="plant";game.rotation_step=0
  game.interaction.refresh(game.illustration.iso(front.x+.5,front.y+.5))
  check(game.interaction.preview_active and not game.interaction.drag_valid,"red invalid prop preview on work tile r"+str(rot))
  check(game.interaction.drag_reason.contains("Stove front blocked"),"hover has precise chef-space rejection r"+str(rot))
  game.interaction._commit_preview();check(state()==before,"invalid UI confirmation cannot charge/place/save r"+str(rot))
  await frames();await capture("blocked-preview-r"+str(rot),front)
  key(KEY_ESCAPE);check(state()==before and not game.interaction.preview_active,"Escape cancels invalid draft without saving r"+str(rot))
  var tools=game.build_tools;game.catalog_category="Build";tools.mode="full"
  tools.preferred_axis="x" if front.y!=4 else "z";tools._cache_key=""
  var mid=(Vector2(5.5,4.5)+Vector2(front)+Vector2(.5,.5))*.5
  tools.refresh(game.illustration.iso(mid.x,mid.y))
  check(not tools.preview_valid and tools.selected_key==m.WallGeometry.edge_between(Vector2i(5,4),front),"wall preview picks and rejects actual work edge r"+str(rot))
  check(tools.preview_reason.contains("Stove front blocked"),"wall preview explains reserved front r"+str(rot))
  tools._commit();check(state()==before,"invalid wall UI confirmation cannot build, charge or save r"+str(rot))
  await frames();await capture("blocked-wall-preview-r"+str(rot),front)
  tools.cancel();game.catalog_category="";check(state()==before,"wall cancel is nonmutating r"+str(rot))
  # A new stove cursor must reserve its own rotated working tile too.
  game.selected_kind="stove";game.selected_id=-1;game.rotation_step=rot
  game.interaction.refresh(game.illustration.iso(8.5,5.5));guide._refresh()
  var draft_front=m.workface_cell({"kind":"stove","x":8,"z":5,"rot":rot})
  check(game.interaction.drag_valid and guide.markers.size()==1 and guide.markers[0].cell==draft_front,"valid stove draft has correct work tile r"+str(rot))
  check(guide.marker_color(guide.markers[0])==Color("aa5845"),"valid stove draft work tile is reserved red r"+str(rot))
  key(KEY_ESCAPE)
  # Keyboard R follows the exact same authority as drag/confirm.
  var next_front=m.workface_cell({"kind":"stove","x":5,"z":4,"rot":posmod(rot+1,4)})
  check(m.place("plant",next_front.x,next_front.y),"rotation obstacle fixture r"+str(rot));var blocker=m.items[-1]
  game._rebuild_furniture();game.interaction._select_item(stove);before=state();key(KEY_R)
  check(state()==before and int(stove.rot)==rot,"immediate R cannot rotate front into obstacle r"+str(rot))
  check(m.remove(int(blocker.id),false),"rotation obstacle removable r"+str(rot))
  game._rebuild_furniture();game.interaction._select_item(stove);var saves=game.saves;key(KEY_R)
  check(int(stove.rot)==posmod(rot+1,4) and game.saves==saves+1,"cleared immediate R commits and saves once r"+str(rot))
  before=state();key(KEY_ESCAPE);check(state()==before,"cancel after valid rotation adds no second save r"+str(rot))
 for size in [Vector2i(344,500),Vector2i(390,844),Vector2i(960,540),Vector2i(1360,880)]:
  root.size=size;await frames();game.illustration.update_projection()
  var front=m.workface_cell(stove);var before=state()
  check(game.interaction.floor_availability.refresh(m)[front].blocked,"resize preserves reservation "+str(size))
  check(game.illustration.screen_to_cell(game.illustration.iso(front.x+.5,front.y+.5))==front,"resize preserves work cell mapping "+str(size))
  NoBottom.verify(game,check,"stove reservation "+str(size));check(state()==before,"resize/notice checks do not save "+str(size))
 game.editing=false;game.workface_guidance._refresh();check(game.workface_guidance.markers.is_empty(),"play hides ground guidance")
 var report={"checks":checks,"failures":failures,"captures":evidence,"native_render":DisplayServer.get_name()!="headless","save_calls":game.saves}
 if OS.get_environment("LL_STOVE_CAPTURE")!="":FileAccess.open(OS.get_environment("LL_STOVE_CAPTURE")+"/report.json",FileAccess.WRITE).store_string(JSON.stringify(report,"  "))
 print("STOVE_RESERVATION_UI_RESULT ",JSON.stringify(report))
 for player in game.audio_players.values():player.stop();player.stream=null
 game.settings_controls.sfx_player.stop();game.settings_controls.sfx_player.stream=null
 for tween in get_processed_tweens():tween.kill()
 game.queue_free();await process_frame;await process_frame;quit(0 if failures.is_empty() else 1)
