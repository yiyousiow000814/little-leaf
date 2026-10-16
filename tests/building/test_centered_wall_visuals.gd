extends SceneTree
const Art=preload("res://scripts/rendering/illustrated_openings.gd")
const Walls=preload("res://scripts/gameplay/cafe_walls.gd")
const Geometry=preload("res://scripts/gameplay/cafe_wall_openings.gd")
const WallArt=preload("res://scripts/rendering/illustrated_walls.gd")
class Painter extends RefCounted:
 var ui_scale=1.0
 var filled=[]
 var outlined=[]
 var lines=[]
 func iso(x,z,h=0.0):return Vector2((x-z)*39,(x+z)*19.5-h)
 func art_draw_polygon(points,colors,_uvs,_texture):filled.append({"points":points,"colors":colors})
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
func _initialize():
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
 for axis in ["x","z"]:inspect_visible_end(axis)
 for axis in ["x","z"]:
  for kind in ["door","window"]:
   for width in ([1.0,1.5] if kind=="door" else [.7]):inspect_frames(axis,kind,width)
 print("CENTERED_WALL_VISUAL_RESULT ",JSON.stringify({"checks":checks,"failures":failures}))
 quit(0 if failures.is_empty() else 1)
