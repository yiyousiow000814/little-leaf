extends "res://tests/test_paint_stroke_ui.gd"
## Real production render/controller code with generated state and suppressed saves.
var frames=[]
var output=OS.get_environment("EDITOR_CAPTURE_OUTPUT")
func shot(label:String):
 await settle()
 game.illustration.queue_redraw()
 for frame in 3:await process_frame
 if DisplayServer.get_name()!="headless":
  await RenderingServer.frame_post_draw
  check(root.get_texture().get_image().save_png(output.path_join(label+".png"))==OK,"write native frame "+label)
 frames.append({"file":label+".png","viewport":[root.size.x,root.size.y],"zoom":game.illustration.zoom,"objects_hidden":game.compact_ui.shop_ui.objects_hidden(),"tool":game.build_tools.mode,"coins":game.model.coins,"saves":game.saves})
func run():
 if not "saveguard" in OS.get_user_data_dir():printerr("Use isolated saveguard profile");quit(2);return
 var native=DisplayServer.get_name()!="headless"
 if native and output=="":printerr("EDITOR_CAPTURE_OUTPUT required");quit(2);return
 if native:DirAccess.make_dir_recursive_absolute(output)
 seed(123456)
 root.size=Vector2i(1360,880);game=TestMain.new();root.add_child(game)
 game.set_process(false);game.illustration.set_process(false);game.paused=true
 game.tutorial.skip();game.cafe_intro.active=false
 await process_frame;game.model.coins=100000;game._toggle_edit();game._set_catalog_category("Build");game.compact_ui._set_tray_reveal(1);await settle()
 var b=game.build_tools;var shop=game.compact_ui.shop_ui;var m=game.model
 shop.show_tiles();await settle();anchor(5.5,5.5)
 await shot("01-tiles-true-color")
 await click(shop.hide_objects_button.get_global_rect().get_center())
 check(shop.objects_hidden(),"real Hide objects button enters inspection")
 await shot("02-tiles-hidden-objects")
 shop.choose_floor_style("cream_tile");await settle();anchor(5.5,7.5)
 var start=point(4.5,7.5);var finish=point(7.5,7.5);var before=snapshot()
 button(start,true);motion(finish)
 check(b.paint_stroke.active and b.paint_stroke.receipt.ok and int(b.paint_stroke.receipt.count)==4,"valid four-cell tile stroke preview")
 check(snapshot()==before,"tile preview is nonmutating")
 await shot("03-tiles-four-cell-preview")
 var charge=int(b.paint_stroke.receipt.net);button(finish,false)
 check(m.coins==before[3]-charge and game.saves==before[5]+1,"tile stroke commits once at exact quote")
 for x in range(4,8):check(m.floor_style_at(Vector2i(x,7))=="cream_tile","committed tile "+str(x))
 await shot("04-tiles-four-cell-applied")
 shop.show_build_products();await settle()
 check(not shop.objects_hidden(),"Back restores objects")
 game._cancel_selection();game.compact_ui.selected_shell="shell:back#9";game.compact_ui.sync()
 check(game.compact_ui.move_button.visible and game.compact_ui.remove_button.visible,"original wall exposes Move and Sell")
 await shot("05-original-wall-actions")
 game.compact_ui._move_opening();anchor(8,6);b.refresh(point(8.5,6))
 check(b.mode=="move_wall" and b.preview_valid,"original wall has valid move preview")
 await shot("06-original-wall-move-preview")
 game.interaction.cancel();b.choose("full");b.material="cream_stripe";b.preferred_axis="x";anchor(8,7)
 start=point(7.5,7);finish=point(9.5,7);before=snapshot();button(start,true);motion(finish)
 check(b.paint_stroke.active and b.paint_stroke.receipt.ok and int(b.paint_stroke.receipt.count)==3,"valid three-edge wall stroke preview")
 check(snapshot()==before,"wall preview is nonmutating")
 await shot("07-wall-three-edge-preview")
 charge=int(b.paint_stroke.receipt.net);button(finish,false)
 check(m.coins==before[3]-charge and game.saves==before[5]+1,"wall stroke commits once at exact quote")
 await shot("08-wall-three-edge-applied")
 game.interaction.cancel();root.size=Vector2i(390,844);shop.show_tiles();await settle()
 await click(shop.hide_objects_button.get_global_rect().get_center())
 check(shop.objects_hidden(),"portrait Hide objects button enters inspection")
 await shot("09-portrait-tiles-inspection")
 root.size=Vector2i(844,390);await settle()
 await shot("10-landscape-tiles-inspection")
 var report={"generated_profile":true,"player_save_used":false,"renderer":RenderingServer.get_video_adapter_name() if native else "headless","native_rendered":native,"checks":checks,"failures":failures,"frames":frames}
 if native:FileAccess.open(output.path_join("capture.json"),FileAccess.WRITE).store_string(JSON.stringify(report,"  "))
 print("EDITOR_CAPTURE_FIXTURE_RESULT ",JSON.stringify(report))
 for player in game.audio_players.values():player.stop();player.stream=null
 game.settings_controls.sfx_player.stop();game.settings_controls.sfx_player.stream=null
 for tween in get_processed_tweens():tween.kill()
 game.queue_free();await process_frame;quit(0 if failures.is_empty() else 1)
