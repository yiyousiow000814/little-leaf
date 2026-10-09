extends RefCounted
## A pointer receipt and cosmetic feedback only. The janitor-owned API is the
## sole authority for changing floor work; this helper never deletes records.
const MessArt=preload("res://scripts/floor_mess_art.gd")
const PUFF_SECONDS=.42
var game
var pending:Dictionary={}
var projection:Array=[]
var puffs:Array=[]

# Reuse the actual paint geometry rather than making an entire tile clickable.
class HitPaint extends RefCounted:
 var art
 var game
 var ui_scale:float
 var zoom:float
 var point:Vector2
 var hit=false
 func _init(source,screen:Vector2):
  art=source;game=source.game;ui_scale=source.ui_scale;zoom=source.zoom;point=screen
 func iso(x:float,z:float,height=0.0)->Vector2:return art.iso(x,z,height)
 func opaque(color)->bool:return (color is String or color.a>.2)
 func poly(points,color):
  if opaque(color) and Geometry2D.is_point_in_polygon(point,PackedVector2Array(points)):hit=true
 func line(a:Vector2,b:Vector2,color,width:float):
  if opaque(color) and Geometry2D.get_closest_point_to_segment(point,a,b).distance_to(point)<=maxf(1.5,width*.5):hit=true
 func ellipse(center:Vector2,radius:Vector2,color):
  if opaque(color) and radius.x>0 and radius.y>0 and ((point-center)/radius).length_squared()<=1:hit=true

func _init(owner):game=owner
func cancel():pending={};projection=[]
func _epoch()->Array:
 return [game.ground_mess_generation,game.floor_tasks.generation,game.floor_tasks.get_instance_id()]
func _projection()->Array:
 var art=game.illustration
 return [art.origin,art.tile,art.zoom,art.get_viewport_rect(),game.wall_detail]
func allowed()->bool:
 if not game.has_method("complete_ground_mess"):return false
 if game.editing or game.paused or game.save_recovery_blocked:return false
 if game.cafe_intro!=null and game.cafe_intro.active:return false
 if game.compact_ui!=null and (game.compact_ui.viewport_too_small or game.compact_ui.has_open_popup()):return false
 return not (is_instance_valid(game.settings) and game.settings.visible)
func _occluded(screen:Vector2)->bool:
 var art=game.illustration
 var item_id=art.hit_item(screen)
 if item_id>=0 and str(game.model.get_item(item_id).get("kind",""))!="rug":return true
 if not art.hit_wall_host(screen).is_empty():return true
 # Ground is painted before people. Avoid activating litter through a body.
 var scale=art.ui_scale*art.zoom*(1.55 if game.wall_detail else 1.0)
 for staff in game.staff_states:
  var p:Vector2=art.iso(staff.pos.x,staff.pos.y)
  if Rect2(p+Vector2(-12,-45)*scale,Vector2(24,49)*scale).has_point(screen):return true
 for guest in game.model.customers:
  var p:Vector2=art.iso(float(guest.x),float(guest.z))
  if Rect2(p+Vector2(-12,-45)*scale,Vector2(24,49)*scale).has_point(screen):return true
 return false
func hit(screen:Vector2)->Dictionary:
 if not allowed() or not game.interaction._point_in_view(screen) or game.interaction._over_ui(screen):return {}
 var art=game.illustration
 art.update_projection()
 if _occluded(screen):return {}
 # Reverse the renderer's floor order when silhouettes overlap.
 for ledger in ["floor","guest"]:
  var records=game.floor_tasks.messes if ledger=="floor" else game.service_guests
  var ids=records.keys();ids.reverse()
  for id in ids:
   var identity:Dictionary=game.ground_mess_identity(ledger,int(id))
   var record:Dictionary=game.resolve_ground_mess(identity)
   if record.is_empty() or not art._floor_mess_active(record):continue
   var paint=HitPaint.new(art,screen)
   MessArt.draw(paint,record)
   if paint.hit:return identity
 return {}
func begin(screen:Vector2):
 cancel()
 pending=hit(screen)
 if not pending.is_empty():projection=_projection()
func release(screen:Vector2)->bool:
 var identity=pending.duplicate();var expected_projection=projection.duplicate();cancel()
 if identity.is_empty() or not allowed():return false
 game.illustration.update_projection()
 if expected_projection!=_projection() or hit(screen)!=identity:return false
 var record:Dictionary=game.resolve_ground_mess(identity)
 if record.is_empty():return false
 var at:Vector2=record.floor_target
 if not game.complete_ground_mess(identity,"manual"):return false
 puffs.append({"at":at,"age":0.0,"epoch":_epoch()})
 game._mark_platform_dirty()
 game._save()
 game.illustration.queue_redraw()
 return true
func tick(delta:float)->bool:
 if puffs.is_empty():return false
 var active=true
 var epoch=_epoch()
 for i in range(puffs.size()-1,-1,-1):
  puffs[i].age+=maxf(0.0,delta)
  if puffs[i].epoch!=epoch or float(puffs[i].age)>=PUFF_SECONDS:puffs.remove_at(i)
 return active
func draw(art):
 if game.editing:return
 var scale=art.ui_scale*art.zoom*(1.55 if game.wall_detail else 1.0)
 for puff in puffs:
  if puff.epoch!=_epoch():continue
  var t=clampf(float(puff.age)/PUFF_SECONDS,0,1)
  var center:Vector2=art.iso(puff.at.x,puff.at.y)
  var radius=lerpf(2.0,8.0,t)*scale
  var alpha=.62*(1.0-t)
  for lobe in [Vector2(-.7,0),Vector2(.65,.1),Vector2(0,-.45)]:
   art.ellipse(center+lobe*radius+Vector2(0,-3*t)*scale,Vector2(radius*.7,radius*.48),Color(.95,.94,.84,alpha))
