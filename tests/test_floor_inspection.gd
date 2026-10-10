extends "res://tests/test_build_tiles_ui.gd"
## Generated café only: Tiles inspection never mutates model, collisions or saves.
class FloorRecorder extends RefCounted:
 var fills=[]
 func iso(x,z):return Vector2(x,z)
 func poly(points,color):fills.append([points,color])
 func line(_a,_b,_color,_width):pass
class ShellProbe extends RefCounted:
 var calls=0
 func draw(_art,_host,_openings,_face,_end):calls+=1
class RenderProbe extends "res://scripts/illustrated_cafe.gd":
 var draws=0
 var furniture=[]
 var scenery_calls=0
 var plot_calls=0
 func _draw():
  draws+=1;furniture=[];shell_draw_cache.calls=0;scenery_calls=0;plot_calls=0;super._draw()
 func _scenery_tree(_world:Vector2,_scale:float):scenery_calls+=1
 func _parcel_sign(_parcel):plot_calls+=1
 func item(kind:String,_point:Vector2,_rot:int,_id:int,_variant:String=""):furniture.append(kind)
 func _chair(_point:Vector2,_rot:int,_back:bool,_style:String="basic"):furniture.append("chair")
func complete_snapshot()->Array:
 var m=game.model
 return [m.items.duplicate(true),m.floor_finishes.duplicate(true),m.built_walls.duplicate(true),m.wall_attachments.duplicate(true),m.shell_segment_products.duplicate(true),m.owned_parcels.duplicate(true),m.customers.duplicate(true),m.outside_queue.duplicate(true),game.staff_states.duplicate(true),game.service_guests.duplicate(true),m.coins,m.revision,game.saves,m._furniture_actor_component(m.ENTRY_LANDING,m.items)]
func paint_count()->int:
 # Placement validity is confined to the selected footprint; Tiles must never
 # reintroduce the removed whole-floor red/green availability wash.
 var recorder=FloorRecorder.new()
 if game.interaction.has_method("draw_floor_feedback"):game.interaction.draw_floor_feedback(recorder)
 return recorder.fills.size()
func click_world(point:Vector2):
 for pressed in [true,false]:
  var event=InputEventMouseButton.new();event.position=point;event.button_index=MOUSE_BUTTON_LEFT;event.pressed=pressed
  if pressed:
   if not ui.handle_unhandled_input(event):game.interaction.handle_unhandled_input(event)
  else:game.interaction.handle_input(event)
func toggle_layout(label:String):
 var button=shop.hide_objects_button;var viewport=Rect2(Vector2.ZERO,Vector2(root.size))
 target(button,label+" hide toggle",viewport)
 check(button.is_visible_in_tree(),label+" toggle remains visible")
 check(not button.get_global_rect().intersects(shop.tiles_back.get_global_rect()),label+" toggle and Back are separate")
 if ui.floor_repair_button.visible:check(not button.get_global_rect().intersects(ui.floor_repair_button.get_global_rect()),label+" toggle and repair are separate")
 var font=button.get_theme_font("font");var font_size=button.get_theme_font_size("font_size")
 for line in button.text.split("\n"):check(font.get_string_size(line,HORIZONTAL_ALIGNMENT_LEFT,-1,font_size).x+16<=button.size.x,label+" toggle text fits")
 check(not button.get_global_rect().intersects(ui.build_scroll.get_global_rect()),label+" toggle does not cover tile shelf")
func run():
 if not "saveguard" in OS.get_user_data_dir():printerr("SAVEGUARD FAILED: use the isolated runner");quit(2);return
 root.size=Vector2i(1360,880)
 game=TestMain.new();root.add_child(game);game.set_process(false);game.paused=true
 await process_frame
 ui=game.compact_ui;shop=ui.shop_ui
 game.editing=true;game.tray.show();game.model.coins=100000;game._set_catalog_category("Build");ui._set_tray_reveal(1);await settle()
 check(paint_count()==0,"ordinary Build has no whole-floor availability tint")
 check(game.model.place("rug",7,6),"fixture places rug")
 check(game.model.place_wall("x",8,5,"full","sage_panels"),"fixture places wall")
 var before=complete_snapshot()
 var file="user://inspection-generated.json"
 check(game.model.save(file),"generated baseline save succeeds")
 var baseline_save=FileAccess.get_sha256(file)
 var probe=RenderProbe.new();probe.game=game;probe.shell_draw_cache=ShellProbe.new()
 probe.use_screen_culling=false;probe.use_background_cache=false;probe.use_cached_moving_art=false;probe.use_cached_heads=false;probe.furniture_art.cache_enabled=false
 game.add_child(probe);probe.set_process(false)
 for frame in 3:await process_frame
 check(probe.draws>0,"render probe receives a real canvas draw")
 check(probe.furniture.has("rug") and probe.shell_draw_cache.calls==2,"normal draw includes rug and both shell walls")
 var environment_calls=[probe.scenery_calls,probe.plot_calls]
 var old_draw=game.illustration.render_idle.snapshot(game.illustration).duplicate(true)
 shop.show_tiles();await settle()
 check(paint_count()==0,"Tiles browsing removes red and green availability paint")
 check(old_draw!=game.illustration.render_idle.snapshot(game.illustration),"Tiles transition invalidates retained draw")
 var item=game.model.items[0]
 var point=game.illustration.iso(item.x+.5,item.z+.5)
 var shell=game.illustration.iso(0,2.5,65)
 var opening=game.illustration.iso(0,5.5,55)
 var wall=game.illustration.iso(8.5,5,65)
 check(game.illustration.hit_item(point)>=0,"visible furniture is pickable")
 check(not game.illustration.hit_wall_host(shell).is_empty(),"visible shell is pickable")
 check(game.illustration.hit_wall_attachment(opening)>=0,"visible door is pickable")
 check(not game.illustration.hit_wall(wall).is_empty(),"visible placed wall is pickable")
 old_draw=game.illustration.render_idle.snapshot(game.illustration).duplicate(true)
 await click(shop.hide_objects_button)
 check(shop.objects_hidden() and shop.hide_objects_button.button_pressed,"real toggle hides objects")
 probe.queue_redraw()
 for frame in 3:await process_frame
 check(probe.furniture.is_empty() and probe.shell_draw_cache.calls==0,"hidden draw excludes all furniture and shell walls")
 check([probe.scenery_calls,probe.plot_calls]==environment_calls and probe.plot_calls>0,"hidden draw preserves scenery and ownership signs")
 check(old_draw!=game.illustration.render_idle.snapshot(game.illustration),"toggle invalidates retained draw")
 check(game.illustration.hit_item(point)<0,"hidden furniture cannot be picked")
 check(game.illustration.hit_wall_host(shell).is_empty(),"hidden shell cannot be picked")
 check(game.illustration.hit_wall_attachment(opening)<0,"hidden door cannot be picked")
 check(game.illustration.hit_wall(wall).is_empty(),"hidden placed wall cannot be picked")
 click_world(point)
 check(game.selected_id<0 and ui.selected_wall=="" and ui.selected_shell=="" and shop.objects_hidden(),"empty-floor click cannot select hidden objects via fallback")
 game.interaction._begin_left(point);game.interaction._move_left(point+Vector2(20,0))
 check(not game.interaction.drag_active and game.interaction._gesture=="pan","hidden furniture drag pans instead of moving it")
 game.interaction.on_focus_lost()
 for style in game.build_tools.FLOOR_STYLES:
  shop.choose_floor_style(style);await settle()
  check(shop.objects_hidden(),"choosing "+style+" preserves inspection")
  check(paint_count()==0,"choosing "+style+" keeps true floor colors")
 check(complete_snapshot()==before,"browsing toggling selecting and panning leave model and pathfinding unchanged")
 check(game.model.save(file) and FileAccess.get_sha256(file)==baseline_save,"inspection is absent from generated save bytes")
 # Hidden furniture still occupies its model footprint; normal one-cell tile
 # installation remains available underneath it at the existing quoted price.
 shop.choose_floor_style("cream_tile")
 var occupied=Vector2i(item.x,item.z);var quote=game.model.floor_quote(occupied,"cream_tile")
 var coins=game.model.coins;var writes=game.saves
 install(occupied)
 check(game.model.floor_style_at(occupied)=="cream_tile" and game.model.coins==coins-int(quote.net) and game.saves==writes+1,"hidden floor placement uses the normal one-cell charge and save")
 check(shop.objects_hidden() and game.model.items==before[0] and game.model.built_walls==before[2] and game.model._furniture_actor_component(game.model.ENTRY_LANDING,game.model.items)==before[-1],"floor placement preserves inspection, objects and collision rules")
 # Cancel covers both the active floor tool and idle browsing input routes.
 var cancel=InputEventKey.new();cancel.keycode=KEY_ESCAPE;cancel.pressed=true
 game.build_tools.handle_input(cancel);await settle()
 check(not shop.objects_hidden(),"Escape from floor tool restores objects")
 probe.queue_redraw()
 for frame in 3:await process_frame
 check(probe.furniture.has("rug") and probe.shell_draw_cache.calls==2,"cancel restores furniture and shell draw commands")
 probe.queue_free();await process_frame
 check(paint_count()==0,"cancel inside Tiles retains true floor colors")
 await click(shop.hide_objects_button);game.interaction.handle_input(cancel);await settle()
 check(not shop.objects_hidden(),"Escape while browsing restores objects")
 for route in ["toggle","cancel-button","right-click","back","category","done"]:
  shop.show_tiles();shop.choose_floor_style("cream_tile");await click(shop.hide_objects_button)
  check(shop.objects_hidden(),route+" begins with objects hidden")
  match route:
   "toggle":await click(shop.hide_objects_button)
   "cancel-button":await click(ui.cancel_button)
   "right-click":
    var event=InputEventMouseButton.new();event.button_index=MOUSE_BUTTON_RIGHT;event.pressed=true;game.build_tools.handle_input(event)
   "back":shop.show_build_products()
   "category":game._set_catalog_category("Decor")
   "done":game._toggle_edit()
  await settle()
  check(not shop.objects_hidden() and not shop.hide_objects,route+" restores objects and clears state")
  check(game.illustration.hit_item(game.illustration.iso(item.x+.5,item.z+.5))>=0,route+" restores picking")
  if route=="done":game._toggle_edit()
  game._set_catalog_category("Build");await settle()
 shop.show_build_products();await settle()
 check(paint_count()==0,"leaving Tiles preserves selected-footprint-only placement feedback")
 for view in [Vector2i(1360,880),Vector2i(344,844),Vector2i(390,844),Vector2i(566,344),Vector2i(566,360),Vector2i(844,390)]:
  root.size=view;shop.show_tiles();await settle();toggle_layout(str(view))
  game.model.floor_finishes.erase("11,8");game.model._notify();await settle();toggle_layout(str(view)+" repair")
  await click(shop.hide_objects_button);toggle_layout(str(view)+" showing")
  game.model.floor_finishes["11,8"]={"style":"warm_oak","paid_cost":0};game.model._notify()
  shop.show_build_products();await settle()
 check(not shop.hide_objects_button.visible,"toggle absent outside Tiles")
 print("FLOOR_INSPECTION_RESULT ",JSON.stringify({"checks":checks,"failures":failures}))
 await dispose();quit(0 if failures.is_empty() else 1)
