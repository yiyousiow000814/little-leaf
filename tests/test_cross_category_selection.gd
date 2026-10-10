extends "res://tests/test_existing_wall_actions.gd"
func door_aim()->Vector2:
 var aperture=game.model.OpeningGeometry.aperture(game.model.wall_attachments[0],game.model.built_walls,game.model.shell_products)
 var middle=(aperture.a+aperture.b)*.5;var art=game.illustration
 var point=art.iso(middle.x,middle.y,28)
 game.interaction._pan_by(art.camera_safe_rect().get_center()-point)
 return art.iso(middle.x,middle.y,28)
func press(point:Vector2,down:bool):
 var event=InputEventMouseButton.new();event.position=point;event.global_position=point;event.button_index=MOUSE_BUTTON_LEFT;event.pressed=down;root.push_input(event,true)
func run():
 root.size=Vector2i(1164,624);game=TestMain.new();root.add_child(game);game.set_process(false);game.illustration.set_process(false);game.paused=true
 await process_frame;game.model.coins=100000;game._toggle_edit();game.compact_ui._set_tray_reveal(1);await settle()
 var ui=game.compact_ui;var model=game.model;var tool=game.build_tools
 var fixture_wall=model.WallGeometry.make("x",9,7,"full","cream_stripe");fixture_wall["id"]=1001;model.built_walls.append(fixture_wall)
 var before=[model.items.duplicate(true),model.wall_attachments.duplicate(true),model.coins,game.saves]
 for category in game.category_buttons:
  game._set_catalog_category(category);game._cancel_selection();await settle()
  await click(aim(2.5));check(ui.selected_shell=="shell:back#2",category+": shell selectable")
  await click(aim(2.5));check(ui.selected_shell=="shell:back#2",category+": repeated shell click remains selected")
  game._cancel_selection();await settle()
  var wall_point=game.illustration.iso(9.5,7,70)
  game.interaction._pan_by(game.illustration.camera_safe_rect().get_center()-wall_point)
  wall_point=game.illustration.iso(9.5,7,70);await click(wall_point)
  check(ui.selected_wall==model.WallGeometry.key_of(fixture_wall),category+": player-built wall selectable")
  game._cancel_selection();await settle();var point=door_aim();await settle()
  check(game.illustration.hit_wall_attachment(point)==int(model.wall_attachments[0].id),category+": door test point hits attached door")
  await click(point);check(tool.opening_source_id==int(model.wall_attachments[0].id),category+": door selectable")
  check(game.catalog_category==category,category+": selection preserves browsing category")
  await click(point);check(tool.opening_source_id==int(model.wall_attachments[0].id),category+": repeated door click remains selected")
  ui._move_opening();check(tool.active() and tool.mode=="move_opening",category+": Move works without category switch")
  game.interaction.cancel();check(tool.mode=="" and ui.selected_shell=="",category+": cancel clears selection")
  point=door_aim();await settle();press(point,true)
  var motion=InputEventMouseMotion.new();motion.position=point+Vector2(25,0);motion.global_position=motion.position;motion.button_mask=MOUSE_BUTTON_MASK_LEFT;root.push_input(motion,true);press(motion.position,false);await settle()
  check(tool.opening_source_id<0,category+": drag pans without selecting or moving door")
  game._cancel_selection();game.selected_kind="plant";point=aim(2.5)
  var event=InputEventMouseButton.new();event.position=point;event.button_index=MOUSE_BUTTON_LEFT;event.pressed=true
  check(not ui.handle_unhandled_input(event) and ui.selected_shell=="",category+": product preview keeps priority")
  game._cancel_selection();await settle()
  var furnishing=model.items.filter(func(item):return item.kind=="table")[0]
  var furniture_point=game.illustration.iso(furnishing.x+.5,furnishing.z+.5,25)
  game.interaction._pan_by(game.illustration.camera_safe_rect().get_center()-furniture_point)
  furniture_point=game.illustration.iso(furnishing.x+.5,furnishing.z+.5,25)
  await click(furniture_point)
  check(game.selected_id==model.logical_item_id(int(furnishing.id)),category+": furniture remains selectable")
  game._cancel_selection();event.position=game.category_buttons[category].get_global_rect().get_center()
  check(not ui.handle_unhandled_input(event),category+": UI press cannot select world wall")
  game._cancel_selection();await settle()
  var empty=game.illustration.iso(10.5,7.5);game.interaction._pan_by(game.illustration.camera_safe_rect().get_center()-empty);empty=game.illustration.iso(10.5,7.5)
  await click(empty);check(ui.selected_shell=="" and tool.opening_source_id<0,category+": empty floor does not select wall")
 check(model.items==before[0] and model.wall_attachments==before[1] and model.coins==before[2] and game.saves==before[3],"selection, drag and cancellation never mutate, purchase or save")
 print("CROSS_CATEGORY_SELECTION_RESULT ",JSON.stringify({"checks":checks,"failures":failures}))
 game.queue_free();await process_frame;quit(0 if failures.is_empty() else 1)
