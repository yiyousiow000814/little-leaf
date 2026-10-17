extends SceneTree
const Art=preload("res://scripts/rendering/illustrated_openings.gd")
const Walls=preload("res://scripts/gameplay/cafe_walls.gd")
const Geometry=preload("res://scripts/gameplay/cafe_wall_openings.gd")
const WallArt=preload("res://scripts/rendering/illustrated_walls.gd")
class Painter extends RefCounted:
 var ui_scale=1.0
 var game={"model":{"built_walls":[]}}
 var zoom=1.0
 var origin=Vector2.ZERO
 var filled=[]
 var outlined=[]
 var lines=[]
 func iso(x,z,h=0.0):return origin+Vector2((x-z)*39,(x+z)*19.5-h)*zoom
 func art_draw_polygon(points,colors,uvs,texture):filled.append({"points":points,"colors":colors,"uvs":uvs,"texture":texture})
 func poly(points,_color):outlined.append(points)
 func line(a,b,_color,_width):lines.append([a,b])
class WallFixture extends Node:
 var model={"built_walls":[]}
 var wall_detail=false
class RetainedPainter extends "res://scripts/rendering/illustrated_cafe.gd":
 var filled=[]
 func art_draw_polygon(points:PackedVector2Array,colors:PackedColorArray,uvs:PackedVector2Array=PackedVector2Array(),texture:Texture2D=null):
  filled.append({"points":points,"colors":colors,"uvs":uvs,"texture":texture})
  if native_draw_target!=null:native_draw_target.submit_shape(&"draw_polygon",[points,colors,uvs,texture],native_command_transform)
var checks=0
var failures=[]
func check(ok,label):
 checks+=1
 if not ok:failures.append(label);printerr("FAIL ",label)
func wall(id,axis,x,z):return Walls.installed(id,Walls.make(axis,x,z,"full","original"),0,0)
func inspect_joint(x_end,z_end):
 var walls=[wall("x","x",-1 if x_end else 0,0),wall("z","z",0,-1 if z_end else 0)]
 var before=walls.duplicate(true)
 var x=Geometry.wall_host(walls[0]);var z=Geometry.wall_host(walls[1])
 var xc=Art.corner_cut(x,walls,x_end);var zc=Art.corner_cut(z,walls,z_end)
 var xf=Art.world(x,xc.x)+Art.front(x);var xb=Art.world(x,xc.y)+Art.back(x)
 var zf=Art.world(z,zc.x)+Art.front(z);var zb=Art.world(z,zc.y)+Art.back(z)
 check((xf.is_equal_approx(zf) and xb.is_equal_approx(zb)) or (xf.is_equal_approx(zb) and xb.is_equal_approx(zf)),"Both axes share one exact cap miter")
 check(is_equal_approx(absf(xc.x-xc.y),.26),"Miter preserves centered visual thickness")
 check(walls==before,"Miter never mutates installed records")
func inspect_frames(axis,kind,width):
 var walls=[wall("a",axis,2,3),wall("b",axis,3 if axis=="x" else 2,3 if axis=="x" else 4)]
 var opening=Geometry.aperture({"id":9,"kind":kind,"wall_ids":["a","b"],"offset":1.0,"width":width},walls)
 var before=opening.duplicate(true);var entries=Art.depth_entries(opening)
 var half=Art.frame_half_width(opening);var cursor=-half
 var origin=Geometry.axis_value(opening.a,axis)
 var perpendicular=opening.a.x+opening.a.y-origin
 var count=0
 check(entries[0].part=="reveal","Jamb reveal has a separate paint entry")
 for entry in entries:
  if entry.part!="reveal":check(entries[0].depth<entry.depth,"Reveal cannot repaint over the casing lip")
  if entry.part!="middle":continue
  var piece=entry.entry
  check(is_equal_approx(piece.frame_from,cursor),"Header slices have no gap")
  cursor=piece.frame_to;count+=1
  var midpoint=origin+(piece.frame_from+piece.frame_to)*.5
  var support_depth=perpendicular+(floorf(midpoint*4)+.5)/4+Art.front(opening.host).x+Art.front(opening.host).y
  check(entry.depth>support_depth and entry.depth<support_depth+.25,"Casing follows matching wall slice, before next slice")
 check(count>=3 and is_equal_approx(cursor,width+half),"Complete header retains original frame span")
 check(opening==before,"Frame slicing preserves aperture, ownership and source host")
func inspect_visible_end(axis):
 var source=wall("source",axis,2,3)
 var host=Geometry.wall_host(source)
 var next=wall("next",axis,host.b.x,host.b.y)
 var unrelated=wall("unrelated","z" if axis=="x" else "x",host.b.x,host.b.y)
 var walls=[unrelated,next];var before=walls.duplicate(true)
 check(Art.visible_end_bottom(host,walls)==128.0,"Full continuation hides the complete end face")
 check(walls==before,"End-face query preserves wall records")
 next.height="half"
 check(Art.visible_end_bottom(host,walls)==58.0,"Half continuation leaves the upper end visible")
 next.x+=.000001
 check(Art.visible_end_bottom(host,walls)==58.0,"Adjacent endpoint retains approximate comparison")
 next.x+=.01
 check(Art.visible_end_bottom(host,walls)==0.0,"A gap exposes the complete end face")
 next.x=host.b.x
 next.placement=Walls.PLACEMENT.duplicate();next.placement.visual_front+=.1
 check(Art.visible_end_bottom(host,walls)==0.0,"Different front planes expose the end face")
 next.placement=Walls.PLACEMENT.duplicate();next.placement.visual_back-=.1
 check(Art.visible_end_bottom(host,walls)==0.0,"Different back planes expose the end face")
 next.erase("placement")
 var full=next.duplicate(true);full.height="full"
 check(Art.visible_end_bottom(host,[next,full])==58.0 and Art.visible_end_bottom(host,[full,next])==128.0,"First compatible continuation retains its original precedence")
 check(Art.visible_end_bottom(host,[unrelated])==0.0,"Perpendicular walls do not hide this end face")
func inspect_slice_preparation(axis):
 var painter=Painter.new()
 var first=wall("first",axis,2,3)
 var second=wall("second",axis,3 if axis=="x" else 2,3 if axis=="x" else 4)
 var walls=[first,second];painter.game.model.built_walls=walls
 var attachments=[{"id":8,"kind":"door","wall_ids":["first","second"],"offset":1.0,"width":1.5}]
 var previous={}
 for transition in range(4):
  if transition==1:attachments[0].offset=.85;attachments[0].width=.7
  if transition==2:attachments[0].kind="window";painter.zoom=1.55;painter.origin=Vector2(135,79)
  if transition==3:first.height="half";attachments.clear()
  var before=[walls,attachments].duplicate(true)
  for member in walls:
   var original=WallArt.depth_entries(member);var pieces=Art.built_depth_entries(member)
   var preparation=pieces[0].wall_preparation
   check(preparation.is_empty() and not is_same(preparation,previous),"Every new wall/draw group starts with independent empty preparation")
   previous=preparation
   for index in pieces.size():
    var ordering=pieces[index].duplicate();ordering.erase("wall_preparation")
    check(ordering==original[index] and is_same(pieces[index].wall_preparation,preparation),"All four slices preserve exact depth records and share one preparation")
   painter.filled=[]
   for piece in original:Art.draw_built_piece(painter,piece,attachments,.68,Color("efd095"))
   var expected=painter.filled
   painter.filled=[]
   for piece in pieces:Art.draw_built_piece(painter,piece,attachments,.68,Color("efd095"))
   check(painter.filled==expected,"Shared preparation preserves every emitted point, color, UV and texture after immediate edits/camera changes")
   check(preparation.size()==5 and preparation.host==Geometry.wall_host(member) and preparation.panels==Geometry.solid_panels(preparation.host,walls,attachments),"Preparation retains this wall descriptor, panels and exact neighbor cuts")
  check(before==[walls,attachments],"Preparing slices never stores scratch data in model inputs")
func slice_group_lifetime()->WeakRef:
 var pieces=Art.built_depth_entries(wall("lifetime","x",2,3))
 var sentinel=RefCounted.new();var observed=weakref(sentinel)
 pieces[0].wall_preparation["lifetime_probe"]=sentinel;sentinel=null
 var final_slice=pieces[-1]
 pieces.clear()
 check(observed.get_ref()!=null,"Remaining slice keeps only its own preparation alive")
 final_slice={}
 return observed
func inspect_retained_slice():
 var painter=RetainedPainter.new();var fixture=WallFixture.new();painter.game=fixture
 var first=wall("first","x",2,3);var next=wall("next","x",3,3)
 fixture.model.built_walls=[first,next]
 painter.render_wall_attachments=[{"id":8,"kind":"door","wall_ids":["first","next"],"offset":1.0,"width":1.5}]
 painter.origin=Vector2(135,79);painter.canvas_stream.active=true
 var alpha=1.0;var tint=Color.WHITE;var prior_revision=0
 for transition in 10:
  match transition:
   1:painter.render_wall_attachments[0].offset=.85
   2:painter.render_wall_attachments[0].kind="window"
   3:first.material="cream_stripe"
   4:next.height="half"
   5:first.x=1;next.x=2
   6:fixture.model.built_walls.erase(next);painter.render_wall_attachments.clear()
   7:painter.zoom=1.55;painter.tile=Vector2(39,19.5)*1.55
   8:painter.origin+=Vector2(17,9)
   9:alpha=.68;tint=Color("efd095")
  var before=[fixture.model.built_walls,painter.render_wall_attachments].duplicate(true)
  var piece=Art.built_depth_entries(first)[3]
  painter.canvas_stream.cursor=0;painter._draw_wall_slice(piece,alpha,tint)
  var node=painter.native_object_nodes[0]
  check(node.paint_revision>prior_revision,"Wall slice immediately invalidates for attachment, style, neighbor, movement, deletion, zoom, origin or draft tint")
  prior_revision=node.paint_revision
  painter.filled=[];painter.paint_native_object(node,node.paint)
  var retained=painter.filled
  painter.filled=[];Art.draw_built_piece(painter,Art.built_depth_entries(first)[3],painter.render_wall_attachments,alpha,tint)
  check(painter.filled==retained,"Retained wall callback preserves exact projected points, colors, UVs and texture")
  check(before==[fixture.model.built_walls,painter.render_wall_attachments],"Retained wall never mutates model or draft inputs")
  painter.canvas_stream.cursor=0;painter._draw_wall_slice(Art.built_depth_entries(first)[3],alpha,tint)
  check(node.paint_revision==prior_revision,"Fresh per-draw preparation does not invalidate unchanged retained wall")
  painter._art_transform=Transform2D(0,Vector2(20+transition,30))
  painter.canvas_stream.cursor=0;painter._draw_wall_slice(Art.built_depth_entries(first)[3],alpha,tint)
  check(node.paint_revision==prior_revision and node.transform==painter._art_transform,"Presentation pan moves retained wall without rebuilding geometry")
 check(painter.native_object_nodes.size()==1,"Repeated wall updates reuse their bounded painter slot")
 var sentinel=RefCounted.new();var source_lifetime=weakref(sentinel)
 painter.render_wall_attachments=[{"id":10,"kind":"window","wall_ids":["first"],"offset":.5,"width":.5,"lifetime_probe":sentinel}]
 sentinel=null
 painter.canvas_stream.cursor=0;painter._draw_wall_slice(Art.built_depth_entries(first)[3],alpha,tint)
 painter.render_wall_attachments=[]
 check(source_lifetime.get_ref()==null,"Wall callback does not retain a discarded attachment array")
 var capacity=0;var child_capacity=0
 for cycle in 12:
  painter.canvas_stream.frame_id+=1
  for slot in [0,2,5,9]:
   painter.canvas_stream.cursor=slot;painter._draw_wall_slice(Art.built_depth_entries(first)[slot%4],alpha,tint)
   var node=painter.native_object_nodes[slot];node.shape_cursor=0
   painter.paint_native_object(node,node.paint)
  painter._finish_native_objects()
  var occupied=painter.native_object_nodes.size()
  var children=0
  for node in painter.native_object_nodes.values():children+=node.shapes.size()
  if cycle==0:capacity=occupied;child_capacity=children
  check(children==child_capacity and children>0,"Repeated depth shifts reuse populated native child-shape capacity")
  check(occupied==capacity,"Repeated wall depth-slot shifts reuse historical bounded slot capacity")
  painter.canvas_stream.frame_id+=1;painter._finish_native_objects()
  check(painter.native_object_nodes.values().all(func(node):return not node.visible),"Removing every wall hides every historical retained slot immediately")

 var observed=weakref(painter.native_object_nodes[0])
 painter.free();fixture.free()
 check(observed.get_ref()==null,"Wall draw-list owner is released with its artist")

func _initialize():
 inspect_retained_slice()
 for cycle in range(12):check(slice_group_lifetime().get_ref()==null,"Dropping the final slice releases preparation on every cycle")
 var painter=Painter.new();var host=Geometry.wall_host(wall("original","x",0,0))
 for index in 4:Art.face(painter,host,index*.25,(index+1)*.25,0,128)
 check(Art.casing_front(host)==Art.front(host),"Casing and wall slices share one projected front plane")
 check(painter.outlined.is_empty(),"No outlines on internal quarter-cell face boundaries")
 check(painter.filled.size()==12 and painter.lines.is_empty(),"Original base, green panel and horizontal rail preserved")
 for x_end in [false,true]:
  for z_end in [false,true]:inspect_joint(x_end,z_end)
 var isolated=[wall("a","x",2,2)];var ih=Geometry.wall_host(isolated[0])
 check(Art.corner_cut(ih,isolated,false)==Vector2.ZERO and Art.corner_cut(ih,isolated,true)==Vector2.ONE,"Isolated wall endpoints unchanged")
 var straight=[wall("a","x",0,0),wall("b","x",1,0)]
 check(Art.corner_cut(Geometry.wall_host(straight[0]),straight,true)==Vector2.ONE,"Straight continuation never mitered")
 var mixed=[wall("a","x",0,0),wall("b","z",0,0)];mixed[1].height="half"
 check(Art.corner_cut(Geometry.wall_host(mixed[0]),mixed,false)==Vector2.ZERO,"Unequal heights retain independent end profile")
 for axis in ["x","z"]:inspect_visible_end(axis);inspect_slice_preparation(axis)
 for axis in ["x","z"]:
  for kind in ["door","window"]:
   for width in ([1.0,1.5] if kind=="door" else [.7]):inspect_frames(axis,kind,width)
 print("CENTERED_WALL_VISUAL_RESULT ",JSON.stringify({"checks":checks,"failures":failures}))
 quit(0 if failures.is_empty() else 1)
