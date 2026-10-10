extends "res://tests/test_existing_wall_actions.gd"
func target_point(x:float,z:float)->Vector2:
 var art=game.illustration;var point=art.iso(x,z)
 game.interaction._pan_by(art.camera_safe_rect().get_center()-point)
 return art.iso(x,z)
func run():
 root.size=Vector2i(1164,624);game=TestMain.new();root.add_child(game);game.set_process(false);game.illustration.set_process(false);game.paused=true
 await process_frame;game.model.coins=100000;game._toggle_edit();game._set_catalog_category("Tables");game.compact_ui._set_tray_reveal(1);await settle()
 var ui=game.compact_ui;var model=game.model;var tool=game.build_tools
 var fixture=model.WallGeometry.make("x",9,7,"full","cream_stripe");fixture["id"]=1001;model.built_walls.append(fixture)
 for source in [model.WallGeometry.key_of(fixture),"shell:back#9"]:
  game._cancel_selection()
  if source.begins_with("shell:"):ui.selected_shell=source
  else:ui.selected_wall=source
  ui.sync()
  check(ui.move_button.visible and ui.remove_button.visible,"wall has Move and Sell: "+source)
  check(ui.remove_button.text=="Sell +"+ui.Money.amount(model.wall_refund(source)),"Sell displays model refund: "+source)
  var before=[model.built_walls.duplicate(true),model.shell_segment_products.duplicate(true),model.coins,game.saves]
  ui._move_opening()
  check(tool.active() and tool.mode=="move_wall" and tool.wall_source_key==source,"Move activates outside Build: "+source)
  var destination=target_point(8.5,7 if not source.begins_with("shell:") else 6)
  tool.refresh(destination)
  check(tool.preview_valid,"wall move has valid edge preview: "+source+" "+tool.preview_reason)
  check(model.built_walls==before[0] and model.shell_segment_products==before[1] and model.coins==before[2] and game.saves==before[3],"preview never commits or charges: "+source)
  tool.rotate();check(tool.preferred_axis=="z","R rotates preview only: "+source)
  game.interaction.cancel();check(tool.mode=="" and tool.wall_source_key=="","cancel clears wall move: "+source)
  check(model.built_walls==before[0] and model.shell_segment_products==before[1] and game.saves==before[3],"cancel leaves wall at source: "+source)
  if source.begins_with("shell:"):ui.selected_shell=source
  else:ui.selected_wall=source
  ui._move_opening();tool.refresh(destination);var target=tool.selected_key
  tool._commit()
  check(tool.mode=="" and ui.selected_wall==target,"commit selects moved wall: "+source)
  check(not model.get_editable_wall(target).is_empty() and model.coins==before[2] and game.saves==before[3]+1,"successful move costs nothing and saves once: "+source)
  var refund=model.wall_refund(target);var coins=model.coins;var saves=game.saves
  ui._remove_selected()
  check(model.get_editable_wall(target).is_empty() and model.coins==coins+refund and game.saves==saves+1,"Sell uses actual model receipt and saves once: "+source)
  check(ui.selected_wall=="" and ui.selected_shell=="","sale clears selection: "+source)
 game._cancel_selection();ui.selected_shell="shell:back#10";ui.sync()
 var coins=model.coins;var saves=game.saves;var refund=model.wall_refund(ui.selected_shell)
 ui._remove_selected()
 check(model.get_editable_wall("shell:back#10").is_empty() and model.coins==coins+refund and game.saves==saves+1,"included shell segment can sell for its actual refund")
 print("WALL_MOVE_SELL_UI_RESULT ",JSON.stringify({"checks":checks,"failures":failures}))
 game.queue_free();await process_frame;quit(0 if failures.is_empty() else 1)
