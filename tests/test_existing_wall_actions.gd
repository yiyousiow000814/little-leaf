extends SceneTree
## The three ordinary user flows: restyle an existing wall, add door, add window.
class TestMain extends "res://scripts/main.gd":
 var saves=0
 func _load_startup():save_writes_suppressed=true;fresh_start=true;MinimalStart.apply(model)
 func _save():saves+=1;return true
var game
var checks=0
var failures=[]
var operations=[]
func check(ok:bool,label:String):
 checks+=1
 if not ok:failures.append(label);printerr("FAIL ",label)
func _initialize():run.call_deferred()
func settle():
 game._update_ui();game.illustration.queue_redraw()
 for frame in 8:await process_frame
func click(point:Vector2):
 var motion=InputEventMouseMotion.new();motion.position=point;motion.global_position=point;root.push_input(motion,true)
 for pressed in [true,false]:
  var event=InputEventMouseButton.new();event.position=point;event.global_position=point;event.button_index=MOUSE_BUTTON_LEFT;event.pressed=pressed;root.push_input(event,true)
 await settle()
func aim(x:float)->Vector2:
 var art=game.illustration;var point=art.iso(x,0,70)
 game.interaction._pan_by(art.camera_safe_rect().get_center()-point)
 return art.iso(x,0,70)
func capture(name:String):
 var output=OS.get_environment("OUTPUT")
 if output=="" or DisplayServer.get_name()=="headless":return
 await RenderingServer.frame_post_draw
 root.get_texture().get_image().save_png(output+"/"+name+".png")
func run():
 if not "saveguard" in OS.get_user_data_dir():printerr("Use isolated profile");quit(2);return
 root.size=Vector2i(1164,624);game=TestMain.new();root.add_child(game);game.set_process(false);game.illustration.set_process(false);game.paused=true
 await process_frame;game.model.coins=1600;game._toggle_edit();game._set_catalog_category("Build");game.compact_ui._set_tray_reveal(1);await settle()
 var ui=game.compact_ui;var model=game.model;var tool=game.build_tools
 game._cancel_selection();await settle();await click(aim(2.5))
 check(ui.selected_shell=="shell:back#2","click existing wall selects exact one-tile host")
 await click(ui.finish_button.get_global_rect().get_center())
 check(ui.shop_ui.build_page=="walls" and not ui.has_open_popup(),"Replace opens existing wall style cards in bottom tray")
 await click(ui.shop_ui.wall_cards["wall:full:cream_stripe"].get_global_rect().get_center());await click(aim(2.5))
 check(ui.wall_review.visible and ui.pending_wall.key=="shell:back#2","wall click opens review for same existing host")
 var wallet=model.coins;var saves=game.saves
 await click(ui.wall_confirm_button.get_global_rect().get_center())
 var style_ok=model.shell_segment_products["shell:back#2"].material=="cream_stripe"
 check(style_ok,"existing wall changes to chosen Cream stripes")
 check(model.coins==wallet-55 and game.saves==saves+1,"existing wall style pays stated price and saves once")
 operations.append({"operation":"existing wall style","passed":style_ok,"coins_before":wallet,"coins_after":model.coins})
 await capture("01-existing-wall-style")
 for spec in [["door",3.5],["window",4.5]]:
  var kind=str(spec[0]);game._cancel_selection();await settle()
  if ui.shop_ui.build_page!="products":await click(ui.shop_ui.tiles_back.get_global_rect().get_center())
  await click(tool.tool_buttons[kind].get_global_rect().get_center())
  check(tool.mode==kind,"catalog click selects "+kind)
  wallet=model.coins;saves=game.saves;var count=model.wall_attachments.size()
  await click(aim(float(spec[1])))
  var installed=model.wall_attachments.size()==count+1 and model.wall_attachments[-1].kind==kind and model.wall_attachments[-1].host_id=="shell:back" and is_equal_approx(float(model.wall_attachments[-1].offset),float(spec[1]))
  check(installed,"click existing wall installs "+kind+" at requested host")
  check(model.coins==wallet-model.attachment_price(kind) and game.saves==saves+1,kind+" pays listed price and saves once")
  operations.append({"operation":"existing wall add "+kind,"passed":installed,"coins_before":wallet,"coins_after":model.coins})
  await capture("02-existing-wall-door" if kind=="door" else "03-existing-wall-window")
 print("EXISTING_WALL_ACTIONS_RESULT ",JSON.stringify({"checks":checks,"failures":failures,"operations":operations,"player_save_used":false,"native_render_verified":DisplayServer.get_name()!="headless"}))
 for player in game.audio_players.values():player.stop();player.stream=null
 game.settings_controls.sfx_player.stop();game.settings_controls.sfx_player.stream=null
 for tween in get_processed_tweens():tween.kill()
 game.queue_free();await process_frame;quit(0 if failures.is_empty() else 1)
