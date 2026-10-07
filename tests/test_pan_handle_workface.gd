extends SceneTree
const Furniture=preload("res://scripts/illustrated_furniture.gd")
const Model=preload("res://scripts/cafe_model.gd")
const AA=preload("res://scripts/retained_aa_strokes.gd")
const Pose=preload("res://scripts/cooking_tool_pose.gd")
const Atlas=preload("res://scripts/furniture_static_atlas.gd")
var checks=0
var failures=[]
class PanSpy:
 extends Node2D
 var calls=[]
 func line(start:Vector2,finish:Vector2,color,width=1.0):calls.append({"kind":"handle","start":start,"finish":finish,"color":color,"width":width})
 func rounded_poly(_points:Array,_radius:float,_color):calls.append({"kind":"body"})
 func ellipse(_at:Vector2,_size:Vector2,_color):calls.append({"kind":"fill"})
 func outlined_ellipse(_at:Vector2,_size:Vector2,_color,_edge,_width=1.0):calls.append({"kind":"rim"})
func check(ok,label):
 checks+=1
 if not ok:failures.append(label);push_error(label)
func _initialize():run.call_deferred()
func run():
 var model=Model.new()
 var artist=PanSpy.new()
 var furniture=Furniture.new()
 furniture.a=artist;furniture.origin=Vector2(100,200);furniture.kitchen_height=true
 for rot in range(4):
  var item={"x":9,"z":4,"rot":rot,"kind":"stove"}
  var work=Vector2(model.workface_cell(item)-Vector2i(9,4))
  var projected=Vector2((work.x-work.y)*34,(work.x+work.y)*17)
  var handle=Furniture.stove_handle_points(rot)
  var center=Furniture.stove_food_surface(rot)
  var mount=handle[0]-center;var tip=handle[1]-center
  check(handle.size()==2,"Handle must have one mount and one end")
  check(mount.dot(projected)>0 and tip.dot(projected)>mount.dot(projected),"Handle points away from chef workface")
  check(absf((handle[1]-handle[0]).normalized().cross(projected.normalized()))<.00001,"Handle is not aligned with chef work side")
  check(mount.distance_to(projected*.16*Furniture.PAN_WIDTH)<.00001 and tip.distance_to(projected*.24*Furniture.PAN_WIDTH)<.00001,"Handle uses a different attachment height or side")
  var rim_distance=pow(mount.x/(8.5*Furniture.PAN_WIDTH),2)+pow(mount.y/(4.2*Furniture.PAN_DEPTH),2)
  check(rim_distance>.9 and rim_distance<1.1,"Handle mount does not meet the existing pan rim")
  check(center.is_equal_approx(Furniture.KitchenGeometry.surface(Vector2.ZERO,41,rot)),"Food contact anchor moved")
  check(is_equal_approx((handle[1]-handle[0]).length(),Vector2(34,17).length()*.08*Furniture.PAN_WIDTH),"Handle length changes with rotation")
  var bounds=Atlas.bounds("stove_pan")
  for point in handle:
   check(bounds.grow(-1.2).has_point(point),"Handle antialias edge leaves existing atlas bounds")
  check(Furniture.stove_handle_in_front(rot)==(projected.y>0),"Handle depth side disagrees with chef workface")
  artist.calls.clear();furniture.turn=rot;furniture.stove_pan()
  var handles=[];var handle_index=-1;var rim_index=-1
  for i in range(artist.calls.size()):
   if artist.calls[i].kind=="handle":
    handles.append(artist.calls[i]);handle_index=i
   if artist.calls[i].kind=="rim":rim_index=i
  check(handles.size()==3,"Handle must contain one collar, one grip and one highlight")
  if handles.size()==3:
   var mount_at=furniture.origin+handle[0];var tip_at=furniture.origin+handle[1]
   check(handles[0].start.is_equal_approx(mount_at) and handles[0].finish.is_equal_approx(mount_at.lerp(tip_at,.32)),"Metal collar does not join the rim")
   check(handles[1].start.is_equal_approx(mount_at.lerp(tip_at,.25)) and handles[1].finish.is_equal_approx(tip_at),"Grip does not overlap the metal collar")
   check(handles[0].color=="aebca5" and handles[1].color=="79674e" and is_equal_approx(handles[1].width,2.2),"Grip material or thickness changed")
   check((handles[2].finish-handles[2].start).is_equal_approx(handles[1].finish-handles[1].start) and handles[2].width<handles[1].width,"Highlight changes grip direction or silhouette")
  check((handle_index>rim_index)==Furniture.stove_handle_in_front(rot),"Handle is hidden by the wrong pan layer")
 # The far-side handle must stay clear of both the skull and the lower
 # muzzle while the chef leans through the entire cooking cycle. Include
 # all nine AA quads: 1.25px at each end and outside the 2.2px grip.
 # Head bounds include the .7px outline plus a .25px real separation.
 for rot in [1,2]:
  var mirror=1.0 if rot==1 else -1.0
  var pan=Vector2(23.4*mirror,-20.3)
  var handle=Furniture.stove_handle_points(rot)
  var center=Furniture.stove_food_surface(rot)
  var start=pan+handle[0]-center
  var finish=pan+handle[1]-center
  var axis=(finish-start).normalized()
  var side=axis.orthogonal()
  var aa_start=start-axis*AA.FEATHER_SIZE
  var aa_finish=finish+axis*AA.FEATHER_SIZE
  for sample in range(371):
   var body=Pose.body_weight(float(sample)*Pose.FRY_SECONDS/370.0)*Vector2(mirror,1)
   for along in [0.0,.25,.5,.75,1.0]:
    for edge in [-1.1-AA.FEATHER_SIZE,0.0,1.1+AA.FEATHER_SIZE]:
     var at=aa_start.lerp(aa_finish,along)+side*edge-body
     var skull=(at-Vector2(0,-38))/Vector2(13.7,13.3)
     var muzzle=(at-Vector2(4.5*mirror,-33))/Vector2(9.1,6.0)
     check(skull.length_squared()>1.0,"Pan handle AA envelope lacks skull clearance")
     check(muzzle.length_squared()>1.0,"Pan handle AA envelope lacks cheek clearance")
 artist.free()
 print("PAN_HANDLE_WORKFACE_TESTS checks=",checks," failures=",failures.size())
 quit(0 if failures.is_empty() else 1)
