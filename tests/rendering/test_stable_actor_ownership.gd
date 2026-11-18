extends SceneTree
class Model extends RefCounted:
 var customers=[]
class Fixture extends Node:
 var model=Model.new()
 var staff_states=[]
 var ground_mess_generation=0
class Artist extends "res://scripts/rendering/illustrated_cafe.gd":
 func _ready():pass
 func _process(_delta):pass
 func _draw():pass
 func proof_paint(id,progress):
  line(Vector2.ZERO,Vector2(5,5),Color.WHITE,1.0)
  return {"id":id,"progress":progress}
var failures=[]
var checks=0
func check(value,label):
 checks+=1
 if not value:failures.append(label);printerr("FAIL ",label)
func _initialize():run.call_deferred()
func start(art):
 art.canvas_stream.begin(art,true);art.render_contacts.clear();art._begin_native_owners()
func submit(art,key,id,progress=.3):
 var order=art.canvas_stream.cursor
 art.retain_native_local_object(art.proof_paint.bind(id,progress),["character",id,progress],Transform2D.IDENTITY,key)
 return art.native_object_nodes[order]
func world(art):
 art._submit_native_world_shape(&"draw_rect",[Rect2(0,0,2,2),Color.WHITE,true,-1.0,false],Transform2D.IDENTITY)
 return art.native_world_shapes[art.canvas_stream.cursor-1]
func finish(art):
 art._finish_native_objects();art.canvas_stream.finish()
func settle():
 await process_frame;await process_frame
func run():
 var fixture=Fixture.new();root.add_child(fixture)
 var staff=Node3D.new();fixture.add_child(staff);fixture.staff_states=[{"node":staff}]
 var guest={"id":1};fixture.model.customers=[guest]
 var art=Artist.new();art.game=fixture;root.add_child(art)
 start(art)
 var body=submit(art,"guest/1|body",1)
 var shape=world(art)
 var worker=submit(art,"staff/0|body",2)
 var overlay=submit(art,"guest/1|overlay",1)
 finish(art);await settle()
 check(art.native_actor_nodes.size()==3,"Only requested live passes allocated")
 check(body.get_index()<shape.get_index() and shape.get_index()<worker.get_index() and worker.get_index()<overlay.get_index(),"Initial mixed painter order")
 check(body.contacts.size()==1 and body.contacts[0].id==1,"Current deferred contact")
 var body_revision=body.paint_revision;var body_draws=body.draw_count
 start(art)
 check(art.native_object_nodes.is_empty(),"Current-order view rebuilt without aliases")
 check(submit(art,"staff/0|body",2)==worker,"Staff stable across painter slots")
 check(submit(art,"guest/1|overlay",1)==overlay,"Overlay stable and separate")
 var moved_shape=world(art)
 check(submit(art,"guest/1|body",1)==body,"Body stable across painter slots")
 finish(art);await settle()
 check(worker.get_index()<overlay.get_index() and overlay.get_index()<moved_shape.get_index() and moved_shape.get_index()<body.get_index(),"Changed mixed painter order")
 check(body.paint_revision==body_revision and body.draw_count==body_draws,"Order-only move retains exact draw list")
 var state=art.character_pick_geometry._node_state(body,0)
 art.move_child(body,0)
 check(state!=art.character_pick_geometry._node_state(body,0),"Unexpected sibling reorder invalidates picker state")
 start(art);var fallback=submit(art,"",99);finish(art);await settle()
 check(fallback!=body and fallback!=worker and fallback!=overlay,"Fallback never borrows stable actor")
 check(art.native_actor_nodes.size()==3 and not body.visible,"Culling retains live actor owners hidden")
 start(art);check(submit(art,"guest/1|body",1)==body,"Hidden actor resurrection retains owner");finish(art);await settle()
 check(body.visible and body.contacts[0].id==1,"Resurrection has current contacts")
 # Queue a new paint, then cull before completion; return must repaint correctly.
 start(art);submit(art,"guest/1|body",1,.6);finish(art)
 start(art);finish(art);await settle()
 check(not body.visible and body.contacts.is_empty(),"Queued culled actor cannot publish contacts")
 start(art);submit(art,"guest/1|body",1,.6);finish(art);await settle()
 check(body.visible and body.contacts.size()==1 and body.contacts[0].progress==.6,"Queued cull resurrection completes exact pending callback")
 # Queue a new paint, then remove the exact actor before it completes.
 start(art);submit(art,"guest/1|body",1,.8);finish(art)
 fixture.model.customers.clear();await settle()
 check(not body.visible and body.contacts.is_empty() and body.appearance.is_empty(),"Queued deleted actor cannot publish or retain stale callback")
 check(art.render_contacts.filter(func(c):return c.get("native_owner",-1)==body.get_instance_id()).is_empty(),"Deleted queued owner purges emitted contacts")
 var retired=weakref(body);start(art);finish(art);await settle()
 check(retired.get_ref()==null and art.native_actor_nodes.size()==1,"Full roster departure frees both guest passes")
 # Same-id, same-value guest dictionaries are distinct logical actors.
 fixture.model.customers=[{"id":1}];start(art);var first=submit(art,"guest/1|body",1);finish(art);await settle()
 var old=weakref(first);fixture.model.customers=[{"id":1}]
 start(art);var replacement=submit(art,"guest/1|body",1);finish(art);await settle()
 check(old.get_ref()==null and replacement!=first,"Same-model reused ID cannot alias a replaced dictionary")
 var old_staff=weakref(worker);var new_staff=Node3D.new();fixture.add_child(new_staff);fixture.staff_states=[{"node":new_staff}]
 start(art);var new_worker=submit(art,"staff/0|body",2);finish(art);await settle()
 check(old_staff.get_ref()==null and new_worker!=worker,"Staff roster replacement uses node identity")
 # Replace the same model record before a queued paint completes.
 start(art);var replaced_pending=submit(art,"guest/1|body",1,.91);finish(art)
 fixture.model.customers=[{"id":1}];await settle()
 check(replaced_pending.contacts.is_empty() and not replaced_pending.visible,"Queued same-ID replacement cannot publish old actor")
 start(art);submit(art,"guest/1|body",1);finish(art);await settle()
 # A same-Main restore epoch invalidates all stable owners.
 start(art);var pending=submit(art,"guest/1|body",1,.9);finish(art)
 fixture.ground_mess_generation+=1;await settle()
 check(pending.contacts.is_empty() and not pending.visible,"Queued restore invalidates old epoch")
 var old_epoch=weakref(pending);start(art);var restored=submit(art,"guest/1|body",1);finish(art);await settle()
 check(old_epoch.get_ref()==null and restored!=pending,"Restore creates new epoch owner")
 # Model replacement is a separate epoch even within the same Main fixture.
 start(art);submit(art,"guest/1|body",1,.92);finish(art)
 fixture.model=Model.new();fixture.model.customers=[{"id":1}];await settle()
 check(restored.contacts.is_empty() and not restored.visible,"Queued model replacement cannot publish old model")
 start(art);restored=submit(art,"guest/1|body",1);finish(art);await settle()
 start(art);submit(art,"guest/1|body",1);art.canvas_stream.active=false;finish(art)
 check(not restored.visible,"Disabled native frame hides registered owners")
 start(art);submit(art,"guest/1|body",1);finish(art);await settle()
 check(restored.visible,"Native path reenable restores current actor")
 art._hide_native_owners();check(not restored.visible,"Early return hides owned nodes")
 check(art.native_actor_nodes.size()<=2*(fixture.model.customers.size()+fixture.staff_states.size()),"Registry bounded by two passes per full live roster")
 for cycle in 8:
  fixture.model.customers=[{"id":1}];start(art);restored=submit(art,"guest/1|body",1);submit(art,"guest/1|overlay",1);finish(art)
  check(art.native_actor_nodes.size()<=2*(fixture.model.customers.size()+fixture.staff_states.size()),"Repeated replacement keeps registered owner bound")
  await settle()
  check(art.get_children().filter(func(n):return n.is_queued_for_deletion()).is_empty(),"Deferred retired owners actually leave tree")
 var observed=weakref(restored);art.free();fixture.free();await settle()
 check(observed.get_ref()==null,"Artist lifetime releases all owned nodes")
 print("STABLE_ACTOR_OWNERSHIP_RESULT ",JSON.stringify({"checks":checks,"failures":failures}));quit(0 if failures.is_empty() else 1)
