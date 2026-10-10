extends RefCounted
## One fixed sign; the owning illustration supplies its current projection.
const ANCHOR=Vector2(5.9,-6.3)
const Money=preload("res://scripts/cafe_money.gd")
static func unit(a)->float:
 return a.ui_scale*a.zoom*(1.55 if a.game.wall_detail else 1.0)
static func bounds(a)->Rect2:
 var scale=unit(a);var center=a.iso(ANCHOR.x,ANCHOR.y)+Vector2(0,-40)*scale
 return Rect2(center-Vector2(46,26)*scale,Vector2(92,52)*scale).grow(maxf(0,22-26*scale))
static func hit(a,screen:Vector2)->bool:
 return not a.game.editing and not a.game.model.parking_owned and bounds(a).has_point(screen)
static func draw(a):
 if a.game.editing or a.game.model.parking_owned:return
 if not a.render_bounds_visible(bounds(a).grow(30)):return
 a.art_transform(a.iso(ANCHOR.x,ANCHOR.y),0,Vector2.ONE*unit(a))
 a.ellipse(Vector2(0,1),Vector2(13,4),Color(.32,.42,.24,.13))
 a.line(Vector2(0,0),Vector2(0,-29),"a2885d",4)
 a.rounded_poly([Vector2(-44,-64),Vector2(44,-64),Vector2(44,-16),Vector2(-44,-16)],3,"dfc795")
 a.line(Vector2(-41,-61),Vector2(41,-61),"ecdbb2",1)
 var font=a.game.ArtFont
 a.art_draw_string(font,Vector2(-38,-48),"FOR SALE",HORIZONTAL_ALIGNMENT_CENTER,76,12,Color("617452"))
 a.art_draw_string(font,Vector2(-38,-34),"4 parking bays",HORIZONTAL_ALIGNMENT_CENTER,76,10,Color("796746"))
 a.art_draw_string(font,Vector2(-38,-20),Money.amount(a.game.model.parking_price()),HORIZONTAL_ALIGNMENT_CENTER,76,12,Color("796746"))
 a.art_transform(Vector2.ZERO)
