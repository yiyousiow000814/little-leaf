extends SceneTree
## Guard wide optical balancing and the unchanged compact icon dimensions.
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
 game.set_process(false);game.paused=true
 var hud=game.compact_ui.hud
 var coin=hud._texture("coin").get_image()
 var original=Image.new();original.load_png_from_buffer(FileAccess.get_file_as_bytes("res://assets/ui/fidelity_hud/coin.png"))
 check(coin!=null and coin.get_size()==Vector2i(72,72),"coin texture has four-pixel transparent sampling guard")
 if coin!=null:
  var intact=true;var clear_edges=true
  for y in coin.get_height():
   for x in coin.get_width():
    if x>=4 and x<4+original.get_width() and y>=4 and y<4+original.get_height():
     if coin.get_pixel(x,y)!=original.get_pixel(x-4,y-4):intact=false
    elif coin.get_pixel(x,y).a!=0:clear_edges=false
  check(intact,"all original coin pixels preserved unchanged")
  check(clear_edges,"coin outer sampling guard is fully transparent")
  check(coin.has_mipmaps(),"padded coin retains minification mipmaps")
 for view in [Vector2i(1360,880),Vector2i(960,540),Vector2i(850,600),Vector2i(849,600),Vector2i(800,600),Vector2i(566,360),Vector2i(390,844),Vector2i(1360,880)]:
  root.size=view;game.editing=false;game._update_ui()
  for frame in 4:await process_frame
  if not hud.layout_host.get_meta("mobile_layout",false):
   var roomy=view.x>=850
   var expected_decorate=Vector2(48 if roomy else 40,273.0/320.0*(48 if roomy else 40))
   var expected_staff=Vector2(241.0/320.0,1)*(48 if roomy else 44)
   var expected_settings=Vector2(1,227.0/320.0)*(56 if roomy else 40)
   for name in ["decorate","staff","settings"]:
    var expected=expected_decorate if name=="decorate" else (expected_staff if name=="staff" else expected_settings)
    check(hud.action_art[name].size.is_equal_approx(expected),str(view)+" "+name+" optical dimensions")
   var d=hud.action_art.decorate.get_global_rect();var s=hud.action_art.staff.get_global_rect();var g=hud.action_art.settings.get_global_rect()
   var gap=18.0 if roomy else 8.0
   check(absf(s.position.x-d.end.x-gap)<.1,str(view)+" decorate/staff gap")
   check(absf(g.position.x-s.end.x-gap)<.1,str(view)+" staff/settings gap")
   check(absf(d.get_center().y-s.get_center().y)<.1 and absf(g.get_center().y-s.get_center().y)<.1,str(view)+" shared centerline")
  else:
   for name in ["decorate","staff","settings"]:
    check(hud.action_art[name].size.x<=32 and hud.action_art[name].size.y<=32,str(view)+" contained mobile icon "+name)
  game.editing=true;game._update_ui()
  for frame in 4:await process_frame
  check(game.edit_button.size.is_equal_approx(Vector2(44,44)),str(view)+" unchanged Done target")
  check(hud.action_art.decorate.size.is_equal_approx(Vector2(22,22) if hud.layout_host.get_meta("mobile_layout",false) else Vector2(26,26)),str(view)+" centered Done icon")
 print("HUD_ICON_SCALE_RESULT ",JSON.stringify({"checks":checks,"failures":failures}))
 game.queue_free();await process_frame;quit(0 if failures.is_empty() else 1)
