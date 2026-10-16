extends RefCounted
## Authored target-table envelope only; unrelated furniture and walls remain solid.
const Dining=preload("res://scripts/gameplay/dining_placement.gd")
const Pose=preload("res://scripts/rendering/cleaning_tool_pose.gd")
const Character=preload("res://scripts/rendering/directional_character_art.gd")
const Contour=preload("res://scripts/rendering/character_arm_occlusion.gd")
const Motion=preload("res://scripts/rendering/illustrated_motion.gd")
const INK_MARGIN=.35 # Existing .7px contour, not a new body radius.
static var _styles:Dictionary={} # At most four authored styles × four quarter-turns.

static func geometry(style:String,rotation:int)->Dictionary:
 if style not in ["basic","cottage","retro","refined"]:style="basic"
 rotation=posmod(rotation,4);var key=style+str(rotation)
 if _styles.has(key):return _styles[key]
 var top=PackedVector2Array();var supports=[]
 if style in ["cottage","refined"]:
  var corners=Dining.COTTAGE_TOP if style=="cottage" else Dining.REFINED_TOP
  var points=[]
  for point in corners:points.append(Dining.plane(point.rotated(rotation*PI*.5)))
  top=Contour.rounded(points,2.3)
  for point in (Dining.COTTAGE_LEGS if style=="cottage" else Dining.REFINED_LEGS):
   var q=point if style=="cottage" else point*1.16
   supports.append({"point":Dining.plane(q.rotated(rotation*PI*.5))+Vector2(0,Dining.TABLE_HEIGHT-1),"radius":1.9 if style=="cottage" else 2.0})
 else:
  for i in 64:top.append(Vector2(cos(i*TAU/64),sin(i*TAU/64))*Dining.ROUND_TOP+Vector2(0,-Dining.TABLE_HEIGHT))
  if style=="retro":
   var disk=PackedVector2Array()
   for i in 64:disk.append(Vector2(cos(i*TAU/64)*15,sin(i*TAU/64)*6.5-1))
   supports.append({"polygon":disk})
  else:
   for point in Dining.BASIC_LEGS:supports.append({"point":point,"radius":1.5})
 _styles[key]={"top":top,"supports":supports,"cloth":Contour.rounded([Vector2(-4,0),Vector2(3,-3),Vector2(7,1),Vector2(0,4)],1.5)}
 return _styles[key]

static func envelope(entry:Dictionary,offset:Vector2)->bool:
 var heading:Vector2=(entry.contact-entry.center).normalized()
 # Keep the authored single-worker maximum approach, not an entire-table waiver.
 return offset.dot(heading)<=entry.natural.length()+.000001 and offset.dot(heading)>=0 and absf(offset.dot(heading.orthogonal()))<=.45+.000001

static func contact(entry:Dictionary,offset:Vector2)->bool:
 var heading:Vector2=entry.contact-entry.center
 var back=heading.x+heading.y<0;var mirror=-1.0 if heading.x-heading.y<0 else 1.0
 var near=Vector2(7,-24) if back else Vector2(-7,-24);var far=Vector2(-6,-26.5) if back else Vector2(6,-26.5)
 var floor=Motion.project(entry.center+offset-entry.contact)
 var top=-floor*Vector2(mirror,1)+Vector2(0,-Dining.TABLE_HEIGHT-1)
 var cloth=entry.table_geometry.cloth
 # Fixed arm and the complete authored cloth, including both stroke extrema.
 for phase in [0.0,.0625,.125,.1875,.25,.3125,.375,.4375]:
  var pose=Pose.table_pose(near,far,top,phase)
  if not pose.contact:return false
  var hand=floor+pose.hand*Vector2(mirror,1)
  for point in cloth:
   if _distance(hand+point*Vector2(mirror,1),entry.table_geometry.top)>-INK_MARGIN:return false
 return true

static func support_gap(entry:Dictionary,offset:Vector2,drawn_settings:Dictionary={})->float:
 var heading:Vector2=entry.contact-entry.center
 var back=heading.x+heading.y<0;var mirror=-1.0 if heading.x-heading.y<0 else 1.0
 # The existing planted-foot controller's settled geometry, not a full tile.
 var walk_heading=offset.normalized() if offset.length_squared()>.00001 else heading.normalized()
 var axis=Motion._shoe_axis(walk_heading)
 var settings={"grounded_feet":true,"mirror":mirror,"rest_axis":axis,"blend":0.0}
 for side in [-1.0,1.0]:
  var key="left" if side<0 else "right";var point=Motion._rest_center(side,walk_heading)
  settings[key+"_rest"]=point;settings[key+"_foot"]=point;settings[key+"_axis"]=axis
 if not drawn_settings.is_empty():settings=drawn_settings.duplicate();settings.mirror=mirror
 var legs=Character.leg_pose(settings,float(settings.get("blend",0))>.02,float(settings.get("phase",0)),back)
 var floor=Motion.project(entry.center+offset-entry.contact);var best=INF
 for key in ["near","far"]:
  var shoe=Contour.rounded(Character.shoe_outline(legs[key+"_foot"]+legs.body,legs[key+"_axis"]),.45)
  for i in shoe.size():shoe[i]=floor+shoe[i]*Vector2(mirror,1)
  for support in entry.table_geometry.supports:
   if support.has("point"):best=minf(best,_distance(support.point,shoe)-float(support.radius))
   else:
    for point in support.polygon:best=minf(best,_distance(point,shoe))
    for point in shoe:best=minf(best,_distance(point,support.polygon))
 return best

static func _distance(point:Vector2,polygon:PackedVector2Array)->float:
 var best=INF
 for i in polygon.size():best=minf(best,point.distance_to(Geometry2D.get_closest_point_to_segment(point,polygon[i],polygon[(i+1)%polygon.size()])))
 return -best if Geometry2D.is_point_in_polygon(point,polygon) else best
