extends SceneTree
class Fixture extends "res://scripts/main.gd":
 func _load_startup():save_writes_suppressed=true;fresh_start=true;MinimalStart.apply(model)
 func _save():return true
 func _setup_music():pass
var checks=0;var failures=[]
func check(ok:bool,label:String):
 checks+=1
 if not ok:failures.append(label);push_error(label)
func _initialize():run.call_deferred()
func signature(game)->Dictionary:
 var staff=[]
 for worker in game.staff_states:
  var copy=worker.duplicate(true);copy.erase("node");staff.append(copy)
 return {"customers":game.model.customers.duplicate(true),"staff":staff,"coins":game.model.coins,"served":game.model.served,"service":game._service_save_snapshot()}
func fixture():
 var game=Fixture.new();root.add_child(game);game.set_process(false);game.illustration.set_process(false);game.illustration.hide();game.cafe_intro.finish()
 game.model._spawn_customer()
 for guest in game.model.customers:
  guest.x=guest.route[0].x;guest.z=guest.route[0].y
 return game
func dispose(game):
 for player in game.audio_players.values():player.stop();player.stream=null
 game.settings_controls.sfx_player.stop();game.settings_controls.sfx_player.stream=null
 game.queue_free()
func run():
 var game=fixture();var ids=game.staff_states.map(func(s):return s.node.get_instance_id())
 for cycle in 3:
  var before=signature(game)
  game._choose("plant");game._cancel_selection();game._rebuild_room()
  check(signature(game)==before,"selection and room refresh preserve simulation and save state")
  var point=game.illustration.iso(3.5,4.5)
  check(game._floor_cell(point)==Vector2i(3,4),"illustrated floor picking survives room refresh")
  game.static_service_paths["obsolete"]=[];game._rebuild_furniture()
  check(game.static_service_paths.is_empty() and game.static_service_revision==game.model.revision,"layout refresh invalidates service paths")
  check(game.staff_states.all(func(s):return s.destination==Vector2i(-100,-100) and s.path.is_empty() and s.index==0),"layout refresh resets staff routes")
  for tick in 100:
   game._tick_live_service(1.0/30);game._animate_staff(1.0/30);game.animation_time+=1.0/30
  game._update_people()
  check(ids==game.staff_states.map(func(s):return s.node.get_instance_id()),"staff node identity survives refresh and service")
  check(game.staff_states.all(func(s):return s.node is Node3D and s.node.get_child_count()==0),"staff nodes stay lightweight")
  for kind in ["GeometryInstance3D","Camera3D","Light3D","WorldEnvironment"]:
   check(game.find_children("*",kind,true,false).is_empty(),"no legacy renderer allocations: "+kind)
  await process_frame
 dispose(game)
 for tween in get_processed_tweens():tween.kill()
 await process_frame;await process_frame
 check(ids.all(func(id):return not is_instance_id_valid(id)),"scene disposal releases all staff placeholders")
 print("LEGACY_3D_SUPPRESSION_RESULT ",JSON.stringify({"checks":checks,"failures":failures,"status":"passed" if failures.is_empty() else "failed"}));quit(0 if failures.is_empty() else 1)
