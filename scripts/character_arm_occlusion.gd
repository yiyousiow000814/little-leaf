extends RefCounted
## Presentation silhouettes only. Sockets, hand targets and arm lengths are
## unchanged; a far upper arm belongs behind the intact torso and head.
static func torso_points(back:bool,profile=false)->Array:
 if profile:return [Vector2(-5.5,-28),Vector2(5,-27),Vector2(8,-22),Vector2(7,-12),Vector2(-6,-11.5),Vector2(-8,-20)]
 if back:return [Vector2(-7.8,-28),Vector2(5.3,-29.5),Vector2(9,-23),Vector2(8.2,-11.5),Vector2(-7,-10),Vector2(-10,-17)]
 return [Vector2(-7.5,-28.5),Vector2(5.6,-27),Vector2(9.3,-21),Vector2(8.0,-10.8),Vector2(-7,-12.2),Vector2(-10,-20)]
static func rounded(points:Array,radius:float)->PackedVector2Array:
 var result=PackedVector2Array()
 for i in points.size():
  var vertex:Vector2=points[i];var previous:Vector2=points[(i+points.size()-1)%points.size()];var next:Vector2=points[(i+1)%points.size()]
  var start=vertex+(previous-vertex).normalized()*minf(radius,vertex.distance_to(previous)*.3)
  var finish=vertex+(next-vertex).normalized()*minf(radius,vertex.distance_to(next)*.3)
  for k in range(6):
   var t=float(k)/5.0;result.append((1-t)*(1-t)*start+2*(1-t)*t*vertex+t*t*finish)
 return result
static func oval(center:Vector2,radii:Vector2)->PackedVector2Array:
 var result=PackedVector2Array()
 for k in range(32):result.append(center+Vector2(cos(k*TAU/32),sin(k*TAU/32))*radii)
 return result
static func capsule(start:Vector2,finish:Vector2,width:float)->PackedVector2Array:
 var angle=(finish-start).angle();var result=PackedVector2Array()
 for k in range(13):result.append(finish+Vector2.from_angle(angle-PI*.5+PI*float(k)/12)*width*.5)
 for k in range(13):result.append(start+Vector2.from_angle(angle+PI*.5+PI*float(k)/12)*width*.5)
 return result
static func head_masks(back:bool,profile:bool,species:int,offset:Vector2)->Array[PackedVector2Array]:
 var result:Array[PackedVector2Array]=[]
 if profile:
  var points=[Vector2(-12,-44),Vector2(-9,-50),Vector2(-1,-52),Vector2(7,-49),Vector2(10,-43),Vector2(9,-38),Vector2(13,-36),Vector2(14,-33),Vector2(9,-29),Vector2(1,-27),Vector2(-9,-30),Vector2(-13,-37)]
  for i in points.size():points[i]+=offset
  result.append(rounded(points,4.0))
 else:
  result.append(oval(Vector2(-.5 if back else 0,-38)+offset,Vector2(13.1,12.7)))
  if not back and species!=1:result.append(oval(Vector2(4.5,-33)+offset,Vector2(8.5,5.4)))
 return result
static func visible_far_arm(shoulder:Vector2,hand:Vector2,width:float,back:bool,profile=false,species=0,head_offset=Vector2.ZERO,body_profile:Dictionary={})->Array[PackedVector2Array]:
 var parts:Array[PackedVector2Array]=[capsule(shoulder,hand,width)]
 var masks:Array[PackedVector2Array]=[rounded(preload("res://scripts/character_proportion_study.gd").points(torso_points(back,profile),body_profile),3.5)]
 masks.append_array(head_masks(back,profile,species,head_offset))
 for mask in masks:
  # Account for the existing 0.7px silhouette stroke on both the body and
  # the clipped arm, so a new cut edge cannot paint back over the shirt.
  for cover in Geometry2D.offset_polygon(mask,.7):
   var visible:Array[PackedVector2Array]=[]
   for part in parts:visible.append_array(Geometry2D.clip_polygons(part,cover))
   parts=visible
 return parts
