extends RefCounted
## Pointer-only stroke state. The planner owns atomic costs and model changes.
const Plan=preload("res://scripts/cafe_paint_plan.gd")
const Walls=preload("res://scripts/cafe_walls.gd")
const Openings=preload("res://scripts/cafe_wall_openings.gd")
const OpeningArt=preload("res://scripts/illustrated_openings.gd")
const Money=preload("res://scripts/cafe_money.gd")
var _owner_ref:WeakRef
var owner:
 get:return _owner_ref.get_ref()
var plan=Plan.new()
var active=false
var receipt={}
var targets:Array=[]
var keys={}
var last_point=Vector2.ZERO
var mode=""
var material=""
var axis=""
func _init(tools):_owner_ref=weakref(tools)
func eligible()->bool:return owner.mode in ["floor","half","full"]
func reset():
 active=false;receipt={};targets.clear();keys.clear();mode="";material="";axis="";plan.invalidate()
func begin(point:Vector2):
 reset();mode=owner.mode;material=owner.floor_material if mode=="floor" else owner.material
 last_point=point;axis=owner.preferred_axis
 if axis=="" and not owner.preview.is_empty():axis=str(owner.preview.get("axis",""))
 _sample(point)
func drag(point:Vector2):
 if not eligible() or owner.game.save_recovery_blocked:reset();return
 active=true
 var step=maxf(2.0,minf(owner.game.illustration.tile.x,owner.game.illustration.tile.y)*.35)
 var samples=clampi(ceili(last_point.distance_to(point)/step),1,1024)
 for index in range(1,samples+1):_sample(last_point.lerp(point,float(index)/samples))
 last_point=point
 receipt=plan.prepare(owner.game.model,mode,material,targets,owner.actor_positions())
 owner.preview_valid=bool(receipt.ok);owner.preview_reason=message();owner.game.tool_text.text=message()
 owner.game.illustration.queue_redraw()
 if owner.game.compact_ui!=null:owner.game.compact_ui.shop_ui.sync_action_details()
func _sample(point:Vector2):
 if not owner._available(point):return
 var target
 var key=""
 if mode=="floor":
  var world=owner._world(point);target=Vector2i(floori(world.x),floori(world.y));key=str(target)
 else:
  var host=owner.game.illustration.hit_wall_host(point)
  if not host.is_empty() and bool(host.shell):
   target=owner.game.model.get_editable_wall(str(host.segment_key)).duplicate(true)
   if target.is_empty():return
   target.key=str(host.segment_key)
  else:
   var wall=owner.game.illustration.hit_wall(point)
   target=wall.duplicate(true) if not wall.is_empty() else Walls.nearest_edge(owner._world(point),axis)
  key=Walls.key_of(target)
 if keys.has(key):return
 keys[key]=true;targets.append(target)
func message()->String:
 if receipt.is_empty():return "Drag to preview a row"
 var text="%d %s · %s coins"%[int(receipt.count),"tiles" if mode=="floor" else "walls",Money.amount(int(receipt.net))]
 return text+" · release to apply" if receipt.ok else text+" · "+str(receipt.error)
func finish(point:Vector2)->bool:
 if not active:return false
 var changed=false
 if owner.active() and not owner.game.save_recovery_blocked and owner._available(point):
  # Release may only apply the targets and total that were previewed.
  var shown_count=targets.size();_sample(point)
  if targets.size()==shown_count and not receipt.is_empty() and receipt.ok:
   var count=int(receipt.get("changed_count",receipt.count))
   if plan.commit(owner.game.model,receipt,owner.actor_positions()):changed=count>0
 reset()
 return changed
func draw_floor(view):
 if not active or mode!="floor":return
 var visible=[]
 for target in receipt.get("targets",[]):
  if int(target.x)>=0 and int(target.z)>=0 and int(target.x)<owner.game.model.MAX_WIDTH and int(target.z)<owner.game.model.MAX_DEPTH:visible.append(target)
 preload("res://scripts/cafe_tile_paint_preview.gd").draw(view,visible,material,bool(receipt.ok))
func draw_walls(view):
 if not active or mode=="floor":return
 for target in receipt.get("targets",[]):
  var host=owner.game.model.get_wall_host(str(target.key)) if str(target.key).begins_with("shell:") else {}
  if host.is_empty():
   var wall=Walls.make(str(target.axis),int(target.x),int(target.z),mode,material);wall.id=-1;host=Openings.wall_host(wall)
  else:host=host.duplicate(true);host.height=mode
  var shape=OpeningArt.segment_selection_geometry(view,host)
  view.draw_colored_polygon(shape.front,Color(.32,.52,.30,.18) if receipt.ok else Color(.66,.38,.29,.20))
  view.draw_multiline(shape.edges,Color("527c58") if receipt.ok else Color("b67561"),2.0,true)
