extends SceneTree
## Workface validation and selected-station ground markers survive notice removal.
const NoBottom=preload("res://tests/no_bottom_notifications.gd")
class FixtureMain extends "res://scripts/main.gd":
 var save_calls=0
 func _load_startup():save_writes_suppressed=true;fresh_start=true;MinimalStart.apply(model)
 func _save():save_calls+=1;return true
var game
var checks=0
var failures=[]
func _init():call_deferred("run")
func check(ok:bool,label:String):
 checks+=1
 if not ok:failures.append(label);printerr("FAIL ",label)
func state():return JSON.stringify([game.model.items,game.model.customers,game.model.coins,game.model.revision,game.save_calls,game.model._next_item_id])
func select(item:Dictionary):
 game.interaction.preview_active=false;game.selected_kind="";game.selected_id=int(item.id)
 game.workface_guidance._refresh()
func run():
 root.size=Vector2i(1360,880);game=FixtureMain.new();root.add_child(game)
 game.set_process(false);game.illustration.set_process(false);game.paused=true;game.editing=true
 await process_frame;await process_frame
 var m=game.model;var guide=game.workface_guidance;var stove={}
 for item in m.items:
  if item.kind=="stove":stove=item;break
 var front=m.workface_cell(stove)
 select(stove)
 check(guide.markers.size()==1 and guide.markers[0].cell==front and guide.markers[0].clear,"selected clear stove shows its true working tile")
 check(guide.markers[0].reserved and guide.marker_color(guide.markers[0])==Color("aa5845"),"clear selected stove keeps its reserved tile red")
 var before=state();var preview=m.placement_access_issues("plant",front.x,front.y)
 check(not m.can_place("plant",front.x,front.y),"new stove-front obstruction is rejected")
 check(preview.size()==1 and int(preview[0].item_id)==int(stove.id) and preview[0].cell==front,"preview validator still identifies actual obstructed station and cell")
 check(state()==before,"workface preview never mutates layout, money or save")
 var blocker={"id":m._next_item_id,"kind":"plant","x":front.x,"z":front.y,"rot":0};m._next_item_id+=1;m.items.append(blocker);m._notify()
 select(stove)
 check(guide.markers.size()==1 and not guide.markers[0].clear,"blocked selected stove keeps red ground guidance")
 var issues=m.layout_access_issues()
 check(issues.size()==1 and int(issues[0].item_id)==int(stove.id) and issues[0].cell==front,"existing invalid layout remains structurally diagnosable")
 before=state()
 var repaired=m.placement_access_issues("plant",4,6,int(blocker.id),0)
 check(m.can_place("plant",4,6,int(blocker.id),0) and repaired.is_empty(),"moving obstruction to clear floor is a valid repair preview")
 check(state()==before,"repair preview preserves committed state")
 for size in [Vector2i(344,500),Vector2i(390,844),Vector2i(960,540),Vector2i(1360,880)]:
  root.size=size;await process_frame;await process_frame
  game._update_ui();game.illustration.update_projection();guide._refresh()
  check(guide.markers.size()==1 and guide.markers[0].cell==front and not guide.markers[0].clear,"resize preserves grid-space ground guidance "+str(size))
  check(game.illustration.screen_to_cell(game.illustration.iso(front.x+.5,front.y+.5))==front,"projection preserves inverse workface pick "+str(size))
  check(state()==before,"resize does not mutate gameplay or save "+str(size))
 NoBottom.verify(game,check,"ground guidance")
 m.items.erase(blocker);m._notify();select(stove)
 check(guide.markers[0].clear and m.layout_access_issues().is_empty(),"repair immediately restores clear ground guidance")
 for kind in ["counter","register"]:
  var station={}
  for item in m.items:
   if item.kind==kind:station=item;break
  select(station)
  check(guide.markers.size()==2 and guide.markers[0].cell!=guide.markers[1].cell,"both working sides stay distinct for "+kind)
 var register=m.checkout_register();var register_front=m.workface_cell(register)
 before=state()
 check(not m.can_place("plant",register_front.x,register_front.y),"required register-front obstruction stays invalid")
 check(not m.last_placement_issue.is_empty() and int(m.last_placement_issue.item_id)==int(register.id),"invalid placement retains exact validator issue")
 check(state()==before,"rejected placement is nonmutating")
 game.selected_kind="stove";game.selected_id=-1
 var interaction=game.interaction;interaction.preview_active=true;interaction.drag_kind="stove";interaction.drag_item_id=-1;interaction.drag_cell=Vector2i(5,6);interaction.drag_rotation=1
 guide._refresh()
 var expected=m.workface_cell({"kind":"stove","x":5,"z":6,"rot":1})
 check(guide.markers.size()==1 and guide.markers[0].cell==expected,"rotated draft uses its own workface")
 check(guide.markers[0].reserved and guide.marker_color(guide.markers[0])==Color("aa5845"),"rotated stove draft shows a red reserved workface")
 game._cancel_selection();guide._refresh()
 check(guide.markers.is_empty(),"Cancel clears draft ground markers")
 select(stove);game.editing=false;guide._refresh()
 check(guide.markers.is_empty() and guide.describe(game).is_empty(),"ground markers remain Decorate-only")
 check(game.save_calls==0,"all presentation and validation checks leave persistence untouched")
 print("WORKFACE_GROUND_GUIDANCE_RESULT ",JSON.stringify({"checks":checks,"failures":failures}))
 for player in game.audio_players.values():player.stop();player.stream=null
 game.settings_controls.sfx_player.stop();game.settings_controls.sfx_player.stream=null
 for tween in get_processed_tweens():tween.kill()
 game.queue_free();await process_frame;await process_frame
 quit(0 if failures.is_empty() else 1)
