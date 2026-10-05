extends Node2D
## Color-only ground work tiles. This node retains state, never canvas commands.
## Pure presentation: never moves objects or widens
## service access. Counter front remains waiter-only and back chef-only.
var game
var signature=[]
var markers=[]
var access_signature=[]
var access_issues=[]
var access_index=0
var access_source="current"
var preview_context=[]
var preview_issues=[]
var preview_latched=false
var preview_source="current"
var ui_hold_pointer=Vector2.INF
var ui_hold_context=[]
var focused_key=""
var focus_hold=false
var focus_pointer=Vector2.INF
var focus_context=[]
var focus_issues=[]
var focus_source="current"
static func blocked_station(owner)->Dictionary:
 for staff in owner.staff_states:
  var reason=str(staff.get("art_block_reason",staff.get("blocked_reason",""))).to_lower()
  if not reason.contains("blocked"):continue
  var item=owner.model.get_item(int(staff.get("blocked_target_id",-1)))
  if not owner.editing and str(item.get("kind",""))=="stove":continue
  if not item.is_empty() and str(item.kind) in ["stove","beverage","sink","counter","bin","register"]:return item
 return {}
static func describe(owner)->Array:
 if not owner.editing:return []
 var item=owner.model.get_item(owner.selected_id)
 var interaction=owner.interaction
 var preview=interaction!=null and interaction.preview_active
 if preview:
  item={"id":interaction.drag_item_id,"kind":interaction.drag_kind,"x":interaction.drag_cell.x,"z":interaction.drag_cell.y,"rot":interaction.drag_rotation}
 if item.is_empty() or str(item.kind) not in ["stove","beverage","sink","counter","bin","register"]:return []
 var layout:Array[Dictionary]=[]
 for other in owner.model.items:
  if int(other.id)!=int(item.id):layout.append(other)
 layout.append(item)
 var base=Vector2i(item.x,item.z)
 var front=owner.model.workface_cell(item)
 var cells=[{"cell":front,"reverse":false}]
 if item.kind=="register":cells.append({"cell":base*2-front,"reverse":true})
 if item.kind=="counter":cells.append({"cell":base*2-front,"reverse":true})
 if item.kind=="bin":
  cells=[]
  for direction in [Vector2i.DOWN,Vector2i.LEFT,Vector2i.UP,Vector2i.RIGHT]:cells.append({"cell":base+direction,"reverse":false})
 var bin_cells=owner.model.bin_service_cells(item,layout) if item.kind=="bin" else []
 var reachable=owner.model._sale_reachable_in(layout)
 var station_owned=owner.model.is_floor_owned(base)
 for marker in cells:
  var facing=item.duplicate()
  if marker.reverse:facing.rot=posmod(int(item.rot)+2,4)
  marker["clear"]=station_owned and (bin_cells.has(marker.cell) if item.kind=="bin" else owner.model._workface_open_in(facing,layout)) and reachable.has(marker.cell)
  marker["station_cell"]=base
  marker["item_id"]=int(item.id)
 return cells
func _refresh():
 if not is_instance_valid(game):return
 if not game.editing:
  signature=[];markers=[]
  return
 var i=game.interaction
 var next=[game.editing,game.selected_id,game.model.revision]
 if i!=null:next.append_array([i.preview_active,i.drag_item_id,i.drag_kind,i.drag_cell,i.drag_rotation])
 if signature==next:return
 signature=next;markers=describe(game)
func _process(_delta):
 _refresh();_refresh_access()
func draw_ground(art):
 # Called only by the illustration, after update_projection and floor drawing,
 # before any wall, prop or actor. No independently retained screen coordinates.
 _refresh()
 if not is_instance_valid(game) or not game.editing:return
 for marker in markers:
  var cell:Vector2i=marker.cell
  var color=Color("527961") if marker.clear else Color("aa5845")
  var corners=PackedVector2Array([art.iso(cell.x+.08,cell.y+.08),art.iso(cell.x+.92,cell.y+.08),art.iso(cell.x+.92,cell.y+.92),art.iso(cell.x+.08,cell.y+.92)])
  var fill=color;fill.a=.20;art.draw_colored_polygon(corners,fill)
  corners.append(corners[0]);art.draw_polyline(corners,color,2.0,true)

func _issue_key(issue:Dictionary)->String:
 return str([issue.get("item_id",-1),issue.get("kind",""),issue.get("station_cell",Vector2i.ZERO),issue.get("side",""),issue.get("cell",Vector2i.ZERO)])
func _refresh_access():
 if not is_instance_valid(game) or not game.model.has_method("layout_access_issues"):return
 if not game.editing:
  access_issues=[];access_signature=[];preview_context=[];preview_issues=[];preview_latched=false;focused_key="";focus_hold=false;return
 var i=game.interaction
 var context=[game.model.revision,game.selected_id,game.selected_kind]
 if focus_hold and (focus_context!=context+[game.rotation_step] or i==null or i.last_pointer.distance_squared_to(focus_pointer)>1.0 or i._left_down):
  focus_hold=false;access_signature=[]
 if focus_hold:
  access_issues=focus_issues.duplicate(true);access_source=focus_source;return
 var edit_context=context+[game.rotation_step]
 if preview_context!=edit_context:preview_context=edit_context;preview_issues=[];preview_latched=false;ui_hold_pointer=Vector2.INF
 var over_ui=i!=null and i._over_ui(i.last_pointer)
 # UI refitting briefly moves this notice while the pointer is stationary.
 # Once captured, only genuine pointer/edit activity can resume world preview.
 if over_ui and preview_latched:
  ui_hold_pointer=i.last_pointer;ui_hold_context=edit_context
 elif i==null or ui_hold_context!=edit_context or i.last_pointer.distance_squared_to(ui_hold_pointer)>1.0 or i._left_down:
  ui_hold_pointer=Vector2.INF
 if ui_hold_pointer.is_finite():over_ui=true
 var preview=i!=null and i.preview_active and (i.drag_active or game.selected_kind!="")
 var key=context+[preview,over_ui]
 if i!=null:key.append_array([i.drag_kind,i.drag_cell,i.drag_rotation,i.drag_valid,i.drag_reason,game.model.last_placement_issue])
 if access_signature==key:return
 access_signature=key
 var next=[];var next_source="current"
 if preview and not over_ui:
  # Invalid access uses the exact validator failure, not every unrelated issue
  # in the proposed room. Other rejections must not inherit a stale warning.
  var failure:Dictionary=game.model.last_placement_issue
  if not i.drag_valid and not failure.is_empty() and i.drag_reason==str(failure.get("reason","")):
   next=[failure.duplicate(true)];next_source="preview"
  elif i.drag_valid:
   var proposed=game.model.placement_access_issues(i.drag_kind,i.drag_cell.x,i.drag_cell.y,i.drag_item_id,i.drag_rotation)
   var existing_issues=game.model.layout_access_issues()
   for issue in proposed:
    var existing=false
    for old in existing_issues:
     if int(old.item_id)==int(issue.item_id) and str(old.side)==str(issue.side):existing=true;break
    if existing or str(issue.kind)=="stove":
     next.append(issue)
     if not existing:next_source="preview"
  preview_issues=next.duplicate(true);preview_latched=true;preview_source=next_source
 elif over_ui and preview_latched:
  next=preview_issues.duplicate(true);next_source=preview_source
 else:next=game.model.layout_access_issues()
 var before=_issue_key(access_issues[access_index]) if not access_issues.is_empty() and access_index<access_issues.size() else ""
 access_issues=next;access_source=next_source;access_index=0
 for index in range(access_issues.size()):
  if _issue_key(access_issues[index])==before:access_index=index;break
 if access_issues.is_empty() or _issue_key(access_issues[access_index])!=before:focused_key=""
func current_access_issue()->Dictionary:
 _refresh_access()
 return access_issues[access_index] if not access_issues.is_empty() else {}
func access_message()->String:
 var issue=current_access_issue()
 if issue.is_empty():return ""
 var name=str(game.compact_ui.SHORT_NAMES.get(str(issue.kind),str(issue.kind).capitalize()))
 var message=("Would block "+name.to_lower()+" access") if access_source=="preview" else name+" access blocked"
 if access_issues.size()>1:message+=" · %d/%d"%[access_index+1,access_issues.size()]
 return message
func show_access_issue():
 if not is_instance_valid(game) or not game.editing or game.compact_ui.has_open_popup() or game.compact_ui.viewport_too_small:return
 var issue=current_access_issue()
 if issue.is_empty():return
 if focused_key==_issue_key(issue) and access_issues.size()>1:
  access_index=(access_index+1)%access_issues.size();issue=access_issues[access_index]
 focused_key=_issue_key(issue)
 # End the held gesture before moving the camera. An existing drag draft is
 # canceled back to its original transform; committed gameplay, selected tool
 # identity and persistence are untouched. A late release cannot commit.
 if game.web_lifecycle!=null:game.web_lifecycle.cancel_pending()
 elif game.interaction!=null:game.interaction.on_focus_lost()
 # Keyboard Show can leave the pointer over the old world position. Hold the
 # reviewed failure across camera-induced cell changes, until a real pointer
 # move/press, rotation, selection or model revision resumes editing.
 focus_hold=access_source=="preview"
 focus_pointer=game.interaction.last_pointer
 focus_context=[game.model.revision,game.selected_id,game.selected_kind,game.rotation_step]
 focus_issues=access_issues.duplicate(true);focus_source=access_source
 var art=game.illustration;art.update_projection()
 var ui=game.compact_ui;ui.status_notice.sync_position()
 _fit_access_camera(art,issue)
 game.interaction.pan_offset=art.pan_offset;art.queue_redraw()
 ui.status_notice.sync_position()
func _access_focus_points(art,issue:Dictionary)->PackedVector2Array:
 var cell:Vector2i=issue.cell;var station:Vector2i=issue.station_cell
 return PackedVector2Array([art.iso(cell.x+.04,cell.y+.04),art.iso(cell.x+.96,cell.y+.04),art.iso(cell.x+.96,cell.y+.96),art.iso(cell.x+.04,cell.y+.96),art.iso(station.x+.5,station.y+.5,68)])
func _access_focus_radius(index:int)->float:
 return 12.0 if index==4 else 2.5
func _access_focus_bounds(points:PackedVector2Array)->Rect2:
 var bounds=Rect2(points[0],Vector2.ZERO)
 for index in range(points.size()):
  var radius=_access_focus_radius(index)
  bounds=bounds.merge(Rect2(points[index]-Vector2.ONE*radius,Vector2.ONE*radius*2.0))
 return bounds
func _access_focus_ratio(points:PackedVector2Array,size:Vector2)->float:
 # Projected positions scale with zoom; outline/marker radii stay in pixels.
 # Every ordered pair bounds its total extent, so one pass finds the exact
 # largest scale that fits without iterative overshoot at the 11px marker.
 var ratio=1.0
 for axis in [0,1]:
  for a in range(points.size()):
   for b in range(points.size()):
    var room=size[axis]-_access_focus_radius(a)-_access_focus_radius(b)
    if room<=0.0:return 0.0
    var distance=absf(points[a][axis]-points[b][axis])
    if distance>.00001:ratio=minf(ratio,room/distance)
 return ratio
func _access_focus_areas(art)->Array[Rect2]:
 var ui=game.compact_ui;var insets=ui.hud._safe_insets();var view=game.get_viewport().get_visible_rect().size
 var top=ui.hud.layout_host.get_global_rect().end.y+12
 var bottom=game.tray.get_global_rect().position.y-12
 if ui.shop_ui.action_background.is_visible_in_tree():bottom=minf(bottom,ui.shop_ui.action_background.get_global_rect().position.y-12)
 var world=art.camera_safe_rect() if art.has_method("camera_safe_rect") else Rect2(Vector2(insets.x,top),Vector2(view.x-insets.x-insets.z,maxf(1.0,bottom-top)))
 var areas:Array[Rect2]=[world]
 var panel=ui.status_notice.panel
 if panel.is_visible_in_tree() and world.intersects(panel.get_global_rect()):
  # A short landscape strip may be too shallow above a 44px notice. Use a
  # clear side of that notice rather than hiding the marker or shrinking UI.
  var blocked=world.intersection(panel.get_global_rect())
  areas=[Rect2(world.position,Vector2(world.size.x,blocked.position.y-world.position.y)),Rect2(world.position,Vector2(blocked.position.x-world.position.x,world.size.y)),Rect2(Vector2(blocked.end.x,world.position.y),Vector2(world.end.x-blocked.end.x,world.size.y)),Rect2(Vector2(world.position.x,blocked.end.y),Vector2(world.size.x,world.end.y-blocked.end.y))]
 var result:Array[Rect2]=[]
 for candidate in areas:
  var inner=candidate.grow(-16.0)
  if inner.size.x>0 and inner.size.y>0:result.append(inner)
 return result
func _fit_access_camera(art,issue:Dictionary):
 var points=_access_focus_points(art,issue)
 var start_zoom:float=art.zoom;var start_pan:Vector2=art.pan_offset
 var best_zoom=-1.0;var best_pan=start_pan
 # Check the normal camera clamp for each clear region. Near map edges a
 # left-side target may be unreachable while the right-side target is clear.
 for area in _access_focus_areas(art):
  var ratio=_access_focus_ratio(points,area.size)
  if ratio<=0.0:continue
  art.zoom=start_zoom*ratio;art.pan_offset=start_pan;art.update_projection()
  var bounds=_access_focus_bounds(_access_focus_points(art,issue))
  art.pan_offset+=area.get_center()-bounds.get_center();art.update_projection()
  bounds=_access_focus_bounds(_access_focus_points(art,issue))
  if area.grow(.1).encloses(bounds) and art.zoom>best_zoom:
   best_zoom=art.zoom;best_pan=art.pan_offset
 art.zoom=best_zoom if best_zoom>0.0 else start_zoom
 art.pan_offset=best_pan;art.update_projection()
func draw_access_focus(art):
 var issue=current_access_issue()
 if issue.is_empty() or not game.editing or game.compact_ui.has_open_popup() or game.compact_ui.viewport_too_small:return
 var station:Vector2i=issue.station_cell;var cell:Vector2i=issue.cell
 var color=Color("a74d3c")
 # Same-frame world projection, drawn over the obstruction for clear location.
 var corners=PackedVector2Array([art.iso(cell.x+.04,cell.y+.04),art.iso(cell.x+.96,cell.y+.04),art.iso(cell.x+.96,cell.y+.96),art.iso(cell.x+.04,cell.y+.96),art.iso(cell.x+.04,cell.y+.04)])
 art.draw_polyline(corners,Color("fff6df"),5.0,true);art.draw_polyline(corners,color,2.5,true)
 var at=art.iso(station.x+.5,station.y+.5,68)
 var floor_point=art.iso(cell.x+.5,cell.y+.5)
 art.draw_line(at+Vector2(0,11),floor_point,Color("fff6df"),4.0,true);art.draw_line(at+Vector2(0,11),floor_point,color,2.0,true)
 art.draw_circle(at,11,Color("fff6df"));art.draw_arc(at,10,0,TAU,24,color,2.0,true)
 art.draw_line(at+Vector2(0,-5),at+Vector2(0,1),color,2.5,true);art.draw_circle(at+Vector2(0,5),1.5,color)
