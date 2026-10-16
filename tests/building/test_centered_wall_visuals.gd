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
 var projection_calls=0
 var filled=[]
 var outlined=[]
 var lines=[]
 func iso(x,z,h=0.0):
  projection_calls+=1
  return origin+Vector2((x-z)*39,(x+z)*19.5-h)*zoom
 func art_draw_polygon(points,colors,uvs,texture):filled.append({"points":points,"colors":colors,"uvs":uvs,"texture":texture})
 func poly(points,_color):outlined.append(points)
 func line(a,b,_color,_width):lines.append([a,b])
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
   check(preparation.size()==2 and preparation.host==Geometry.wall_host(member) and preparation.panels==Geometry.solid_panels(preparation.host,walls,attachments),"Preparation retains only this wall descriptor and its current panels")
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
func inspect_face_corner_reuse(axis):
 var painter=Painter.new();var host=Geometry.wall_host(wall("face",axis,2,3))
 var tint=Color("efd095");var alpha=.68
 for camera in [false,true]:
  painter.zoom=1.55 if camera else 1.0;painter.origin=Vector2(135,79) if camera else Vector2.ZERO
  for limits in [Vector2(0,128),Vector2(0,20),Vector2(35,37),Vector2(36,128),Vector2(40,128)]:
   var low=limits.x;var high=limits.y;var a=.125;var b=.375;var offset=Art.front(host)
   var expected=[]
   var bands=[[low,high,"e0e7d0" if axis=="x" else "cfdbc2"]]
   if low<36:bands.append([low,minf(high,36),"91a27d" if axis=="x" else "819874"])
   if low<=36 and high>=36:bands.append([35,37,"a9b797"])
   for band in bands:
    var points=PackedVector2Array()
    for corner in [Vector2(a,band[0]),Vector2(b,band[0]),Vector2(b,band[1]),Vector2(a,band[1])]:
     var world=host.a+(host.b-host.a).normalized()*corner.x+offset
     points.append(painter.iso(world.x,world.y,corner.y))
    var color=Color(band[2])*Color(tint.r,tint.g,tint.b,alpha*tint.a)
    expected.append({"points":points,"colors":PackedColorArray([color,color,color,color]),"uvs":PackedVector2Array(),"texture":null})
   var before=host.duplicate(true);painter.filled=[];painter.projection_calls=0
   Art.face(painter,host,a,b,low,high,"unused","unused",alpha,tint)
   check(painter.filled==expected,"Face reuses corners with identical ordered points/colors/UVs after an immediate camera change")
   check(painter.projection_calls==bands.size()*4-(2 if low<36 else 0),"Face saves exactly two projections only when a lower panel shares the corners")
   check(host==before,"Face keeps scratch coordinates local and never mutates its host")

func _initialize():
 for axis in ["x","z"]:inspect_face_corner_reuse(axis)
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
