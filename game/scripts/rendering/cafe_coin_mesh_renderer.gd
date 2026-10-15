extends RefCounted
## Actual MeshInstance3D coins in one isolated, transparent 3D viewport.
## The viewport texture is only the compositing bridge into the existing floor
## painter. The coin itself is imported indexed geometry, not a 2D polygon.
const MODEL_PATH="res://assets/effects/leaf_coin_3d.glb"
const MAX_MODELS=32
const MAX_RENDER_SIDE=2048
var game_ref:WeakRef
var viewport:SubViewport
var camera:Camera3D
var world_root:Node3D
var model_scene:PackedScene
var model_load_attempted=false
var model_ready=false
var pool:Array=[]
var support_vertices:PackedVector3Array=PackedVector3Array()
var mesh_surface_count=0
var mesh_triangle_count=0
var active_count=0
var model_bounds=AABB()

func _init(game):game_ref=weakref(game)
func pose_basis(turn:float,tilt:float)->Basis:
 return Basis(Vector3(0,0,1),tilt)*Basis(Vector3.RIGHT,-.18)*Basis(Vector3.UP,turn)
func _collect_meshes(node:Node,relative:Transform3D,meshes:Array):
 var xf=relative*node.transform if node is Node3D else relative
 if node is MeshInstance3D and node.mesh!=null:meshes.append({"node":node,"transform":xf})
 for child in node.get_children():_collect_meshes(child,xf,meshes)
func load_model()->bool:
 if model_load_attempted:return model_ready
 model_load_attempted=true
 model_scene=load(MODEL_PATH) as PackedScene
 if model_scene==null:return false
 var sample=model_scene.instantiate();var meshes=[]
 _collect_meshes(sample,Transform3D.IDENTITY,meshes)
 var unique={};var first=true
 for item in meshes:
  var mesh:Mesh=item.node.mesh
  mesh_surface_count+=mesh.get_surface_count()
  for surface in range(mesh.get_surface_count()):
   var arrays=mesh.surface_get_arrays(surface)
   var vertices:PackedVector3Array=arrays[Mesh.ARRAY_VERTEX]
   var indices:PackedInt32Array=arrays[Mesh.ARRAY_INDEX]
   mesh_triangle_count+=(indices.size() if not indices.is_empty() else vertices.size())/3
   for vertex in vertices:
    var at:Vector3=item.transform*vertex
    unique[at.snapped(Vector3.ONE*.000001)]=true
    if first:model_bounds=AABB(at,Vector3.ZERO);first=false
    else:model_bounds=model_bounds.expand(at)
 for vertex in unique:support_vertices.append(vertex)
 sample.free()
 model_ready=mesh_surface_count>0 and model_bounds.size.z>.1
 return model_ready
func support_clearance(pose:Basis,radius:float)->float:
 var clearance=0.0
 for vertex in support_vertices:clearance=maxf(clearance,-(pose*vertex).y*radius)
 return clearance
func _ensure_viewport()->bool:
 if is_instance_valid(viewport):return true
 var game=game_ref.get_ref()
 if not is_instance_valid(game) or not load_model():return false
 viewport=SubViewport.new();viewport.name="CleanupCoins3D"
 viewport.transparent_bg=true;viewport.own_world_3d=true
 viewport.gui_disable_input=true;viewport.handle_input_locally=false
 viewport.size=Vector2i(2,2);viewport.msaa_3d=Viewport.MSAA_4X
 viewport.render_target_update_mode=SubViewport.UPDATE_DISABLED
 game.add_child(viewport)
 world_root=Node3D.new();world_root.name="CoinMeshWorld";viewport.add_child(world_root)
 camera=Camera3D.new();camera.name="CoinCamera3D";world_root.add_child(camera)
 camera.projection=Camera3D.PROJECTION_ORTHOGONAL;camera.keep_aspect=Camera3D.KEEP_HEIGHT
 camera.position=Vector3(0,0,1000);camera.near=.05;camera.far=2000;camera.current=true
 var environment=Environment.new()
 environment.background_mode=Environment.BG_COLOR;environment.background_color=Color.TRANSPARENT
 environment.ambient_light_source=Environment.AMBIENT_SOURCE_COLOR
 environment.ambient_light_color=Color(1.0,.96,.88);environment.ambient_light_energy=.72
 environment.reflected_light_source=Environment.REFLECTION_SOURCE_DISABLED
 environment.tonemap_mode=Environment.TONE_MAPPER_LINEAR
 camera.environment=environment
 var key=DirectionalLight3D.new();key.name="WarmKey";world_root.add_child(key)
 key.rotation_degrees=Vector3(-35,-35,0);key.light_color=Color(1.0,.95,.82);key.light_energy=.85;key.shadow_enabled=false
 var fill=DirectionalLight3D.new();fill.name="SoftFill";world_root.add_child(fill)
 fill.rotation_degrees=Vector3(20,145,0);fill.light_color=Color(.83,.91,1.0);fill.light_energy=.30;fill.shadow_enabled=false
 return true
func _slot(index:int)->Dictionary:
 while pool.size()<=index and pool.size()<MAX_MODELS:
  var root:Node3D=model_scene.instantiate();world_root.add_child(root)
  root.name="CleanupCoinMesh"+str(pool.size())
  var meshes=[];_collect_meshes(root,Transform3D.IDENTITY,meshes)
  var materials=[]
  for item in meshes:
   var mesh_node:MeshInstance3D=item.node
   mesh_node.cast_shadow=GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
   for surface in range(mesh_node.mesh.get_surface_count()):
    var original=mesh_node.get_active_material(surface)
    var material:StandardMaterial3D=original.duplicate() if original is StandardMaterial3D else StandardMaterial3D.new()
    material.transparency=BaseMaterial3D.TRANSPARENCY_ALPHA
    material.cull_mode=BaseMaterial3D.CULL_BACK
    material.depth_draw_mode=BaseMaterial3D.DEPTH_DRAW_OPAQUE_ONLY
    mesh_node.set_surface_override_material(surface,material)
    materials.append({"material":material,"color":material.albedo_color})
  root.visible=false
  pool.append({"root":root,"materials":materials,"meshes":meshes})
 return pool[index]
func deactivate():
 active_count=0
 if not is_instance_valid(viewport):return
 for slot in pool:
  if is_instance_valid(slot.root):slot.root.visible=false
 viewport.render_target_update_mode=SubViewport.UPDATE_DISABLED
func draw(art,entries:Array):
 active_count=0
 if entries.is_empty():deactivate();return
 if not _ensure_viewport():return
 var size:Vector2=art.get_viewport_rect().size
 var factor=minf(1.0,float(MAX_RENDER_SIDE)/maxf(size.x,size.y))
 var target=Vector2i(maxi(2,roundi(size.x*factor)),maxi(2,roundi(size.y*factor)))
 if viewport.size!=target:viewport.size=target
 if not is_equal_approx(camera.size,size.y):camera.size=size.y
 for entry in entries.slice(0,MAX_MODELS):
  var slot=_slot(active_count)
  var radius:float=entry.radius
  var pose=pose_basis(entry.turn,entry.tilt)
  var position:Vector2=entry.ground-Vector2(0,entry.height+support_clearance(pose,radius))
  slot.root.transform=Transform3D(pose.scaled(Vector3.ONE*radius),Vector3(position.x-size.x*.5,size.y*.5-position.y,entry.ground.y*.01))
  slot.root.visible=true
  for target_material in slot.materials:
   var tint:Color=target_material.color;tint.a=entry.alpha
   if target_material.material.albedo_color!=tint:target_material.material.albedo_color=tint
  active_count+=1
 for i in range(active_count,pool.size()):pool[i].root.visible=false
 viewport.render_target_update_mode=SubViewport.UPDATE_ALWAYS
 # Cancel the painter's retained presentation offset exactly once: meshes
 # already use screen-space anchors including that same offset.
 var rect=Rect2(-art._presentation_offset,size)
 art.art_draw_texture_rect_region(viewport.get_texture(),rect,Rect2(Vector2.ZERO,Vector2(viewport.size)))
func receipt()->Dictionary:
 return {"model":MODEL_PATH,"model_class":"PackedScene with MeshInstance3D","viewport_class":"SubViewport","camera_class":"Camera3D","isolated_world":is_instance_valid(viewport) and viewport.own_world_3d,"pool_size":pool.size(),"active_models":active_count,"surfaces_per_model":mesh_surface_count,"triangles_per_model":mesh_triangle_count,"model_bounds":str(model_bounds),"render_size":str(viewport.size) if is_instance_valid(viewport) else "not allocated","last_frame_visible_3d_objects":viewport.get_render_info(Viewport.RENDER_INFO_TYPE_VISIBLE,Viewport.RENDER_INFO_OBJECTS_IN_FRAME) if is_instance_valid(viewport) else 0,"last_frame_visible_3d_draw_calls":viewport.get_render_info(Viewport.RENDER_INFO_TYPE_VISIBLE,Viewport.RENDER_INFO_DRAW_CALLS_IN_FRAME) if is_instance_valid(viewport) else 0}
