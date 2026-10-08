extends SceneTree
const Furniture=preload("res://scripts/illustrated_furniture.gd")
class PayloadSpy:
 extends Node2D
 var calls=[]
 func _station_payloads(_id,_kind,_rotation):calls.append("payload")
class RendererSpy:
 extends "res://scripts/illustrated_furniture.gd"
 var cached=false
 func _can_cache(_artist,_p=Vector2.ZERO)->bool:return cached
 func _cached_part(artist,part,_p,_rotation):artist.calls.append(part)
 func _beverage_base():a.calls.append("beverage_base")
 func espresso():a.calls.append("beverage_machine")
 func beverage_accessories():a.calls.append("beverage_accessories")
var checks=0
var failures=[]
func check(ok,label):
 checks+=1
 if not ok:failures.append(label);push_error(label)
func _initialize():run.call_deferred()
func run():
 var artist=PayloadSpy.new();var renderer=RendererSpy.new()
 for rotation in range(4):
  var spare_depth=Vector2(-.32,.15).rotated(rotation*PI/2).dot(Vector2.ONE)
  var machine_depth=Vector2(.08,-.13).rotated(rotation*PI/2).dot(Vector2.ONE)
  var front=spare_depth>machine_depth
  check(Furniture.beverage_accessories_in_front(rotation)==front,"Cup stack depth ignores its ground position")
  var parts=Furniture.part_sequence("beverage",rotation)
  check((parts.find("beverage_accessories")>parts.find("beverage_machine"))==front,"Rear cup stack paints over the dispenser")
  check(parts.find("beverage_base")==0 and parts.count("beverage_accessories")==1,"Cup stack duplicates or loses countertop support")
  check((parts.find("payload")>parts.find("beverage_machine"))==(rotation in [0,3]),"Live preparation cup ordering changed")
  for cached in [false,true]:
   renderer.cached=cached;artist.calls.clear()
   renderer.draw_item(artist,"beverage",Vector2.ZERO,rotation,0)
   check(artist.calls==parts,"Cached and source station painters disagree")
   artist.calls.clear();renderer.draw_beverage_foreground(artist,Vector2.ZERO,rotation)
   var expected=["beverage_machine","beverage_accessories"] if front else ["beverage_accessories","beverage_machine"]
   check(artist.calls==expected,"Staff foreground pass restores the wrong cup depth")
 artist.free()
 print("BEVERAGE_ACCESSORY_DEPTH_RESULT ",JSON.stringify({"checks":checks,"failures":failures}))
 quit(0 if failures.is_empty() else 1)
