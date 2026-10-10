extends "res://tests/test_existing_wall_actions.gd"
## Native, disposable-profile acceptance of opening ownership and UI transactions.
func opening_point(id:int)->Vector2:
 var a=game.model.get_wall_attachment(id)
 var aperture=game.build_tools.OpeningGeometry.aperture(a,game.model.built_walls)
 var center=(aperture.a+aperture.b)*.5
 var art=game.illustration;var point=art.iso(center.x,center.y,70)
 game.interaction._pan_by(art.camera_safe_rect().get_center()-point)
 return art.iso(center.x,center.y,70)
func run():
 if not "saveguard" in OS.get_user_data_dir():printerr("Use isolated profile");quit(2);return
 root.size=Vector2i(1360,880);game=TestMain.new();root.add_child(game);game.set_process(false);game.illustration.set_process(false);game.paused=true
 await process_frame;game.model.coins=1600;game._toggle_edit();game._set_catalog_category("Build");game.compact_ui._set_tray_reveal(1);await settle()
 var ui=game.compact_ui;var model=game.model;var tool=game.build_tools
 # Baseline includes a free door only. This explicitly synthetic restored window
 # exercises free-window provenance without claiming a default starter window.
 model.wall_attachments.append({"id":2,"kind":"window","host_id":"shell:back","offset":2.5,"width":.70,"paid_cost":0});model._next_attachment_id=3
 var cases=[{"id":1,"label":"starter free door"},{"id":2,"label":"restored free window fixture"}]
 for spec in [["door",3.5],["window",4.5]]:
  game._cancel_selection();await settle();await click(tool.tool_buttons[spec[0]].get_global_rect().get_center())
  var wallet=model.coins;var saves=game.saves;var count=model.wall_attachments.size()
  await click(aim(spec[1]))
  check(model.wall_attachments.size()==count+1,"buy via catalog/world click "+spec[0])
  check(model.coins==wallet-model.attachment_price(spec[0]) and game.saves==saves+1,"buy charges and saves exactly once "+spec[0])
  cases.append({"id":int(model.wall_attachments[-1].id),"label":"purchased "+spec[0]})
 for entry in cases:
  var id=int(entry.id);var label=str(entry.label)
  game._cancel_selection();await settle();await click(opening_point(id))
  check(tool.opening_source_id==id and ui.move_button.visible and ui.remove_button.visible,"world selection exposes Move/Sell "+label)
  check(ui.remove_button.text=="Sell +"+ui.Money.amount(model.wall_attachment_refund(id)),"UI uses authoritative refund "+label)
  var before=model.get_wall_attachment(id).duplicate(true);var wallet=model.coins;var saves=game.saves
  await click(ui.move_button.get_global_rect().get_center());var target=aim(8.5);tool.refresh(target)
  check(tool.preview_valid,"clear destination preview "+label+": "+tool.preview_reason)
  check(model.get_wall_attachment(id)==before and model.coins==wallet and game.saves==saves,"preview preserves provenance and wallet "+label)
  game.interaction.cancel();await settle()
  check(tool.mode=="" and model.get_wall_attachment(id)==before and game.saves==saves,"cancel leaves opening unchanged "+label)
  await click(opening_point(id));await click(ui.move_button.get_global_rect().get_center());await click(aim(8.5))
  var moved=model.get_wall_attachment(id).duplicate(true)
  check(moved.host_id=="shell:back" and is_equal_approx(float(moved.offset),8.5),"move commits destination "+label)
  check(moved.id==before.id and moved.width==before.width and moved.paid_cost==before.paid_cost and model.coins==wallet and game.saves==saves+1,"move preserves identity/payment, saves once "+label)
  check(model.save("user://opening-acceptance.json"),"synthetic save "+label+": "+model.last_error)
  check(model.load_save("user://opening-acceptance.json"),"synthetic reload "+label+": "+model.last_error)
  check(model.get_wall_attachment(id)==moved,"reload preserves opening provenance "+label)
  game._cancel_selection();await settle();await click(opening_point(id));await capture("selected-"+str(id))
  var refund=model.wall_attachment_refund(id);wallet=model.coins;saves=game.saves
  await click(ui.remove_button.get_global_rect().get_center())
  check(model.get_wall_attachment(id).is_empty() and model.coins==wallet+refund and game.saves==saves+1,"sale applies one actual refund "+label)
  ui._remove_selected();check(model.coins==wallet+refund and game.saves==saves+1,"stale repeated sale cannot refund twice "+label)
  check(model.save("user://opening-acceptance.json") and model.load_save("user://opening-acceptance.json") and model.get_wall_attachment(id).is_empty(),"sold opening stays removed after reload "+label)
  operations.append({"case":label,"id":id,"paid_cost":before.paid_cost,"refund":refund})
 game._cancel_selection();ui.shop_ui.show_tiles();await settle()
 var cell=Vector2i(7,7)
 for style in ["cream_tile","sage_tile","warm_oak"]:
  var wallet=model.coins;var saves=game.saves
  await click(ui.shop_ui.tile_cards[style].get_global_rect().get_center())
  check(tool.mode=="floor" and tool.floor_material==style and ui.shop_ui.tiles_active(),"Tiles card selects true-color inspection "+style)
  check(model.coins==wallet and game.saves==saves,"material selection does not buy tiles "+style)
  var point=game.illustration.iso(7.5,7.5)
  game.interaction._pan_by(game.illustration.camera_safe_rect().get_center()-point)
  point=game.illustration.iso(7.5,7.5);tool.refresh(point)
  var quote=model.floor_quote(cell,style)
  await click(point)
  check(model.floor_style_at(cell)==style and model.coins==wallet-int(quote.net) and game.saves==saves+1,"world tile click uses quoted transaction "+style)
  check(model.save("user://opening-acceptance.json") and model.load_save("user://opening-acceptance.json") and model.floor_style_at(cell)==style,"tile material survives reload "+style)
  await capture("tiles-"+style)
 game.interaction.cancel();check(tool.mode=="" and not ui.shop_ui.objects_hidden(),"cancel stops painting and restores objects")
 await click(ui.shop_ui.tiles_back.get_global_rect().get_center());check(not ui.shop_ui.tiles_active(),"Back exits true-color inspection")
 print("OPENING_TRANSACTIONS_UI_RESULT ",JSON.stringify({"checks":checks,"failures":failures,"operations":operations,"player_save_used":false,"native_render_verified":DisplayServer.get_name()!="headless"}))
 game.queue_free();await process_frame;quit(0 if failures.is_empty() else 1)
