extends SceneTree
## Physical whole-footprint plans replace the retired all-floor color cache.
const Plan=preload("res://scripts/gameplay/cafe_edit_plan.gd")
class TestMain extends "res://scripts/main.gd":
 var saves=0
 func _load_startup():save_writes_suppressed=true;fresh_start=true;MinimalStart.apply(model)
 func _save():saves+=1;return true
 func _interaction_over_ui(_screen:Vector2)->bool:return false
var checks=0;var failures=[]
func check(ok,label):
 checks+=1
 if not ok:failures.append(label);printerr("FAIL ",label)
func has_property(object,key):
 for value in object.get_property_list():
  if str(value.name)==key:return true
 return false
func _initialize():run.call_deferred()
func run():
 root.size=Vector2i(1360,880)
 var game=TestMain.new();root.add_child(game);game.set_process(false);game.illustration.set_process(false);game.paused=true;game.editing=true;game.model.coins=100000
 await process_frame
 var m=game.model;var interaction=game.interaction;var plan=interaction.edit_plan
 check(not has_property(interaction,"floor_availability"),"retired background cache is not allocated")
 check(not interaction.has_method("draw_floor_feedback"),"retired whole-floor painter is actually absent")
 check(not FileAccess.file_exists("res://scripts/gameplay/cafe_floor_availability.gd"),"obsolete cache source is deleted")
 check(not has_property(game,"workface_guidance"),"unused guidance node is not retained")
 for kind in ["","plant","table_set"]:
  for rot in 4:
   game.selected_kind=kind;game.rotation_step=rot
   check(plan.validations==0,"background selection never requests a placement plan "+kind+str(rot))
 for staff in game.staff_states:staff.pos=Vector2(1.5,7.5)
 m.wall_actor_positions.clear()
 var actors=interaction._staff_positions()
 var receipt=plan.prepare(m,"table_set",-1,0,Vector2i(5,8),actors)
 check(not receipt.ok and not receipt.physical_ok and receipt.error=="Chair needs owned floor","whole table rejects a seat beyond owned floor")
 var count=plan.validations
 for repeat in 100:plan.prepare(m,"table_set",-1,0,Vector2i(5,8),actors)
 check(plan.validations==count,"unchanged hover reuses the current receipt")
 receipt=plan.prepare(m,"table_set",-1,2,Vector2i(5,8),actors)
 check(receipt.ok and receipt.physical_ok,"rotated whole footprint fits owned edge")
 receipt=plan.prepare(m,"table_set",-1,0,Vector2i(3,2),actors)
 check(not receipt.ok and not receipt.physical_ok and receipt.error=="Chair overlaps table","hidden member overlap remains rejected")
 var coins=m.coins;m.coins=0
 receipt=plan.prepare(m,"plant",-1,0,Vector2i(5,6),actors)
 check(not receipt.ok and receipt.physical_ok,"funding and physical fit stay independent")
 check(not plan.commit(m,receipt,actors),"unfunded receipt cannot publish")
 m.coins=coins;game.staff_states[0].pos=Vector2(2.5,.5);actors=interaction._staff_positions()
 var before=JSON.stringify([m.items,m.coins,m.revision,m._next_item_id,actors,game.saves])
 receipt=plan.prepare(m,"plant",-1,0,Vector2i(2,0),actors)
 check(not receipt.ok and not receipt.physical_ok,"present staff body rejects placement without hypothetical relocation")
 check(not plan.commit(m,receipt,actors),"body-overlapping receipt cannot commit")
 check(JSON.stringify([m.items,m.coins,m.revision,m._next_item_id,interaction._staff_positions(),game.saves])==before,"body refusal preserves layout, wallet, identity and people")
 receipt=plan.prepare(m,"plant",-1,0,Vector2i(5,6),actors)
 check(receipt.ok and receipt.physical_ok,"clear owned footprint prepares")
 plan.invalidate();check(not plan.commit(m,receipt,actors),"cancel revokes the receipt")
 receipt=plan.prepare(m,"plant",-1,0,Vector2i(5,6),actors)
 game.staff_states[0].pos=Vector2(5.5,6.5)
 check(not plan.commit(m,receipt,interaction._staff_positions()),"a newly moved body invalidates an earlier receipt")
 game.staff_states[0].pos=actors[0]
 game.selected_kind="plant";game.selected_id=-1;game.rotation_step=0
 var old_count=m.items.size();interaction.refresh(game.illustration.iso(5.5,6.5));interaction._commit_preview()
 check(m.items.size()==old_count+1 and m.coins==coins-m.price_of("plant"),"live clear-footprint purchase publishes and charges once")
 check(game.saves==1,"successful live purchase saves once")
 check(game.staff_states[0].pos==actors[0],"purchase never silently relocates a body")
 print("FLOOR_AVAILABILITY_RESULT ",JSON.stringify({"checks":checks,"failures":failures,"target_validations":plan.validations,"retired_cache_allocated":false}))
 for player in game.audio_players.values():player.stop();player.stream=null
 game.settings_controls.sfx_player.stop();game.settings_controls.sfx_player.stream=null
 for tween in get_processed_tweens():tween.kill()
 game.queue_free();await process_frame;await process_frame;quit(0 if failures.is_empty() else 1)
