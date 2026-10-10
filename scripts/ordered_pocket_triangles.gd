extends RefCounted
## Closed positive-width AA outlines, in native core/left/right strip order.
## Adapted from Godot4.6.3 renderer_canvas_cull.cpp (MIT).
## See docs/third-party/GODOT-AA-LICENSE.txt for attribution and license.
var vertices=PackedVector2Array()
var colors=PackedColorArray()
var indices=PackedInt32Array()
static func f32(value:float)->float:return PackedFloat32Array([value])[0]
func append_triangles(points:PackedVector2Array,tints:PackedColorArray,triangles:PackedInt32Array):
 var base=vertices.size();vertices.append_array(points);colors.append_array(tints)
 for index in triangles:indices.append(base+index)
func append_strip(points:PackedVector2Array,tints:PackedColorArray):
 var triangles=PackedInt32Array()
 for i in range(points.size()-2):
  if i%2==0:triangles.append_array(PackedInt32Array([i,i+1,i+2]))
  else:triangles.append_array(PackedInt32Array([i+1,i,i+2]))
 append_triangles(points,tints,triangles)
static func edge(current:Vector2,previous:Vector2)->Vector2:
 var bisector=(previous*current.length()-current*previous.length()).normalized()
 var angle=bisector.angle_to(previous)
 var sine=Vector2.from_angle(angle).y
 var length=1.0
 if not is_zero_approx(sine) and not current.is_equal_approx(previous):length=clampf(f32(1.0/sine),-3.0,3.0)
 else:bisector=current.orthogonal()
 if bisector.is_zero_approx():bisector=current.orthogonal()
 return bisector*length
func append_closed_outline(points:PackedVector2Array,color:Color,width:float):
 var count=points.size();var first=Vector2.ZERO;var last=Vector2.ZERO
 for i in range(1,count):
  first=(points[i]-points[i-1]).normalized()
  if not first.is_zero_approx():break
 for i in range(count-1,0,-1):
  last=(points[i]-points[i-1]).normalized()
  if not last.is_zero_approx():break
 var native_width=f32(width);var feather=1.25
 if native_width<1.0:feather=f32(feather*native_width)
 var core=PackedVector2Array();var left=PackedVector2Array();var right=PackedVector2Array()
 var solid=PackedColorArray();var fading=PackedColorArray();var clear=Color(color,0.0);var previous=Vector2.ZERO
 for i in range(count):
  var current=previous if i==count-1 else (points[i+1]-points[i]).normalized()
  if current.is_zero_approx():current=previous
  if i==0:previous=last
  elif i==count-1:previous=first
  var direction=edge(current,previous);var offset=direction*(native_width*.5);var border=direction*feather;var p=points[i]
  core.append(p+offset);core.append(p-offset)
  left.append(p+offset);left.append(p+offset+border)
  right.append(p-offset);right.append(p-offset-border)
  solid.append(color);solid.append(color);fading.append(color);fading.append(clear)
  previous=current
 append_strip(core,solid);append_strip(left,fading);append_strip(right,fading)
func append_contour(points:PackedVector2Array,color:Color,width:float)->bool:
 var triangles=Geometry2D.triangulate_polygon(points)
 if triangles.is_empty():return false
 var tints=PackedColorArray();tints.resize(points.size());tints.fill(color)
 append_triangles(points,tints,triangles)
 var closed=points.duplicate();closed.append(closed[0]);append_closed_outline(closed,color,width)
 return true
