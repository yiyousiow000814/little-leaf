extends SceneTree
const Plan=preload("res://scripts/cafe_edit_plan.gd")
const Floor=preload("res://scripts/cafe_floor_availability.gd")
class TestMain extends "res://scripts/main.gd":
 var saves=0
 func _load_startup():save_writes_suppressed=true;fresh_start=true;MinimalStart.apply(model)
 func _save():saves+=1;return true
 func _interaction_over_ui(_screen:Vector2)->bool:return false
var checks=0;var failures=[]
func check(ok,label):
 checks+=1
 if not ok:failures.append(label);printerr("FAIL ",label)
func _initialize():run.call_deferred()
func run():
 root.size=Vector2i(1360,880)
 var game=TestMain.new();root.add_child(game);game.set_process(false);game.editing=true;game.model.coins=100000
 await process_frame
 var floor=game.interaction.floor_availability;var plan=game.interaction.edit_plan
 var cells=floor.refresh(game.model).duplicate(true);var builds=floor.builds
 check(cells.size()==108,"owned cells only")
 var blocked=0
 for cell in cells:
  if cells[cell].blocked:blocked+=1
 check(game.model.items.size()==6 and game.model.count_kind("counter")==0 and game.model.count_kind("bin")==0,"direct-pickup starter contains six furnishings, no service counter or mandatory bin")
 check(blocked==13,"six furnishings and seven required clear spaces are red, including chef workface")
 for x in 12:check(not cells[Vector2i(x,8)].blocked,"empty edge row is free "+str(x))
 check(cells[Vector2i(0,5)].blocked and cells[Vector2i(1,5)].blocked,"actual entrance and landing remain required")
 check(not cells[Vector2i(0,4)].blocked and not cells[Vector2i(1,4)].blocked,"table anchor dilation does not enlarge doorway red mask")
 var stove={}
 for item in game.model.items:
  if item.kind=="stove":stove=item;break
 check(cells[game.model.workface_cell(stove)].blocked,"stove workface is a mandatory red cell")
 for kind in ["","plant","table_set"]:
  game.selected_kind=kind
  for rotation in 4:
   game.rotation_step=rotation
   check(floor.refresh(game.model)==cells,"selection-independent floor "+kind+str(rotation))
 check(floor.builds==builds and plan.validations==0,"background selection/rotation does not scan placement candidates")
 # This relocation case needs an actor under the prospective plant. Do not
 # depend on the public new-game spawn point to arrange the obstruction.
 game.staff_states[0].pos=Vector2(2.5,.5)
 game.staff_states[0].node.position=Vector3(2.5,0,.5)
 var actors=game.interaction._staff_positions()
 var receipt=plan.prepare(game.model,"table_set",-1,0,Vector2i(5,8),actors)
 check(not receipt.ok and receipt.error=="Chair needs owned floor","whole table preview rejects chair extending beyond owned edge")
 check(not floor.refresh(game.model)[Vector2i(5,8)].blocked,"invalid whole footprint does not paint empty anchor floor red")
 var count=plan.validations
 for repeat in 100:plan.prepare(game.model,"table_set",-1,0,Vector2i(5,8),actors)
 check(plan.validations==count,"same hover reuses one immutable plan")
 receipt=plan.prepare(game.model,"table_set",-1,2,Vector2i(5,8),actors)
 check(receipt.ok,"rotated whole footprint fits inside same edge anchor")
 check(floor.refresh(game.model)==cells,"rotation changes cursor only")
 receipt=plan.prepare(game.model,"table_set",-1,0,Vector2i(3,2),actors)
 check(not receipt.ok and receipt.error=="Chair overlaps table","specific member explains hidden footprint overlap")
 var coins=game.model.coins;game.model.coins=0
 receipt=plan.prepare(game.model,"plant",-1,0,Vector2i(5,6),actors)
 check(not receipt.ok,"cursor still checks actual purchase funds")
 check(floor.refresh(game.model)==cells,"wallet does not change physical floor colors")
 game.model.coins=coins
 var before=[game.model.items.duplicate(true),game.model.coins,actors.duplicate()]
 receipt=plan.prepare(game.model,"plant",-1,0,Vector2i(2,0),actors)
 check(receipt.ok,"single hovered plan retains safe hidden-staff relocation")
 check(game.model.items==before[0] and game.model.coins==before[1] and game.interaction._staff_positions()==before[2] and game.saves==0,"preview is nonmutating")
 check(not plan.commit(game.model,receipt,actors),"live staff transition cannot be omitted")
 plan.invalidate();check(not plan.commit(game.model,receipt,actors,game._apply_edit_staff_positions),"cancel revokes receipt")
 receipt=plan.prepare(game.model,"plant",-1,0,Vector2i(2,0),actors)
 game.staff_states[0].pos=Vector2(5.5,.5)
 check(not plan.commit(game.model,receipt,game.interaction._staff_positions(),game._apply_edit_staff_positions),"stale actor position rejects commit")
 game.staff_states[0].pos=actors[0]
 game.selected_kind="plant";game.selected_id=-1;game.rotation_step=0
 game.interaction.refresh(game.illustration.iso(2.5,.5));game.interaction._commit_preview()
 check(game.model.items.size()==before[0].size()+1 and game.model.coins==coins-game.model.price_of("plant"),"live whole-plan purchase charges exactly once")
 check(game.saves==1,"successful commit saves once")
 for staff in game.staff_states:check(Plan.StaffRelocation.point_clear(game.model,staff.pos,game.model.items),"staff remains clear after joint commit")
 check(floor.refresh(game.model)[Vector2i(2,0)].blocked,"background updates only after actual occupancy changed")
 check(floor.builds==builds+1,"one actual layout change refreshes background cache once")
 print("FLOOR_AVAILABILITY_RESULT ",JSON.stringify({"checks":checks,"failures":failures,"red":blocked,"green":108-blocked,"target_validations":plan.validations,"background_builds":floor.builds}))
 game.queue_free();await process_frame;quit(0 if failures.is_empty() else 1)
