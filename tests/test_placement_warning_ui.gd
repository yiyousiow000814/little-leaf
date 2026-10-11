extends "res://tests/test_existing_wall_actions.gd"
class WarningMain extends TestMain:
 func _interaction_over_ui(_point:Vector2)->bool:return false
func aim_floor(at:Vector2i)->Vector2:
 var art=game.illustration;game.interaction._pan_by(art.camera_safe_rect().get_center()-art.iso(at.x+.5,at.y+.5))
 return art.iso(at.x+.5,at.y+.5)
func snapshot():return JSON.stringify([game.model.items,game.model.coins,game.model.revision,game.saves])
func run():
 root.size=Vector2i(1360,880);game=WarningMain.new();root.add_child(game)
 game.set_process(false);game.illustration.set_process(false);game.paused=true;game.tutorial.skip();game.cafe_intro.finish()
 await process_frame;game.model.enable_footprint_placement();game.model.coins=100000;game._toggle_edit()
 var m=game.model;var ui=game.compact_ui;var input=game.interaction
 check(m.move_wall_attachment(1,"shell:west",2.5),"move actual doorway")
 for x in m.BASE_WIDTH:check(m.place_wall("x",x,m.BASE_DEPTH),"close front boundary")
 for z in m.BASE_DEPTH:check(m.place_wall("z",m.BASE_WIDTH,z),"close right boundary")
 game._rebuild_room();game.selected_kind="plant";var before=snapshot()
 input.refresh(aim_floor(Vector2i(0,5)));ui.update_pointer()
 check(input.drag_valid and input.drag_warning=="" and not ui.hint.visible and not ui.hint_warning.visible,"vacated doorway has no obsolete warning icon")
 input.refresh(aim_floor(Vector2i(0,2)));ui.update_pointer()
 check(input.drag_valid and input.drag_warning!="" and ui.hint.visible and ui.hint_warning.visible,"actual blocked path uses separate warning icon while placement stays valid")
 check(ui.hint_warning.accessibility_name=="Walking warning; placement allowed","warning explicitly distinguishes walking from physical permission")
 check(ui.hint.mouse_filter==Control.MOUSE_FILTER_IGNORE and ui.hint_warning.mouse_filter==Control.MOUSE_FILTER_IGNORE,"warning icon cannot intercept placement input")
 check(snapshot()==before,"warning preview preserves layout wallet revision and saves")
 await settle();await capture("furniture-warning-desktop")
 var at=Vector2i(0,2);var wallet=m.coins;var saved=game.saves;input._commit_preview()
 check(m.items.any(func(item):return item.kind=="plant" and Vector2i(item.x,item.z)==at),"walking warning does not prevent actual purchase")
 check(m.coins==wallet-m.price_of("plant") and game.saves==saved+1,"warning purchase charges and saves once")
 input.refresh(aim_floor(at));ui.update_pointer()
 check(not input.drag_valid and ui.hint.visible and not ui.hint_warning.visible,"physical overlap stays invalid without allowed-placement icon")
 await settle();await capture("furniture-invalid-desktop")
 game._cancel_selection();ui.update_pointer();check(not ui.hint.visible and not ui.hint_warning.visible,"cancel clears independent warning")
 game.MinimalStart.apply(m);m.enable_footprint_placement();m.coins=100000;game._rebuild_room();await settle()
 var station=m.items.filter(func(item):return item.kind=="beverage")[0]
 check(m.move(int(station.id),7,6),"prepare actual beverage station away from shell hit targets")
 game._rebuild_room();game._set_catalog_category("Build");game.build_tools.choose("full");game.build_tools.preferred_axis="x"
 var front=m.workface_cell(station)
 var middle=(Vector2(station.x+.5,station.z+.5)+Vector2(front.x+.5,front.y+.5))*.5
 var wall=game.illustration.iso(middle.x,middle.y);game.interaction._pan_by(game.illustration.camera_safe_rect().get_center()-wall);wall=game.illustration.iso(middle.x,middle.y)
 game.build_tools.refresh(wall);ui.update_pointer()
 check(game.build_tools.preview_valid and game.build_tools.preview_warning!="","real wall preview remains physically valid despite walking issue: "+game.build_tools.preview_reason+" "+JSON.stringify(game.build_tools.preview))
 check(ui.hint.visible and ui.hint_warning.visible and ui.last_detail==game.build_tools.preview_warning,"legal wall exposes independent walking warning")
 await settle();game.build_tools.refresh(wall);game.illustration.queue_redraw();await capture("wall-warning-initial-desktop")
 for size in [Vector2i(390,844),Vector2i(844,390),Vector2i(1360,880)]:
  root.size=size;await process_frame;game._update_ui();ui.update_pointer();await process_frame
  check(ui.hint.get_global_rect().end.x<=size.x and ui.hint.get_global_rect().end.y<=size.y,"warning fits supported viewport "+str(size))
  await settle();game.illustration.update_projection()
  var aim=game.illustration.iso(middle.x,middle.y);game.interaction._pan_by(game.illustration.camera_safe_rect().get_center()-aim);aim=game.illustration.iso(middle.x,middle.y)
  game.build_tools.refresh(aim);ui.update_pointer();game.illustration.queue_redraw()
  check(game.build_tools.preview_valid and not game.build_tools.preview.is_empty(),"actual warning wall remains selected after resize "+str(size))
  await capture("wall-warning-"+str(size.x)+"x"+str(size.y))
 var walls_before=m.built_walls.size();wallet=m.coins;saved=game.saves
 game.build_tools._commit()
 check(m.built_walls.size()==walls_before+1 and m.coins==wallet-m.wall_price("full") and game.saves==saved+1,"legal warning wall commits and charges/saves exactly once")
 game._cancel_selection();ui.update_pointer();check(not ui.hint.visible,"wall cancel clears warning")
 print("PLACEMENT_WARNING_UI_RESULT ",JSON.stringify({"checks":checks,"failures":failures}))
 game.queue_free();await process_frame;quit(0 if failures.is_empty() else 1)
