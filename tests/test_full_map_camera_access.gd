extends "res://tests/test_existing_wall_actions.gd"
## Finite painted environment, not merely purchasable cafe floor, stays reachable.
const Neighborhood=preload("res://scripts/exterior_environment.gd")
const Extent=preload("res://scripts/exterior_world_extent.gd")
class GroundRecorder extends RefCounted:
 var origin=Vector2(1300,500)
 var tile=Vector2(39,19.5)
 var ui_scale=1.0
 var zoom=1.0
 var viewport=Rect2(0,0,1360,880)
 var curves=[]
 var polygons=[]
 func iso(x:float,z:float,h:float=0.0):return origin+Vector2((x-z)*tile.x,(x+z)*tile.y)-Vector2(0,h)
 func get_viewport_rect():return viewport
 func render_bounds_visible(bounds):return bounds.grow(6).intersects(viewport,true)
 func poly(points:Array,color):
  polygons.append(points)
  if color is String and color=="8b9b90" and points.size()==Neighborhood.stop_edges.size():curves.append(points)
 func line(_a,_b,_color,_width=1.0):pass
var targets=[]
var reach_results=[]
func add_rect(name:String,rect:Rect2,height:float=0.0):
 for point in [rect.position,Vector2(rect.end.x,rect.position.y),rect.end,Vector2(rect.position.x,rect.end.y)]:targets.append({"name":name,"point":Vector3(point.x,point.y,height)})
func build_targets():
 # Use rendering constants/feature geometry, independently of camera bounds.
 add_rect("road ends",Rect2(Neighborhood.ROAD_LEFT,Extent.STREET_Z_MIN,Neighborhood.ROAD_RIGHT-Neighborhood.ROAD_LEFT,Extent.STREET_Z_MAX-Extent.STREET_Z_MIN))
 add_rect("road vehicle silhouette",Rect2(Neighborhood.ROAD_LEFT,Extent.STREET_Z_MIN,Neighborhood.ROAD_RIGHT-Neighborhood.ROAD_LEFT,Extent.STREET_Z_MAX-Extent.STREET_Z_MIN).grow(1.25),42)
 add_rect("opposite pavement",Rect2(Neighborhood.OPPOSITE_LEFT,Extent.PAVEMENT_Z_MIN,Neighborhood.ROAD_LEFT-Neighborhood.OPPOSITE_LEFT,Extent.PAVEMENT_Z_MAX-Extent.PAVEMENT_Z_MIN))
 add_rect("cafe pavement",Rect2(-3.26,Extent.PAVEMENT_Z_MIN,3.0,Extent.PAVEMENT_Z_MAX-Extent.PAVEMENT_Z_MIN))
 add_rect("grass field",Rect2(Extent.GRASS_MIN,Extent.GRASS_MIN,Extent.GRASS_MAX-Extent.GRASS_MIN,Extent.GRASS_MAX-Extent.GRASS_MIN))
 for spec in [["parking",Neighborhood.LOT],["driveway",Neighborhood.MOUTH],["pedestrian link",Neighborhood.PEDESTRIAN_LINK],["bus stop",Neighborhood.STOP_PAD],["shelter roof",Neighborhood.SHELTER_ROOF]]:add_rect(spec[0],spec[1],Neighborhood.SHELTER_HEIGHT if spec[0]=="shelter roof" else 0.0)
 add_rect("whole bus",Rect2(Neighborhood.BUS_POSITION-Vector2(1,2.85),Vector2(2,5.7)),60)
 for row in [Neighborhood.stop_rows.front(),Neighborhood.stop_rows.back()]:
  for point in row.points:targets.append({"name":"curved pavement end","point":Vector3(point.x,point.y,0)})
 for tree in Neighborhood.TREES:
  targets.append({"name":"outer tree ground","point":Vector3(tree.x,tree.y,0)})
  targets.append({"name":"outer tree crown","point":Vector3(tree.x,tree.y,160*tree.z)})
 for point in Neighborhood.POCKETS+Neighborhood.BUFFER_PLANTING:targets.append({"name":"outer planting","point":Vector3(point.x,point.y,30)})
 add_rect("full cafe expansion",Rect2(0,0,18,18))
func run():
 if not "saveguard" in OS.get_user_data_dir():printerr("Use isolated profile");quit(2);return
 var recorder=GroundRecorder.new();Neighborhood.draw_ground(recorder)
 check(recorder.curves.size()==1 and recorder.curves[0]==Neighborhood.projected(recorder,Neighborhood.stop_edges),"visible curved road retains complete original polygon")
 recorder.origin=Vector2(150000,150000);recorder.curves.clear();Neighborhood.draw_ground(recorder)
 check(recorder.curves.is_empty(),"far-offscreen curved road never submits large-coordinate polygon")
 recorder.origin=Vector2(1300,500);Neighborhood.draw_ground(recorder)
 check(recorder.curves.size()==1 and recorder.curves[0]==Neighborhood.projected(recorder,Neighborhood.stop_edges),"panning back restores original curved road without geometry changes")
 for row in Neighborhood.stop_paving:
  var polygon=Neighborhood.projected(recorder,row.points)
  if recorder.render_bounds_visible(Neighborhood.Visibility.points_bounds(polygon)):check(recorder.polygons.has(polygon),"visible curved paving retains its complete original polygon")
 root.size=Vector2i(1164,624);game=TestMain.new();root.add_child(game);game.set_process(false);game.illustration.set_process(false);game.paused=true
 await process_frame;game._toggle_edit();game._set_catalog_category("Build");game.compact_ui._set_tray_reveal(1);await settle();build_targets()
 var art=game.illustration;var tool=game.build_tools;var before=JSON.stringify([game.model.coins,game.model.items,game.model.wall_attachments,game.model.owned_parcels])
 for view in [Vector2i(1164,624),Vector2i(1360,880),Vector2i(390,844),Vector2i(344,680),Vector2i(844,390),Vector2i(566,360)]:
  root.size=view;await settle();tool.choose("door")
  for zoom in [art.camera_zoom_limits().x,1.15,art.camera_zoom_limits().y]:
   art.zoom=zoom;art.update_projection();var expected_zoom=art.zoom
   var fit_before=art.camera_fit_zoom();var fit_bounds=art.camera_world_bounds()
   for target in targets:
    var world:Vector3=target.point;var center=art.camera_safe_rect().get_center();var point=art.iso(world.x,world.y,world.z)
    game.interaction._pan_by(center-point);point=art.iso(world.x,world.y,world.z)
    var error=point.distance_to(center);var usable=not game.interaction._over_ui(point)
    check(error<1.0,str(view)+" zoom "+str(zoom)+" reaches "+str(target.name)+" "+str(world)+" error="+str(error))
    check(usable,"finite scenery target clears HUD, action row and shop")
    check(is_equal_approx(art.zoom,expected_zoom),"scenery inspection preserves zoom")
    reach_results.append({"viewport":str(view),"zoom":zoom,"feature":target.name,"world":str(world),"error":error,"usable":usable})
   # Exercise actual retained/native draw submissions both far away and back
   # at the curve; offscreen guards must never discard the visible feature.
   for position in [Neighborhood.STOP_PAD.get_center(),Vector2(Extent.GRASS_MAX,Extent.GRASS_MAX),Neighborhood.STOP_PAD.get_center()]:
    game.interaction._pan_by(art.camera_safe_rect().get_center()-art.iso(position.x,position.y))
    art.queue_redraw();await process_frame
    check(art.iso(position.x,position.y).distance_to(art.camera_safe_rect().get_center())<1.0,"near/far/near draw keeps requested camera reach")
   check(is_equal_approx(art.camera_fit_zoom(),fit_before) and art.camera_world_bounds()==fit_bounds,"large environment traversal does not expand cafe Fit")
  # One actual left-drag while a build tool is active, far out on the road.
  art.zoom=art.camera_zoom_limits().y;art.update_projection();var world=Vector2(Neighborhood.ROAD_RIGHT,Extent.STREET_Z_MIN+3)
  game.interaction._pan_by(art.camera_safe_rect().get_center()-art.iso(world.x,world.y))
  var start=art.camera_safe_rect().get_center();var delta=Vector2(32,16);var origin_before=art.origin
  var event=InputEventMouseButton.new();event.position=start;event.button_index=MOUSE_BUTTON_LEFT;event.pressed=true;root.push_input(event,true)
  var move=InputEventMouseMotion.new();move.position=start+delta;move.relative=delta;move.button_mask=MOUSE_BUTTON_MASK_LEFT;root.push_input(move,true)
  event=event.duplicate();event.pressed=false;event.position=start+delta;root.push_input(event,true)
  check(art.origin.distance_to(origin_before+delta)<1.0,"normal drag works at far street while Door is selected")
 check(JSON.stringify([game.model.coins,game.model.items,game.model.wall_attachments,game.model.owned_parcels])==before,"environment camera cannot grant land, charge or change layout")
 var output=OS.get_environment("OUTPUT")
 if output!="":FileAccess.open(output+"/full-map-reach.json",FileAccess.WRITE).store_string(JSON.stringify(reach_results,"  "))
 print("FULL_MAP_CAMERA_ACCESS_RESULT ",JSON.stringify({"checks":checks,"failures":failures,"target_count":targets.size(),"viewports":6,"zoom_levels":3,"player_save_used":false,"native_render_verified":false}))
 for player in game.audio_players.values():player.stop();player.stream=null
 game.settings_controls.sfx_player.stop();game.settings_controls.sfx_player.stream=null
 for tween in get_processed_tweens():tween.kill()
 game.queue_free();await process_frame;quit(0 if failures.is_empty() else 1)
