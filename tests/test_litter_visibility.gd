extends SceneTree
const Geometry=preload("res://scripts/cafe_floor_geometry.gd")
const LegacyGeometry=preload("res://tests/fixtures/litter_art_v2/cafe_floor_geometry.gd")
const AcceptedArt=preload("res://tests/fixtures/litter_art_v6/floor_mess_art.gd")
const Art=preload("res://scripts/floor_mess_art.gd")
class Recorder extends RefCounted:
 var ui_scale=1.0
 var zoom=1.0
 var points=[]
 var polygons=[]
 var screen_mode=false
 var calls=0
 var colors=[]
 var heights=[]
 func iso(x,z,h=0.0):
  heights.append(h)
  return Vector2((x-z)*39,(x+z)*19.5-h) if screen_mode else Vector2(x,z)
 func poly(shape,_color):points.append_array(shape);polygons.append(shape);colors.append(_color);calls+=1
 func line(a,b,_color,_width=1.0):points.append(a);points.append(b);calls+=1
var checks=0
var failures=[]
func check(ok,label):
 checks+=1
 if not ok:failures.append(label);printerr(label)
func _initialize():
 var highest_calls=0
 for seed in range(64):
  for kind in ["banana","crumbs"]:
   var entry={"floor_cell":Vector2i(4,6),"floor_target":Vector2(4.5,6.5),"debris_target":Vector2(4.5,6.5),"spill_target":Vector2(4.5,6.5),"floor_debris":kind,"floor_spill":false}
   var legacy=LegacyGeometry._build(entry,seed,.55)
   check(Geometry._build(entry,seed,.55)==legacy,"legacy default geometry changed")
   for natural in [false,true]:
    var shape=Geometry._build(entry,seed,1.08,natural)
    var saved=shape.duplicate(true)
    for piece in shape.pieces:
     var recorder=Recorder.new();Art._draw_dry_piece(recorder,piece,1.0);highest_calls=maxi(highest_calls,recorder.calls)
     if piece.kind!="bag":
      var accepted=Recorder.new();AcceptedArt._draw_dry_piece(accepted,piece,1.0)
      check(recorder.points==accepted.points and recorder.heights==accepted.heights and recorder.colors==accepted.colors,"accepted non-remnants artwork changed: "+piece.kind)
     for height in recorder.heights:check(height>=0 and height<=23.0,"fold height out of range")
     if piece.kind=="bag":
      var bound=Geometry._hull(Geometry.piece_bounds(piece))
      for direction in [Vector2.LEFT,Vector2.RIGHT,Vector2.UP,Vector2.DOWN]:
       var contact=Geometry.nearest_boundary(piece.center+direction*1.5,bound).move_toward(piece.center,.055)
       var closest=INF
       for visible in recorder.polygons:
        closest=minf(closest,Geometry.nearest_boundary(contact,visible).distance_to(contact))
       check(closest<=.19*piece.size,"sweep contact too far from visible food remnants")
     var screen=Recorder.new();screen.screen_mode=true;Art._draw_dry_piece(screen,piece,1.0)
     for polygon in screen.polygons:check(not Geometry2D.triangulate_polygon(PackedVector2Array(polygon)).is_empty(),"projected face fails triangulation: "+piece.kind)
     var hull=Geometry._hull(Geometry.piece_bounds(piece))
     for point in recorder.points:
      check(Geometry2D.is_point_in_polygon(point,PackedVector2Array(hull)) or Geometry.nearest_boundary(point,hull).distance_to(point)<.00001,"paint exceeds saved physical hull: "+piece.kind+" local="+str((point-piece.center).rotated(-piece.angle)/piece.size))
    check(shape==saved,"painting mutated saved shape")
 print(JSON.stringify({"checks":checks,"failures":failures,"max_drawing_calls_per_piece":highest_calls}))
 FileAccess.open("res://docs/litter-remnants-visibility/material-tests.json",FileAccess.WRITE).store_string(JSON.stringify({"checks":checks,"failures":failures,"max_drawing_calls_per_piece":highest_calls},"  "))
 quit(0 if failures.is_empty() else 1)
