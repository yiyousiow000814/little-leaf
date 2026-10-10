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
 func poly(points:Array,_color):calls.append({"kind":"body","points":points})
 func ellipse(at:Vector2,size:Vector2,color):calls.append({"kind":"fill","at":at,"size":size,"color":color})
 func _face_line(start:Vector2,finish:Vector2,color,width=1.0):calls.append({"kind":"indicator","start":start,"finish":finish,"color":color,"width":width})
 func _face_ellipse(_at:Vector2,_size:Vector2,_color):calls.append({"kind":"indicator_cap"})
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
  var side_center=Furniture.KitchenGeometry.surface(Vector2.ZERO,Furniture.stove_handle_height(rot),rot)
  var mount=handle[0]-side_center;var tip=handle[1]-side_center
  check(handle.size()==2,"Handle must have one mount and one end")
  check(mount.dot(projected)>0 and tip.dot(projected)>mount.dot(projected),"Handle points away from chef workface")
  check(absf((handle[1]-handle[0]).normalized().cross(projected.normalized()))<.00001,"Handle is not aligned with chef work side")
  var outset=0.0 if Furniture.stove_handle_in_front(rot) else Furniture.PAN_REAR_HANDLE_OUTSET
  check(mount.distance_to(projected*(.16*Furniture.PAN_WIDTH+outset))<.00001 and tip.distance_to(projected*(.26*Furniture.PAN_WIDTH+outset))<.00001,"Handle uses a different attachment height or side")
  var old_mount=Furniture.KitchenGeometry.surface(Vector2(0,.16*Furniture.PAN_WIDTH),39.0,rot)
  var old_tip=Furniture.KitchenGeometry.surface(Vector2(0,.26*Furniture.PAN_WIDTH),39.0,rot)
  var expected_shift=Vector2.ZERO if Furniture.stove_handle_in_front(rot) else projected*Furniture.PAN_REAR_HANDLE_OUTSET+Vector2(0,2)
  check((handle[0]-old_mount).is_equal_approx(expected_shift) and (handle[1]-old_tip).is_equal_approx(expected_shift),"Annotated rear offset differs or unmarked front handle moved")
  var rim_distance=pow(mount.x/(8.5*Furniture.PAN_WIDTH),2)+pow(mount.y/(4.2*Furniture.PAN_DEPTH),2)
  if Furniture.stove_handle_in_front(rot):
   check(rim_distance>.9 and rim_distance<1.1,"Front handle ground location does not meet the vessel side")
  else:
   var hidden_mount=(handle[0]-center)/Vector2(8.5*Furniture.PAN_WIDTH,4.2*Furniture.PAN_DEPTH)
   check(hidden_mount.length_squared()<1.0,"Rear mount must stay behind the vessel silhouette")
  for equivalent in [rot-4,rot+4]:
   check(Furniture.stove_handle_points(equivalent)==handle,"Equivalent rotation changes pan attachment")
  check(is_equal_approx(side_center.y-center.y,2.0 if Furniture.stove_handle_in_front(rot) else 4.0),"Handle floats above the sidewall instead of below the lip")
  check(center.is_equal_approx(Furniture.KitchenGeometry.surface(Vector2.ZERO,41,rot)),"Food contact anchor moved")
  check(is_equal_approx((handle[1]-handle[0]).length(),Vector2(34,17).length()*.10*Furniture.PAN_WIDTH),"Handle length changes with rotation")
  var bounds=Atlas.bounds("stove_pan")
  for point in handle:
   check(bounds.grow(-1.1-AA.FEATHER_SIZE).has_point(point),"Handle antialias edge leaves existing atlas bounds")
  check(Furniture.stove_handle_in_front(rot)==(projected.y>0),"Handle depth side disagrees with chef workface")
  artist.calls.clear();furniture.turn=rot;furniture.stove_pan()
  var handles=[];var handle_index=-1;var rim_index=-1
  for i in range(artist.calls.size()):
   if artist.calls[i].kind=="handle":
    handles.append(artist.calls[i]);handle_index=i
   if artist.calls[i].kind=="rim":rim_index=i
   if artist.calls[i].kind=="body" and artist.calls[i].has("points"):
    for scale in [1.0,4.0,12.0]:
     var polygon=PackedVector2Array(artist.calls[i].points)
     check(not Geometry2D.triangulate_polygon(Transform2D(0,Vector2.ONE*scale,0,Vector2.ZERO)*polygon).is_empty(),"Actual pan shell cannot be filled at native or magnified scale")
  check(handles.size()==3,"Handle must contain exactly one collar, grip and highlight, without a foreground collar repaint")
  if handles.size()>=3:
   var mount_at=furniture.origin+handle[0];var tip_at=furniture.origin+handle[1]
   check(handles[0].start.is_equal_approx(mount_at) and handles[0].finish.is_equal_approx(mount_at.lerp(tip_at,.80)),"Metal collar does not join the rim")
   check(handles[1].start.is_equal_approx(mount_at.lerp(tip_at,.68)) and handles[1].finish.is_equal_approx(tip_at),"Grip does not overlap the metal collar")
   check(handles[0].color=="6d8475" and handles[1].color=="79674e" and is_equal_approx(handles[1].width,2.2),"Grip material or thickness changed")
   check((handles[2].finish-handles[2].start).is_equal_approx(handles[1].finish-handles[1].start) and handles[2].width<handles[1].width,"Highlight changes grip direction or silhouette")
  if Furniture.stove_handle_in_front(rot):
   check(handle_index>rim_index,"Front handle hidden behind pan")
  else:
   check(handle_index<rim_index and handles[2].color=="b49b73","Far collar and wood grip must remain behind the pan lip")
   for i in range(rim_index+1,artist.calls.size()):
    check(artist.calls[i].kind!="handle","Hidden rear collar must not be repainted over the pan or wood grip")
  artist.calls.clear();furniture._stove_controls()
  var knobs=[];var indicators=[]
  for call in artist.calls:
   if call.kind=="fill":knobs.append(call)
   if call.kind=="indicator":indicators.append(call)
  var visible_controls=furniture.front_visible()
  check(knobs.size()==(1 if visible_controls else 0),"Single-burner stove must have one knob on its visible control face")
  check(indicators.size()==knobs.size(),"Each stove knob must have exactly one indicator")
  if visible_controls and knobs.size()==1 and indicators.size()==1:
   var knob_at=furniture.point(0,Furniture.STOVE_TILE_SPAN*.5,26)
   check(knobs[0].at.is_equal_approx(knob_at),"Stove knob must stay centered on its rotated control face")
   check(knobs[0].size==Vector2(1.8,1.8) and knobs[0].color=="f0e5c7","Centered knob must retain its size and material")
   check(indicators[0].start.is_equal_approx(knob_at) and indicators[0].finish.is_equal_approx(knob_at+Vector2(0,-1)),"Centered knob indicator must retain its orientation")
 # The far-side handle must stay clear of both the skull and the lower
 # muzzle while the chef leans through the entire cooking cycle. Include
 # all nine AA quads: 1.25px at each end and outside the 2.2px grip.
 # Head bounds include the .7px outline plus a .25px real separation.
 for rot in [1,2]:
  var mirror=1.0 if rot==1 else -1.0
  var distance=1.0-Pose.WORK_INSET
  var pan=Vector2(39.0*distance*mirror,19.5*distance-Furniture.KitchenGeometry.height(41))
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
