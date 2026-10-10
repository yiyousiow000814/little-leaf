extends SceneTree
const Fixture=preload("res://tests/role_fixture.gd")
const Character=preload("res://scripts/directional_character_art.gd")
class ScaledArtist extends "res://scripts/illustrated_cafe.gd":
 func character_render_transform(position:Vector2,face:float=1.0)->Transform2D:
  var transform=super.character_render_transform(position,face)
  transform.x*=1.4;transform.y*=1.4
  return transform
# Record the actual painter's body/head primitives, not an independent model.
class PaintBounds extends Node2D:
 var shapes=[]
 func col(c):return Color(c) if c is String else c
 func add(points,width=0.0):
  if points.is_empty():return
  var box=Rect2(points[0],Vector2.ZERO)
  for p in points:box=box.expand(p)
  shapes.append(box.grow(width*.5))
 func body_color(color)->bool:
  var tint=col(color)
  if tint.a<.3:return false
  # Stove food and spatula are work-surface props, not the animal body.
  for tool in ["9a7c48","866b3e","c4ad79","ead6a0"]:
   if tint.is_equal_approx(Color(tool)):return false
  for food in Character.CookingPose.FOOD_COLOR:
   if tint.is_equal_approx(Color(food)) or tint.is_equal_approx(Color(food).lightened(.14)):return false
  return true
 func poly(points,color):
  if body_color(color):add(points,.7)
 func rounded_poly(points,_radius,color):
  if body_color(color):add(points,.7)
 func line(a,b,color,width=1.0):
  if body_color(color):add([a,b],width)
 func art_polyline(points,color,width):
  if body_color(color):add(points,width)
 func _round_limb(a,b,_color,width):add([a,b],width)
 func ellipse(p,r,color):
  if body_color(color):shapes.append(Rect2(p-r,r*2))
 func _face_ellipse(p,r,c):ellipse(p,r,c)
 func _face_line(a,b,c,w):line(a,b,c,w)
 func _draw_head(p,species,_back,_blink,hat,_blocked,view):
  var box=Character.head_bounds(species,view==2,hat);box.position+=p;shapes.append(box)
 func _draw_floor_tools(_at,_pose,_action,_payload):pass
 func _action_prop(_p,_carry,_action,_t,_payload,_tool,_hand,_tip,_floor):pass
 func _dustpan(_p,_hand,_axis,_filled):pass
var game
var checks=0
var failures=[]
func _initialize():run.call_deferred()
func check(ok,label):
 checks+=1
 if not ok and not failures.has(label):failures.append(label);printerr("FAIL ",label)
func geometry_for(state:Dictionary,pure:bool,artist)->Dictionary:
 var d=game.illustration.character_description(state.id,state.staff,state.seated,state.action,state.progress,state.reach,state.direction,state.payload,state.tool,state.pose,state.role)
 d.options.geometry_only=pure
 return Character.new().draw(artist,Vector2.ZERO,d.species,d.away,state.moving,float(state.pose.get("phase",0)),state.staff,false,d.options)
func inspect_entry(entry:Dictionary,label:String):
 var art=game.illustration;var state=art.character_draw_state(entry)
 var recorder=PaintBounds.new()
 var actual=geometry_for(state,false,recorder);var measured=geometry_for(state,true,art)
 for key in ["near_hand","far_hand","near_hip","far_hip","near_foot","far_foot","body","head_origin"]:
  check(actual[key].distance_to(measured[key])<.00001,label+" pure bounds use actual painted "+key)
 for shape in recorder.shapes:
  check(measured.occlusion_bounds.grow(.001).encloses(shape),label+" bounds contain actual painted body/head primitive")
 for key in ["near_shoe_polygon","far_shoe_polygon"]:
  check(measured[key].size()==9,label+" exact nine-point shoe outline exposed")
  for point in measured[key]:check(measured.occlusion_bounds.has_point(point),label+" shoe vertex remains inside measured body bounds")
 var expected:Rect2=art.get_global_transform_with_canvas()*state.transform*measured.occlusion_bounds
 var bounds=art.character_screen_bounds(entry)
 check(bounds.position.distance_to(expected.position)<.0001 and bounds.size.distance_to(expected.size)<.0001,label+" bounds share real render transform")
 var top:Vector2=(art.get_global_transform_with_canvas()*state.transform)*(measured.head_origin+Vector2(0,Character.head_bounds(posmod(state.id,3),false,state.staff and state.role=="chef").position.y+1))
 check(art.character_occludes(top),label+" actual species head/ears block ground input")
 recorder.free()
 return {"state":state,"bounds":bounds}
func assert_vacated_point(entry:Dictionary,logical:Vector2,label:String):
 var art=game.illustration;var bounds=art.character_screen_bounds(entry);var unit=art.ui_scale*art.zoom*(1.55 if game.wall_detail else 1.0)
 var old=Rect2(art.iso(logical.x,logical.y)+Vector2(-12,-45)*unit,Vector2(24,49)*unit)
 var found=false
 for y in range(1,49,2):
  for x in range(1,24,2):
   var point=old.position+Vector2(x,y)*unit
   if not bounds.has_point(point):
    check(not art.character_occludes(point),label+" vacated logical-cell space is no longer blocked");found=true;break
  if found:break
 check(found,label+" genuinely exercises logical-versus-rendered displacement")
func run():
 if not "saveguard" in OS.get_user_data_dir():printerr("Isolated profile required");quit(2);return
 root.size=Vector2i(1360,880);game=Fixture.new();root.add_child(game);await process_frame
 game.set_process(false);game.illustration.set_process(false);game.paused=false
 if game.cafe_intro!=null:game.cafe_intro.finish()
 var art=game.illustration
 game.model.customers.clear();game.service_guests.clear()
 for worker in game.staff_states:worker.pos=Vector2(-30,-30)
 var chef=game.worker("chef");var chef_index=game.staff_states.find(chef)
 var stove=game.model.get_item(1);var workface=game.model.workface_cell(stove)
 chef.pos=Vector2(workface)+Vector2(.5,.5);chef.art_action="cooking";chef.art_role="chef";chef.art_target_id=1
 chef.art_target=Vector2(float(stove.x)+.5,float(stove.z)+.5);chef.art_station=chef.art_target;chef.art_phase=.4;chef.job_elapsed=18.0;chef.art_tool="spatula";chef.art_payload="none"
 var entry={"type":"staff","entry":chef,"index":chef_index}
 var saved=JSON.stringify([game.model.coins,game.model.items,chef.pos,chef.job_elapsed])
 for zoom in [1.15,art.camera_zoom_limits().y]:
  art.zoom=zoom;art.update_projection()
  for seconds in [.05,.12,.5]:
   art.update_motion(seconds)
   var visible=art._render_position("staff_%s"%chef_index,chef.pos)
   check(visible.distance_to(chef.pos)>.01,"actual working inset differs from logical cell")
   var checked=inspect_entry(entry,"working chef")
   check(checked.state.position.distance_to(art.iso(visible.x,visible.y))<.0001,"working bounds follow interpolated stance")
  assert_vacated_point(entry,chef.pos,"working chef")
 check(JSON.stringify([game.model.coins,game.model.items,chef.pos,chef.job_elapsed])==saved,"rendered bounds never mutate physical position or work clock")
 # Existing dirty fixture gives complete guest fields, then use a real seated
 # eating presentation so chair docking and interpolated seat mix are exercised.
 chef.pos=Vector2(-30,-30);chef.art_action="idle";chef.art_target=chef.pos;art.stance_offsets.clear()
 var record=game.setup_dirty();var guest=record.guest;var chair=game.model.get_item(int(guest.chair_id))
 guest.phase="eating";guest.paid=false;guest.seated=true;guest.x=float(chair.x)+.5;guest.z=float(chair.z)+.5;guest.elapsed=2.0;guest.duration=10.0;guest.dismounting=false
 record.meal_done=true;record.drink_done=true;record.plate_owner="table";record.plate_target_id=int(guest.table_id);record.drink_owner="table";record.drink_target_id=int(guest.table_id)
 for worker in game.staff_states:worker.pos=Vector2(-30,-30);worker.art_action="idle";worker.art_target=worker.pos
 for species in 3:
  game.service_guests.clear();guest.id=species+3;game.service_guests[int(guest.id)]=record
  var key="guest_%s"%guest.id;art.stance_offsets.erase(key);art.seat_blends[int(guest.id)]=0.0
  for seconds in [.05,.12,.5]:
   art.update_motion(seconds)
   var seated_entry={"type":"guest","entry":guest}
   var checked=inspect_entry(seated_entry,"seated species %d"%species)
   var logical=Vector2(float(guest.x),float(guest.z));var visible=art._render_position(key,logical)
   check(visible.distance_to(logical)>.01 and checked.state.pose.seat_mix>0,"seat/meal docking moves actual drawn body")
   check(checked.state.position.distance_to(art.iso(visible.x,visible.y))<.0001,"seated bounds share docking interpolation")
  assert_vacated_point({"type":"guest","entry":guest},Vector2(float(guest.x),float(guest.z)),"seated guest")
 # A future whole-body scale must change paint and input through one helper.
 var scaled=ScaledArtist.new();scaled.game=game;root.add_child(scaled);scaled.set_process(false);scaled.hide()
 for property in ["origin","tile","ui_scale","zoom","stance_offsets","seat_blends","character_facings","carry_hand_offsets","meal_chair_offsets","table_dining_directions","motion"]:scaled.set(property,art.get(property))
 var seated_entry={"type":"guest","entry":guest}
 var original_state=art.character_draw_state(seated_entry);var scaled_state=scaled.character_draw_state(seated_entry)
 var original_bounds=art.character_screen_bounds(seated_entry);var scaled_bounds=scaled.character_screen_bounds(seated_entry)
 check(scaled_state.transform.origin.distance_to(original_state.transform.origin)<.0001,"whole-character scale retains actual rendered floor-root pivot")
 check(scaled_bounds.size.distance_to(original_bounds.size*1.4)<.0001,"whole-character scale affects shared bounds and paint equally")
 check(scaled_state.transform.x.length()>original_state.transform.x.length()*1.39,"render path consumes same scaled transform")
 scaled.queue_free()
 var hidden=art.character_screen_bounds({"type":"guest","entry":guest}).get_center()
 guest.phase="dirty";check(not art.character_occludes(hidden),"retained dirty guest ledger is not an invisible body")
 print("MANUAL_CHARACTER_OCCLUSION_RESULT ",JSON.stringify({"checks":checks,"failures":failures,"player_save_used":false,"actual_painter_geometry":true}))
 quit(0 if failures.is_empty() else 1)
