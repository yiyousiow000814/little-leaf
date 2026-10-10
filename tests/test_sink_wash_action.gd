extends SceneTree
const Art=preload("res://scripts/cafe_sink_wash_art.gd")
const Fixture=preload("res://tests/role_fixture.gd")
const Painter=preload("res://scripts/directional_character_art.gd")
class LimbRecorder extends RefCounted:
 var segments=[]
 var polygons=[]
 func _round_limb(start:Vector2,finish:Vector2,_color,_width):
  segments.append([start,finish])
 func poly(points:Array,_color):polygons.append(PackedVector2Array(points))
var checks=0
var failures=[]
func _initialize():run.call_deferred()
func check(ok,label):
 checks+=1
 if not ok:failures.append(label);printerr("FAIL ",label)
func run():
 # Exercise the painter, not only the IK output: ordinary paw() normalizes to
 # a full arm and must never be used to render either half of a washing arm.
 var recorder=LimbRecorder.new();var painter=Painter.new();painter.a=recorder
 painter.origin=Vector2(37,61)
 for target in [Vector2(1,4),Vector2(8,-1),Vector2(-4,7),Vector2(0,10.4)]:
  var part=Art.arm(Vector2.ZERO,target);recorder.segments.clear();recorder.polygons.clear()
  painter.washing_arm(part,"efe5c7",4.8,2,false)
  check(recorder.segments.size()==1 and recorder.polygons.size()==1,"washing painter draws one upper arm and one tapered forearm")
  check(recorder.segments[0][0].is_equal_approx(painter.origin+part.shoulder) and recorder.segments[0][1].is_equal_approx(painter.origin+part.elbow),"painted upper arm ends at solved elbow")
  var outline:PackedVector2Array=recorder.polygons[0];var axis:Vector2=(part.hand-part.elbow).normalized()
  check(Geometry2D.is_point_in_polygon(painter.origin+part.hand,outline),"tapered forearm remains connected to solved wrist")
  for vertex in outline:
   check((vertex-painter.origin-part.hand).dot(axis)<=1.701,"painted forearm stops at palm end cap, never a re-extended arm")
 var max_error=0.0;var worst={}
 for rotation in range(4):
  var heading=-Vector2.DOWN.rotated(rotation*PI/2)
  var mirror=-1.0 if heading.x-heading.y<0 else 1.0;var back=heading.x+heading.y<0
  var ground=Vector2((heading.x-heading.y)*39,(heading.x+heading.y)*19.5)*(1.0-Art.work_inset(rotation))
  var near=Vector2(7,-24) if back else Vector2(-7,-24);var far=Vector2(-6,-26.5) if back else Vector2(6,-26.5)
  for count in [1,6]:
   var ref=Art.geometry(rotation,1.0,count);var ref_axes:Transform2D=ref.basis
   var reference={"center":(ground+ref.center)*Vector2(mirror,1),"basis":Transform2D(ref_axes.x*Vector2(mirror,1),ref_axes.y*Vector2(mirror,1),Vector2.ZERO)}
   var previous={};var largest_step=0.0;var largest_at=0.0
   for tick in range(1,2000):
    var seconds=tick*.01;var g=Art.geometry(rotation,seconds,count)
    var axes:Transform2D=g.basis;var basis=Transform2D(axes.x*Vector2(mirror,1),axes.y*Vector2(mirror,1),Vector2.ZERO)
    var pose=Art.pose(near,far,(ground+g.center)*Vector2(mirror,1),basis,seconds,reference)
    if not previous.is_empty():
     for name in ["near","far"]:
      var distance:float=pose[name].elbow.distance_to(previous[name].elbow)
      if distance>largest_step:largest_step=distance;largest_at=seconds
      if distance>=1.0:printerr("WASH_JUMP_DETAIL ",JSON.stringify({"rotation":rotation,"count":count,"seconds":seconds,"arm":name,"previous":previous[name],"current":pose[name]}))
      check(distance<1.0,"continuous anatomical elbow at rotation/count/time %s/%s/%.2f, step %.4f"%[rotation,count,seconds,distance])
      check(pose[name].hand.distance_to(previous[name].hand)<1.0,"continuous wrist through full lift/wash/lower cycle")
    previous=pose
   print("WASH_CONTINUITY rotation=",rotation," count=",count," max_step=",largest_step," time=",largest_at)
   for sample in range(1,400):
    var seconds=sample*.05;var g=Art.geometry(rotation,seconds,count)
    var center=(ground+g.center)*Vector2(mirror,1)
    var axes:Transform2D=g.basis;var basis=Transform2D(axes.x*Vector2(mirror,1),axes.y*Vector2(mirror,1),Vector2.ZERO)
    var pose=Art.pose(near,far,center,basis,seconds,reference)
    for part in [pose.near,pose.far]:
     check(is_equal_approx(part.shoulder.distance_to(part.elbow),5.25) and is_equal_approx(part.elbow.distance_to(part.hand),5.25),"fixed compact arm lengths")
     if seconds>=.8 and seconds<=19.3 and part.error>max_error:max_error=part.error;worst={"rotation":rotation,"seconds":seconds,"error":part.error,"center":str(center)}
    var local=(g.transform as Transform2D).affine_inverse()*g.water_contact
    check((local/Vector2(14,6.4)).length_squared()<1.02,"water lands on the active dish")
    check(absf(g.outlet.x-g.water_contact.x)<.001,"water starts directly under the outlet")
    check((g.scrub_local/Vector2(10,4)).length_squared()<1.0,"scrubbing and foam remain inside plate")
 check(max_error<.03,"both hands contact active dish while scrubbing: "+str(worst))
 # Front-view scrub wrist lies over the apron in projection; the actual bent
 # forearm must stay connected there while the far upper arm stays behind.
 painter.back=false;painter.profile=false
 var far_part=Art.arm(Vector2(6,-26.5),Vector2(7.76,-18.52),-1.0)
 var visible=painter.washing_forearm_parts(far_part,4.4,2)
 for fraction in [.2,.5,.8,1.0]:
  var point=far_part.elbow.lerp(far_part.hand,fraction);var covered=false
  for polygon in visible:
   if Geometry2D.is_point_in_polygon(point,polygon):covered=true
  check(covered,"working forearm remains connected through projected apron to wrist")
 for polygon in visible:
  for head in Painter.ArmOcclusion.head_masks(false,false,2,Vector2.ZERO):
   check(Geometry2D.intersect_polygons(polygon,head).is_empty(),"working forearm never paints over head")
 var lower_a=Art.arm(Vector2(7,-24),Vector2(9.295780671,-24.146546931),1.0)
 var lower_b=Art.arm(Vector2(7,-24),Vector2(9.392633807,-23.955624705),1.0)
 check(lower_a.elbow.distance_to(lower_b.elbow)<1.0,"lowering across shoulder height keeps the same elbow branch")
 var game=Fixture.new();root.add_child(game);await process_frame
 game.set_process(false);game.illustration.set_process(false);game.setup_dirty(false)
 var sink=game.model.get_item(3);var cleaner=game.worker("cleaner")
 game.model.customers.clear();game.service_guests.clear()
 game.dishwashing.dishes[1]={"id":1,"sink_id":3,"elapsed":0.0};game.dishwashing.next_id=2
 cleaner.pos=game.model.cell_center(game.model.workface_cell(sink));game._assign_service_job(cleaner,game.staff_states.find(cleaner));game.advance(.05)
 game.paused=false
 check(not Art.state(game,3).is_empty() and Art.state(game,3).water,"water starts with actual washing")
 game.paused=true;check(not Art.state(game,3).water,"paused simulation has no running stream")
 game.paused=false;game.editing=true;check(not Art.state(game,3).water,"editing stops running water")
 game.editing=false;cleaner.art_action="walking";check(Art.state(game,3).is_empty(),"leaving stops water immediately")
 cleaner.art_action="washing";cleaner.pos+=Vector2(1,0);check(Art.state(game,3).is_empty(),"stale action away from basin cannot produce water")
 cleaner.pos=game.model.cell_center(game.model.workface_cell(sink));cleaner.job_kind="";check(Art.state(game,3).is_empty(),"cancelled job cannot produce water")
 game.dishwashing.dishes[1].elapsed=19.95
 game._assign_service_job(cleaner,game.staff_states.find(cleaner));game.advance(.05)
 check(game.dishwashing.dishes.is_empty() and game.dishwashing.completed==1,"one washed dish is removed only at the twenty-second completion")
 check(Art.state(game,3).is_empty(),"completed washing has no water or foam source")
 print("SINK_WASH_ACTION_RESULT ",JSON.stringify({"checks":checks,"failures":failures,"max_hand_error":max_error,"worst":worst}));quit(0 if failures.is_empty() else 1)
