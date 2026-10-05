extends SceneTree
## Synthetic balances only; never loads or writes a player save.
class TestMain extends "res://scripts/main.gd":
 var saves=0
 func _load_startup():save_writes_suppressed=true;fresh_start=true;MinimalStart.apply(model)
 func _save():saves+=1;return true
var game
var checks=0
var failures=[]
func check(ok:bool,label:String):
 checks+=1
 if not ok:failures.append(label);printerr("FAIL ",label)
func _initialize():run.call_deferred()
func settle():
 game.compact_ui.hud.last_coins=-1
 game._update_ui()
 for frame in 3:await process_frame
func click(control:Control):
 var point=control.get_global_rect().get_center()
 # Use the same input queue as touch emulation, rather than mixing buffered
 # emulated releases with direct Viewport.push_input mouse dispatch.
 var motion=InputEventMouseMotion.new();motion.position=point;motion.global_position=point;Input.parse_input_event(motion);Input.flush_buffered_events()
 await process_frame
 for pressed in [true,false]:
  var event=InputEventMouseButton.new();event.position=point;event.global_position=point;event.button_index=MOUSE_BUTTON_LEFT;event.pressed=pressed;Input.parse_input_event(event);Input.flush_buffered_events()
  await process_frame
func tap(control:Control):
 for pressed in [true,false]:
  var event=InputEventScreenTouch.new();event.position=control.get_global_rect().get_center();event.pressed=pressed;Input.parse_input_event(event)
  await process_frame
func run():
 game=TestMain.new();root.add_child(game);game.set_process(false);game.paused=true
 await process_frame
 var hud=game.compact_ui.hud
 var balances=[0,9,10,99,100,999,1000,9999,10000,99999,100000,999999,1000000,9999999,10000000,999999999,1000000000]
 for view in [Vector2i(320,568),Vector2i(344,568),Vector2i(390,844),Vector2i(566,360),Vector2i(800,600),Vector2i(895,540),Vector2i(1360,880),Vector2i(2560,1440)]:
  root.size=view
  for editing in [false,true]:
   game.editing=editing
   for amount in balances:
    game.model.coins=amount;await settle()
    var label="%s %s %s"%[str(view),str(editing),str(amount)]
    var exact=game.Money.amount(amount);var font=game.top_text.get_theme_font_size("font_size")
    var fits=hud.font_bold.get_string_size(exact,HORIZONTAL_ALIGNMENT_LEFT,-1,font).x<=game.top_text.size.x
    var rendered_width=hud.font_bold.get_string_size(game.top_text.text,HORIZONTAL_ALIGNMENT_LEFT,-1,font).x
    if not hud.layout_host.get_meta("mobile_layout",false):
     check(absf(game.top_text.get_global_rect().get_center().x-hud.wallet_title.get_global_rect().get_center().x)<.01,label+" amount and Coins share center")
     check(absf(game.top_text.position.x-(hud.wallet_box.size.x-game.top_text.size.x)*.5)<.01 and game.top_text.size.x<hud.wallet_box.size.x,label+" symmetric clearance from painted coins and pins")
    else:
     check(hud.wallet_box.get_global_rect().encloses(game.top_text.get_global_rect()),label+" mobile digits inside status chip")
     check(game.top_text.get_theme_font_size("font_size")==18,label+" mobile balance readable18px")
    check(rendered_width<=game.top_text.size.x,label+" amount fits without clipping")
    check((game.top_text.text==exact)==fits,label+" exact digits kept whenever they fit")
    check(hud.wallet.tooltip_text==exact+" Leaf Coins",label+" exact hover amount")
    check(hud.wallet.accessibility_name==exact+" Leaf Coins",label+" exact accessible amount")
    check(hud.wallet.focus_mode==(Control.FOCUS_NONE if fits else Control.FOCUS_ALL),label+" compact amount keyboard access")
    check(Rect2(Vector2.ZERO,Vector2(view)).encloses(hud.wallet.get_global_rect()),label+" wallet inside viewport")
  game.model.coins=1000000000;game.editing=false;await settle()
  if view.x<344:
   check(game.compact_ui.viewport_too_small,"unsupported 320px view keeps its existing input guard")
   continue
  hud.action_help.hide();await click(hud.wallet)
  check(hud.action_help.panel.visible,str(view)+" click reveals compact amount")
  check(hud.action_help.label.text=="1,000,000,000 Leaf Coins",str(view)+" hint contains full balance")
  check(Rect2(Vector2.ZERO,Vector2(view)).encloses(hud.action_help.panel.get_global_rect()),str(view)+" full balance hint inside viewport")
  check(not hud.action_help.panel.get_global_rect().intersects(hud.layout_host.get_global_rect()),str(view)+" full balance hint leaves toolbar controls visible")
  hud.action_help.hide();hud.wallet.release_focus();hud.wallet.grab_focus();await process_frame
  check(hud.action_help.panel.visible,str(view)+" keyboard focus reveals compact amount")
  hud.action_help.hide();await click(hud.wallet)
  check(hud.action_help.panel.visible,str(view)+" repeat click reopens balance")
  hud.action_help.hide();await tap(hud.wallet)
  check(hud.action_help.panel.visible,str(view)+" touch tap reveals compact amount")
  check(game.model.coins==1000000000,str(view)+" revealing balance never changes funds")
  game.model.coins=120;await settle();hud.action_help.hide();await click(hud.wallet)
  check(not hud.action_help.panel.visible,str(view)+" exact amounts need no redundant hint")
 # Formatter boundaries: preserve exact values until measured space requires K/M/B.
 for pair in [[999999,"999.9K"],[1000000,"1M"],[999999999,"999.9M"],[1000000000,"1B"]]:
  var exact_width=hud.font_bold.get_string_size(game.Money.amount(pair[0]),HORIZONTAL_ALIGNMENT_LEFT,-1,13).x
  var compact_width=hud.font_bold.get_string_size(pair[1],HORIZONTAL_ALIGNMENT_LEFT,-1,13).x
  check(hud._wallet_amount(pair[0],(exact_width+compact_width)*.5,13)==pair[1],"compact boundary "+str(pair[0]))
 check(hud._wallet_amount(999999,35,13)=="999K","extra narrow amount drops decimal without rounding up")
 check(game.saves==0,"no save writes")
 print("WALLET_ALIGNMENT_RESULT ",JSON.stringify({"checks":checks,"failures":failures}))
 for player in game.audio_players.values():player.stop();player.stream=null
 game.settings_controls.sfx_player.stop();game.settings_controls.sfx_player.stream=null
 for tween in get_processed_tweens():tween.kill()
 game.queue_free();await process_frame;quit(0 if failures.is_empty() else 1)
