extends "res://tests/test_existing_wall_actions.gd"
func button(point:Vector2,down:bool,canceled:bool=false):
 var event=InputEventMouseButton.new();event.position=point;event.button_index=MOUSE_BUTTON_LEFT;event.pressed=down;event.canceled=canceled
 if down:game.build_tools.handle_unhandled_input(event)
 else:game.build_tools.handle_input(event)
func motion(point:Vector2):
 var event=InputEventMouseMotion.new();event.position=point;event.button_mask=MOUSE_BUTTON_MASK_LEFT;game.build_tools.handle_input(event)
func point(x:float,z:float)->Vector2:return game.illustration.iso(x,z)
func anchor(x:float,z:float):
 game.interaction._pan_by(game.illustration.camera_safe_rect().get_center()-point(x,z))
func snapshot()->Array:
 var m=game.model
 return [m.floor_finishes.duplicate(true),m.built_walls.duplicate(true),m.shell_segment_products.duplicate(true),m.coins,m.revision,game.saves]
func run():
 root.size=Vector2i(1360,880);game=TestMain.new();root.add_child(game);game.set_process(false);game.illustration.set_process(false);game.paused=true
 await process_frame;game.model.coins=100000;game._toggle_edit();game._set_catalog_category("Build");game.compact_ui._set_tray_reveal(1);await settle()
 var b=game.build_tools;var shop=game.compact_ui.shop_ui;var m=game.model
 shop.show_tiles();b.floor_material="cream_tile";b.choose("floor");anchor(5.5,7.5)
 var start=point(4.5,7.5);var finish=point(7.5,7.5);var before=snapshot();var camera=game.illustration.pan_offset
 button(start,true);motion(finish)
 game.illustration.queue_redraw();await process_frame;await process_frame
 check(b.paint_stroke.active and b.paint_stroke.receipt.ok,"drag starts valid bulk tile preview")
 check(int(b.paint_stroke.receipt.count)==4,"fast pointer traverses all four cells")
 check(snapshot()==before,"whole stroke remains nonmutating before release")
 check(game.illustration.pan_offset==camera,"painting does not pan camera")
 var cost=int(b.paint_stroke.receipt.net);motion(start);motion(finish)
 check(int(b.paint_stroke.receipt.count)==4 and int(b.paint_stroke.receipt.net)==cost,"revisiting cells does not duplicate count or cost")
 check(shop.price_label.text=="Pay "+shop.ui.Money.amount(cost),"preview shows total stroke price")
 button(finish,false)
 for x in range(4,8):check(m.floor_style_at(Vector2i(x,7))=="cream_tile","release paints cell "+str(x))
 check(m.coins==before[3]-cost and game.saves==before[5]+1,"bulk tiles charge exact total and save once")
 button(finish,false);check(game.saves==before[5]+1,"duplicate release cannot charge again")
 b.floor_material="sage_tile";b.choose("floor");before=snapshot();button(start,true);motion(finish)
 game.interaction.cancel();check(snapshot()==before and not b.paint_stroke.active,"Escape/cancel rolls back entire preview")
 b.choose("floor");button(start,true);motion(finish);button(finish,false,true)
 check(snapshot()==before and not b.paint_stroke.active,"canceled pointer cannot buy partial stroke")
 b.choose("floor");button(start,true);motion(finish);b.on_focus_lost();button(finish,false)
 check(snapshot()==before,"focus loss discards stroke")
 b.choose("floor");button(start,true);motion(point(5.5,7.5));button(finish,false)
 check(snapshot()==before,"release cannot add unpreviewed cells to purchase")
 b.choose("floor");button(start,true);motion(finish);m.coins-=1;before=snapshot();button(finish,false)
 check(snapshot()==before,"wallet change invalidates shown-price receipt")
 m.coins=1;b.choose("floor");before=snapshot();button(start,true);motion(finish)
 check(not b.paint_stroke.receipt.ok,"total affordability blocks over-budget stroke")
 button(finish,false);check(snapshot()==before,"over-budget stroke is atomic")
 m.coins=100000;b.choose("floor");anchor(10.5,8.5);start=point(10.5,8.5);finish=point(12.5,8.5);before=snapshot()
 button(start,true);motion(finish);check(not b.paint_stroke.receipt.ok,"unowned cell invalidates whole stroke")
 button(finish,false);check(snapshot()==before,"unowned crossing buys nothing")
 b.choose("floor");anchor(5.5,6.5);start=point(4.5,6.5);finish=point(7.5,6.5);before=snapshot()
 button(start,true);motion(finish);game.save_recovery_blocked=true;button(finish,false);game.save_recovery_blocked=false
 check(snapshot()==before and not b.paint_stroke.active,"recovery interrupts stroke without committing")
 b.choose("full");b.material="cream_stripe";b.preferred_axis="x";anchor(8,7);start=point(7.5,7);finish=point(9.5,7);before=snapshot()
 button(start,true);motion(finish)
 game.illustration.queue_redraw();await process_frame;await process_frame
 check(b.paint_stroke.active and b.paint_stroke.receipt.ok,"drag starts valid wall row preview")
 check(int(b.paint_stroke.receipt.count)==3,"wall row visits three unique edges")
 cost=int(b.paint_stroke.receipt.net);motion(start);motion(finish)
 check(int(b.paint_stroke.receipt.count)==3 and snapshot()==before,"wall revisits remain nonmutating and unique")
 button(finish,false)
 for x in range(7,10):check(not m.get_wall(m.WallGeometry.key("x",x,7)).is_empty(),"release builds edge "+str(x))
 check(m.coins==before[3]-cost and game.saves==before[5]+1,"wall row charges once and saves once")
 b.choose("full");b.material="leaf_print";b.preferred_axis="x";before=snapshot();button(start,true);motion(finish)
 check(b.paint_stroke.receipt.ok,"existing wall row can be restyled in one stroke")
 cost=int(b.paint_stroke.receipt.net);button(finish,false)
 for x in range(7,10):check(m.get_wall(m.WallGeometry.key("x",x,7)).material=="leaf_print","bulk replacement preserves edge "+str(x))
 check(m.coins==before[3]-cost and game.saves==before[5]+1,"bulk replacement uses exact quoted net price")
 print("PAINT_STROKE_UI_RESULT ",JSON.stringify({"checks":checks,"failures":failures}))
 game.queue_free();await process_frame;quit(0 if failures.is_empty() else 1)
