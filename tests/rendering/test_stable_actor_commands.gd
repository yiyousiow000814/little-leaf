extends SceneTree
const Proof=preload("res://test_standby_native_retention.gd")
class Model extends RefCounted:
 var customers=[]
class Fixture extends Node:
 var model=Model.new()
 var staff_states=[]
 var ground_mess_generation=0
 var wall_detail=false
 var animation_time=0.0
var checks=0
var failures=[]
func check(value,label):
 checks+=1
 if not value:failures.append(label);printerr("FAIL ",label)
func _initialize():run.call_deferred()
func run():
 var fixture=Fixture.new();root.add_child(fixture)
 for id in 3:fixture.model.customers.append({"id":id})
 for index in 4:
  var node=Node3D.new();fixture.add_child(node);fixture.staff_states.append({"node":node})
 var art=Proof.Recorder.new();art.game=fixture
 art.use_retained_geometry=false;art.use_cached_heads=false;art.use_cached_moving_art=false;art.use_retained_head_nodes=false
 root.add_child(art)
 var roles=["chef","waiter","cleaner","cashier"]
 for frame in 24:
  fixture.animation_time=float(frame)*.17
  art.canvas_stream.begin(art,true);art.render_contacts.clear();art._begin_native_owners()
  var owners=[]
  var actors=range(7)
  if frame%2:actors.reverse()
  for index in actors:
   var staff=index>=3;var id=index-3 if staff else index
   var action=["standby","walking","taking_order","cooking"][frame%4] if staff else ["ordering","eating","drinking","paying"][frame%4]
   var moving=action=="walking";var seated=not staff
   var t=float(frame%17)/16.0
   for overlay in [false,true]:
    var pose={"seat_mix":1.0 if seated else 0.0,"view_back":frame%2==0,"mirror":-1.0 if frame%3==0 else 1.0,"phase":t,"hide_reach":not overlay,"reach_overlay":overlay,"cooking_elapsed":float(frame)*.2,"cooking_remaining":4.0,"cooking_strength":1.0}
    art.art_transform(Vector2(index*20,frame%3),0,Vector2(pose.mirror,1))
    var key=("staff/" if staff else "guest/")+str(id)+("|overlay" if overlay else "|body")
    var order=art.canvas_stream.cursor
    art.character(Vector2.ZERO,id,staff,moving,seated,action,t,Vector2(18,-28),Vector2(1,0),"none","none",pose,roles[id] if staff else "chef",key)
    owners.append(art.native_object_nodes[order])
   art._submit_native_world_shape(&"draw_rect",[Rect2(index,0,2,2),Color.WHITE,true,-1.0,false],Transform2D.IDENTITY)
  art._finish_native_objects();art.canvas_stream.finish()
  await process_frame;await process_frame
  check(art.native_actor_nodes.size()==14,"Exactly two nodes per live café actor")
  var last=-1
  for order in range(art.canvas_stream.cursor):
   var node=art.native_object_nodes.get(order,art.native_world_shapes.get(order))
   check(node.get_index()>last,"Actual mixed painter order matches submissions");last=node.get_index()
  for owner in owners:
   var reference=art.NativeDrawNode.new()
   var expected_arguments=owner.paint.get_bound_arguments().duplicate(true)
   expected_arguments[8]=float(frame%17)/16.0;expected_arguments[11].progress=float(frame%17)/16.0
   art.paint_native_object(reference,art._paint_native_character.bindv(expected_arguments))
   check(owner.get_meta("proof_commands")==reference.get_meta("proof_commands"),"Stable owner commands equal exact current original callback")
   var actual=owner.contacts[0].duplicate(true);var expected=reference.contacts[0].duplicate(true)
   actual.erase("native_owner");expected.erase("native_owner")
   check(actual==expected,"Stable owner contact fields equal original callback")
   reference.free()
 art.free();fixture.free();await process_frame;await process_frame
 print("STABLE_ACTOR_COMMANDS_RESULT ",JSON.stringify({"checks":checks,"failures":failures,"pixels":false}));quit(0 if failures.is_empty() else 1)
