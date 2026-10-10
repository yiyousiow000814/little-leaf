extends SceneTree
## Native HUD-only evidence from synthetic balances; never uses player saves.
class TestMain extends "res://scripts/main.gd":
 var saves=0
 func _load_startup():save_writes_suppressed=true;fresh_start=true;MinimalStart.apply(model)
 func _save():saves+=1;return true
var game
var records=[]
func _initialize():run.call_deferred()
func run():
 seed(8246)
 game=TestMain.new();root.add_child(game);game.set_process(false);game.paused=true
 # Isolate the real HUD from unrelated world draw buffers. The size guard may
 # show the illustration again after resize, so remove it from this QA fixture.
 game.illustration.free();game.illustration=null
 game.workface_guidance.hide();game.workface_guidance.set_process(false)
 await process_frame
 var hud=game.compact_ui.hud
 for view in [Vector2i(344,568),Vector2i(566,360),Vector2i(895,540),Vector2i(1360,880),Vector2i(2560,1440)]:
  root.size=view
  for amount in [1200,99999,999999,9999999,999999999,1000000000]:
   game.model.coins=amount;hud.last_coins=-1;game._update_ui()
   for frame in 6:await process_frame
   await RenderingServer.frame_post_draw
   var name="%s-%dx%d-%d"%[OS.get_environment("PHASE"),view.x,view.y,amount]
   var output=OS.get_environment("OUTPUT")+"/"+name
   var shot=root.get_texture().get_image();shot.save_png(output+".png")
   shot.get_region(Rect2i(0,0,view.x,150 if view.x<566 else 120)).save_png(output+"-toolbar.png")
   records.append({"name":name,"amount":amount,"displayed":game.top_text.text,"amount_center":game.top_text.get_global_rect().get_center().x,"title_center":hud.wallet_title.get_global_rect().get_center().x,"save_writes":game.saves})
   if amount==1000000000 and game.top_text.text!=game.Money.amount(amount) and hud.wallet is Button:
    hud._show_wallet_balance()
    for frame in 3:await process_frame
    await RenderingServer.frame_post_draw
    root.get_texture().get_image().save_png(output+"-exact-hint.png");hud.action_help.hide()
 FileAccess.open(OS.get_environment("OUTPUT")+"/"+OS.get_environment("PHASE")+"-geometry.json",FileAccess.WRITE).store_string(JSON.stringify(records,"  "))
 print("WALLET_CAPTURE ",JSON.stringify(records))
 for player in game.audio_players.values():player.stop();player.stream=null
 game.settings_controls.sfx_player.stop();game.settings_controls.sfx_player.stream=null
 for tween in get_processed_tweens():tween.kill()
 game.queue_free();await process_frame;await create_timer(.1).timeout;quit()
