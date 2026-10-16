extends SceneTree
## Physical placement and runtime station usability remain separate.
const Guide=preload("res://scripts/rendering/cafe_workface_guidance.gd")
const Model=preload("res://scripts/core/cafe_model.gd")
class TestMain extends "res://scripts/main.gd":
 var saves=0
 func _load_startup():save_writes_suppressed=true;fresh_start=true;MinimalStart.apply(model)
 func _save():saves+=1;return true
var checks=0;var failures=[]
func check(ok,label):
 checks+=1
 if not ok:failures.append(label);printerr("FAIL ",label)
func inspect_live_idle_constraints(game):
 game._refresh_idle_homes()
 var free=[]
 for z in range(game.model.depth):
  for x in range(1,game.model.width):
   var cell=Vector2i(x,z)
   if game._is_station_workface(cell) or not game._idle_cell_clear(cell,1,[]):continue
   if game.staff_states.any(func(peer):return peer.idle_home_cell==cell):continue
   if not game._static_service_path(Model.ENTRY_LANDING,cell).is_empty():free.append(cell)
 check(free.size()>=2,"synthetic layout has two reachable idle destinations")
 if free.size()<2:return
 var from:Vector2i=free[0];var home:Vector2i=free[1]
 var worker=game.staff_states[1];worker.pos=game.model.cell_center(from);worker.idle_home_cell=home;worker.idle_return_delay=.01
 check(game._staff_idle_cell(1,[])==from,"positive home delay keeps the valid current cell")
 var revision=game.model.revision
 game.model.customers.append({"id":99001,"phase":"checkout_wait","checkout_cell":from})
 check(game.model.revision==revision and game._staff_idle_cell(1,[])!=from,"live checkout claim excludes current cell without a revision change")
 game.model.customers.pop_back()
 check(game.model.revision==revision and game._staff_idle_cell(1,[])==from,"removing a live checkout claim restores current-cell eligibility")
 game.model.items.append({"id":99002,"kind":"plant","x":home.x,"z":home.y,"rot":0})
 worker.idle_return_delay=0.0
 check(game._staff_idle_cell(1,[])==from and worker.idle_return_delay==1.5,"blocked home resets return delay before choosing current cell")
 check(game._static_service_path(from,home).is_empty(),"geometry mutation invalidates the previously reachable home path")
 game.model.items.pop_back();worker.idle_return_delay=0.0
 check(game._staff_idle_cell(1,[])==home and not game._static_service_path(from,home).is_empty(),"geometry reversal restores home priority and reachability")
 worker.idle_return_delay=.01
 check(game._staff_idle_cell(1,[])==from,"current cell remains preferred before delay reaches zero")
 worker.idle_return_delay=0.0
 check(game._staff_idle_cell(1,[])==home,"home wins immediately when delay crosses zero")
 worker.idle_return_delay=1.5
 var peer=game.staff_states[2];var peer_home=peer.idle_home_cell;peer.idle_home_cell=from
 check(game._staff_idle_cell(1,[])!=from,"live peer-home change excludes current cell")
 peer.idle_home_cell=peer_home
 check(game._staff_idle_cell(1,[])==from,"removing peer-home reservation restores current cell")
func _initialize():run.call_deferred()
func run():
 var m=Model.new();m.items.clear();m.dining_sets.clear();m.customers.clear();m.coins=100000
 check(m.place("plant",5,4),"decorative blocker places")
 var before=[m.items.duplicate(true),m.coins,m.revision,m._next_item_id]
 check(m.can_place("stove",5,3,-1,0),"physically clear blocked stove preview is allowed")
 check(before==[m.items,m.coins,m.revision,m._next_item_id],"rejected preview is pure")
 check(m.place("stove",5,3,0),"physically valid blocked stove commits")
 var stove=m.items[-1]
 check(m.layout_access_issues().size()==1 and m.layout_access_issues()[0].item_id==stove.id,"blocked stove remains locatable")
 check(not m._sale_station_usable_in(stove,m.items,m._sale_reachable_in(m.items)),"blocked stove is unavailable to work")
 check(not m.can_place("plant",5,3),"physical overlap remains invalid")
 check(not m.can_place("stove",99,99),"ownership remains enforced")
 check(m.can_place("plant",m.ENTRY_LANDING.x,m.ENTRY_LANDING.y),"empty idle entrance remains physically placeable")
 check(m.save("user://decorative-stove.json"),"blocked decorative layout saves")
 var restored=Model.new();check(restored.load_save("user://decorative-stove.json"),"blocked decorative layout reloads")
 check(restored.layout_access_issues().size()==1,"restored blocked stove still has decorate guidance")
 var wall_model=Model.new();wall_model.items.clear();wall_model.dining_sets.clear();wall_model.customers.clear();wall_model.coins=100000
 check(wall_model.place("stove",5,3,0),"wall obstruction fixture places stove")
 check(wall_model.place_wall("x",5,4),"body-free wall may block operational access")
 check(wall_model.layout_access_issues().size()==1,"wall obstruction is still described in decorate")
 check(wall_model.place("stove",11,8,0),"owned stove footprint may face unusable working space")
 for kind in ["beverage","sink","counter","register"]:
  var test=Model.new();test.items.clear();test.dining_sets.clear();test.customers.clear();test.coins=100000
  test.place("plant",5,4)
  check(test.can_place(kind,5,3,-1,0),"appliance physical fit is independent of service access: "+kind)
 var game=TestMain.new();root.add_child(game);game.set_process(false);game.illustration.set_process(false)
 var live_stove={}
 for item in game.model.items:
  if item.kind=="stove":live_stove=item;break
 var face=game.model.workface_cell(live_stove)
 for staff in game.staff_states:staff.pos=Vector2(1.5,7.5)
 check(game.model.place("plant",face.x,face.y),"clear stove-side footprint commits without an access veto")
 game._rebuild_furniture();game.editing=true;game.selected_id=int(live_stove.id)

 check(game.model.layout_access_issues().size()==1 and int(game.model.layout_access_issues()[0].item_id)==int(live_stove.id),"structural validation identifies blocked stove")
 check(Guide.describe(game).size()==1 and not Guide.describe(game)[0].clear,"selected blocked stove retains operational diagnosis")
 var chef=game.staff_states[0]
 chef.blocked_reason="Stove front blocked · make space in Decorate";chef.art_block_reason=chef.blocked_reason;chef.blocked_target_id=live_stove.id
 game.editing=false
 check(Guide.blocked_station(game).is_empty(),"play hides stove locate badge")

 check(Guide.describe(game).is_empty(),"play clears decorate-only diagnosis")
 game.idle_home_revision=-1;game._refresh_idle_homes()
 check(chef.idle_home_id==-1,"decorative stove is not an idle working home")
 check(game._service_station("stove",Vector2i(1,7),0).is_empty(),"new cooking job skips blocked stove")
 chef.blocked_reason="";chef.art_block_reason="";chef.blocked_target_id=-1
 game._staff_idle_cell(0,[])
 check(chef.blocked_reason=="","idle decorative stove does not generate recurring blocked prompt")
 inspect_live_idle_constraints(game)
 check(game.saves==0,"diagnosis and idle planning never save")
 print("STOVE_OPTIONAL_RESULT ",JSON.stringify({"checks":checks,"failures":failures}))
 for player in game.audio_players.values():player.stop();player.stream=null
 game.settings_controls.sfx_player.stop();game.settings_controls.sfx_player.stream=null
 for tween in get_processed_tweens():tween.kill()
 game.queue_free();await process_frame;await process_frame;quit(0 if failures.is_empty() else 1)
