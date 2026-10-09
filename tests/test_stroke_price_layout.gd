extends "res://tests/test_existing_wall_actions.gd"
func run():
 game=TestMain.new();root.add_child(game);game.set_process(false);game.paused=true;await process_frame
 game._toggle_edit();game._set_catalog_category("Build");game.compact_ui._set_tray_reveal(1)
 var ui=game.compact_ui;var shop=ui.shop_ui;var b=game.build_tools
 shop.show_tiles();b.choose("floor")
 var money=game.model.coins;var saves=game.saves
 for view in [Vector2i(390,844),Vector2i(440,700),Vector2i(566,360),Vector2i(844,390),Vector2i(1360,880)]:
  root.size=view
  b.paint_stroke.active=true;b.paint_stroke.receipt={"count":4,"net":40,"paid":40,"refund":0,"ok":true,"targets":[]}
  await settle();shop.sync_action_details();await settle()
  check(ui.context_label.text=="4 tiles" and shop.price_label.text=="40",str(view)+" quantity and numeric total")
  check(shop.action_coin.visible and shop.action_coin.texture==ui.hud._texture("coin"),str(view)+" existing coin visible")
  var board=shop.action_background.get_global_rect()
  for control in [ui.context_label,shop.action_coin,shop.price_label]:check(board.encloses(control.get_global_rect()),str(view)+" summary inside action board")
  check(not shop.action_coin.get_global_rect().intersects(shop.price_label.get_global_rect()),str(view)+" icon and number do not overlap")
  check(shop.price_label.accessibility_name=="40 coins",str(view)+" accessible currency")
 b.cancel();await settle();check(not shop.action_coin.visible,"cancel removes price icon")
 check(game.model.coins==money and game.saves==saves,"presentation does not change funds or saves")
 print("STROKE_PRICE_LAYOUT_RESULT ",JSON.stringify({"checks":checks,"failures":failures}))
 game.queue_free();await process_frame;quit(0 if failures.is_empty() else 1)
