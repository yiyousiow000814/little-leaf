extends SceneTree
## Idle blocked workfaces remain diagnosable without reserving furniture footprints.
const Model=preload("res://scripts/cafe_model.gd")
class TestMain extends "res://scripts/main.gd":
 var saves=0
 func _load_startup():save_writes_suppressed=true;fresh_start=true;MinimalStart.apply(model)
 func _save():saves+=1;return true
var checks=0;var failures=[]
func check(ok,label):
 checks+=1
 if not ok:failures.append(label);printerr("FAIL ",label)
func _initialize():run.call_deferred()
func run():
 var m=Model.new();m.items.clear();m.dining_sets.clear();m.customers.clear();m.coins=100000
 check(m.place("plant",5,4),"decorative blocker places")
 var before=[m.items.duplicate(true),m.coins,m.revision,m._next_item_id]
 check(m.can_place("stove",5,3,-1,0),"idle blocked stove preview is physically valid")
 check(before==[m.items,m.coins,m.revision,m._next_item_id],"rejected preview is pure")
 check(m.place("stove",5,3,0),"idle blocked stove confirmation commits")
 var stove=m.items[-1]
 check(m.layout_access_issues().size()==1 and m.layout_access_issues()[0].item_id==stove.id,"blocked stove remains locatable")
 check(not m._sale_station_usable_in(stove,m.items,m._sale_reachable_in(m.items)),"blocked stove is unavailable to work")
 check(not m.can_place("plant",5,3),"physical overlap remains invalid")
 check(not m.can_place("stove",99,99),"ownership remains enforced")
 check(m.can_place("plant",m.ENTRY_LANDING.x,m.ENTRY_LANDING.y),"idle landing is not a reserved footprint")
 check(m.save("user://decorative-stove.json"),"blocked decorative layout saves")
 var restored=Model.new();check(restored.load_save("user://decorative-stove.json"),"blocked decorative layout reloads")
 check(restored.layout_access_issues().size()==1,"restored blocked stove still has decorate guidance")
 var wall_model=Model.new();wall_model.items.clear();wall_model.dining_sets.clear();wall_model.customers.clear();wall_model.coins=100000
 check(wall_model.place("stove",5,3,0),"wall obstruction fixture places stove")
 check(not wall_model.place_wall("x",5,4),"new wall cannot block stove front")
 var legacy_wall=Model.WallGeometry.make("x",5,4);legacy_wall.id=wall_model._next_wall_id;wall_model._next_wall_id+=1;wall_model.built_walls.append(legacy_wall);wall_model._notify()
 check(wall_model.layout_access_issues().size()==1,"wall obstruction is still described in decorate")
 check(wall_model.place("stove",11,8,0),"owned stove footprint may face beyond usable work floor")
 for kind in ["beverage","sink","register"]:
  var test=Model.new();test.items.clear();test.dining_sets.clear();test.customers.clear();test.coins=100000
  test.place("plant",5,4)
  check(test.can_place(kind,5,3,-1,0),"idle appliance access is a warning: "+kind)
 var retired_counter=Model.new()
 check(not retired_counter.can_place("counter",5,3) and retired_counter.last_error=="Meals are collected directly from the stove","idle placement policy preserves direct-stove pickup and retired counter purchase")
 var game=TestMain.new();root.add_child(game);game.set_process(false);game.illustration.set_process(false)
 var live_stove={}
 for item in game.model.items:
  if item.kind=="stove":live_stove=item;break
 var face=game.model.workface_cell(live_stove)
 for staff in game.staff_states:staff.pos=Vector2(1.5,7.5)
 check(game.model.place("plant",face.x,face.y),"idle live café permits physical stove-front purchase")
 game._rebuild_furniture();game.editing=true;game.selected_id=int(live_stove.id)
 game.workface_guidance._refresh()
 check(game.model.layout_access_issues().size()==1 and int(game.model.layout_access_issues()[0].item_id)==int(live_stove.id),"structural validation identifies blocked stove")
 check(game.workface_guidance.markers.size()==1 and not game.workface_guidance.markers[0].clear,"selected blocked stove retains red ground marker")
 var chef=game.staff_states[0]
 chef.blocked_reason="Stove front blocked · make space in Decorate";chef.art_block_reason=chef.blocked_reason;chef.blocked_target_id=live_stove.id
 game.editing=false
 check(game.workface_guidance.blocked_station(game).is_empty(),"play hides stove locate badge")
 game.workface_guidance._refresh()
 check(game.workface_guidance.markers.is_empty(),"play clears Decorate ground markers")
 game.idle_home_revision=-1;game._refresh_idle_homes()
 check(chef.idle_home_id==-1,"decorative stove is not an idle working home")
 check(game._service_station("stove",Vector2i(1,7),0).is_empty(),"new cooking job skips blocked stove")
 chef.blocked_reason="";chef.art_block_reason="";chef.blocked_target_id=-1
 game._staff_idle_cell(0,[])
 check(chef.blocked_reason=="","idle decorative stove does not generate recurring blocked prompt")
 check(game.saves==0,"diagnosis and idle planning never save")
 print("STOVE_OPTIONAL_RESULT ",JSON.stringify({"checks":checks,"failures":failures}))
 for player in game.audio_players.values():player.stop();player.stream=null
 game.settings_controls.sfx_player.stop();game.settings_controls.sfx_player.stream=null
 for tween in get_processed_tweens():tween.kill()
 game.queue_free();await process_frame;await process_frame;quit(0 if failures.is_empty() else 1)
