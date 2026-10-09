extends RefCounted
## Opaque feedback has the same meaning over every installed floor finish.
## Furniture feedback only; tile painting owns a separate material/perimeter preview.
const VALID_FILL=Color("b7d9c6")
const INVALID_FILL=Color("e7b3aa")
const VALID_EDGE=Color("2b6951")
const INVALID_EDGE=Color("9c352f")
static func fill_color(valid:bool)->Color:return VALID_FILL if valid else INVALID_FILL
static func edge_color(valid:bool)->Color:return VALID_EDGE if valid else INVALID_EDGE
static func draw_cell(artist,corners:Array,valid:bool,emphasis=false,fill=true):
 if fill:artist.poly(corners,fill_color(valid))
 for index in 4:
  artist.line(corners[index],corners[(index+1)%4],Color("fff9eb"),4.0 if emphasis else 2.2)
  artist.line(corners[index],corners[(index+1)%4],edge_color(valid),2.0 if emphasis else 1.1)
 if emphasis:
  var at=(corners[0]+corners[1]+corners[2]+corners[3])*.25
  var radius=clampf(corners[0].distance_to(corners[2])*.13,4.0,8.0)
  artist.draw_circle(at,radius+3,Color("fff9eb"))
  if valid:
   artist.line(at+Vector2(-radius*.7,0),at+Vector2(-radius*.1,radius*.55),edge_color(true),2.0)
   artist.line(at+Vector2(-radius*.1,radius*.55),at+Vector2(radius*.75,-radius*.55),edge_color(true),2.0)
  else:
   for flip in [-1,1]:artist.line(at+Vector2(-radius*.6,-radius*.6*flip),at+Vector2(radius*.6,radius*.6*flip),edge_color(false),2.0)
