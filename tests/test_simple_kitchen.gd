extends SceneTree
const Artist=preload("res://scripts/illustrated_cafe.gd")
class PlateSpy:
 extends "res://scripts/illustrated_cafe.gd"
 var calls=[]
 func _plate(at:Vector2,remaining=1.0,dirty=false):calls.append({"at":at,"remaining":remaining,"dirty":dirty})
var checks=0
var failures=[]
func check(ok,label):
 checks+=1
 if not ok:failures.append(label);push_error(label)
func _initialize():run.call_deferred()
func tick(game,delta):
 game._tick_live_service(delta);game._update_people();game._animate_staff(delta)
func run():
 check(Artist._kitchen_visual_action("plating",true,"chef")=="idle","Chef keeps a plating gesture")
 for action in ["cooking","preparing_food","placing_plate","serving"]:
  check(Artist._kitchen_visual_action(action,true,"chef")==action,"Unrelated work gesture changed")
 for level in [1,3]:
  seed(123456)
  var game=load("res://main.tscn").instantiate();game.set_process(false);root.add_child(game)
  game.editing=false;game.paused=false;game.model.operating_open=true
  var stove=game.model.get_item(1);stove.level=level
  var chef
  for step in range(3000):
   tick(game,.1)
   for candidate in game.staff_states:
    if candidate.art_action=="cooking":chef=candidate;break
   if chef!=null:break
  check(chef!=null,"Real meal did not start")
  if chef==null:game.queue_free();await process_frame;continue
  var spy=PlateSpy.new();spy.game=game
  var record=game.service_guests[int(chef.job_guest_id)]
  for action in ["preparing_food","cooking","plating"]:
   chef.art_action=action
   for phase in [0.0,.2,.64,1.0]:
    chef.art_phase=phase
    spy.calls.clear();spy._station_payloads(1,"stove",0)
    check(spy.calls.is_empty(),"Kitchen worktop still draws a plate")
  chef.art_action="cooking"
  chef.job_elapsed=game.Model.cooking_seconds(game.Model.stove_speed_multiplier(stove))-.05
  game._animate_staff(.1);game._animate_staff(.1)
  check(chef.job_step==2 and chef.art_action=="plating","Existing handoff phase/timing changed")
  check(record.plate_owner=="kitchen","Ready meal transfers too early")
  check(is_equal_approx(spy._stove_food_remaining(1),1.0),"Food shrinks into an invisible worktop plate")
  check(game.illustration._stove_heat_state(1).is_empty(),"Finished meal still burns")
  for step in range(30):
   game._animate_staff(.05)
   if record.plate_owner=="staff":break
  check(record.plate_owner=="staff" and chef.art_payload=="plate","Ready meal never reaches chef")
  check(is_zero_approx(spy._stove_food_remaining(1)),"Ready meal duplicates food in pan")
  for step in range(2000):
   tick(game,.05)
   if record.plate_owner=="station":break
  check(record.plate_owner=="station","Direct stove output never completes")
  spy.calls.clear();spy._station_payloads(int(record.plate_target_id),"stove",0)
  check(spy.calls.size()==1 and is_equal_approx(spy.calls[0].remaining,1.0),"Ready meal missing from stove output")
  spy.free();game.queue_free();chef=null;game=null
  await process_frame
 print("SIMPLE_KITCHEN_TESTS checks=",checks," failures=",failures.size())
 quit(0 if failures.is_empty() else 1)
