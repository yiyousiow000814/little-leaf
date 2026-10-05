extends SceneTree
const Model=preload("res://scripts/cafe_model.gd")
const Dishes=preload("res://scripts/cafe_dishwashing.gd")
const Wash=preload("res://scripts/cafe_sink_wash_art.gd")
class FixtureGame extends Node:
 var model=Model.new()
 var dishwashing=Dishes.new()
 var service_guests={}
 var staff_states=[]
 var editing=false
 var paused=false
 var wall_detail=false
 var animation_time=0.0
class Sheet extends "res://scripts/illustrated_cafe.gd":
 var font=preload("res://assets/fonts/NotoSans-Regular.ttf")
 var mode="sheet"
 var seconds=4.3
 var control="washing"
 func _ready():set_process(false)
 func _process(_delta):pass
 func sample(rotation:int,time:float,count:int=6):
  var sink=game.model.get_item(3);sink.x=0;sink.z=0;sink.rot=rotation
  game.dishwashing.dishes.clear();game.staff_states.clear();game.paused=control=="paused";game.animation_time=time
  var finished=time>=20.0 or control=="idle"
  for index in range(count-1 if finished else count):game.dishwashing.dishes[index+1]={"id":index+1,"sink_id":3,"elapsed":time if index==0 else 0.0}
  var worker={"role":"cleaner","job_kind":"" if finished else "wash","job_dish_id":1,"station_id":3,"job_elapsed":time,"pos":game.model.cell_center(game.model.workface_cell(sink)),"art_action":"idle" if finished else "washing"}
  game.staff_states.append(worker)
  return worker
 func draw_case(center:Vector2,scale:float,rotation:int,time:float,count:int=6):
  var worker=sample(rotation,time,count)
  var front=Vector2.DOWN.rotated(rotation*PI/2);var heading=-front
  var mirror=-1.0 if heading.x-heading.y<0 else 1.0;var back=heading.x+heading.y<0
  var offset=Vector2((front.x-front.y)*39,(front.x+front.y)*19.5)*(1.0-Wash.INSET)
  var finished=worker.job_kind==""
  var g=Wash.geometry(rotation,minf(time,19.99),count)
  var basis:Transform2D=g.basis
  var reach=(g.center-offset)*Vector2(mirror,1)
  var pose={"blend":0.0,"phase":0.0,"view_back":back,"mirror":mirror,"washing_basis":Transform2D(basis.x*Vector2(mirror,1),basis.y*Vector2(mirror,1),Vector2.ZERO),"washing_seconds":time}
  var ref=Wash.geometry(rotation,1.0,count);var ref_axes:Transform2D=ref.basis
  pose["washing_grip_reference"]={"center":(ref.center-offset)*Vector2(mirror,1),"basis":Transform2D(ref_axes.x*Vector2(mirror,1),ref_axes.y*Vector2(mirror,1),Vector2.ZERO)}
  var behind=front.x+front.y<0
  if behind:draw_worker(center+offset*scale,scale,mirror,heading,reach,pose,true,false,finished)
  art_transform(center,0,Vector2.ONE*scale)
  furniture_art.draw_item(self,"sink",Vector2.ZERO,rotation,3);_sink_dishes(3)
  draw_worker(center+offset*scale,scale,mirror,heading,reach,pose,false,behind,finished)
  art_transform(Vector2.ZERO)
 func draw_worker(at:Vector2,scale:float,mirror:float,heading:Vector2,reach:Vector2,pose:Dictionary,hide:bool,overlay:bool,finished:bool):
  pose=pose.duplicate();pose.hide_reach=hide;pose.reach_overlay=overlay
  art_transform(at,0,Vector2(mirror,1)*scale)
  character(Vector2.ZERO,2,true,false,false,"idle" if finished else "washing",seconds/20,reach,heading,"none","none",pose,"cleaner")
 func _draw():
  render_contacts.clear();draw_rect(Rect2(0,0,1360,1024),Color("e5e9d5"))
  draw_string(font,Vector2(28,35),"Automatic washing · water, plate and hands share the same contacts",HORIZONTAL_ALIGNMENT_LEFT,-1,21,Color("29473c"))
  if mode=="sheet":
   var times=[.4,4.3,18.8,20.0]
   for rotation in range(4):
    draw_string(font,Vector2(14,115+rotation*220),str(rotation*90)+"°",HORIZONTAL_ALIGNMENT_LEFT,-1,17,Color("29473c"))
    for column in range(4):
     if rotation==0:draw_string(font,Vector2(95+column*330,67),["Lift · 0.4 s","Scrub · 4.3 s","Rinse · 18.8 s","Finished · 20 s"][column],HORIZONTAL_ALIGNMENT_LEFT,-1,16,Color("426050"))
     draw_case(Vector2(170+column*330,240+rotation*220),2.3,rotation,times[column])
  elif mode in ["lift_continuity","lower_continuity"]:
   var times=[.55,.56,.59,.60,.61] if mode=="lift_continuity" else [19.59,19.60,19.61,19.65,19.70]
   for row in range(4):
    var rotation=0 if row<2 else 3;var count=1 if row%2==0 else 6
    draw_string(font,Vector2(14,115+row*220),str(rotation*90)+"° / "+str(count),HORIZONTAL_ALIGNMENT_LEFT,-1,15,Color("29473c"))
    for column in range(5):
     if row==0:draw_string(font,Vector2(100+column*260,67),"%.2f s"%times[column],HORIZONTAL_ALIGNMENT_LEFT,-1,17,Color("426050"))
     draw_case(Vector2(140+column*260,240+row*220),2.0,rotation,times[column],count)
  else:
   draw_string(font,Vector2(75,85),control.capitalize()+" · "+("water stopped" if control!="washing" else "short scrub and rinse motions"),HORIZONTAL_ALIGNMENT_LEFT,-1,24,Color("426050"))
   draw_case(Vector2(680,650),7.0,1,seconds)
func _initialize():run.call_deferred()
func capture(sheet,label):
 sheet.queue_redraw()
 for frame in 3:await process_frame
 await RenderingServer.frame_post_draw
 var error=root.get_texture().get_image().save_png(OS.get_environment("OUTPUT")+"/"+label+".png")
 assert(error==OK)
func run():
 root.size=Vector2i(1360,1024);DisplayServer.window_set_title("Little Leaf automatic washing QA")
 var fixture=FixtureGame.new();fixture.model.reset_new();root.add_child(fixture)
 var sheet=Sheet.new();sheet.game=fixture;root.add_child(sheet)
 await capture(sheet,"wash-cycle-all-rotations")
 var contacts=sheet.render_contacts.duplicate(true)
 sheet.mode="lift_continuity";await capture(sheet,"lift-continuity")
 sheet.mode="lower_continuity";await capture(sheet,"lower-continuity")
 sheet.mode="motion"
 for frame in range(20):
  sheet.seconds=3.0+frame*.12
  await capture(sheet,"motion-%02d"%frame)
 sheet.control="paused";await capture(sheet,"paused-water-off")
 sheet.control="idle";await capture(sheet,"idle-water-off")
 FileAccess.open(OS.get_environment("OUTPUT")+"/contacts.json",FileAccess.WRITE).store_string(JSON.stringify({"synthetic":true,"uses_production_renderers":true,"normal_saves":false,"contacts":contacts},"  "))
 print("AUTOMATIC_WASH_NATIVE_COMPLETE frames=25 rotations=4")
 quit()
