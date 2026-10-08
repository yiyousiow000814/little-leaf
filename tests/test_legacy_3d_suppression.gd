extends SceneTree
class Fixture extends "res://scripts/main.gd":
 var people_created=0
 func _load_startup():save_writes_suppressed=true;fresh_start=true;MinimalStart.apply(model)
 func _save():return true
 func _setup_music():pass
 func _person(color:Color,apron=false)->Node3D:
  people_created+=1
  return super._person(color,apron)
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
 var illustrated=fixture()
 check(illustrated.people_created==0,"illustrated startup creates no legacy person meshes")
 check(illustrated.staff_states.all(func(s):return s.node is Node3D and s.node.get_child_count()==0),"staff retain stable lightweight Node3D placeholders")
 var fallback=fixture();var ids=fallback.staff_states.map(func(s):return s.node.get_instance_id())
 root.disable_3d=false;fallback._update_people()
 check(fallback.staff_states.all(func(s):return s.node.get_child_count()>0),"explicit legacy enable creates original staff visuals")
 check(ids==fallback.staff_states.map(func(s):return s.node.get_instance_id()),"lazy visual attachment preserves staff node identity")
 var fallback_person_count=fallback.people_created
 fallback._update_people()
 check(fallback.people_created==fallback_person_count,"repeated legacy synchronization does not recreate staff art")
 for tick in 300:
  root.disable_3d=true;illustrated._tick_live_service(1.0/30);illustrated._animate_staff(1.0/30);illustrated.animation_time+=1.0/30
  root.disable_3d=false;fallback._tick_live_service(1.0/30);fallback._animate_staff(1.0/30);fallback.animation_time+=1.0/30
  check(signature(illustrated)==signature(fallback),"2D and legacy authoritative movement/art/service/save parity tick %s"%tick)
  if tick%60==0:await process_frame
 var guest=fallback.model.customers[0];fallback._sync_service_guests();fallback.service_guests[int(guest.id)].plate_owner="table"
 root.disable_3d=false;fallback._update_service_props()
 check(not fallback.service_props.is_empty(),"enabled legacy view creates tableware props")
 root.disable_3d=true;fallback._update_service_props()
 check(fallback.service_props.is_empty(),"illustrated view retires hidden tableware props")
 root.disable_3d=false;fallback._update_service_props()
 check(not fallback.service_props.is_empty(),"reenabled legacy view reconstructs current props")
 fallback.paused=true
 root.disable_3d=true;fallback._update_people()
 var relocated=fallback.staff_states[0];relocated.pos+=Vector2(.25,.25)
 root.disable_3d=false;fallback._update_people()
 check(relocated.node.position==Vector3(relocated.pos.x,0.0,relocated.pos.y),"paused legacy reenable synchronizes authoritative position")
 var fallback_children=0
 for worker in fallback.staff_states:fallback_children+=worker.node.get_child_count()
 var counts={"fallback_staff_visual_children":fallback_children,"staff":illustrated.staff_states.size(),"illustrated_person_meshes":illustrated.people_created,"fallback_person_meshes":fallback.people_created}
 dispose(illustrated);dispose(fallback)
 for tween in get_processed_tweens():tween.kill()
 await process_frame;await process_frame
 print("LEGACY_3D_SUPPRESSION_RESULT ",JSON.stringify({"checks":checks,"failures":failures,"counts":counts,"status":"passed" if failures.is_empty() else "failed"}));quit(0 if failures.is_empty() else 1)
