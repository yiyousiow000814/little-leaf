extends RefCounted
## Original native geometry shared by placed furniture, placement ghosts and cards.
## Cosmetic only: dining tops share a lower plane; seats remain 18px high. No collision,
## service points, guest poses, texture files or resource-loader branches live here.
const Placement=preload("res://scripts/dining_placement.gd")
var table_geometry=false
var a:Node2D
var p:Vector2
var r:int
func point(x:float,z:float,h:float,basis:float=34.0)->Vector2:
 var q=Vector2(x,z).rotated(r*PI/2.0)
 return p+Vector2((q.x-q.y)*basis,(q.x+q.y)*basis*.5-(Placement.table_height(h) if table_geometry else h))
func edge(x:Vector2,y:Vector2,c,w:float=1.0):a.line(x,y,c,w)
func face(points:Array,c,rounding:float=1.5):a.rounded_poly(points,rounding,c)
func ring(cx:float,cz:float,h:float,rx:float,rz:float,c):
 var points=[]
 for i in range(24):points.append(point(cx+cos(i*TAU/24.0)*rx,cz+sin(i*TAU/24.0)*rz,h))
 a.poly(points,c)
func slab(corners:Array,h:float,thickness:float,top,front,side):
 # Cull the rear rim. Camera-facing walls keep their shade as the piece turns.
 for i in range(corners.size()):
  var v:Vector2=corners[i];var w:Vector2=corners[(i+1)%corners.size()]
  var normal=Vector2(w.y-v.y,v.x-w.x).rotated(r*PI/2)
  if normal.dot(Vector2.ONE)<=0:continue
  face([point(v.x,v.y,h-thickness),point(w.x,w.y,h-thickness),point(w.x,w.y,h),point(v.x,v.y,h)],front if normal.y>normal.x else side,1.1)
 var surface=[]
 for q in corners:surface.append(point(q.x,q.y,h))
 face(surface,top,2.3)
func table(artist:Node2D,at:Vector2,rotation:int,style:String)->bool:
 if style=="basic":return false
 a=artist;p=at;r=posmod(rotation,4);table_geometry=true
 match style:
  "cottage":_cottage_table()
  "retro":_retro_table()
  "refined":_refined_table()
  _:return false
 return true
func chair(artist:Node2D,at:Vector2,rotation:int,back_only:bool,style:String)->bool:
 if style=="basic":return false
 a=artist;p=at;r=posmod(rotation,4);table_geometry=false
 match style:
  "cottage":_cottage_chair(back_only)
  "retro":_retro_chair(back_only)
  "refined":_refined_chair(back_only)
  _:return false
 return true
func _cottage_table():
 # Wide square painted farmhouse top and turned cream legs.
 var feet=[Vector2(-.32,-.32),Vector2(.32,-.32),Vector2(-.32,.32),Vector2(.32,.32)]
 for q in feet:a.ellipse(point(q.x,q.y,0),Vector2(2.6,1.3),Color(.45,.39,.23,.16))
 for q in feet:
  edge(point(q.x,q.y,0),point(q.x,q.y,29),"b8baa0",3.8)
  edge(point(q.x-.018,q.y,2),point(q.x-.018,q.y,29),"f0e8c9",1.7)
  a.ellipse(point(q.x,q.y,9),Vector2(2.4,1.5),"d6d4b6")
  a.ellipse(point(q.x,q.y,23),Vector2(2.3,1.4),"e8dfbe")
 var square=[Vector2(-.45,-.45),Vector2(.45,-.45),Vector2(.45,.45),Vector2(-.45,.45)]
 slab(square,29,5,"e2dcc0","c6c3a4","b0b899")
 slab(square,33,3,"f3eace","d9ccaa","c9c3a3")
 # Inset sage border and subtle plank seams are actual tabletop detail.
 var inner=[Vector2(-.37,-.37),Vector2(.37,-.37),Vector2(.37,.37),Vector2(-.37,.37)]
 for i in range(4):edge(point(inner[i].x,inner[i].y,33.15),point(inner[(i+1)%4].x,inner[(i+1)%4].y,33.15),"b2bea0",.85)
 for z in [-.13,.13]:edge(point(-.35,z,33.2),point(.35,z,33.2),"e0d6b5",.6)
func _retro_table():
 # A low chrome disk and single pedestal contrast with every four-leg set.
 a.ellipse(p,Vector2(16,8),Color(.45,.39,.23,.13))
 a.ellipse(p,Vector2(15,6.5),"8a9c95")
 a.outlined_ellipse(p+Vector2(0,-Placement.table_height(2.7)),Vector2(14.5,6.1),"c9d4c8","768d84",.8)
 edge(p+Vector2(0,-Placement.table_height(3)),p+Vector2(0,-Placement.table_height(29)),"829c92",6.0)
 edge(p+Vector2(-1,-Placement.table_height(4)),p+Vector2(-1,-Placement.table_height(29)),"e0e4d1",2.0)
 a.ellipse(p+Vector2(0,-Placement.table_height(29)),Placement.ROUND_TOP,"718f84")
 a.outlined_ellipse(p+Vector2(0,-Placement.table_height(33)),Placement.ROUND_TOP,"8ebdab","5f897b",1.1)
 a.ellipse(p+Vector2(0,-Placement.table_height(33.7)),Vector2(22.3,9.7),"add0b6")
 # Gentle curved laminate motif, without baked light/glow or a shadow layer.
 edge(point(-.27,.04,34),point(.09,.30,34),"8db9a1",.85)
 edge(point(-.30,-.04,34),point(-.05,.20,34),"c0dac1",.8)
func _refined_table():
 # Faceted walnut silhouette, tapered legs, a fine brass rim and ivory inset.
 var feet=[Vector2(-.30,-.30),Vector2(.30,-.30),Vector2(-.30,.30),Vector2(.30,.30)]
 for q in feet:a.ellipse(point(q.x*1.16,q.y*1.16,0),Vector2(2.6,1.3),Color(.45,.39,.23,.16))
 for q in feet:
  var foot=point(q.x*1.16,q.y*1.16,0);var top=point(q.x,q.y,29)
  edge(foot,top,"6e5846",4.0)
  edge(foot+Vector2(-.7,0),top+Vector2(-.7,0),"a47f56",1.2)
  edge(foot,foot+Vector2(0,-4),"c3a66b",3.1)
 var octagon=[Vector2(-.45,-.27),Vector2(-.27,-.45),Vector2(.27,-.45),Vector2(.45,-.27),Vector2(.45,.27),Vector2(.27,.45),Vector2(-.27,.45),Vector2(-.45,.27)]
 slab(octagon,30.5,5,"967148","776047","67553f")
 slab(octagon,32,1.5,"cab17d","b3925a","9e8354")
 slab(octagon,33,1,"99784f","846443","705638")
 var inset=[]
 for q in octagon:inset.append(q*.83)
 var pts=[]
 for q in inset:pts.append(point(q.x,q.y,33.2))
 face(pts,"e6dcc2",1.6)
 for i in range(inset.size()):edge(pts[i],pts[(i+1)%pts.size()],"bca374",.75)
 edge(point(-.23,-.12,33.3),point(-.02,.07,33.3),"ccc6b2",.6)
 edge(point(-.02,.07,33.3),point(.17,.08,33.3),"ccc6b2",.6)
func seat_point(x:float,z:float,h:float)->Vector2:return point(x,z,h,25.0)
func chair_seat(top,rim,rounded:float=2.5):
 var pts=[]
 for q in [Vector2(-.35,-.35),Vector2(.35,-.35),Vector2(.35,.35),Vector2(-.35,.35)]:pts.append(seat_point(q.x,q.y,18))
 var lower=[]
 for q in pts:lower.append(q+Vector2(0,2.5))
 face(lower,rim,rounded);face(pts,top,rounded)
func chair_legs(main,light,width:float=2.6,spread:float=1.1):
 for q in [Vector2(-.28,-.28),Vector2(.28,-.28),Vector2(-.28,.28),Vector2(.28,.28)]:
  var foot=seat_point(q.x*spread,q.y*spread,1);var upper=seat_point(q.x,q.y,17)
  edge(foot,upper,main,width);edge(foot+Vector2(-.6,0),upper+Vector2(-.6,0),light,.8)
func _cottage_chair(back_only:bool):
 if back_only:
  for x in [-.31,.31]:edge(seat_point(x,.28,17),seat_point(x,.28,36),"d8d4b5",3.2)
  var l=seat_point(-.35,.28,35);var rr=seat_point(.35,.28,35)
  face([l,rr,rr+Vector2(0,4),l+Vector2(0,4)],"f0e4c3",1.7)
  edge(seat_point(-.26,.28,21),seat_point(.26,.28,31),"a5b193",1.8)
  edge(seat_point(.26,.28,21),seat_point(-.26,.28,31),"bbc4a3",1.8)
  return
 chair_legs("bbbfa1","e7dec0",3.1)
 chair_seat("a6ba93","809776",2.6)
 # A small cushion seam makes the sage fabric legible at catalog scale.
 edge(seat_point(-.23,.30,18.5),seat_point(.23,.30,18.5),"c6d0aa",.8)
func _retro_chair(back_only:bool):
 if back_only:
  for x in [-.28,.28]:
   edge(seat_point(x,.30,15),seat_point(x,.32,30),"819b92",2.2)
   edge(seat_point(x-.025,.30,16),seat_point(x-.025,.32,30),"e3e6d5",.7)
  var l=seat_point(-.37,.31,34);var rr=seat_point(.37,.31,34)
  face([l+Vector2(0,2),l,rr,rr+Vector2(0,9),l+Vector2(0,9)],"b86f61",3.2)
  face([l+Vector2(1,0),rr+Vector2(-1,0),rr+Vector2(-1,6),l+Vector2(1,6)],"db9480",2.6)
  edge(l+Vector2(2,1),rr+Vector2(-2,1),"efb8a0",.8)
  return
 chair_legs("78978c","d7e0ce",2.0,1.18)
 # Chrome crossbar remains below the usual seat contact plane.
 edge(seat_point(-.29,.30,7),seat_point(.29,.30,7),"a4b5a9",1.2)
 chair_seat("df9b84","ab6c5c",3.4)
func _refined_chair(back_only:bool):
 if back_only:
  for x in [-.30,.30]:edge(seat_point(x,.28,17),seat_point(x,.28,35),"6d5947",3.1)
  var pts=[seat_point(-.35,.28,20),seat_point(.35,.28,20),seat_point(.35,.28,32),seat_point(.25,.28,37),seat_point(-.25,.28,37),seat_point(-.35,.28,32)]
  face(pts,"96794f",2.5)
  var padding=[seat_point(-.27,.28,22),seat_point(.27,.28,22),seat_point(.27,.28,31),seat_point(.19,.28,35),seat_point(-.19,.28,35),seat_point(-.27,.28,31)]
  face(padding,"557b67",2.3)
  edge(seat_point(-.20,.28,34),seat_point(.20,.28,34),"819b79",.9)
  for x in [-.11,.11]:a.ellipse(seat_point(x,.28,28.5),Vector2(.85,.85),"bec196")
  return
 chair_legs("715d46","a08056",2.8)
 for x in [-.30,.30]:edge(seat_point(x,.31,1),seat_point(x,.31,4),"c4a973",2.7)
 chair_seat("65876d","405f50",2.7)
 edge(seat_point(-.25,.31,18.5),seat_point(.25,.31,18.5),"b8b78d",.8)
