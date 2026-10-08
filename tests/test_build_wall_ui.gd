extends "res://tests/test_existing_wall_actions.gd"
## Wall browsing has the same shelf/back interaction as Tiles at every size.
func run():
 if not "saveguard" in OS.get_user_data_dir():printerr("Use isolated profile");quit(2);return
 root.size=Vector2i(1164,624);game=TestMain.new();root.add_child(game);game.set_process(false);game.illustration.set_process(false);game.paused=true
 await process_frame;game._toggle_edit();game._set_catalog_category("Build");game.compact_ui._set_tray_reveal(1);await settle()
 var shop=game.compact_ui.shop_ui;var ui=game.compact_ui;var tool=game.build_tools
 for view in [Vector2i(1164,624),Vector2i(1360,880),Vector2i(390,844),Vector2i(566,360),Vector2i(844,390)]:
  root.size=view;shop.show_build_products();await settle()
  var wallet=game.model.coins;var saves=game.saves
  await click(tool.tool_buttons["full"].get_global_rect().get_center())
  check(shop.build_page=="walls" and not ui.has_open_popup(),str(view)+" Wall opens bottom shelf without old modal")
  check(shop._visible_build_keys().size()==6,"Wall collection shows all six height/style products")
  check(shop.tiles_back.is_visible_in_tree() and shop.tiles_title.text=="Wall","Wall uses matching Build back navigation and header")
  for key in shop._visible_build_keys():
   var card=shop.wall_cards[key]
   ui.build_scroll.ensure_control_visible(card);await settle()
   var bounds=card.get_global_rect();var shelf=ui.build_scroll.get_global_rect()
   check(shelf.grow(1).encloses(bounds),str(view)+" complete wall card can be reached: "+key)
   for label in [card.get_child(0).get_child(1),card.get_child(0).get_child(3)]:
    if label.is_visible_in_tree():
     var font=label.get_theme_font("font");var size=label.get_theme_font_size("font_size")
     check(font.get_string_size(label.text,HORIZONTAL_ALIGNMENT_LEFT,-1,size).x<=label.size.x+.6,str(view)+" wall text fits: "+label.text)
   await click(bounds.get_center())
   var choice=shop.wall_styles[key]
   check(tool.mode==choice.height and tool.material==choice.material,"wall card picks exact height and material")
   check(not ui.has_open_popup() and shop.build_page=="walls","choosing style keeps tray and world available")
  check(game.model.coins==wallet and game.saves==saves,"browsing every style never charges or saves")
  await click(shop.tiles_back.get_global_rect().get_center())
  check(shop.build_page=="products" and shop._visible_build_keys().size()==4,"Back returns to four Build collections")
  ui.build_scroll.ensure_control_visible(shop.tiles_card);await settle()
  await click(shop.tiles_card.get_global_rect().get_center())
  check(shop.build_page=="tiles" and shop._visible_build_keys().size()==3,"Tiles interaction remains unchanged")
  shop.show_walls("shell:back#2");await settle()
  check(shop._visible_build_keys().size()==8,"selected starter wall also offers Original room finish")
  game._set_catalog_category("Kitchen");await settle()
  check(shop.build_page=="products","changing category exits Wall shelf cleanly")
  game._set_catalog_category("Build");await settle()
 print("BUILD_WALL_UI_RESULT ",JSON.stringify({"checks":checks,"failures":failures,"player_save_used":false,"native_render_verified":false}))
 for player in game.audio_players.values():player.stop();player.stream=null
 game.settings_controls.sfx_player.stop();game.settings_controls.sfx_player.stream=null
 for tween in get_processed_tweens():tween.kill()
 game.queue_free();await process_frame;quit(0 if failures.is_empty() else 1)
