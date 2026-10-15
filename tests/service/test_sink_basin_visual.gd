extends SceneTree
const Geometry=preload("res://scripts/rendering/kitchen_worktop_geometry.gd")
const Furniture=preload("res://scripts/rendering/illustrated_furniture.gd")
const Atlas=preload("res://scripts/rendering/furniture_static_atlas.gd")
var checks=0
var failures=[]
class Probe extends Node2D:
 var upright_dishes=0
 var points=[]
 func rounded_poly(shape,_radius,_color):points.append_array(shape)
 func poly(shape,_color):points.append_array(shape)
 func line(a,b,_color,_width=1):points.append(a);points.append(b)
 func _face_line(a,b,_color,_width=1):points.append(a);points.append(b)
 func _face_ellipse(at,radius,_color):points.append(at-radius);points.append(at+radius)
 func ellipse(at,radius,_color):points.append(at-radius);points.append(at+radius)
 func outlined_ellipse(at,radius,_fill,_stroke,_width=1):
  upright_dishes+=1;points.append(at-radius);points.append(at+radius)
class PlateProbe extends "res://scripts/rendering/illustrated_cafe.gd":
 var fills=[]
 var outlines=[]
 var cup_shadows=0
 var cup_rims=[]
 func _retained_fill(points:PackedVector2Array,_tint:Color):fills.append(points)
 func art_polyline(points:PackedVector2Array,_tint:Color,_width:float):outlines.append(points)
 func rounded_poly(_points,_radius,_color):pass
 func line(_a:Vector2,_b:Vector2,_color,_width:float=1):pass
 func outlined_ellipse(at:Vector2,radius:Vector2,_fill,_stroke,_width:float=1):
  if radius==Vector2(3.7,1.4):cup_rims.append(at)
 func ellipse(_at,radius,_color):
  if radius==Vector2(4.2,1.6):cup_shadows+=1
class SinkModel extends RefCounted:
 var sink={"id":1,"kind":"sink","rot":0,"x":0,"z":0}
 func get_item(_id):return sink
 func workface_cell(_sink):return Vector2i(0,1)
 func cell_center(cell):return Vector2(cell)+Vector2(.5,.5)
class SinkQueue extends RefCounted:
 var dishes={}
 func count_at(_id):return dishes.size()
 func entry(worker):return dishes.get(int(worker.job_dish_id),{})
class SinkGame extends Node:
 var model=SinkModel.new()
 var dishwashing=SinkQueue.new()
 var staff_states=[]
 var service_guests={}
 var paused=true
 var editing=false
class SinkFurnitureProbe extends "res://scripts/rendering/illustrated_furniture.gd":
 func draw_sink_front_rim(artist:Node2D,_at:Vector2,_rotation:int):artist.events.append("rim")
 func draw_sink_front_tap(artist:Node2D,_at:Vector2,_rotation:int):artist.events.append("tap")
class SinkPayloadProbe extends PlateProbe:
 var events=[]
 var plate_clips=[]
 func _plate(_at:Vector2,_remaining=1.0,_dirty=false):
  events.append("plate");plate_clips.append(_plate_clip.duplicate())
func _initialize():run.call_deferred()
func check(ok,label):
 checks+=1
 if not ok:failures.append(label);printerr("FAIL ",label)
func run():
 var furniture=Furniture.new();var probe=Probe.new();root.add_child(probe)
 for rotation in range(4):
  var center=Geometry.surface(Geometry.SINK_BASIN_CENTER,Geometry.SINK_RIM_HEIGHT,rotation)
  var rim=PackedVector2Array()
  for step in 128:
   var theta=step*TAU/128.0
   rim.append(Geometry.surface(Geometry.SINK_BASIN_CENTER+Vector2(cos(theta)*Geometry.SINK_BASIN_OUTER.x,sin(theta)*Geometry.SINK_BASIN_OUTER.y),30.0,rotation))
  for step in 128:
   var theta=step*TAU/128.0
   var point=center+Vector2(cos(theta)*14.0,sin(theta)*6.4)
   check(Geometry2D.is_point_in_polygon(point,rim),"unchanged plate footprint fits basin rim r%s sample%s"%[rotation,step])
  check(Geometry.height(Geometry.SINK_BOTTOM_HEIGHT)<Geometry.height(Geometry.SINK_RIM_HEIGHT)-5.0,"basin floor is more than five art pixels recessed r"+str(rotation))
  check(Geometry.sink_plate_anchor(rotation).y>center.y+4.0,"bottom dish rests inside the bowl r"+str(rotation))
  var stack_top=Geometry.sink_plate_anchor(rotation)+Vector2(0,-5*2.2-6.4)
  var outlet=Geometry.surface(Vector2(Geometry.SINK_BASIN_CENTER.x,Geometry.SINK_TAP_OUTLET_Z),Geometry.SINK_TAP_OUTLET_HEIGHT,rotation)
  check(outlet.y<stack_top.y-8.0,"outlet has eight projected pixels above full stack r"+str(rotation))
  check(Geometry.sink_tap_in_front(rotation)==(rotation in [1,2]),"tap layering follows rotated physical mount r"+str(rotation))
  probe.points.clear();probe.upright_dishes=0
  furniture.draw_item(probe,"sink",Vector2.ZERO,rotation,3)
  check(probe.upright_dishes==0,"no ornamental rack plates r"+str(rotation))
  var safe=Atlas.bounds("sink").grow(-1.0)
  for p in probe.points:check(safe.has_point(p),"static basin/tap remains within retained atlas r"+str(rotation))
  var zero_count=probe.points.size()
  probe.points.clear();furniture.draw_item(probe,"sink",Vector2(200,300),rotation,3)
  check(abs(probe.points.size()-zero_count)<12,"translated catalog sink preserves cavity polygons r"+str(rotation))
  for p in probe.points:check(safe.has_point(p-Vector2(200,300)),"translated sink geometry stays correctly anchored r"+str(rotation))
  check(Geometry.SINK_BASIN_CENTER.x-Geometry.SINK_BASIN_OUTER.x>-Furniture.CABINET_TILE_SPAN*.5 and Geometry.SINK_BASIN_CENTER.x+Geometry.SINK_BASIN_OUTER.x<Furniture.CABINET_TILE_SPAN*.5,"basin fits full-cell cabinet width r"+str(rotation))
  check(Geometry.SINK_BASIN_CENTER.y-Geometry.SINK_BASIN_OUTER.y>-Furniture.CABINET_TILE_SPAN*.5 and Geometry.SINK_BASIN_CENTER.y+Geometry.SINK_BASIN_OUTER.y<Furniture.CABINET_TILE_SPAN*.5,"basin fits full-cell cabinet depth r"+str(rotation))
 var plate=PlateProbe.new()
 plate._plate_clip=PackedVector2Array([Vector2(5,-2),Vector2(12,-2),Vector2(12,12),Vector2(5,12)])
 plate._plate_clipped_shape(PackedVector2Array([Vector2(0,0),Vector2(10,0),Vector2(10,10),Vector2(0,10)]),Color.WHITE,Color.BLACK,1.0)
 check(not plate.fills.is_empty(),"submerged ceramic keeps clipped fills")
 var cut_stroked=false
 for segment in plate.outlines:
  for index in range(segment.size()-1):
   if is_equal_approx(segment[index].x,5.0) and is_equal_approx(segment[index+1].x,5.0):cut_stroked=true
 check(not plate.outlines.is_empty() and not cut_stroked,"only original ceramic contour is stroked, never artificial clipping edge")
 # The basin is painted immediately before its payload. Its original rim must
 # not gain another contour when a dish appears; aperture masking owns depth.
 var sink_game=SinkGame.new();var payload=SinkPayloadProbe.new()
 payload.game=sink_game;payload.furniture_art=SinkFurnitureProbe.new()
 for rotation in range(4):
  sink_game.model.sink.rot=rotation
  for state in ["empty","queued","washing","lowering"]:
   sink_game.dishwashing.dishes={} if state=="empty" else {1:{"id":1,"sink_id":1}}
   sink_game.staff_states=[]
   if state in ["washing","lowering"]:
    sink_game.staff_states=[{"role":"cleaner","job_kind":"wash","station_id":1,"art_action":"washing","pos":Vector2(.5,1.5),"job_dish_id":1,"job_elapsed":8.0 if state=="washing" else 19.99}]
   payload.events.clear();payload.plate_clips.clear();payload._sink_dishes(1)
   check(not payload.events.has("rim"),"no second rim ink in %s r%s"%[state,rotation])
   if state=="empty":
    check(payload.events.is_empty(),"idle basin painter stays untouched r%s"%rotation)
   else:
    check(payload.events==["plate","tap"],"plate followed by rotated faucet in %s r%s"%[state,rotation])
    var expected=PackedVector2Array() if state=="washing" else Geometry.sink_outline(Geometry.SINK_BASIN_INNER,Geometry.SINK_OPENING_HEIGHT,rotation)
    check(payload.plate_clips.size()==1 and payload.plate_clips[0]==expected,"submerged aperture mask and raised clearance preserved in %s r%s"%[state,rotation])
 payload.free();sink_game.free()
 plate._action_prop(Vector2.ZERO,Vector2.ZERO,"carrying_drink",.4,"drink","none")
 check(plate.cup_shadows==0,"held cup does not cast a floating surface shadow")
 plate._cup(Vector2.ZERO)
 check(plate.cup_shadows==1,"resting cup retains its original contact shadow")
 # The held glass keeps its original rim/size and front head painter order.
 var character=preload("res://scripts/rendering/directional_character_art.gd")
 var masks=preload("res://scripts/rendering/character_arm_occlusion.gd")
 for away in [false,true]:
  plate.cup_rims.clear()
  var hand=character.carry_anchor(away)
  plate._action_prop(Vector2.ZERO,hand,"carrying_drink",.4,"drink","none")
  check(plate.cup_rims.size()==1,"held cup draws its complete original rim")
  if plate.cup_rims.size()!=1:continue
  var cup_rim=plate.cup_rims[0]
  for species in range(3):
   var visible=true
   for mask in masks.head_masks(away,false,species,Vector2.ZERO):
    for step in range(48):
     var angle=step*TAU/48.0
     var point=cup_rim+Vector2(cos(angle)*4.1,sin(angle)*1.8)
     if Geometry2D.is_point_in_polygon(point,mask):visible=false
   check(visible,"complete held cup rim clears unchanged head "+str(away)+":"+str(species))
 plate.free()
 print("SINK_BASIN_VISUAL_RESULT ",JSON.stringify({"checks":checks,"failures":failures,"rotations":4,"plate_radius_unchanged":[14,6.4]}))
 quit(0 if failures.is_empty() else 1)
