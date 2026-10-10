extends SceneTree
## Deterministic native capture through the actual game renderer, with synthetic
## state only. No player save is loaded, and all normal save writes are disabled.
class TestMain extends "res://scripts/main.gd":
 var save_attempts=0
 func _load_startup():save_writes_suppressed=true;fresh_start=true;MinimalStart.apply(model)
 func _save():save_attempts+=1;return true
var game
var records=[]
func _initialize():run.call_deferred()
func capture(label:String,register:Dictionary):
 game.illustration.queue_redraw()
 for frame in 8:await process_frame
 await RenderingServer.frame_post_draw
 var image=root.get_texture().get_image()
 var output=OS.get_environment("OUTPUT")
 var phase=OS.get_environment("PHASE")
 image.save_png(output+"/"+phase+"-"+label+".png")
 var p=game.illustration.iso(float(register.x)+.5,float(register.z)+.5)
 records.append({"label":label,"rotation":register.rot,"register_position":str(p),"zoom":game.illustration.zoom,"ui_scale":game.illustration.ui_scale,"save_attempts":game.save_attempts,"save_writes_suppressed":game.save_writes_suppressed,"wallet":game.model.coins,"staff":game.staff_states.size()})
func set_rotation(register:Dictionary,rotation:int):
 register.rot=rotation
 for staff in game.staff_states:
  if staff.role=="cashier":
   var rear=game.Checkout.rear(game.model,register)
   staff.pos=Vector2(rear)+Vector2(.5,.5);staff.path=[];staff.destination=rear
   staff.art_heading=Vector2(float(register.x)+.5,float(register.z)+.5)-staff.pos
   staff.art_action="idle";staff.art_phase=0.0
 game.illustration.character_facings.clear()
 game.illustration.stance_offsets.clear()
func run():
 seed(1776)
 root.size=Vector2i(1360,880)
 game=TestMain.new();root.add_child(game)
 game.set_process(false);game.illustration.set_process(false);game.paused=true
 for frame in 60:await process_frame
 game.animation_time=0.0
 game.model.operating_open=false
 var register=game.model.checkout_register()
 assert(not register.is_empty())
 register.x=6;register.z=4
 game._update_ui()
 game.illustration.zoom=1.0;game.illustration.pan_offset=Vector2.ZERO;game.illustration.update_projection()
 set_rotation(register,1)
 await capture("game-overview",register)
 game.illustration.zoom=minf(5.0,game.illustration.camera_zoom_limits().y)
 game.illustration.update_projection()
 var center=game.illustration.iso(float(register.x)+.5,float(register.z)+.5)
 game.illustration.pan_offset+=Vector2(680,550)-center
 game.illustration.update_projection()
 for rotation in range(4):
  set_rotation(register,rotation)
  await capture("rotation-"+str(rotation),register)
 FileAccess.open(OS.get_environment("OUTPUT")+"/"+OS.get_environment("PHASE")+"-capture.json",FileAccess.WRITE).store_string(JSON.stringify(records,"  "))
 print("REGISTER_NATIVE_CAPTURE ",JSON.stringify(records))
 assert(game.save_attempts==0 and game.save_writes_suppressed)
 for player in game.audio_players.values():player.stop();player.stream=null
 game.settings_controls.sfx_player.stop();game.settings_controls.sfx_player.stream=null
 for tween in get_processed_tweens():tween.kill()
 game.queue_free()
 for frame in 8:await process_frame
 await create_timer(.2).timeout;quit()
