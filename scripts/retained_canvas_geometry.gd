extends RefCounted
## Native geometry resources survive CanvasItem command-list regeneration.
## Exact submitted coordinates are keys: no quantization or hash-only hits.
## Mesh colors are white/transparent; the original float tint is applied at draw.
## A bounded FIFO evicts resources, never visible draw commands or live state.
const Outline=preload("res://scripts/ordered_pocket_triangles.gd")
const MAX_BYTES=16*1024*1024
const MAX_ENTRIES=4096
var entries={}
var fifo=[]
var cursor=0
var bytes=0
var hits=0
var builds=0
var frame_resources=[]
var seen_previous={}
var seen_current={}
var use_dynamic_fills=true
var force_dynamic_fills=false
var fill_pool={}
var fill_pool_used={}
var fill_pool_bytes=0
var fill_pool_count=0
func begin_frame():
 frame_resources.clear();seen_previous=seen_current;seen_current={}
 fill_pool_used.clear()
func _dynamic_fill(points:PackedVector2Array,indices:PackedInt32Array)->ArrayMesh:
 if not use_dynamic_fills:return null
 var key=[points.size(),indices]
 var slot=int(fill_pool_used.get(key,0));fill_pool_used[key]=slot+1
 var available=fill_pool.get(key,[])
 var mesh:ArrayMesh
 if slot<available.size():
  mesh=available[slot];mesh.surface_update_vertex_region(0,0,points.to_byte_array())
 else:
  var cost=points.size()*24+indices.size()*4
  if fill_pool_count>=MAX_ENTRIES or fill_pool_bytes+cost>MAX_BYTES:return null
  mesh=_mesh(points,PackedColorArray(),indices,true)
  available.append(mesh);fill_pool[key]=available;fill_pool_bytes+=cost;fill_pool_count+=1
 var bounds=Rect2(points[0],Vector2.ZERO)
 for point in points:bounds=bounds.expand(point)
 mesh.custom_aabb=AABB(Vector3(bounds.position.x,bounds.position.y,-1),Vector3(bounds.size.x,bounds.size.y,2))
 return _hold(mesh)
func _admit(key)->bool:
 seen_current[key]=true
 return seen_previous.has(key)
func _hold(mesh:ArrayMesh)->ArrayMesh:
 frame_resources.append(mesh)
 return mesh
func _store(key,mesh:ArrayMesh,cost:int)->ArrayMesh:
 if cost>MAX_BYTES:return _hold(mesh)
 while not entries.is_empty() and (bytes+cost>MAX_BYTES or entries.size()>=MAX_ENTRIES):
  var oldest=fifo[cursor];cursor+=1
  bytes-=entries[oldest][1];entries.erase(oldest)
 if cursor>1024:
  fifo=fifo.slice(cursor);cursor=0
 entries[key]=[mesh,cost];fifo.append(key);bytes+=cost;builds+=1
 return _hold(mesh)
func _mesh(vertices:PackedVector2Array,colors:PackedColorArray,indices:PackedInt32Array,dynamic:bool=false)->ArrayMesh:
 var arrays=[];arrays.resize(Mesh.ARRAY_MAX)
 arrays[Mesh.ARRAY_VERTEX]=vertices
 if not colors.is_empty():arrays[Mesh.ARRAY_COLOR]=colors
 arrays[Mesh.ARRAY_INDEX]=indices
 var mesh=ArrayMesh.new()
 var flags=Mesh.ARRAY_FLAG_USE_2D_VERTICES
 if dynamic:
  flags|=Mesh.ARRAY_FLAG_USE_DYNAMIC_UPDATE
  mesh.set_meta("retained_dynamic",true)
 mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES,arrays,[],{},flags)
 return mesh
func fill(points:PackedVector2Array,color:Color)->ArrayMesh:
 if force_dynamic_fills:
  var triangles=Geometry2D.triangulate_polygon(points)
  return _dynamic_fill(points,triangles) if not triangles.is_empty() else null
 var key=[0,points.duplicate()]
 if entries.has(key):hits+=1;return _hold(entries[key][0])
 var stable=_admit(key)
 var indices=Geometry2D.triangulate_polygon(points)
 if indices.is_empty():return null
 var colors=PackedColorArray()
 if not stable:return _dynamic_fill(points,indices)
 return _store(key,_mesh(points,colors,indices),points.size()*24+indices.size()*4)
func closed_outline(points:PackedVector2Array,color:Color,width:float)->ArrayMesh:
 if width<=0.0 or points.size()<4 or points[0]!=points[-1]:return null
 var key=[1,points.duplicate(),width]
 if entries.has(key):hits+=1;return _hold(entries[key][0])
 if not _admit(key):return null
 var outline=Outline.new();outline.append_closed_outline(points,Color.WHITE,width)
 return _store(key,_mesh(outline.vertices,outline.colors,outline.indices),outline.vertices.size()*24+outline.indices.size()*4)
