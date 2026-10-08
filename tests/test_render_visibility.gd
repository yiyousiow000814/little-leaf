extends SceneTree
const Visibility=preload("res://scripts/cafe_render_visibility.gd")
const Art=preload("res://scripts/illustrated_cafe.gd")
var checks=0
var failures=[]
func check(ok,label):
 checks+=1
 if not ok:failures.append(label);push_error(label)
func _initialize():run.call_deferred()
func run():
 var view=Rect2(0,0,390,844)
 for margin in [0.0,6.0,20.0]:
  check(Visibility.visible(Rect2(390,100,0,10),view,margin),"edge-touch stays visible")
  check(Visibility.visible(Rect2(Vector2.INF,Vector2.ONE),view,margin),"unknown bounds fail open")
  check(not Visibility.visible(Rect2(2000,2000,100,100),view,margin),"far offscreen omitted")
  check(Visibility.visible(Rect2(-50,-50,500,950),view,margin),"covering viewport retained")
 var art=Art.new();root.add_child(art);art.set_process(false)
 check(art.render_bounds_visible(Rect2(2000,2000,100,100)),"standalone artists fail open")
 art.icon_kind="chair"
 check(art.render_bounds_visible(Rect2(2000,2000,100,100)),"icons fail open")
 art.queue_free();await process_frame
 print("RENDER_VISIBILITY_RESULT ",JSON.stringify({"checks":checks,"failures":failures}));quit(0 if failures.is_empty() else 1)
