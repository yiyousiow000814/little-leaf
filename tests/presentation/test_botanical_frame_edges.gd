extends SceneTree
## Synthetic retained frame geometry and mask ownership; actual PNG review is separate.
const Frame=preload("res://scripts/ui/reference_botanical_frame.gd")
var checks=0
var failures=[]
func check(ok:bool,label:String):
 checks+=1
 if not ok:failures.append(label);push_error(label)
func _initialize():run.call_deferred()
func run():
 var frame=Frame.new();root.add_child(frame);frame.set_premium(true)
 for allocation in [Vector2(1757.788,752.886),Vector2(1270.24,797.28),Vector2(1790,786)]:
  frame.size=allocation;frame._arrange()
  frame.set_surfaces(Rect2(allocation.x*.48,90,allocation.x*.48,allocation.y-200),Rect2(10,allocation.y-90,allocation.x-20,80),true)
  check(frame.pieces[0].texture_filter==CanvasItem.TEXTURE_FILTER_LINEAR,"adjacent frame slices share level-zero linear sampling")
  check(frame.pieces[0].position==Vector2(12,8),"upper-left paint stays on panel inner edge")
  check(is_equal_approx(frame.pieces[1].get_rect().end.x,allocation.x-12),"upper-right paint stays on panel inner edge")
  check(is_equal_approx(frame.pieces[2].get_rect().end.y,allocation.y-8),"lower-left paint stays on panel inner edge")
  check(is_equal_approx(frame.pieces[0].size.x,frame.pieces[0].size.y),"corner leaf proportions remain uniform")
  check(is_equal_approx(frame.pieces[5].position.x,frame.pieces[0].get_rect().end.x) and is_equal_approx(frame.pieces[5].get_rect().end.x,frame.pieces[1].position.x),"upper edge spans both anchored corners")
  check(is_equal_approx(frame.pieces[7].position.y,frame.pieces[0].get_rect().end.y) and is_equal_approx(frame.pieces[7].get_rect().end.y,frame.pieces[2].position.y),"left edge spans both anchored corners")
  var quiet:Array[Rect2]=[Rect2(10,0,220,90),Rect2(20,allocation.y*.52,allocation.x*.45,allocation.y*.31)]
  frame.set_quiet_rects(quiet)
  var materials=[]
  for part in frame.pieces+frame.local_pieces+frame.finials+frame.emboss:
   check(part.material is ShaderMaterial and part.material.get_shader_parameter("quiet_count")==2,"every ornament owns actual quiet-mask shader state")
   var regions=part.material.get_shader_parameter("quiet_rects")
   var point=quiet[0].position-part.position
   check(regions[0]==Vector4(point.x,point.y,point.x+quiet[0].size.x,point.y+quiet[0].size.y),"mask coordinates follow each retained piece")
   materials.append(part.material.get_instance_id())
  for repeat in 10:frame.set_surfaces(frame._library,frame._tray,true);frame.set_quiet_rects(quiet)
  var index=0
  for part in frame.pieces+frame.local_pieces+frame.finials+frame.emboss:
   check(part.material.get_instance_id()==materials[index],"repeated layout reuses mask material")
   index+=1
  for ink in frame.ink_rects():
   for area in quiet:check(not ink.intersection(area).has_area(),"reported visible ink agrees with actual quiet masks")
 var owned_masks=[]
 for part in frame.pieces+frame.local_pieces+frame.finials+frame.emboss:owned_masks.append(weakref(part.material))
 frame.free()
 for probe in owned_masks:check(probe.get_ref()==null,"panel teardown releases every owned mask material")
 print("BOTANICAL_FRAME_EDGES_RESULT ",JSON.stringify({"checks":checks,"failures":failures}));quit(0 if failures.is_empty() else 1)
