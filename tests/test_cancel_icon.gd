extends SceneTree
var game
var checks=0
var failures=[]
func check(ok:bool,label:String):
 checks+=1
 if not ok:failures.append(label);printerr("FAIL ",label)
func _initialize():run.call_deferred()
func run():
 game=load("res://main.tscn").instantiate();root.add_child(game)
 await process_frame
 game.set_process(false);game.paused=true;game.editing=true
 for view in [Vector2i(1360,880),Vector2i(960,540),Vector2i(800,600),Vector2i(640,480),Vector2i(390,844)]:
  root.size=view
  for active in [false,true]:
   game.selected_kind="plant" if active else ""
   game._update_ui()
   for frame in range(4):await process_frame
   var hud=game.compact_ui.hud
   var button_center=hud.edit_cancel.get_global_rect().get_center()
   var glyph_center=hud.cancel_art.get_global_transform()*(hud.cancel_art.size/2)
   check(glyph_center.distance_to(button_center)<0.01,str(view)+" glyph center matches button center")
   check(is_equal_approx(hud.cancel_art.rotation,PI/4),str(view)+" preserves rotated plus artwork")
   check(hud.edit_cancel.disabled==not active,str(view)+" preserves enabled state")
   if active:
    for pressed in [true,false]:
     var click=InputEventMouseButton.new();click.position=button_center;click.global_position=button_center;click.button_index=MOUSE_BUTTON_LEFT;click.pressed=pressed;root.push_input(click,true)
    await process_frame
    check(game.selected_kind=="",str(view)+" centered click cancels current selection")
 print("CANCEL_ICON_RESULT ",JSON.stringify({"checks":checks,"failures":failures}))
 game.queue_free();await process_frame;quit(0 if failures.is_empty() else 1)
