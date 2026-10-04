extends SceneTree
const Model=preload("res://scripts/cafe_model.gd")
const Art=preload("res://scripts/illustrated_cafe.gd")
class FakeGame extends Node:
 var model=Model.new()
 var editing=true
 var wall_detail=false
var checks=0
var failures=[]
func check(ok:bool,label:String):
 checks+=1
 if not ok:failures.append(label);printerr("FAIL ",label)
func signature(game)->String:return JSON.stringify({"coins":game.model.coins,"items":game.model.items,"owned":game.model.owned_parcels,"floors":game.model.floor_finishes})
func _init():
 var game=FakeGame.new();var art=Art.new();art.game=game
 var before=signature(game)
 check(game.model.parcel_by_id("corner_0").visible and not game.model.parcel_by_id("corner_0").unlocked,"first-ring tree plot remains visible and locked")
 check(not art._scenery_tree_visible_at(Vector2(14.5,11.5)),"hide scenery tree on visible sale plot in Decorate")
 check(art._scenery_tree_visible_at(Vector2(.6,-2.7)),"entrance-side scenery preserved")
 check(art._scenery_tree_visible_at(Vector2(13.5,-.5)),"back scenery preserved")
 check(art._scenery_tree_visible_at(Vector2(16.5,10.5)),"hidden future land does not suppress unrelated scenery")
 for p in game.model.expansion_parcels():
  check(art._parcel_sign_point(p)==art.iso(p.x+p.w*.5,p.z+p.h*.5),"centered sign anchor for "+str(p.id))
 game.editing=false
 check(art._scenery_tree_visible_at(Vector2(14.5,11.5)),"unowned tree returns outside sale/Decorate view")
 game.editing=true
 check(not art._scenery_tree_visible_at(Vector2(14.5,11.5)),"returning to Decorate hides tree again")
 check(signature(game)==before,"render predicates and sign layout never mutate save state or player items")
 game.model.coins=50000
 check(game.model.buy_parcel("front_3"),"purchase adjacent parcel with existing rule")
 check(game.model.parcel_by_id("corner_0").unlocked and not art._scenery_tree_visible_at(Vector2(14.5,11.5)),"tree remains hidden when its sale plot unlocks")
 check(game.model.buy_parcel("corner_0"),"purchase tree parcel with existing rule")
 for editing in [true,false]:
  game.editing=editing
  check(not art._scenery_tree_visible_at(Vector2(14.5,11.5)),"owned land keeps pre-existing scenery suppression")
 var full_after=signature(game)
 for editing in [true,false,true]:
  game.editing=editing
  art._scenery_tree_visible_at(Vector2(14.5,11.5))
  art._parcel_sign_point(game.model.parcel_by_id("corner_1"))
 check(signature(game)==full_after,"purchased player's model data stays unchanged by rendering")
 print("EXPANSION_TREE_RESULT ",JSON.stringify({"checks":checks,"failures":failures}))
 art.free();game.free();quit(0 if failures.is_empty() else 1)
