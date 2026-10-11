extends SceneTree
const Furniture=preload("res://scripts/illustrated_furniture.gd")
class MockModel extends RefCounted:
 var customers=[]
class MockGame extends Node:
 var staff_states=[]
 var model=MockModel.new()
class Probe extends Node2D:
 var game=MockGame.new()
 var commands=[]
 func rounded_poly(points,rounding,color):commands.append({"kind":"face","points":points,"rounding":rounding,"color":color})
 func poly(points,color):commands.append({"kind":"poly","points":points,"color":color})
 func line(p,q,color,width):commands.append({"kind":"line","color":color,"p":p,"q":q,"width":width})
var checks=0
var failures=[]
func check(ok:bool,label:String):
 checks+=1
 if not ok:failures.append(label);printerr("FAIL ",label)
func _initialize():
 var probe=Probe.new()
 var furniture=Furniture.new()
 for phase in ["idle","paying","recent"]:
  probe.game.staff_states=[{"job_kind":"take_payment","station_id":15,"art_action":"taking_payment","art_phase":.5}] if phase=="paying" else []
  probe.game.model.customers=[{"paid":true,"checkout_register_id":15,"phase":"leaving","elapsed":.4}] if phase=="recent" else []
  for rotation in range(4):
   var label=phase+" rotation "+str(rotation)
   probe.commands.clear()
   var before=JSON.stringify([probe.game.staff_states,probe.game.model.customers])
   furniture.draw_item(probe,"register",Vector2.ZERO,rotation,15)
   var seams=[];var doors=0;var handles=0;var base_index=-1;var cabinet_top=-1;var expected_light="526f62"
   if phase=="paying":expected_light="e2c973"
   if phase=="recent":expected_light="79ac78"
   var has_light=false;var receipts=0;var receipt_index=-1;var screen_index=-1
   for index in probe.commands.size():
    var command=probe.commands[index]
    if command.color=="756d53":seams.append(index)
    if command.color in ["bc9a63","d4b782"]:doors+=1
    if command.color=="8f7950":handles+=1
    if command.color=="8faaa0":base_index=index
    if command.color=="e7d7ad":cabinet_top=index
    if command.color==expected_light:has_light=true
    if command.color=="a4bbb0":screen_index=index
    if command.color=="fff5d8":
     receipts+=1;receipt_index=index
     check(command.points==[furniture.point(-.05,.15,33.25),furniture.point(.07,.15,33.25),furniture.point(.07,.27,33.25),furniture.point(-.05,.27,33.25)],label+" receipt keeps its surface and extent")
   check(seams.is_empty(),label+" no drawer seam on the plain panel or rear view")
   check(doors==0 and handles==0,label+" no customer-facing doors or handles")
   check(cabinet_top>=0 and base_index>cabinet_top,label+" same cabinet top under terminal equipment")
   check(has_light,label+" checkout indicator preserved")
   check(receipts==int(phase=="recent"),label+" receipt preserved")
   if receipts:
    check(receipt_index>base_index,label+" receipt rests above the terminal base")
    check((receipt_index<screen_index) if rotation in [1,2] else (receipt_index>screen_index),label+" screen occludes far-side paper; near-side paper remains in front")
   check(before==JSON.stringify([probe.game.staff_states,probe.game.model.customers]),label+" renderer does not mutate checkout state")
 # The generic kitchen cabinet retains its original storage doors.
 for rotation in range(4):
  probe.commands.clear()
  furniture.draw_item(probe,"counter",Vector2.ZERO,rotation,15)
  var doors=probe.commands.filter(func(c):return c.color=="bc9a63")
  var handles=probe.commands.filter(func(c):return c.color=="8f7950")
  check(doors.size()==(2 if rotation in [0,3] else 0),"ordinary cabinet doors preserved rotation "+str(rotation))
  check(handles.size()==(2 if rotation in [0,3] else 0),"ordinary cabinet handles preserved rotation "+str(rotation))
 probe.game.free();probe.free()
 print("REGISTER_EDGE_RESULT ",JSON.stringify({"checks":checks,"failures":failures}))
 quit(0 if failures.is_empty() else 1)
