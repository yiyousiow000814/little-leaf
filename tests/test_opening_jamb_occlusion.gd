extends SceneTree
const Art=preload("res://scripts/illustrated_openings.gd")
const Geometry=preload("res://scripts/cafe_wall_openings.gd")
const Model=preload("res://scripts/cafe_model.gd")
class ScreenProjection extends RefCounted:
 var scale=1.0
 func iso(x:float,z:float,h=0.0)->Vector2:return Vector2(137,211)+Vector2((x-z)*39,(x+z)*19.5-h)*scale
var checks=0
var failures=[]
func check(ok:bool,label:String):
 checks+=1
 if not ok:failures.append(label);printerr("FAIL ",label)
func area(points:PackedVector2Array)->float:
 var total=0.0
 for index in points.size():total+=points[index].cross(points[(index+1)%points.size()])
 return absf(total)*.5
func in_or_on(point:Vector2,polygon:PackedVector2Array)->bool:
 if Geometry2D.is_point_in_polygon(point,polygon):return true
 for index in polygon.size():
  if point.distance_to(Geometry2D.get_closest_point_to_segment(point,polygon[index],polygon[(index+1)%polygon.size()]))<.002:return true
 return false
func contains_vertex(polygon:PackedVector2Array,point:Vector2)->bool:
 for vertex in polygon:
  if vertex.distance_to(point)<.002:return true
 return false
func inspect(view,opening:Dictionary,label:String):
 var before=opening.duplicate(true)
 var host:Dictionary=opening.host;var af:Vector2=opening.a+Art.front(host);var bf:Vector2=opening.b+Art.front(host);var ab:Vector2=opening.a+Art.back(host)
 var low=float(opening.bottom);var high=float(opening.top)
 var front_low=view.iso(af.x,af.y,low);var front_top=view.iso(af.x,af.y,high)
 var back_low=view.iso(ab.x,ab.y,low);var back_top=view.iso(ab.x,ab.y,high)
 var aperture=PackedVector2Array([front_low,view.iso(bf.x,bf.y,low),view.iso(bf.x,bf.y,high),front_top])
 var original=PackedVector2Array([front_low,back_low,back_top,front_top])
 check(not in_or_on(back_top,aperture),label+" reproduces old rear tip above the front aperture")
 var result=Art.visible_jamb_reveal(view,opening)
 check(result.size()==1,label+" reveal remains one visible face")
 if result.size()!=1:return
 var visible:PackedVector2Array=result[0]
 check(visible.size()>=3 and area(visible)>.1,label+" jamb thickness remains visible")
 check(area(visible)<area(original)-.01,label+" hidden lintel overlap is removed")
 check(contains_vertex(visible,front_low),label+" front lower attachment unchanged")
 check(contains_vertex(visible,back_low),label+" rear lower attachment unchanged")
 check(contains_vertex(visible,front_top),label+" front upper attachment unchanged")
 check(not contains_vertex(visible,back_top),label+" protruding rear upper tip absent")
 for vertex in visible:
  check(in_or_on(vertex,aperture),label+" every reveal vertex stays in the actual opening")
  check(in_or_on(vertex,original),label+" clipped reveal introduces no new area")
 # Convex face edges must remain inside both input polygons, including the
 # newly exposed diagonal at the front lintel's lower edge.
 for index in visible.size():
  var end=visible[(index+1)%visible.size()]
  for step in range(1,10):
   var sample=visible[index].lerp(end,float(step)/10.0)
   check(in_or_on(sample,aperture) and in_or_on(sample,original),label+" edge sample is visible through aperture")
 check(before==opening,label+" renderer does not mutate dimensions, host, identity or ownership")
func _initialize():
 var view=ScreenProjection.new()
 var walls:Array=[{"id":1,"axis":"x","x":2,"z":2,"height":"full","material":"original"},{"id":2,"axis":"x","x":3,"z":2,"height":"full","material":"original"},{"id":3,"axis":"z","x":6,"z":2,"height":"full","material":"original"},{"id":4,"axis":"z","x":6,"z":3,"height":"full","material":"original"}]
 var hosts=Geometry.shell_hosts("original",walls)
 for wall in walls:hosts.append(Geometry.wall_host(wall))
 hosts.append(Geometry.resolve_host("span:1,2",walls));hosts.append(Geometry.resolve_host("span:3,4",walls))
 for scale in [.65,1.0,2.5,5.0]:
  view.scale=scale
  for host in hosts:
   var length:float=host.a.distance_to(host.b)
   for kind in ["door","window"]:
    for width in ([.76,1.0,1.5] if kind=="door" else [.7]):
     if width>length:continue
     var attachment={"id":10,"kind":kind,"host_id":host.host_id,"offset":length*.5,"width":width,"paid_cost":40 if kind=="door" else 30}
     var opening=Geometry.aperture(attachment,walls)
     inspect(view,opening,str(host.host_id)+" "+kind+" width="+str(width)+" scale="+str(scale))
 # Exact starter doorway, including its existing collision/route dimensions.
 var model=Model.new();var starter=model.wall_openings()[0]
 var before=model.wall_attachments.duplicate(true)
 var passable=model.segment_blocked(Vector2(-.6,5.5),Vector2(.6,5.5))
 inspect(view,starter,"exact starter")
 check(model.wall_attachments==before and starter.width==1.0,"starter attachment remains unchanged")
 check(model.segment_blocked(Vector2(-.6,5.5),Vector2(.6,5.5))==passable,"starter passage is unchanged")
 print("OPENING_JAMB_RESULT ",JSON.stringify({"checks":checks,"failures":failures}))
 quit(0 if failures.is_empty() else 1)
