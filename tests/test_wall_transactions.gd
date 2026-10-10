extends SceneTree
const Model=preload("res://scripts/cafe_model.gd")
var failures=[]
var checks=0
func check(ok:bool,label:String):
 checks+=1
 if not ok:failures.append(label);printerr("FAIL ",label)
func snapshot(m):return JSON.stringify([m.coins,m.built_walls,m.wall_attachments,m.shell_segment_products,m._next_wall_id,m.revision,m.decoration_build_purchases])
func fresh():
 var m=Model.new();m.items.clear();m.dining_sets.clear();m.customers.clear();m.coins=10000;return m
func _initialize():run.call_deferred()
func run():
 if not "saveguard" in OS.get_user_data_dir():quit(2);return
 var m=fresh()
 check(m.get_editable_wall("shell:west#2").material=="original","included wall uses common lookup")
 check(m.wall_refund("shell:west#2")==0,"free shell has zero sale value")
 check(m.can_remove_wall("shell:west#2") and m.remove_wall("shell:west#2"),"sell included wall")
 check(not m.edge_blocked(Vector2i(-1,2),Vector2i(0,2)),"removed wall opens boundary")
 check(not m.segment_blocked(Vector2(-.5,2.5),Vector2(.5,2.5)),"removed wall clears physical collision")
 check(m.get_wall_host("shell:west#2").is_empty(),"removed wall no longer selectable")
 check(m.coins==10000 and not m.remove_wall("shell:west#2"),"no repeated shell sale")
 check(m.place_wall("z",0,2),"can buy a wall on a removed original edge")
 check(m.edge_blocked(Vector2i(-1,2),Vector2i(0,2)),"replacement edge blocks")
 check(m.place_wall_attachment("door","wall:1",.5),"one-tile standard door fits replacement")
 check(m.wall_attachments[-1].width==1.0,"bought door is one tile")
 var before=snapshot(m)
 check(not m.can_move_wall("shell:west#1","z",14,2) and snapshot(m)==before,"move cannot reach unpurchased land")
 check(not m.can_move_wall("shell:west#1","z",4,3,[Vector2(4,3.5)]) and snapshot(m)==before,"crossing actor blocks move without edits")
 check(not m.remove_wall("z:0:2") and snapshot(m)==before,"hosted opening prevents unsupported wall sale")
 m=fresh();before=snapshot(m)
 check(m.can_move_wall("shell:west#2","z",4,3),"included wall move quote valid: "+m.last_error)
 check(snapshot(m)==before,"move preview is pure")
 check(m.move_wall("shell:west#2","z",4,3),"move included wall: "+m.last_error)
 check(m.get_wall("z:4:3").material=="original" and m.wall_refund("z:4:3")==0,"moved free wall keeps appearance and zero receipt")
 check(m.remove_wall("z:4:3") and m.coins==10000,"selling moved starter does not mint coins")
 m=fresh();check(m.move_wall("shell:west#5","z",4,3),"move one-tile shell door host atomically: "+m.last_error)
 check(m.wall_attachments[0].host_id=="wall:1" and m.wall_attachments[0].offset==.5,"door identity follows moved host")
 m=fresh();m.begin_decoration_session()
 check(m.replace_wall("shell:west#2","half","sage_panels"),"buy shell replacement")
 check(m.wall_refund("shell:west#2")==35,"current session shell returns exact receipt")
 check(m.move_wall("shell:west#2","z",4,3),"move paid shell: "+m.last_error)
 check(m.wall_refund("z:4:3")==35,"session receipt survives shell move")
 check(m.remove_wall("z:4:3") and m.coins==10000,"session shell purchase/move/sell nets zero")
 m=Model.new();m.coins=10000
 check(m.replace_wall("shell:west#8","half","sage_panels"),"buy final starter wall tile")
 check(m.move_wall("shell:west#8","z",0,8),"move paid last shell tile onto same edge")
 check(m.save("user://last-shell.json"),"save paid last shell tile")
 var last=Model.new();check(last.load_save("user://last-shell.json"),"reload paid last shell tile: "+last.last_error)
 check(last.wall_refund("z:0:8")==17,"paid last tile retains half actual cost")
 m=Model.new();m.coins=10000
 check(m.move_wall("shell:back#11","x",11,8),"original shell move on furnished cafe: "+m.last_error)
 check(m.save("user://transactions.json"),"save edited cafe")
 var loaded=Model.new()
 check(loaded.load_save("user://transactions.json"),"reload original moved wall: "+loaded.last_error)
 check(loaded.get_wall_host("shell:back#11").is_empty() and loaded.wall_refund("x:11:8")==0,"absence and zero provenance survive load")
 var data=JSON.parse_string(FileAccess.get_file_as_string("user://transactions.json"))
 data.built_walls[0].paid_cost=55;data.built_walls[0].refund_credit=27
 var file=FileAccess.open("user://forged.json",FileAccess.WRITE);file.store_string(JSON.stringify(data));file.close()
 before=snapshot(loaded)
 check(not loaded.load_save("user://forged.json") and snapshot(loaded)==before,"forged included-wall receipts rejected atomically")
 print("WALL_TRANSACTIONS_RESULT ",JSON.stringify({"checks":checks,"failures":failures}))
 quit(0 if failures.is_empty() else 1)
