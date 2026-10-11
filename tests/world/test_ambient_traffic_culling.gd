extends "res://tests/test_render_visibility.gd"
## Compare the public traffic entry point with its authoritative car renderer.
const Traffic=preload("res://scripts/ambient_road_traffic.gd")
func _initialize():
 var recorder=Recorder.new();var traffic=Traffic.new();var cases=0;var proven_visible=0;var offscreen_empty=0
 var world=Vector2(Traffic.LANES[0],0)
 traffic.cars.clear()
 traffic.cars.append({"position":world,"direction":1,"color":"a2b3b3"})
 for viewport in [Rect2(0,0,390,844),Rect2(0,0,1360,880),Rect2(0,0,844,390)]:
  recorder.viewport=viewport
  for scale in [.35,1.0,2.0,4.0]:
   recorder.zoom=scale
   for detail in [1.0,1.55]:
    recorder.detail=detail
    for direction in [-1,1]:
     traffic.cars[0].direction=direction
     # First position is the proven (-64,200) omission at ordinary scale.
     for anchor in [Vector2(-64,200),Vector2(-64*scale,viewport.size.y*.5),Vector2(viewport.end.x+64*scale,viewport.size.y*.5),Vector2(viewport.size.x*.5,-64*scale),Vector2(viewport.size.x*.5,viewport.end.y+64*scale),viewport.get_center(),Vector2(-100000,-100000)]:
      recorder.origin=anchor-Vector2((world.x-world.y)*39,(world.x+world.y)*19.5)*scale*detail
      recorder.commands=[];Neighborhood.draw_car(recorder,world,direction,"a2b3b3")
      var expected=recorder.commands.duplicate(true)
      recorder.commands=[];traffic.draw(recorder)
      check(recorder.commands==expected,"traffic preserves authoritative car commands at viewport edges: %s scale=%s detail=%s anchor=%s direction=%s"%[viewport,scale,detail,anchor,direction])
      check(visible_keys(recorder.commands,viewport)==visible_keys(expected,viewport),"edge-visible command parity")
      if anchor==Vector2(-64,200) and is_equal_approx(scale,1.0):
       check(not visible_keys(expected,viewport).is_empty(),"proven (-64,200) case contains visible car geometry at normal/detail zoom")
       proven_visible+=1
      if anchor==Vector2(-100000,-100000):
       check(expected.is_empty() and recorder.commands.is_empty(),"authoritative projected bounds still cull distant traffic")
       offscreen_empty+=1
      cases+=1
 check(proven_visible>0 and offscreen_empty>0,"edge-visible and fully offscreen cases exercised")
 print("AMBIENT_TRAFFIC_CULLING_RESULT ",JSON.stringify({"checks":checks,"failures":failures,"cases":cases,"proven_visible_cases":proven_visible,"offscreen_empty_cases":offscreen_empty}));quit(0 if failures.is_empty() else 1)
