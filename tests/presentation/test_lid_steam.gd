extends SceneTree
const Pose=preload("res://scripts/rendering/cooking_tool_pose.gd")
const Furniture=preload("res://scripts/rendering/illustrated_furniture.gd")
class Artist extends Node2D:
 var motion={"pot":Vector2.ZERO,"lid":Vector2.ZERO}
 var matrix=Transform2D.IDENTITY
 var shapes=[]
 var meshes=[]
 var transforms=[]
 var tints=[]
 func _stove_vessel_motion(_id):return motion
 func art_local_begin(at):
  var saved=matrix;matrix=matrix.translated_local(at);return saved
 func _set_art_matrix(value):matrix=value
 func art_local_end(saved):matrix=saved
 func art_draw_mesh(mesh,_texture,transform,tint):
  meshes.append(mesh);transforms.append(transform);tints.append(tint);shapes.append("steam")
 func col(tint):return tint
 func poly(_p,_c):shapes.append("pan")
 func line(_a,_b,_c,_w=1.0):pass
 func ellipse(at,size,color):shapes.append({"at":at,"size":size,"color":color,"matrix":matrix})
 func outlined_ellipse(at,size,color,_edge,_w=1.0):ellipse(at,size,color)
 func clear():meshes.clear();transforms.clear();tints.clear();shapes.clear()
var checks=0
var failures=[]
func check(ok,label):
 checks+=1
 if not ok:failures.append(label);printerr("FAIL ",label)
func _initialize():
 var artist=Artist.new();var furniture=Furniture.new()
 furniture.draw_stove_vessel(artist,Vector2.ZERO,0)
 check(artist.meshes.is_empty() and furniture._stove_steam_meshes.is_empty(),"idle allocates/draws no steam")
 for rotation in range(4):
  artist.clear();artist.motion={"pot":Vector2.ZERO,"lid":Vector2.ZERO}
  furniture.draw_stove_vessel(artist,Vector2.ZERO,rotation)
  var idle=artist.shapes.duplicate(true)
  artist.clear();artist.motion=Pose.vessel(5.9,-1.0,0.0)
  furniture.draw_stove_vessel(artist,Vector2.ZERO,rotation)
  check(artist.shapes==idle,"zero-strength/idle geometry unchanged")
  for time in [1.0,3.0,5.70,6.0,6.6,7.2,8.0]:
   artist.clear();artist.motion=Pose.vessel(time)
   furniture.draw_stove_vessel(artist,Vector2.ZERO,rotation)
   check(artist.meshes.size()==(12 if time>=5.616 and time<7.366 else 6),"bounded continuous and timed rim-release draws")
   check(artist.matrix==Transform2D.IDENTITY,"lid restores artist transform")
   check(artist.shapes.slice(0,6)==["steam","steam","steam","steam","steam","steam"],"steam remains in original behind-vessel pass")
   var mouth=furniture.point(0,0,34)+artist.motion.pot+Vector2(0,-7.0)
   var rim=Vector2(8.5*Furniture.PAN_WIDTH,4.2*Furniture.PAN_DEPTH)
   check(artist.transforms[0].origin.is_equal_approx(mouth+Vector2(0,-rim.y*.82)),"rear ribbon rooted at rim")
   check(artist.transforms[2].origin.is_equal_approx(mouth+Vector2(-rim.x*.82,.6)),"left ribbon rooted at rim")
   check(artist.transforms[4].origin.is_equal_approx(mouth+Vector2(rim.x*.82,.6)),"right ribbon rooted at rim")
   for tint in artist.tints:check(tint.a>=0 and tint.a<.80,"vapor translucent")
 check(Pose.vessel(3.0).steam>0 and Pose.vessel(3.0).lid.y>-.4,"steam with closed lid")
 check(Pose.vessel(5.9).lid.y< -6.0,"occasional lid lift")
 check(absf(Pose.vessel(5.8).lid_tilt)>.001,"slight asymmetric lid tilt")
 check(Pose.vessel(6.6).steam>0 and Pose.vessel(6.6).lid.y>-.4,"vapor persists after lid settles")
 for strength in [0.0]:
  check(Pose.vessel(5.9,-1,strength).steam_age<0,"zero presentation strength disables steam")
 check(Pose.vessel(5.9,0).steam_age<0,"completed cooking disables steam")
 var first=furniture._stove_steam_meshes[0];var second=furniture._stove_steam_meshes[1]
 for sample in range(120):
  artist.clear();artist.motion=Pose.vessel(1.0+sample*.067)
  furniture.draw_stove_vessel(artist,Vector2.ZERO,0)
 check(furniture._stove_steam_meshes.size()==2,"two immutable meshes across phases")
 check(furniture._stove_steam_meshes[0]==first and furniture._stove_steam_meshes[1]==second,"no per-phase mesh variants")
 var arrays=first.surface_get_arrays(0)
 check(arrays[Mesh.ARRAY_VERTEX].size()==125,"bounded125 vertices per mesh")
 check(arrays[Mesh.ARRAY_INDEX].size()==576,"bounded192 triangles per mesh")
 var transparent=0
 for tint in arrays[Mesh.ARRAY_COLOR]:
  if tint.a==0:transparent+=1
 check(transparent>=50,"feathered transparent ribbon edges")
 artist.clear();artist.motion={"pot":Vector2.ZERO,"lid":Vector2.ZERO}
 furniture.draw_stove_vessel(artist,Vector2.ZERO,0)
 check(artist.meshes.is_empty(),"idle draws no residual steam")
 artist.free()
 print("LID_STEAM_RESULT ",JSON.stringify({"checks":checks,"failures":failures,"mesh_count":2,"max_draws":12,"player_save_used":false}))
 quit(0 if failures.is_empty() else 1)
