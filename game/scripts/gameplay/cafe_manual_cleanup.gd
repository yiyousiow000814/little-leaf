extends RefCounted
## Certified player cleanup feedback and its explicitly approved one-coin
## reward. The shared janitor API alone changes floor-work ownership.
const MessArt=preload("res://scripts/rendering/floor_mess_art.gd")
const PUFF_SECONDS=.98
const POP_SECONDS=.58
const POP_PEAK_SECONDS=.18
const POP_PEAK_SCALE=1.50
const COIN_DELAY=.45
const COIN_SECONDS=2.10
const COIN_FIRST_CONTACT=.70
const COIN_CONTACTS=[[.70,0.0],[1.14,-4.0],[1.46,-8.0]]
const COIN_PICKUP_START=1.60
const COIN_PICKUP_HEIGHT=52.0
const EFFECT_SECONDS=COIN_DELAY+COIN_SECONDS
const CLEANUP_REWARD=1
const MAX_COINS=1000000000 # Existing save-contract upper bound.
const CoinMeshRenderer=preload("res://scripts/rendering/cafe_coin_mesh_renderer.gd")
const COIN_TRAVEL_MIN=.46
const COIN_TRAVEL_MAX=.82
const MAX_PUFFS=32
# One stalled release may obtain a fresh receipt, never an expired one.
# The total intent lifetime and original two certification attempts stay bounded.
const RELEASE_MSEC=750
var game
var coin_rng=RandomNumberGenerator.new()
var coin_renderer
var coin_audio
var pending:Dictionary={}
var projection:Array=[]
var puffs:Array=[]
var released=false
var release_point=Vector2.ZERO
var release_deadline=0
var release_rearmed=false
var release_state:Array=[]
var release_record:Dictionary={}
var hovered:Dictionary={}
var hover_projection:Array=[]
var hover_state:Array=[]

# Cosmetic projection only. The original paint hit-test and saved geometry
# remain unchanged, including while the visible litter is highlighted.
class FeedbackPaint extends RefCounted:
 var art
 var game
 var ui_scale:float
 var zoom:float
 var center:Vector2
 var factor:float
 var light:float
 var opacity:float
 func _init(source,anchor:Vector2,size:float,highlight=0.0,alpha=1.0):
  art=source;game=source.game;zoom=source.zoom
  ui_scale=source.ui_scale*size;center=anchor;factor=size;light=highlight;opacity=alpha
 func iso(x:float,z:float,height=0.0)->Vector2:return center+(art.iso(x,z,height)-center)*factor
 func color(value)->Color:
  var tint=Color(value) if value is String else value
  var result:Color=tint.lerp(Color(1.0,.98,.89,tint.a),light)
  result.a*=opacity
  return result
 func poly(points,tint):art.poly(points,color(tint))
 func line(a:Vector2,b:Vector2,tint,width:float):art.line(a,b,color(tint),width)
 func ellipse(at:Vector2,radius:Vector2,tint):art.ellipse(at,radius,color(tint))

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

func _init(owner):
 game=owner
 coin_rng.randomize()
 coin_renderer=CoinMeshRenderer.new(owner)
 coin_audio=preload("res://scripts/audio/cafe_cleanup_coin_sfx.gd").new(owner)
func cancel():
 pending={};projection=[];released=false
 release_deadline=0;release_rearmed=false;release_state=[];release_record={}
 clear_hover()
 if is_instance_valid(game.illustration):game.illustration.character_pick_geometry.close_query()
func clear_hover():
 var had_hover=not hovered.is_empty()
 hovered={};hover_projection=[];hover_state=[]
 if had_hover and is_instance_valid(game.illustration):game.illustration.queue_redraw()
func hover(screen:Vector2):
 if not allowed():clear_hover();return
 # Hover is provisional and cosmetic, below all world solids in the floor pass.
 # Never open/replace the certified release query from a pointer motion.
 if released:clear_hover();return
 # refresh() is also called for a stationary mouse each gameplay frame.
 # Cache only cheap identity/visibility scalars, never painter geometry.
 var state=[screen,_projection(),_epoch(),game.model.revision,allowed(),game.interaction._over_ui(screen)]
 for records in [game.floor_tasks.messes,game.service_guests]:
  state.append(records.size())
  for id in records:
   var record:Dictionary=records[id]
   state.append([id,record.get("token",-1),record.get("floor_dirty",false),record.get("floor_cleaned",false),record.get("trash_owner","none"),record.get("floor_spill",false),record.get("spill_cleaned",false),record.get("spill_remaining",0.0)])
 if state==hover_state:return
 hover_state=state
 var identity=hit(screen,false)
 hover_projection=_projection() if not identity.is_empty() else []
 if identity==hovered:return
 hovered=identity
 game.illustration.queue_redraw()
func draw_record(art,record:Dictionary):
 var live=game.resolve_ground_mess(hovered) if not hovered.is_empty() else {}
 if allowed() and not live.is_empty() and is_same(record,live):
  var anchor:Vector2=art.iso(record.floor_target.x,record.floor_target.y)
  MessArt.draw(FeedbackPaint.new(art,anchor,1.06,.20),record)
 else:MessArt.draw(art,record)
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
func hit(screen:Vector2,certified=true)->Dictionary:
 if not allowed() or not game.interaction._point_in_view(screen) or game.interaction._over_ui(screen):return {}
 var art=game.illustration
 art.update_projection()
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
   # Press/hover only nominate the original litter silhouette. No coarse
   # furniture/wall mask may reject visible floor; release alone settles after
   # the renderer certifies actual painted coverage in its completed frame.
   if paint.hit:return {} if certified and art.ground_mess_occluded(screen) else identity
 return {}
func begin(screen:Vector2):
 cancel()
 pending=hit(screen,false)
 if not pending.is_empty():projection=_projection()
func release(screen:Vector2)->bool:
 if released:return true # Duplicate release cannot restart its lifetime or work.
 if pending.is_empty() or not allowed():cancel();return false
 game.illustration.update_projection()
 if projection!=_projection() or hit(screen,false)!=pending:cancel();return false
 released=true;release_point=screen
 release_deadline=Time.get_ticks_msec()+RELEASE_MSEC
 release_record=game.resolve_ground_mess(pending)
 release_state=_release_state()
 game.illustration.character_pick_geometry.request_query()
 game.illustration.queue_redraw()
 return true
func _release_state()->Array:
 var record:Dictionary=game.resolve_ground_mess(pending)
 if record.is_empty():return []
 # Guest records also contain live guest/meal/waiter state. Only ground-mess
 # semantics belong to this intent; ordinary guest progress must not cancel it.
 # The fresh painter receipt owns world coverage, actors and texture alpha.
 var ground=[]
 for key in ["floor_dirty","floor_cleaned","floor_debris","floor_spill","spill_cleaned","spill_remaining","trash_owner","trash_staff_index","trash_target_id","floor_cell","floor_target","debris_target","spill_target"]:
  ground.append(record.get(key))
 ground.append(hash(record.get("mess_shape",{})))
 return [game.illustration.character_pick_geometry._projection(game.illustration),game.model.revision,ground]
func _release_current()->bool:
 return Time.get_ticks_msec()<release_deadline and allowed() and projection==_projection() and not release_state.is_empty() and is_same(release_record,game.resolve_ground_mess(pending)) and release_state==_release_state()
func presented():
 if not released:return
 var pick=game.illustration.character_pick_geometry
 if not _release_current():cancel();return
 if not pick.query_active():
  # No completed frame means there are no old pixels we may authorize. Re-arm
  # once, only with unused attempts, then wait for a NEW completed receipt.
  var attempts:int=pick.query_frames
  if release_rearmed or pick.presented_frame>=0 or attempts<=0 or hit(release_point,false)!=pending:cancel();return
  release_rearmed=true
  pick.request_query()
  pick.query_frames=attempts
  pick.query_deadline=mini(pick.query_deadline,release_deadline)
  game.illustration.queue_redraw()
  return
 if pick.presented_frame!=game.illustration.canvas_stream.frame_id:return
 var identity=pending.duplicate()
 var valid=_release_current() and hit(release_point)==identity and pick.query_active()
 cancel()
 if not valid:return
 _complete(identity)
func _complete(identity:Dictionary)->bool:
 var record:Dictionary=game.resolve_ground_mess(identity)
 if record.is_empty():return false
 # Keep a capped wallet/load contract intact rather than silently discarding
 # the explicitly promised reward or cleaning without room for that reward.
 if game.model.coins<0 or game.model.coins>MAX_COINS-CLEANUP_REWARD:return false
 var at:Vector2=record.floor_target
 var snapshot=record.duplicate(true)
 if not game.complete_ground_mess(identity,"manual"):return false
 # Only this successful player transaction earns a coin. Shared NPC/domain
 # cleanup is unchanged; removed identities cannot reward or sound twice.
 game.model.coins+=CLEANUP_REWARD
 if puffs.size()>=MAX_PUFFS:puffs.pop_front()
 puffs.append({"at":at,"age":0.0,"epoch":_epoch(),"record":snapshot,"coin_motion":new_coin_motion(at)})
 clear_hover()
 game._update_ui()
 game._mark_platform_dirty()
 game.illustration.queue_redraw()
 return true
func tick(delta:float)->bool:
 if not is_instance_valid(game) or not game.has_method("ground_mess_identity"):return false
 if released and not _release_current():cancel()
 var epoch=_epoch()
 coin_audio.tick(epoch)
 if not hovered.is_empty() and (not allowed() or hover_projection!=_projection() or game.resolve_ground_mess(hovered).is_empty()):clear_hover()
 if puffs.is_empty():
  coin_renderer.deactivate()
  return false
 var active=true
 for i in range(puffs.size()-1,-1,-1):
  var puff:Dictionary=puffs[i]
  # A restore invalidates cosmetic events before they can play stale sounds.
  if puff.epoch!=epoch:puffs.remove_at(i);continue
  var previous=float(puff.age)
  puff.age=previous+maxf(0.0,delta)
  _play_coin_events(previous,float(puff.age))
  if float(puff.age)>=EFFECT_SECONDS:puffs.remove_at(i)
 return active
func _play_coin_events(previous:float,current:float):
 # Cross each genuine contact once, including every contact passed by a slow
 # frame. Each voice has its own gain; later bounces cannot cut off earlier ones.
 for contact in COIN_CONTACTS:
  var when=COIN_DELAY+float(contact[0])
  if previous<when and current>=when:coin_audio.play("coin_drop",float(contact[1]))
 var pickup=COIN_DELAY+COIN_PICKUP_START
 if previous<pickup and current>=pickup:coin_audio.play("coin_pickup",0.0)
func pop_scale(age:float)->float:
 if age<POP_PEAK_SECONDS:return lerpf(1.0,POP_PEAK_SCALE,smoothstep(0.0,POP_PEAK_SECONDS,maxf(age,0.0)))
 return lerpf(POP_PEAK_SCALE,0.0,smoothstep(POP_PEAK_SECONDS,POP_SECONDS,age))
func coin_path_clear(at:Vector2,direction:Vector2,distance:float)->bool:
 var finish=at+direction*distance
 if game.model.segment_blocked(at,finish):return false
 for step in range(1,9):
  var point=at.lerp(finish,float(step)/8.0)
  if not game.floor_tasks.geometry._point_clear(point):return false
 return true
func new_coin_motion(at:Vector2=Vector2(4.5,6.5))->Dictionary:
 # Cosmetic emission state only. It never enters the model RNG or save data.
 var angle=coin_rng.randf_range(-PI,PI)
 var requested=coin_rng.randf_range(COIN_TRAVEL_MIN,COIN_TRAVEL_MAX)
 var direction=Vector2(cos(angle),sin(angle));var distance=0.0
 # A bounded search redirects near a wall/furniture instead of drawing a coin
 # through it. All path work happens once, never in draw or tick.
 for fraction in [1.0,.5,.25]:
  for offset in [0.0,PI*.5,-PI*.5,PI]:
   var candidate=Vector2(cos(angle+offset),sin(angle+offset))
   if coin_path_clear(at,candidate,requested*fraction):
    direction=candidate;distance=requested*fraction;break
  if distance>0.0:break
 return {"direction":direction,"distance":distance,"turn_start":coin_rng.randf_range(-.35,.35),"spin":-1.0 if coin_rng.randf()<.5 else 1.0}
func coin_phase(age:float,motion:Dictionary={})->Dictionary:
 var t=age-COIN_DELAY
 if t<0.0 or t>=COIN_SECONDS-.00001:return {}
 var height=0.0
 var travel=1.0
 # Momentum continues outward at all three contacts. Each rebound loses
 # vertical height and lateral speed; it never jumps back to the spawn point.
 for arc in [[0.0,.70,26.0,0.0,.68],[.70,.44,12.0,.68,.92],[1.14,.32,4.8,.92,1.0]]:
  if t>=arc[0] and t<arc[0]+arc[1]:
   var u=(t-arc[0])/arc[1]
   height=4.0*arc[2]*u*(1.0-u)
   travel=lerpf(arc[3],arc[4],u)
   break
 # Pickup translates the same rigid coin upward. Radius and all three mesh
 # axes remain unchanged: no stretching, squash or streak substitutes.
 if t>=COIN_PICKUP_START:
  height=COIN_PICKUP_HEIGHT*smoothstep(COIN_PICKUP_START,COIN_SECONDS,t)
 return {"height":height,"travel":travel,"turn":.20+float(motion.get("turn_start",0.0))+t*1.4*float(motion.get("spin",1.0)),"tilt":.08,"alpha":1.0-smoothstep(COIN_PICKUP_START+.08,COIN_SECONDS,t)}
func coin_ground(puff:Dictionary,phase:Dictionary)->Vector2:
 var motion:Dictionary=puff.get("coin_motion",{})
 return puff.at+motion.get("direction",Vector2.RIGHT)*float(motion.get("distance",.64))*float(phase.travel)
func _cloud_lobe(art,at:Vector2,size:Vector2,tint:Color):
 var points=PackedVector2Array()
 for i in range(24):
  var angle=TAU*float(i)/24.0
  points.append(at+Vector2(cos(angle)*size.x,sin(angle)*size.y))
 art.art_draw_colored_polygon(points,tint)
func _ring(art,center:Vector2,unit:float,age:float):
 var t=(age-.28)/(PUFF_SECONDS-.28)
 if t<0.0 or t>=1.0:return
 var radius=lerpf(9.0,19.0,smoothstep(0.0,1.0,t))*unit
 var swell=sin(minf(1.0,t*3.0)*PI*.5)
 var body=maxf(lerpf(4.2,6.5,swell)*unit,radius*.36)
 var alpha=.90*(1.0-smoothstep(.42,1.0,t))
 var lobes=[]
 for i in range(12):
  var angle=TAU*(float(i)+.055*sin(float(i)*2.7))/12.0
  var varied=1.0+.15*sin(float(i)*2.3)+.06*cos(float(i)*4.1)
  var at=center+Vector2(cos(angle)*radius,sin(angle)*radius*.62-2.2*t*unit)
  lobes.append({"at":at,"size":Vector2(body*varied,body*varied*.77)})
 lobes.sort_custom(func(a,b):return a.at.y<b.at.y)
 # Overlapping cloud volumes form one open ring, not a stroked flat annulus.
 # Shading belongs to each puff's body; it does not add a floor shadow.
 for lobe in lobes:
  _cloud_lobe(art,lobe.at+Vector2(.5,1.0)*unit,lobe.size,Color(.77,.81,.77,alpha*.56))
 for lobe in lobes:
  _cloud_lobe(art,lobe.at-Vector2(.15,.3)*unit,lobe.size*Vector2(1.0,.96),Color(.965,.972,.925,alpha))
  _cloud_lobe(art,lobe.at+Vector2(-.8,-1.1)*unit,lobe.size*Vector2(.76,.63),Color(1.0,.998,.963,alpha*.82))
func _coin_shadow(art,puff:Dictionary,unit:float,age:float):
 var phase=coin_phase(age,puff.get("coin_motion",{}))
 if phase.is_empty():return
 var ground_world=coin_ground(puff,phase)
 var ground:Vector2=art.iso(ground_world.x,ground_world.y)
 var radius=9.0*unit
 var alpha=float(phase.alpha)
 # A small soft contact cue follows the moving floor point, never the airborne
 # image center or the original litter anchor; all coin solids paint above it.
 var proximity=1.0-clampf(float(phase.height)/36.0,0.0,1.0)
 art.ellipse(ground,Vector2(radius*.72,radius*.23)*lerpf(.88,1.0,proximity),Color(.38,.32,.21,alpha*lerpf(.055,.16,proximity)))
func draw(art):
 if game.editing:
  coin_renderer.deactivate()
  return
 var scale=art.ui_scale*art.zoom*(1.55 if game.wall_detail else 1.0)
 var mesh_entries=[]
 for puff in puffs:
  if puff.epoch==_epoch():_coin_shadow(art,puff,scale,float(puff.age))
 for puff in puffs:
  if puff.epoch!=_epoch():continue
  var age=float(puff.age)
  var center:Vector2=art.iso(puff.at.x,puff.at.y)
  if age<POP_SECONDS and puff.has("record"):
   MessArt.draw(FeedbackPaint.new(art,center,maxf(.001,pop_scale(age))),puff.record)
  _ring(art,center,scale,age)
  var phase=coin_phase(age,puff.get("coin_motion",{}))
  if not phase.is_empty():
   var floor_at=coin_ground(puff,phase)
   var ground:Vector2=art.iso(floor_at.x,floor_at.y)+art._presentation_offset
   mesh_entries.append({"ground":ground,"radius":9.0*scale,"height":float(phase.height)*scale,"turn":float(phase.turn),"tilt":float(phase.tilt),"alpha":float(phase.alpha)})
 coin_renderer.draw(art,mesh_entries)
