extends SceneTree
# Read-only visual diagnosis using the unchanged live renderer and synthetic poses.
# No Main, player profile, saved state, service controller, or storage access.
class Board extends "res://scripts/illustrated_cafe.gd":
 var test_species=0
 var test_phase=.5
 var markers=false
 var split_overlay=false
 var records=[]
 func _ready():
  set_process(false)
  use_cached_heads=false;use_cached_moving_art=false
 func label(at:Vector2,text:String,size=18):
  draw_string(ThemeDB.fallback_font,at,text,HORIZONTAL_ALIGNMENT_LEFT,-1,size,Color("516248"))
 func _draw():
  records.clear()
  draw_rect(Rect2(0,0,1600,1200),Color("e8dfbf"))
  label(Vector2(24,28),OS.get_environment("PHASE").to_upper()+" ARM OCCLUSION + VERTICAL STANDING REST | species="+str(test_species)+" | phase="+str(test_phase)+" | overlay="+str(split_overlay)+" | synthetic production-renderer diagnosis",20)
  var views=[[1.0,false,"Front-right"],[-1.0,false,"Front-left"],[1.0,true,"Back-right"],[-1.0,true,"Back-left"]]
  var cases=[["standby","cleaner","none","none"],["taking_payment","cashier","none","none"],["taking_order","waiter","none","notepad"],["carrying_plate","waiter","plate","none"],["cooking","chef","none","spatula"]]
  for col in range(4):label(Vector2(170+col*390,62),views[col][2])
  for row in range(cases.size()):
   var data=cases[row]
   label(Vector2(14,98+row*216),data[0],16)
   for col in range(4):
    var view=views[col];var back=bool(view[1]);var mirror=float(view[0])
    var at=Vector2(210+col*390,282+row*216)
    var pose={"mirror":mirror,"view_back":back,"seat_mix":0.0,"blend":0.0,"phase":.17,"carry_hand":DirectionalCharacter.carry_anchor(back),"cooking_elapsed":test_phase*2.6,"cooking_remaining":-1.0}
    var reach=Vector2(17,-34) if back else Vector2(16,-22)
    if data[0]=="cooking":reach=Vector2(22,-37) if back else Vector2(18,-17)
    var settings=pose.duplicate()
    settings.merge({"role":data[1],"shirt":{"cashier":"b68b92","waiter":"b99578","chef":"739c7f","cleaner":"91b2ad"}[data[1]],"action":data[0],"progress":test_phase,"payload":data[2],"tool":data[3],"reach":reach,"chef_hat":data[1]=="chef"},true)
    art_transform(at,0,Vector2(mirror,1)*2.5)
    if split_overlay and data[0] in ["taking_payment","cooking"]:
     settings["hide_reach"]=true
     directional_character.draw(self,Vector2.ZERO,test_species,back,false,.17,true,false,settings)
     settings["hide_reach"]=false;settings["reach_overlay"]=true
    var g=directional_character.draw(self,Vector2.ZERO,test_species,back,false,.17,true,false,settings)
    records.append({"action":data[0],"species":test_species,"phase":test_phase,"view":view[2],"near_shoulder":str(g.near_shoulder),"far_shoulder":str(g.far_shoulder),"near_hand":str(g.near_hand),"far_hand":str(g.far_hand),"payment_near":g.payment_pose.get("use_near",null),"body":str(g.body)})
    if markers:
     draw_circle(g.near_shoulder,1.15,Color("dd5544"));draw_circle(g.far_shoulder,1.15,Color("4466cc"))
     draw_line(g.near_shoulder,g.far_shoulder,Color("996699"),.4)
     draw_rect(DirectionalCharacter.head_bounds(test_species,false,false),Color(1,.2,.2,.5),false,.35)
    art_transform(Vector2.ZERO)
var board
func _initialize():run.call_deferred()
func run():
 root.size=Vector2i(1600,1200)
 board=Board.new();root.add_child(board)
 var output=OS.get_environment("OUTPUT")
 var all=[]
 for species in range(3):
  for phase in [.08,.5,.88]:
   board.test_species=species;board.test_phase=phase;board.markers=false;board.queue_redraw()
   for frame in 4:await process_frame
   await RenderingServer.frame_post_draw
   root.get_texture().get_image().save_png(output+"/species-"+str(species)+"-phase-"+str(phase)+".png")
   all.append_array(board.records)
 board.test_species=0;board.test_phase=.5;board.markers=true;board.queue_redraw()
 for frame in 4:await process_frame
 await RenderingServer.frame_post_draw
 root.get_texture().get_image().save_png(output+"/rabbit-phase-mid-sockets.png")
 for species in range(3):
  board.test_species=species;board.test_phase=.5;board.markers=false;board.split_overlay=true;board.queue_redraw()
  for frame in 4:await process_frame
  await RenderingServer.frame_post_draw
  root.get_texture().get_image().save_png(output+"/species-"+str(species)+"-mid-split-overlay.png")
 FileAccess.open(output+"/geometry.json",FileAccess.WRITE).store_string(JSON.stringify(all,"  "))
 print("SHOULDER_ACTION_NATIVE_RESULT actions=5 facings=4 phases=3 species=3 poses=180 synthetic=true save_loaded=false")
 board.queue_free();await process_frame;quit()
