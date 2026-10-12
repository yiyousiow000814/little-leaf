extends RefCounted
## Calm, tapered grass blades from the existing world-anchored stroke pairs.
## No RNG, map/model access, texture, timer or per-frame allocation. The caller
## retains the resulting one-surface mesh until its opacity changes.
const STEPS=3
const FEATHER=.38
const LEFT=Color(.44,.57,.30,.38)
const RIGHT=Color(.53,.64,.37,.35)

static func blade(from:Vector2,to:Vector2,width:float,tint:Color)->Dictionary:
 var vertices=PackedVector2Array()
 var colors=PackedColorArray()
 var indices=PackedInt32Array()
 var axis=to-from
 var normal=axis.normalized().orthogonal()
 # Stable left/right bend gives each existing clump a soft uneven silhouette.
 # It is deliberately smaller than the old positive-width AA fringe.
 var sign=-1.0 if axis.x<0 else 1.0
 var bend=normal*.34*sign
 for step in range(STEPS+1):
  var t=float(step)/STEPS
  var center=from.lerp(to,t)+bend*sin(t*PI)
  var tangent=(axis+bend*PI*cos(t*PI)).normalized()
  var side=tangent.orthogonal()
  var half=width*.5*(1.0-t)
  var core=Color(tint,tint.a*lerpf(1.0,.82,t))
  var clear=Color(core,0.0)
  vertices.append(center-side*(half+FEATHER))
  vertices.append(center-side*half)
  vertices.append(center+side*half)
  vertices.append(center+side*(half+FEATHER))
  colors.append(clear);colors.append(core);colors.append(core);colors.append(clear)
  if step==0:continue
  var previous=(step-1)*4
  var current=step*4
  for band in range(3):
   for index in [previous+band,previous+band+1,current+band+1,previous+band,current+band+1,current+band]:indices.append(index)
 return {"vertices":vertices,"colors":colors,"indices":indices}

# Conservative cosmetic zone: all current and future 18x18 buildable land,
# plus a .75-cell margin, is excluded from the larger exterior accents.
const BUILDABLE=Rect2(Vector2.ZERO,Vector2(18,18))
const BUILD_MARGIN=.75
static func world_cell(p:Vector2)->Vector2:
 return Vector2(p.x/78.0+p.y/39.0,p.y/39.0-p.x/78.0)
static func exterior_safe(p:Vector2)->bool:
 var cell=world_cell(p)
 return not BUILDABLE.grow(BUILD_MARGIN).has_point(cell) and not (cell.x>=-6.20 and cell.x<=.20)
static func readable_blade(from:Vector2,to:Vector2,width:float,tint:Color)->Dictionary:
 var cell=world_cell(from)
 var selected=posmod(floori(cell.x)*7+floori(cell.y)*13,3)!=0
 if selected and exterior_safe(from):
  var richer=Color(tint,tint.a*1.52)
  var grown=blade(from,from+(to-from)*1.72,width*1.38,richer)
  var safe=true
  var occupied=Rect2(world_cell(grown.vertices[0]),Vector2.ZERO)
  for point in grown.vertices:
   safe=safe and exterior_safe(point)
   occupied=occupied.expand(world_cell(point))
  safe=safe and not occupied.intersects(BUILDABLE.grow(BUILD_MARGIN))
  safe=safe and (occupied.end.x< -6.20 or occupied.position.x>.20)
  if safe:
   grown["enhanced"]=true
   return grown
 var quiet=blade(from,to,width,tint)
 quiet["enhanced"]=false
 return quiet

static func geometry(left:PackedVector2Array,right:PackedVector2Array,opacity:float)->Dictionary:
 var vertices=PackedVector2Array()
 var colors=PackedColorArray()
 var indices=PackedInt32Array()
 var count=0
 for batch in [{"points":left,"color":LEFT,"width":.94},{"points":right,"color":RIGHT,"width":.86}]:
  assert(batch.points.size()%2==0,"Grass expects existing disconnected point pairs")
  var tint:Color=batch.color;tint.a*=opacity
  for i in range(0,batch.points.size(),2):
   var shape=readable_blade(batch.points[i],batch.points[i+1],batch.width,tint)
   var offset=vertices.size()
   vertices.append_array(shape.vertices);colors.append_array(shape.colors)
   for index in shape.indices:indices.append(offset+index)
   count+=1
 return {"vertices":vertices,"colors":colors,"indices":indices,"blade_count":count}

static func make_mesh(left:PackedVector2Array,right:PackedVector2Array,opacity:float)->ArrayMesh:
 var data=geometry(left,right,opacity)
 var mesh=ArrayMesh.new()
 if data.vertices.is_empty():return mesh
 var arrays=[];arrays.resize(Mesh.ARRAY_MAX)
 arrays[Mesh.ARRAY_VERTEX]=data.vertices
 arrays[Mesh.ARRAY_COLOR]=data.colors
 arrays[Mesh.ARRAY_INDEX]=data.indices
 mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES,arrays,[],{},Mesh.ARRAY_FLAG_USE_2D_VERTICES)
 return mesh
