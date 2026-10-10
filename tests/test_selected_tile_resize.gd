extends "res://tests/test_existing_wall_actions.gd"
func run():
 root.size=Vector2i(1360,880);game=TestMain.new();root.add_child(game);game.set_process(false);game.paused=true;await process_frame
 game._toggle_edit();game.category_buttons["Build"].pressed.emit();game.compact_ui._set_tray_reveal(1)
 var ui=game.compact_ui;var shop=ui.shop_ui
 shop.show_tiles();await settle();shop.tile_cards["cream_tile"].pressed.emit();await settle()
 var coins=game.model.coins;var saves=game.saves
 for view in [Vector2i(390,844),Vector2i(844,390),Vector2i(1360,880),Vector2i(390,844)]:
  root.size=view;await settle();await settle()
  var card=shop.tile_cards["cream_tile"]
  check(card.button_pressed and game.build_tools.floor_material=="cream_tile",str(view)+" active material survives resize")
  check(ui.build_scroll.get_global_rect().encloses(card.get_global_rect()),str(view)+" active Cream card remains fully visible")
 check(game.model.coins==coins and game.saves==saves,"rotation cannot buy or save")
 print("SELECTED_TILE_RESIZE_RESULT ",JSON.stringify({"checks":checks,"failures":failures}))
 game.queue_free();await process_frame;quit(0 if failures.is_empty() else 1)
