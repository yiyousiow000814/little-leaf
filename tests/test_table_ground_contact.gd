extends SceneTree
const Placement=preload("res://scripts/dining_placement.gd")
const Atlas=preload("res://scripts/furniture_static_atlas.gd")
const Styles=preload("res://scripts/dining_style_art.gd")
class RecordingArt extends "res://scripts/illustrated_cafe.gd":
 var commands=[]
 func line(start:Vector2,finish:Vector2,color,width=1.0):commands.append({"kind":"line","start":start,"finish":finish,"color":color,"width":width})
 func ellipse(at:Vector2,size:Vector2,color):commands.append({"kind":"ellipse","at":at,"size":size,"color":color})
 func outlined_ellipse(at:Vector2,size:Vector2,color,border,width=1.0):commands.append({"kind":"top","at":at,"size":size,"color":color})
 func rounded_poly(points:Array,radius:float,color):commands.append({"kind":"face","points":points,"color":color})
 func poly(points:Array,color):commands.append({"kind":"face","points":points,"color":color})
var checks=0
var failures=[]
func check(ok:bool,label:String):
 checks+=1
 if not ok and not failures.has(label):failures.append(label);printerr(label)
func _initialize():
 var art=RecordingArt.new();var styles=Styles.new()
 for origin in [Vector2.ZERO,Vector2(19,-7)]:
  art.commands.clear();art._table_body(origin)
  var lines=art.commands.filter(func(c):return c.kind=="line" and c.color=="947340")
  var contacts=art.commands.filter(func(c):return c.kind=="ellipse" and c.color is Color and is_equal_approx(c.color.a,.16))
  check(lines.size()==4 and contacts.size()==4,"Basic table retains four supports with four floor patches")
  var feet=[Vector2(-17,-5),Vector2(18,-5),Vector2(-16,6),Vector2(17,6)]
  for i in 4:
   var foot=origin+feet[i]
   check(lines[i].start==foot,"Basic foot position must not move")
   check(lines[i].finish==foot+Vector2(0,-Placement.table_height(30)),"Basic upper attachment must not move")
   check(contacts[i].at==foot,"Basic contact patch must touch the foot")
   check(contacts[i].size==Vector2(2.3,1.15),"Basic contact patch must follow the floor 2:1 basis")
   check(art.commands.find(contacts[i])<art.commands.find(lines[0]),"All shadows must be behind all supports")
   check(Atlas.bounds("table_body").encloses(Rect2(feet[i]-Vector2(2.7,1.55),Vector2(5.4,3.1))),"Cached table bounds must keep shadow and AA fringe")
   for scale in [.5,1.0,2.2,4.0]:
    var transform=Transform2D(0,Vector2.ONE*scale,0,Vector2(680,530))
    check((transform*lines[i].start)==(transform*contacts[i].at),"Pan/zoom must keep foot and patch attached")
  var tops=art.commands.filter(func(c):return c.kind=="top")
  check(tops.size()==1 and tops[0].size==Placement.ROUND_TOP,"Basic tabletop footprint must stay put")
  check(tops[0].at==origin+Vector2(0,-Placement.TABLE_HEIGHT),"Basic tabletop height must stay put")
  for rotation in 4:
   for style in ["cottage","refined","retro"]:
    art.commands.clear();check(styles.table(art,origin,rotation,style),"Style must draw")
    contacts=art.commands.filter(func(c):return c.kind=="ellipse" and c.color is Color)
    if style=="retro":
     check(contacts.size()==1 and contacts[0].at==origin,"Pedestal shadow must share the floor center")
     var bases=art.commands.filter(func(c):return c.kind=="ellipse" and c.color is String and c.color=="8a9c95")
     check(bases.size()==1 and bases[0].at==origin,"Pedestal base must reach the floor")
     check(art.commands.find(contacts[0])<art.commands.find(bases[0]),"Pedestal must occlude its shadow")
     continue
    var shade="b8baa0" if style=="cottage" else "6e5846"
    lines=art.commands.filter(func(c):return c.kind=="line" and c.color==shade)
    check(lines.size()==4 and contacts.size()==4,"Styled table must retain four grounded supports")
    var extent=.32 if style=="cottage" else .30
    var spread=1.0 if style=="cottage" else 1.16
    var corners=[Vector2(-extent,-extent),Vector2(extent,-extent),Vector2(-extent,extent),Vector2(extent,extent)]
    for i in 4:
     var q:Vector2=corners[i];var foot=styles.point(q.x*spread,q.y*spread,0)
     check(lines[i].start.is_equal_approx(foot),"Styled support must start at actual zero-height floor")
     check(lines[i].finish.is_equal_approx(styles.point(q.x,q.y,29)),"Styled upper attachment must stay put")
     check(contacts[i].at.is_equal_approx(foot),"Styled foot and contact patch must coincide")
     check(contacts[i].size==Vector2(2.6,1.3),"Styled contact patch must follow 2:1 floor basis")
     check(art.commands.find(contacts[i])<art.commands.find(lines[0]),"Styled shadows must be behind all supports")
 art.free()
 print("TABLE_GROUND_CONTACT_RESULT ",JSON.stringify({"checks":checks,"failures":failures,"table_height":Placement.TABLE_HEIGHT,"round_top":str(Placement.ROUND_TOP)}))
 quit(0 if failures.is_empty() else 1)
